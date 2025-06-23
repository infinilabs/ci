#!/bin/bash

# 设置 Go 源码基础路径
GOSRC="$HOME/go/src"

# 确保基础路径存在
mkdir -p "$GOSRC" || { echo "Error: Failed to create base directory $GOSRC"; exit 1; }

# 定义一个函数来克隆仓库，包含检查和父目录创建
clone_repo() {
  local repo_url="$1"
  local target_path="$2"
  local target_dir="$GOSRC/$target_path"
  local parent_dir

  # 获取父目录路径
  parent_dir=$(dirname "$target_dir")

  echo "Processing $target_path..."

  # 确保父目录存在
  if [ ! -d "$parent_dir" ]; then
    echo "  Creating parent directory: $parent_dir"
    mkdir -p "$parent_dir" || { echo "  Error: Failed to create parent directory $parent_dir"; return 1; }
  fi

  # 检查目标目录是否已存在
  if [ ! -d "$target_dir" ]; then
    echo "  Cloning $repo_url into $target_dir"
    # 执行克隆，--depth 1 只获取最新提交，加快速度
    git clone --quiet --depth 1 "$repo_url" "$target_dir" || { echo "  Error: Failed to clone $repo_url"; return 1; }
    echo "  Successfully cloned $target_path."
  else
    echo "  Directory $target_dir already exists, skipping clone."
  fi
  echo
  return 0
}

# --- 开始克隆仓库 ---

# Google Cloud & Related (GitHub SSH)
clone_repo "git@github.com:googleapis/google-cloud-go.git"                 "cloud.google.com/go"
clone_repo "git@github.com:felixge/httpsnoop.git"                          "github.com/felixge/httpsnoop"
clone_repo "git@github.com:golang/groupcache.git"                          "github.com/golang/groupcache"
clone_repo "git@github.com:google/s2a-go.git"                              "github.com/google/s2a-go"
clone_repo "git@github.com:google/uuid.git"                                "github.com/google/uuid"
clone_repo "git@github.com:googleapis/enterprise-certificate-proxy.git"    "github.com/googleapis/enterprise-certificate-proxy"
clone_repo "git@github.com:googleapis/gax-go.git"                          "github.com/googleapis/gax-go"
clone_repo "git@github.com:go-logr/logr.git"                               "github.com/go-logr/logr"
clone_repo "git@github.com:go-logr/stdr.git"                               "github.com/go-logr/stdr"

# Mcp
clone_repo "git@github.com:mark3labs/mcp-go.git"                            "github.com/mark3labs/mcp-go"
clone_repo "git@github.com:i2y/langchaingo-mcp-adapter.git"                 "github.com/i2y/langchaingo-mcp-adapter"
clone_repo "git@github.com:yosida95/uritemplate.git"                        "github.com/yosida95/uritemplate"
clone_repo "git@github.com:gocolly/colly.git"                               "github.com/gocolly/colly"
clone_repo "git@github.com:antchfx/htmlquery.git"                           "github.com/antchfx/htmlquery"
clone_repo "git@github.com:antchfx/xmlquery.git"                            "github.com/antchfx/xmlquery"
clone_repo "git@github.com:gobwas/glob.git"                                 "github.com/gobwas/glob"
clone_repo "git@github.com:kennygrant/sanitize.git"                         "github.com/kennygrant/sanitize"
clone_repo "git@github.com:nlnwa/whatwg-url.git"                            "github.com/nlnwa/whatwg-url"
clone_repo "git@github.com:saintfish/chardet.git"                           "github.com/saintfish/chardet"
clone_repo "git@github.com:temoto/robotstxt.git"                            "github.com/temoto/robotstxt"
clone_repo "git@github.com:antchfx/xpath.git"                               "github.com/antchfx/xpath"

# OpenCensus/OpenTelemetry (GitHub SSH)
clone_repo "git@github.com:census-instrumentation/opencensus-go.git"            "go.opencensus.io"
clone_repo "git@github.com:open-telemetry/opentelemetry-go-contrib.git"         "go.opentelemetry.io/contrib"
clone_repo "git@github.com:open-telemetry/opentelemetry-go.git"                 "go.opentelemetry.io/otel"
clone_repo "git@github.com:open-telemetry/opentelemetry-go-instrumentation.git" "go.opentelemetry.io/auto"

# Google APIs & gRPC (GitHub SSH)
clone_repo "git@github.com:googleapis/google-api-go-client.git"            "google.golang.org/api"
clone_repo "git@github.com:googleapis/go-genproto.git"                     "google.golang.org/genproto"
clone_repo "git@github.com:grpc/grpc-go.git"                               "google.golang.org/grpc"
clone_repo "git@github.com:protocolbuffers/protobuf-go.git"                "google.golang.org/protobuf"
clone_repo "git@github.com:golang/appengine.git"                           "google.golang.org/appengine"

# Golang Sub-repositories (Googlesource HTTPS)
clone_repo "https://go.googlesource.com/sys.git"                            "golang.org/x/sys"
clone_repo "https://go.googlesource.com/net.git"                            "golang.org/x/net"
clone_repo "https://go.googlesource.com/text.git"                           "golang.org/x/text"
clone_repo "https://go.googlesource.com/image.git"                          "golang.org/x/image"
clone_repo "https://go.googlesource.com/oauth2.git"                         "golang.org/x/oauth2"
clone_repo "https://go.googlesource.com/crypto.git"                         "golang.org/x/crypto"

echo "--- Repository cloning process finished. ---"

# 检查是否有失败的克隆 (简单检查)
# 注意: 这不会捕获所有可能的错误，更健壮的脚本需要更复杂的错误处理
if [[ $(jobs -p | wc -l) -gt 0 ]]; then
  echo "Warning: Some clone operations might have failed (check output above)."
fi

exit 0