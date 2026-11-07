#!/bin/zsh
# 构建仅包含 adhoc 签名的 ipa（本项目唯一交付构建方式，见 AGENTS.md）
# 产物: ios/build/TiebaLite-adhoc.ipa
#
# 关键事实（本机 Xcode 26.6 / iOS 26.5 SDK 实测）：
# - xcodebuild 直接用 CODE_SIGN_IDENTITY="-" 报错
#   "Ad Hoc code signing is not allowed with SDK 'iOS 26.5'"
# - 可行路径：CODE_SIGNING_ALLOWED=NO 构建 → codesign --sign - 手动 adhoc 签名
# 验收（全部走退出码，不打印即失败）：
#   Signature=adhoc；TeamIdentifier=not set；无 embedded.mobileprovision；
#   codesign --verify --strict 通过；签名身份列表无其他证书
set -euo pipefail
IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$IOS_DIR"
BUILD_DIR="$IOS_DIR/build"
APP_NAME="TiebaLite"

echo "== 1) 未签名 Release 构建（真机 arm64）=="
xcodebuild \
  -project TiebaLite.xcodeproj \
  -scheme TiebaLite \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
echo "构建退出码 0"

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "❌ 未找到 .app: $APP_PATH"; exit 1; }

echo "== 2) 手动 adhoc 签名（嵌套代码先签，自内向外）=="
# 未来若引入嵌套 framework/dylib，必须先签（codesign 不递归）
find "$APP_PATH" -depth 2 \( -name "*.framework" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' nested; do
  echo "  签名嵌套: $(basename "$nested")"
  codesign --force --sign - --timestamp=none "$nested"
done
codesign --force --sign - --timestamp=none "$APP_PATH"

echo "== 3) 签名验收（退出码驱动）=="
SIG_LINE="$(codesign -dv "$APP_PATH" 2>&1 | grep '^Signature=')"
echo "$SIG_LINE"
[ "$SIG_LINE" = "Signature=adhoc" ] || { echo "❌ Signature 不是 adhoc: $SIG_LINE"; exit 1; }
codesign -dv "$APP_PATH" 2>&1 | grep -q '^TeamIdentifier=not set$' \
  || { echo "❌ TeamIdentifier 异常"; exit 1; }
codesign --verify --strict "$APP_PATH"
echo "✅ strict 校验通过"
# 确认签名身份列表无其他证书（adhoc 无 identity）
security find-identity -v -p codesigning >/dev/null 2>&1 || true
if codesign -dvv "$APP_PATH" 2>&1 | grep -q "Authority=Apple"; then
  echo "❌ 检测到 Apple 证书链（不应存在）"; exit 1
fi
echo "✅ 仅 adhoc（无其他证书/描述文件）"

echo "== 4) 组装 ipa =="
rm -rf "$BUILD_DIR/Payload" "$BUILD_DIR/$APP_NAME-adhoc.ipa"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && zip -qry "$APP_NAME-adhoc.ipa" Payload)

echo "== 5) 验收 ipa =="
if unzip -l "$BUILD_DIR/$APP_NAME-adhoc.ipa" | grep -q "embedded.mobileprovision"; then
  echo "❌ 包内含 embedded.mobileprovision（不应存在）"; exit 1
fi
echo "✅ 无 embedded.mobileprovision"
# 复核包内二进制签名仍是 adhoc
TMP_CHECK="$(mktemp -d)"
unzip -q "$BUILD_DIR/$APP_NAME-adhoc.ipa" "Payload/$APP_NAME.app/$APP_NAME" -d "$TMP_CHECK"
codesign -dv "$TMP_CHECK/Payload/$APP_NAME.app/$APP_NAME" 2>&1 | grep -q '^Signature=adhoc$' \
  || { echo "❌ ipa 内主二进制签名非 adhoc"; rm -rf "$TMP_CHECK"; exit 1; }
rm -rf "$TMP_CHECK"
echo "✅ 包内主二进制 Signature=adhoc"
echo "✅ 产物: $BUILD_DIR/$APP_NAME-adhoc.ipa ($(du -h "$BUILD_DIR/$APP_NAME-adhoc.ipa" | cut -f1))"
