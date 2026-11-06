#!/bin/zsh
# P2: 用 protoc + protoc-gen-swift 把 Android 端 protos 编译成 Swift
# 产物: ios/Generated/Protos/*.swift（不手改）
set -e
IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/.." && pwd)"
TOOLS_DIR="$IOS_DIR/.tools"
PROTO_SRC="$REPO_DIR/app/src/main/protos"
OUT_DIR="$IOS_DIR/Generated/Protos"
PROTOC="$TOOLS_DIR/protoc/bin/protoc"
GEN_SWIFT="$TOOLS_DIR/swift-protobuf/.build/release/protoc-gen-swift"

[ -x "$PROTOC" ] || { echo "缺少 protoc，先运行 bootstrap_tools.sh"; exit 1; }
[ -x "$GEN_SWIFT" ] || { echo "缺少 protoc-gen-swift，先运行 bootstrap_tools.sh"; exit 1; }
[ -d "$PROTO_SRC" ] || { echo "缺少 proto 源目录 $PROTO_SRC"; exit 1; }

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# 收集全部 proto（根目录 + 子目录），-I 同时提供两个根以支持相对 import
PROTO_FILES=()
for f in "$PROTO_SRC"/*.proto; do
  [ -e "$f" ] && PROTO_FILES+=("$f")
done
for f in "$PROTO_SRC"/*/*.proto; do
  [ -e "$f" ] && PROTO_FILES+=("$f")
done
echo "共 ${#PROTO_FILES[@]} 个 proto 文件"

# 生成（--swift_opt=FileNaming=FullPath 避免子目录同名文件冲突）
"$PROTOC" \
  --plugin="$GEN_SWIFT" \
  --swift_out="$OUT_DIR" \
  --swift_opt=FileNaming=FullPath \
  -I "$PROTO_SRC" \
  "${PROTO_FILES[@]}"

echo "生成 $(find "$OUT_DIR" -name '*.swift' | wc -l | tr -d ' ') 个 Swift 文件"
echo "总行数: $(find "$OUT_DIR" -name '*.swift' -exec cat {} + | wc -l | tr -d ' ')"
