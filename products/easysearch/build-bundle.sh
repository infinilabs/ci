#!/bin/bash

# =====================================================================
# build-bundle.sh
#   1. JDK 并行下载；5 个平台的 bundle 并行打包（每个平台独立工作目录）
#   2. OSS 上传可通过 SKIP_OSS_UPLOAD / ONLY_DOCKER 跳过
#   3. STAGE_ARTIFACTS=true 时，每个 bundle 暂存为独立 artifact 目录：
#      $GITHUB_WORKSPACE/artifacts/bundle-<platform>/
#   注意：并行会同时占用多份解压空间，磁盘紧张时调小 BUNDLE_PARALLEL
# =====================================================================

USE_GRAALVM=true
USE_MACOS_TARGZ=false

# ── 通用函数 ──────────────────────────────────────────────
is_true() { [[ "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" == "true" ]]; }
should_upload_oss() {
  is_true "${PUBLISH_STABLE:-}" && ! is_true "${ONLY_DOCKER:-}" && ! is_true "${SKIP_OSS_UPLOAD:-}"
}
should_stage() { is_true "${STAGE_ARTIFACTS:-}" && ! is_true "${ONLY_DOCKER:-}"; }

ART="$GITHUB_WORKSPACE/artifacts"
stage_file() {
  local name="$1" sub="$2" f="$3"
  mkdir -p "$ART/$name/$sub"
  ln -f "$f" "$ART/$name/$sub/" 2>/dev/null || cp -f "$f" "$ART/$name/$sub/"
}

