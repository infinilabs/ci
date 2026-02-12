#!/bin/bash
set -e

# This script creates uber JARs by merging native libraries from platform-specific JARs
# 
# Usage:
#   ./create-uber-jars.sh [options]
#
# Options:
#   --static          Create static uber JAR only
#   --dynamic         Create dynamic uber JAR only
#   --sources         Create sources uber JAR only
#   --javadoc         Create javadoc uber JAR only
#   --all             Create all uber JARs (default)
#
# Environment variables:
#   VERSION           Maven artifact version (default: 1.0.0)
#   ARTIFACT_ID       Maven artifact ID (default: tongsuo-openjdk)
#   REPO_PATH         Path to Maven repository with platform JARs (default: .)
#   TEMP_DIR          Temporary work directory (default: uber-temp)

# Parse command line arguments
CREATE_STATIC=false
CREATE_DYNAMIC=false
CREATE_SOURCES=false
CREATE_JAVADOC=false
CREATE_ALL=true

while [[ $# -gt 0 ]]; do
  case $1 in
    --static)
      CREATE_STATIC=true
      CREATE_ALL=false
      shift
      ;;
    --dynamic)
      CREATE_DYNAMIC=true
      CREATE_ALL=false
      shift
      ;;
    --sources)
      CREATE_SOURCES=true
      CREATE_ALL=false
      shift
      ;;
    --javadoc)
      CREATE_JAVADOC=true
      CREATE_ALL=false
      shift
      ;;
    --all)
      CREATE_ALL=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--static] [--dynamic] [--sources] [--javadoc] [--all]"
      exit 1
      ;;
  esac
done

# If --all or no specific options, create everything
if [ "$CREATE_ALL" = true ]; then
  CREATE_STATIC=true
  CREATE_DYNAMIC=true
  CREATE_SOURCES=true
  CREATE_JAVADOC=true
fi

VERSION="${VERSION:-1.0.0}"
ARTIFACT_ID="${ARTIFACT_ID:-tongsuo-openjdk}"
REPO_PATH="${REPO_PATH:-.}"
TEMP_DIR="${TEMP_DIR:-uber-temp}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Creating Uber JARs from available platforms"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Version:      $VERSION"
echo "Artifact ID:  $ARTIFACT_ID"
echo "Repo Path:    $REPO_PATH"
echo "Create:"
echo "  Static:     $CREATE_STATIC"
echo "  Dynamic:    $CREATE_DYNAMIC"
echo "  Sources:    $CREATE_SOURCES"
echo "  Javadoc:    $CREATE_JAVADOC"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p "$TEMP_DIR"
cd "$REPO_PATH"

# Detect available platform JARs
STATIC_JARS=()
DYNAMIC_JARS=()

echo ""
echo "🔍 Detecting available platform JARs..."
for jar in *.jar; do
  [ -f "$jar" ] || continue
  
  # Skip sources and javadoc JARs
  [[ "$jar" == *-sources.jar ]] && continue
  [[ "$jar" == *-javadoc.jar ]] && continue
  
  # Classify as static or dynamic
  if [[ "$jar" == *-dynamic.jar ]]; then
    DYNAMIC_JARS+=("$jar")
    echo "  ✓ Dynamic: $jar"
  else
    STATIC_JARS+=("$jar")
    echo "  ✓ Static:  $jar"
  fi
done

