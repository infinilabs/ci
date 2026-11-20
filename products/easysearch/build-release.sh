#!/bin/bash

# =====================================================================
# build-release.sh
#   1. 5 个平台的包并行重打包（后台任务 + 独立工作目录）
#   2. OSS 上传可通过 SKIP_OSS_UPLOAD / ONLY_DOCKER 跳过
#   3. STAGE_ARTIFACTS=true 时，把产物按「每个包一个目录」暂存到
#      $GITHUB_WORKSPACE/artifacts/<artifact-name>/，由 workflow 分别上传
#      artifact 名称：pkg-<platform>、plugins
# =====================================================================

# ── 通用函数 ──────────────────────────────────────────────
is_true() { [[ "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" == "true" ]]; }

# release 且 非 ONLY_DOCKER 且 未显式跳过 才上传 OSS
should_upload_oss() {
  is_true "${PUBLISH_STABLE:-}" && ! is_true "${ONLY_DOCKER:-}" && ! is_true "${SKIP_OSS_UPLOAD:-}"
}
should_stage() { is_true "${STAGE_ARTIFACTS:-}" && ! is_true "${ONLY_DOCKER:-}"; }

ART="$GITHUB_WORKSPACE/artifacts"
# stage_file <artifact-name> <子目录(可空)> <文件>   优先硬链接，避免多占一份磁盘
stage_file() {
  local name="$1" sub="$2" f="$3"
  mkdir -p "$ART/$name/$sub"
  ln -f "$f" "$ART/$name/$sub/" 2>/dev/null || cp -f "$f" "$ART/$name/$sub/"
}

# ── 并行任务工具 ──────────────────────────────────────────
MAX_PARALLEL="${MAX_PARALLEL:-5}"
FAIL_DIR=""; LOGDIR=""
throttle() { while (( $(jobs -rp | wc -l) >= MAX_PARALLEL )); do wait -n 2>/dev/null || true; done; }
# run_bg <label> <function> [args...]   日志写到文件，结束后统一按 group 打印
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
WORKDIR="$(mktemp -d)"
SRC=$GITHUB_WORKSPACE/$PNAME
DEST=$GITHUB_WORKSPACE/dest
PKGS="$WORKDIR/src"      # gradle 产出的原始包（只读使用）
OUT="$WORKDIR/out"       # 重打包产物
SHA="$WORKDIR/sha"       # sha512 文件（不放进 DEST，避免被 bundle 脚本的通配符误选）
FAIL_DIR="$WORKDIR/fail"; LOGDIR="$WORKDIR/logs"
mkdir -p "$DEST" "$PKGS" "$OUT" "$SHA" "$FAIL_DIR" "$LOGDIR"

echo "Prepar build release files"
echo "Repack $PNAME from $SRC to $DEST with [ $VERSION-$BUILD_NUMBER ]"
echo "OSS upload: $(should_upload_oss && echo enabled || echo SKIPPED) | stage artifacts: $(should_stage && echo yes || echo no)"

# 查找符合条件的文件
FOUND_FILES=$(find "$SRC/distribution/archives/oss-no-jdk-linux-tar/build/distributions" -name "$PNAME-oss-*.tar.gz" -type f -print -quit)
if [ -z "$FOUND_FILES" ]; then
  echo "Error: $PNAME distribution files not found exit now."
  exit 1
fi

cp -rf $SRC/distribution/archives/oss-no-jdk-*/build/distributions/$PNAME-oss* "$PKGS"
ls -lrt "$PKGS"

# ── 单个平台重打包（在后台子 shell 中运行）────────────────
pack() {  # pack <输出文件绝对路径> <条目...>
  local out="$1"; shift
  if [[ "$out" == *.gz ]]; then tar -zcf "$out" "$@"; else zip -r -q "$out" "$@"; fi
}

repack_one() {
  local FNAME="$1"
  local MAJOR="${VERSION%%.*}" TOP_DIR="$PNAME-$VERSION"
  local W ONAME
  W="$(mktemp -d -p "$WORKDIR" job.XXXXXX)" || return 1

  ONAME=$(echo "$FNAME" | sed "s/$VERSION/$VERSION-$BUILD_NUMBER/" | sed 's/darwin/mac/;s/aarch64/arm64/;s/x86_64/amd64/' | awk -F'-' '{print $1"-"$3"-"$4"-"$(NF-1)"-"$NF}')

  cd "$W" || return 1
  # 解压
  if [ "${FNAME##*.}" == "gz" ]; then tar -zxf "$PKGS/$FNAME" || return 1; else unzip -q "$PKGS/$FNAME" || return 1; fi

  # mac 平台的 tar.gz 改为 zip
  if [ "${FNAME##*.}" == "gz" ] && [[ "$ONAME" == *-mac-* ]]; then
    ONAME="${ONAME%.tar.gz}.zip"
  fi

  # 重新打包
  if [[ "$MAJOR" =~ ^[0-9]+$ && "$MAJOR" -ge 3 ]]; then
    # 3.x+：包内保留 $TOP_DIR 这一层
    pack "$OUT/$ONAME" "$TOP_DIR" || return 1
  else
    # 1.x/2.x：包内没有顶层目录
    cd "$TOP_DIR" || return 1
    pack "$OUT/$ONAME" * || return 1
  fi
  echo -e "Repackaged file at $OUT/$ONAME \nfrom $FNAME \nto $ONAME"
  rm -rf "$W"
}