# ── 并行任务工具 ──────────────────────────────────────────
MAX_PARALLEL=5
FAIL_DIR=""; LOGDIR=""
throttle() { while (( $(jobs -rp | wc -l) >= MAX_PARALLEL )); do wait -n 2>/dev/null || true; done; }
run_bg() {
  local label="$1"; shift
  throttle
  { "$@" >"$LOGDIR/$label.log" 2>&1 || touch "$FAIL_DIR/$label"; } &
}
finish_jobs() {
  wait
  local f rc=0
  for f in "$LOGDIR"/*.log; do
    [ -e "$f" ] || continue
    echo "::group::$(basename "$f" .log)"; cat "$f"; echo "::endgroup::"
  done
  if [ -n "$(ls -A "$FAIL_DIR" 2>/dev/null)" ]; then
    echo "Error: parallel job(s) failed: $(ls "$FAIL_DIR" | tr '\n' ' ')" >&2
    rc=1
  fi
  rm -f "$LOGDIR"/*.log "$FAIL_DIR"/* 2>/dev/null
  return $rc
}

# ── 初始化 ────────────────────────────────────────────────
WORK="$(mktemp -d)"
MAJOR="${VERSION%%.*}"
DEST=$GITHUB_WORKSPACE/dest
BUILD_JDKS=$GITHUB_WORKSPACE/jdks
JAVA_VERSION=$BUNDLE_JAVA_VERSION
JDK_BASE_URL="$RELEASE_URL/$PNAME/jdk"
BUNDLE_PARALLEL="${BUNDLE_PARALLEL:-3}"
PKGS="$WORK/src"       # 重打包后的 no-jdk 包
OUT="$WORK/out"        # bundle 产物
FAIL_DIR="$WORK/fail"; LOGDIR="$WORK/logs"
mkdir -p "$DEST" "$BUILD_JDKS" "$PKGS" "$OUT" "$FAIL_DIR" "$LOGDIR"

echo "Prepar build bundle files for $PNAME version $VERSION (build number: $BUILD_NUMBER) using JDK: $(if [[ "$USE_GRAALVM" == "true" ]]; then echo GraalVM; else echo Zulu; fi)"
echo "OSS upload: $(should_upload_oss && echo enabled || echo SKIPPED) | stage artifacts: $(should_stage && echo yes || echo no) | parallel: $BUNDLE_PARALLEL"

# ── Plugin dependency map ─────────────────────────────────
declare -A PLUGIN_DEPS
PLUGIN_DEPS["ai"]="knn"
PLUGIN_DEPS["analysis-ik"]="ingest-common"

# ── Topological sort（依赖调用者作用域里的 _vis / _srt / raw_plugins）──
_topo_visit() {
  local node="$1"
  [[ "${_vis[$node]:-}" == "done" ]]     && return
  [[ "${_vis[$node]:-}" == "visiting" ]] && { echo "Error: circular dependency on '$node'" >&2; exit 1; }
  _vis[$node]="visiting"
  for dep in ${PLUGIN_DEPS[$node]:-}; do
    for p in "${raw_plugins[@]}"; do
      [[ "$p" == "$dep" ]] && { _topo_visit "$dep"; break; }
    done
  done
  _vis[$node]="done"
  _srt+=("$node")
}

# ── 并行下载 JDK ──────────────────────────────────────────
download_jdk() {
  local x="$1" EXT FILE
  if [[ "$USE_GRAALVM" == "true" ]]; then
    EXT=tar.gz; [[ $x == windows-* ]] && EXT=zip
    FILE=graalvm-jdk-${JAVA_VERSION}_${x}_bin.$EXT
    echo "Download GraalVM JDK with $JDK_BASE_URL/${JAVA_VERSION}/$FILE"
    if [ ! -e "$BUILD_JDKS/$FILE" ]; then
      wget -nv -t 3 "$JDK_BASE_URL/${JAVA_VERSION}/$FILE" -P "$BUILD_JDKS" || { rm -f "$BUILD_JDKS/$FILE"; return 1; }
    fi
  else
    FILE=$ZULU_JAVA_VERSION-$x.tar.gz
    if [ ! -e "$BUILD_JDKS/$FILE" ]; then
      wget -nv -t 3 "https://cdn.azul.com/zulu/bin/$FILE" -P "$BUILD_JDKS" || { rm -f "$BUILD_JDKS/$FILE"; return 1; }
    fi
  fi
}

MAX_PARALLEL=5
if [[ "$USE_GRAALVM" == "true" ]]; then
  JDK_PLATFORMS="linux-x64 linux-aarch64 macos-x64 macos-aarch64 windows-x64"
else
  JDK_PLATFORMS="linux_x64 linux_aarch64 macosx_x64 macosx_aarch64 win_x64"
fi
for x in $JDK_PLATFORMS; do run_bg "jdk-$x" download_jdk "$x"; done
finish_jobs || exit 1

echo "JDKs download complete"
ls -lrt $BUILD_JDKS

# 取出 release 阶段产出的 no-jdk 包（按平台名精确匹配，不再依赖 ls 排序）
cp -rf $DEST/$PNAME-$VERSION-$BUILD_NUMBER-* "$PKGS"

# ── 单个平台 bundle（在后台子 shell 中运行）───────────────
bundle_one() {
  local x="$1"
  local FNAME DNAME JARK JNAME W P TOP_DIR URL HTTP_STATUS
  local -a ITEMS
  # 这两个变量被 _topo_visit 通过动态作用域读写，必须是本函数的局部变量
  local -A _vis=()
  local -a _srt=() raw_plugins=()

  FNAME=$(ls "$PKGS" | grep -F -- "$PNAME-$VERSION-$BUILD_NUMBER-$x." | head -n 1)
  if [ -z "$FNAME" ]; then echo "Error: package for $x not found in $PKGS" >&2; return 1; fi
  case "$FNAME" in
    *.tar.gz) DNAME="${FNAME%.tar.gz}-bundle.tar.gz" ;;
    *.zip)    DNAME="${FNAME%.zip}-bundle.zip" ;;
    *)        echo "Error: unknown package type $FNAME" >&2; return 1 ;;
  esac

  if [[ "$USE_GRAALVM" == "true" ]]; then
    JARK=$(echo "$x" | sed -e 's/-amd64/-x64/;s/-arm64/-aarch64/;s/mac/macos/')
    JNAME=$(find $BUILD_JDKS -name "graalvm*_$JARK*" | head -n 1)
  else
    JARK=$(echo "$x" | sed -e 's/-amd64/_x64/;s/-arm64/_aarch64/;s/mac/macosx/;s/windows/win/')
    JNAME=$(find $BUILD_JDKS -name "$ZULU_JAVA_VERSION-$JARK*" | head -n 1)
  fi
  if [ -z "$JNAME" ]; then echo "Error: JDK for $x ($JARK) not found" >&2; return 1; fi

  URL="$RELEASE_URL/$PNAME/stable/bundle/$DNAME"
  HTTP_STATUS=$(curl -s -I -o /dev/null -w "%{http_code}" "$URL" || true)
  if [[ "$HTTP_STATUS" =~ ^2[0-9]{2}$ ]]; then
    echo "Exists release file $DNAME will overwrite it"
  fi
  echo -e "From: $FNAME \nTo:   $DNAME \nJark: $JARK \nJdk:  $JNAME"

  # 每个平台独立目录
  W="$WORK/job-$x"; P="$W/$PNAME"
  rm -rf "$W"; mkdir -p "$P" && cd "$P" || return 1
  echo "Current work directory: $(pwd)"

  # 解压
  if [ "${FNAME##*.}" == "gz" ]; then
    if [[ "$MAJOR" =~ ^[0-9]+$ && "$MAJOR" -ge 3 ]]; then
      tar -zxf "$PKGS/$FNAME" --strip-components=1 || return 1   # 3.x+：忽略最外层 $PNAME-$VERSION
    else
      tar -zxf "$PKGS/$FNAME" || return 1
    fi
  else
    unzip -q "$PKGS/$FNAME" || return 1
    if [[ "$MAJOR" =~ ^[0-9]+$ && "$MAJOR" -ge 3 ]]; then
      # zip 没有 strip 选项：把 $PNAME-$VERSION 里的内容提上来（含隐藏文件）
      shopt -s dotglob
      mv "$PNAME-$VERSION"/* . && rmdir "$PNAME-$VERSION"
      shopt -u dotglob
    fi
  fi

  # 配置 jdk
  if [[ "$USE_MACOS_TARGZ" == "true" && "$x" == mac-* ]]; then
    echo "Mac JDK detected, keep as tar.gz (no extract, no transform)"
  else
    if [ "${JNAME##*.}" == "gz" ]; then
      tar -zxf "$JNAME" || return 1
    else
      unzip -q "$JNAME" || return 1
    fi
  fi

  # plugin install need before bundle jdk
  if [ -z "$(ls -A $P/plugins 2>/dev/null)" ]; then
    # exclude some plugins for bundle: analysis-hanlp jieba
    # rules is linux-only (arch-specific zip), excluded for mac/windows
    raw_plugins=($(find $DEST/plugins -mindepth 1 -maxdepth 1 -type d \
      ! -name "analysis-hanlp" \
      ! -name "jieba" \
      $([ "${x%%\-*}" != "linux" ] && echo "! -name rules") \
      -exec basename {} \;))

    local p
    for p in "${raw_plugins[@]}"; do
      _topo_visit "$p"
    done
    echo "Plugin install order: ${_srt[*]}"

    local dist_dir zip RULES_PLAT
    local -a files
    for p in "${_srt[@]}"; do
      dist_dir="$DEST/plugins/$p"

      if [ "$p" = "rules" ]; then
        RULES_PLAT=$(echo "$x" | sed 's/-amd64/-x64/;s/-arm64/-aarch64/')
        files=(
          "$dist_dir/$p-$RULES_PLAT-$VERSION"*.zip
          "$dist_dir/$p-$VERSION-$RULES_PLAT"*.zip
        )
      else
        files=( "$dist_dir/$p-$VERSION"*.zip "$dist_dir/$p-"*"-$VERSION"*.zip )
      fi

      for zip in "${files[@]}"; do
        [ -f "$zip" ] || continue
        echo "Installing plugin $zip ..."
        if $P/bin/$PNAME-plugin install --batch "file:///$zip"; then
          echo "Plugin $p installed successfully."
        else
          echo "Error: Failed to install plugin $p" >&2
          return 1
        fi
      done
    done
  fi

  # Copy the JDK to the expected location
  if [[ "$USE_MACOS_TARGZ" == "true" && "$x" == mac-* ]]; then
    mv "$JNAME" $P/jdk.tar.gz
  else
    if [[ "$USE_GRAALVM" == "true" ]]; then
      mv graalvm* $P/jdk || return 1
    else
      mv zulu* $P/jdk || return 1
    fi
  fi

  # 重新打包
  if [[ "$MAJOR" =~ ^[0-9]+$ && "$MAJOR" -ge 3 ]]; then
    # 3.x+：包内多一层 $PNAME-$VERSION
    TOP_DIR="$PNAME-$VERSION"
    mkdir "$TOP_DIR"
    local f
    for f in *; do [ "$f" = "$TOP_DIR" ] || mv "$f" "$TOP_DIR"/; done
    ITEMS=("$TOP_DIR")
  else
    ITEMS=(*)
  fi

  if [ "${DNAME##*.}" == "gz" ]; then
    tar -zcf "$OUT/$DNAME" "${ITEMS[@]}" || return 1
  else
    zip -r -q "$OUT/$DNAME" "${ITEMS[@]}" || return 1
  fi
  echo "Repackaged file at $OUT/$DNAME"

  # 释放该平台的解压空间
  cd "$WORK" && rm -rf "$W"
}

MAX_PARALLEL="$BUNDLE_PARALLEL"
for x in linux-amd64 linux-arm64 mac-amd64 mac-arm64 windows-amd64; do
  run_bg "bundle-$x" bundle_one "$x"
done
finish_jobs || exit 1

# ── 上传 / 暂存（串行）────────────────────────────────────
if is_true "$PRE_RELEASE"; then BUNDLE_KEY="$PNAME/snapshot/bundle"; else BUNDLE_KEY="$PNAME/stable/bundle"; fi

for f in "$OUT"/*; do
  [ -f "$f" ] || continue
  DNAME=$(basename "$f")
  (cd "$OUT" && sha512sum "$DNAME" > "$DNAME.sha512")

  # 平台标识：easysearch-<ver>-<build>-<plat>-bundle.<ext> -> <plat>
  PLAT="${DNAME#$PNAME-$VERSION-$BUILD_NUMBER-}"; PLAT="${PLAT%%-bundle*}"

  if should_upload_oss; then
    echo "$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S') INFO Upload $DNAME to OSS"
    oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $OUT/$DNAME -k $BUNDLE_KEY
    oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $OUT/$DNAME.sha512 -k $BUNDLE_KEY
  else
    echo "Skip OSS upload for $DNAME (SKIP_OSS_UPLOAD=${SKIP_OSS_UPLOAD:-} ONLY_DOCKER=${ONLY_DOCKER:-})"
  fi

  if should_stage; then
    echo "Stage artifact bundle-$PLAT <- $DNAME"
    stage_file "bundle-$PLAT" "" "$OUT/$DNAME"
    stage_file "bundle-$PLAT" "" "$OUT/$DNAME.sha512"
  fi
done

rm -rf "$WORK"
