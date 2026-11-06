#!/bin/zsh
# P1 工具链准备：protoc(预编译) + swift-protobuf(源码构建 protoc-gen-swift) + Temurin JDK17(测试向量)
# 全部下载物放 ios/.tools/（已 gitignore）。默认走 Clash 代理 7890。
set -e
TOOLS_DIR="$(cd "$(dirname "$0")/.." && pwd)/.tools"
PROXY="${CLASH_PROXY:-http://127.0.0.1:7890}"
mkdir -p "$TOOLS_DIR"/{downloads,protoc,swift-protobuf,jdk}
cd "$TOOLS_DIR"

curl_() { # curl_ <output> <url>  先代理后直连
  local out="$1" url="$2"
  if curl -sfL --connect-timeout 10 -x "$PROXY" -o "$out" "$url"; then
    echo "[proxy] $url"
  else
    echo "[direct] $url"
    curl -fL --connect-timeout 15 -o "$out" "$url"
  fi
}

# 1) protoc 预编译 (osx-x86_64)
if [ ! -x protoc/bin/protoc ]; then
  echo "== 查询 protoc 最新版本 =="
  VER_JSON=$(curl_ - "https://api.github.com/repos/protocolbuffers/protobuf/releases/latest")
  PROTOC_URL=$(echo "$VER_JSON" | /usr/bin/python3 -c "import sys,json;assets=json.load(sys.stdin)['assets'];print(next(a['browser_download_url'] for a in assets if 'osx-x86_64.zip' in a['name'] and 'protoc' in a['name']))")
  echo "protoc: $PROTOC_URL"
  curl_ downloads/protoc.zip "$PROTOC_URL"
  rm -rf protoc && mkdir -p protoc && tar -xf downloads/protoc.zip -C protoc
  chmod +x protoc/bin/protoc
  protoc/bin/protoc --version
else
  echo "protoc 已就绪"
fi

# 2) swift-protobuf 浅克隆（固定最新 release tag）
if [ ! -d swift-protobuf/.git ]; then
  SP_TAG=$(curl_ - "https://api.github.com/repos/apple/swift-protobuf/releases/latest" | /usr/bin/python3 -c "import sys,json;print(json.load(sys.stdin)['tag_name'])")
  echo "swift-protobuf tag: $SP_TAG"
  git clone --depth 1 --branch "$SP_TAG" https://github.com/apple/swift-protobuf.git swift-protobuf
else
  echo "swift-protobuf 已克隆"
fi

# 3) Temurin JDK 17 (x64 mac, tar.gz) — 用于运行 Android 端 helios Java 源码生成测试向量
if [ ! -x jdk/jdk*/Contents/Home/bin/java ] 2>/dev/null && ! ls jdk/jdk*/Contents/Home/bin/java >/dev/null 2>&1; then
  echo "== 下载 Temurin 17 =="
  curl_ downloads/jdk17.tar.gz "https://api.adoptium.net/v3/binary/latest/17/ga/mac/x64/jdk/hotspot/normal/eclipse?project=jdk"
  tar -xzf downloads/jdk17.tar.gz -C jdk
  ls jdk/
else
  echo "JDK 已就绪"
fi

echo "== 全部下载完成 =="
ls -R "$TOOLS_DIR" | head -30