# 并行：每个平台一个后台任务
for f in "$PKGS"/$PNAME-oss*; do
  [ -f "$f" ] || continue
  run_bg "repack-$(basename "$f")" repack_one "$(basename "$f")"
done
finish_jobs || exit 1

# ── 上传 / 暂存（串行：OSS 带宽有限，并发上传不会更快）────
if should_upload_oss; then
  [ ! -f /tmp/.oss.yml ] && cp -rf $GITHUB_WORKSPACE/.oss.yml /tmp
  if is_true "$PRE_RELEASE"; then
    grep -wq "pre" /tmp/.oss.yml || echo "pre: true" >> /tmp/.oss.yml
  fi
fi

for f in "$OUT"/*; do
  [ -f "$f" ] || continue
  ONAME=$(basename "$f")
  mv "$f" "$DEST/"

  # 平台标识：easysearch-<ver>-<build>-<plat>.<ext> -> <plat>
  PLAT="${ONAME#$PNAME-$VERSION-$BUILD_NUMBER-}"; PLAT="${PLAT%.tar.gz}"; PLAT="${PLAT%.zip}"
  (cd "$DEST" && sha512sum "$ONAME" > "$SHA/$ONAME.sha512")

  if should_upload_oss; then
    echo Upload $ONAME to oss
    oss upload -c /tmp/.oss.yml -o -p $PNAME -f "$DEST/$ONAME"
    oss upload -c /tmp/.oss.yml -o -p $PNAME -f "$SHA/$ONAME.sha512"
  else
    echo "Skip OSS upload for $ONAME (SKIP_OSS_UPLOAD=${SKIP_OSS_UPLOAD:-} ONLY_DOCKER=${ONLY_DOCKER:-})"
  fi

  if should_stage; then
    echo "Stage artifact pkg-$PLAT <- $ONAME"
    stage_file "pkg-$PLAT" "" "$DEST/$ONAME"
    stage_file "pkg-$PLAT" "" "$SHA/$ONAME.sha512"
  fi
done

# ── 插件 exclude some plugins for release fast-terms filter-distinct ──
plugins=($(find $SRC/plugins -mindepth 1 -maxdepth 1 -type d \
  ! -name "fast-terms" \
  ! -name "filter-distinct" \
  -exec basename {} \;))
for q in "${plugins[@]}"; do
  p=$q
  if [ "$p" == "search-sql" ]; then
    p=sql
  fi

  if [ ! -d $DEST/plugins/$p ]; then
    mkdir -p $DEST/plugins/$p
  fi

  if [ "$p" == "sql" ]; then
    JAR_DIR="$SRC/plugins/$q/sql-jdbc/build/libs"
    JAR="sql-jdbc-$VERSION.jar"
    (cd "$JAR_DIR" && sha512sum "$JAR" > "$JAR.sha512")
    if should_upload_oss; then
      echo Upload $JAR_DIR/$JAR to oss
      oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $JAR_DIR/$JAR -k $PNAME/archive/plugins
      oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $JAR_DIR/$JAR.sha512 -k $PNAME/archive/plugins
    else
      echo "Skip OSS upload for $JAR"
    fi
    if [ ! -d $DEST/archive/plugins ]; then
      mkdir -p $DEST/archive/plugins
    fi
    cp -rf $JAR_DIR/$JAR $DEST/archive/plugins
    if should_stage; then
      stage_file plugins archive/plugins "$DEST/archive/plugins/$JAR"
      stage_file plugins archive/plugins "$JAR_DIR/$JAR.sha512"
    fi
  fi

  dist_dir="$SRC/plugins/$q/build/distributions"
  files=( "$dist_dir/$p-$VERSION"*.zip "$dist_dir/$p-"*"-$VERSION"*.zip )

  for zip in "${files[@]}"; do
    if [ -e "$zip" ]; then
      filename=$(basename "$zip")
      f="$DEST/plugins/$p/$filename"

      echo "Processing plugin file: $zip"
      cp -rf "$zip" "$f"
      (cd "$(dirname "$f")" && sha512sum "$filename" > "$filename.sha512")

      if should_upload_oss; then
        echo "Upload plugin $filename to oss"
        oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $f -k $PNAME/stable/plugins/$p
        oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $f.sha512 -k $PNAME/stable/plugins/$p
      else
        echo "Skip OSS upload for plugin $filename"
      fi

      if should_stage; then
        stage_file plugins "plugins/$p" "$f"
        stage_file plugins "plugins/$p" "$f.sha512"
      fi
    fi
  done
done

rm -rf "$WORKDIR"
echo