# Function to create uber JAR from platform JARs
create_uber_jar() {
  local jar_type="$1"
  local output_jar="$2"
  local platform_jars=("${@:3}")
  
  if [ ${#platform_jars[@]} -eq 0 ]; then
    echo "⚠️  No $jar_type platform JARs - skipping $jar_type uber"
    return
  fi
  
  echo ""
  echo "📦 Creating $jar_type Uber JAR from ${#platform_jars[@]} platform(s)..."
  
  local work_base="$TEMP_DIR/${jar_type}-base"
  local work_temp="$TEMP_DIR/${jar_type}-temp"
  
  mkdir -p "$work_base"
  mkdir -p "$work_temp"
  cd "$work_base"
  
  # Extract first JAR to get base structure (classes, resources, etc.)
  local first_jar="${platform_jars[0]}"
  echo "   Using $first_jar as base..."
  unzip -q "$REPO_PATH/$first_jar"
  
  # Extract native libraries from all platform JARs
  for jar in "${platform_jars[@]}"; do
    echo "   Extracting native libraries from $jar..."
    cd "$work_temp"
    unzip -q "$REPO_PATH/$jar" "META-INF/native/*" 2>/dev/null || true
    if [ -d META-INF/native ]; then
      mkdir -p "$work_base/META-INF/native"
      cp -v META-INF/native/* "$work_base/META-INF/native/" 2>/dev/null || true
      rm -rf META-INF
    fi
  done
  
  # Create enhanced MANIFEST.MF
  cd "$work_base"
  local platform_list=$(printf '%s,' "${platform_jars[@]}" | sed 's/,$//' | sed 's/.jar//g')
  
  cat > META-INF/MANIFEST.MF << EOF
Manifest-Version: 1.0
Implementation-Title: Tongsuo Java SDK (${jar_type^} Uber)
Implementation-Version: ${VERSION}
Implementation-Vendor: Infinilabs
Jar-Type: uber-${jar_type}
Platforms: ${platform_list}
EOF
  
  # Create uber JAR
  jar cfm "$REPO_PATH/$output_jar" META-INF/MANIFEST.MF .
  
  local native_count=$(find META-INF/native -type f 2>/dev/null | wc -l)
  echo "✅ $jar_type Uber JAR: $output_jar"
  echo "   Size: $(du -h "$REPO_PATH/$output_jar" | cut -f1)"
  echo "   Native libraries: $native_count"
  
  cd "$REPO_PATH"
}

# Function to create uber JAR from same-type JARs (sources/javadoc)
create_simple_uber_jar() {
  local jar_type="$1"
  local output_jar="$2"
  local pattern="$3"
  
  echo ""
  echo "📦 Creating Uber $jar_type JAR..."
  mkdir -p "$TEMP_DIR/$jar_type"
  cd "$TEMP_DIR/$jar_type"
  
  local count=0
  for jar in "$REPO_PATH"/$pattern; do
    if [ -f "$jar" ]; then
      count=$((count + 1))
      echo "   Extracting $(basename $jar)..."
      jar xf "$jar"
    fi
  done
  
  if [ $count -gt 0 ]; then
    jar cf "$REPO_PATH/$output_jar" .
    echo "✅ $jar_type Uber JAR: $output_jar ($(du -h "$REPO_PATH/$output_jar" | cut -f1))"
  else
    echo "⚠️  No $jar_type JARs found"
  fi
  
  cd "$REPO_PATH"
}

# 1. Create Static Uber JAR
if [ "$CREATE_STATIC" = true ]; then
  create_uber_jar "static" "$ARTIFACT_ID-$VERSION.jar" "${STATIC_JARS[@]}"
fi

# 2. Create Dynamic Uber JAR
if [ "$CREATE_DYNAMIC" = true ]; then
  create_uber_jar "dynamic" "$ARTIFACT_ID-$VERSION-dynamic.jar" "${DYNAMIC_JARS[@]}"
fi

# 3. Create Sources Uber JAR
if [ "$CREATE_SOURCES" = true ]; then
  create_simple_uber_jar "Sources" "$ARTIFACT_ID-$VERSION-sources.jar" "*-sources.jar"
fi

# 4. Create Javadoc Uber JAR
if [ "$CREATE_JAVADOC" = true ]; then
  create_simple_uber_jar "Javadoc" "$ARTIFACT_ID-$VERSION-javadoc.jar" "*-javadoc.jar"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Uber JAR creation completed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
