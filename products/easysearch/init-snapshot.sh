#!/bin/bash
set -e

cd "$GITHUB_WORKSPACE/$PNAME"

# 1. 生成快照版本号

BASE_VERSION=$(echo "$PUBLISH_VERSION" | awk -F- '{print $1}')
echo "Snapshot build $BUILD_TYPE with base version is $BASE_VERSION"
if [[ "$BUILD_TYPE" == "schedule" ]]; then
  SNAPSHOT_VERSION=$(echo "$BASE_VERSION" | awk -F'[._]' -v OFS=. '{ $2 = $2 + 1; $3 = 0; print $1, $2, $3 }')
else
  SNAPSHOT_VERSION=$(echo "$BASE_VERSION" | awk -F'[._]' -v OFS=. '{ $3 = $3; print $1, $2, $3 }')
fi

echo "Snapshot build $BUILD_TYPE with version: $SNAPSHOT_VERSION"

# 2. 转换为 Java 变量名 (V_x_y_z)
JVER=$(echo "$SNAPSHOT_VERSION" | tr '.' '_' | awk '{print "V_"$0}')

# 3. 提取 major, minor, revision
IFS='.' read -r major minor revision <<< "$SNAPSHOT_VERSION"

# 4. 计算版本 ID (build 固定为 99)
id=$((major * 1000000 + minor * 10000 + revision * 100 + 99))

# 5. 获取 Lucene 版本 (从最后一个 Version 定义中提取)
FVER="server/src/main/java/org/easysearch/Version.java"
LUCENE_VERSION=$(grep -Po 'public static final Version V_.*?\.LUCENE_\K[^)]+' "$FVER" | tail -n 1)
echo "Lucene version: $LUCENE_VERSION"

# 6. 检查 Version.java 中是否已存在该版本
if ! grep -q "public static final Version $JVER " "$FVER"; then
  echo "Version $JVER not found in $FVER. Adding..."

  # 7. 构建新的版本定义行
  snapshot_version_line="    public static final Version $JVER = new Version($id, org.apache.lucene.util.Version.LUCENE_$LUCENE_VERSION);"

  # 8. 找到已发布的版本定义，并在其下一行插入快照版本定义
  PUBLISH_JVER=$(echo "$BASE_VERSION" | tr '.' '_' | awk '{print "V_"$0}')
  sed -i "/public static final Version $PUBLISH_JVER /a\\$snapshot_version_line" "$FVER"
fi

# 9. 更新 CURRENT
sed -i "s/public static final Version CURRENT.*/public static final Version CURRENT = $JVER;/" "$FVER"

# 10. 更新 buildSrc/version.properties
sed -i "s/^[# ]*easysearch *[=].*/easysearch     = $SNAPSHOT_VERSION/" "buildSrc/version.properties"

# 11. 取消注释并设置 build_snapshot = true
sed -i "s/^#*build_snapshot *=.*/build_snapshot = true/" "buildSrc/version.properties"

echo "Snapshot version update $SNAPSHOT_VERSION complete."