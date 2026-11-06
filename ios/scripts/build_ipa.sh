#!/bin/zsh
# P6: 构建仅 adhoc 签名的可安装 ipa
# 产物: ios/build/TiebaLite-adhoc.ipa
#
# 关键事实（本机 Xcode 26.6 / iOS 26.5 SDK 实测）：
# - xcodebuild 直接用 CODE_SIGN_IDENTITY="-" 报错
#   "Ad Hoc code signing is not allowed with SDK 'iOS 26.5'"
# - 可行路径：CODE_SIGNING_ALLOWED=NO 构建 → codesign --sign - 手动 adhoc 签名
# 验收：Signature=adhoc；TeamIdentifier=not set；无 embedded.mobileprovision；
#       codesign --verify --strict 通过
set -e
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
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "❌ 未找到 .app: $APP_PATH"; exit 1; }

echo "== 2) 手动 adhoc 签名 =="
codesign --force --sign - --timestamp=none "$APP_PATH"
codesign -dv "$APP_PATH" 2>&1 | grep -E "Signature|TeamIdentifier" || true
codesign --verify --strict "$APP_PATH"
echo "✅ strict 校验通过"

echo "== 3) 组装 ipa =="
rm -rf "$BUILD_DIR/Payload" "$BUILD_DIR/$APP_NAME-adhoc.ipa"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && zip -qry "$APP_NAME-adhoc.ipa" Payload)

echo "== 4) 验收 ipa =="
if unzip -l "$BUILD_DIR/$APP_NAME-adhoc.ipa" | grep -q "embedded.mobileprovision"; then
  echo "❌ 包内含 embedded.mobileprovision（不应存在）"; exit 1
else
  echo "✅ 无 embedded.mobileprovision"
fi
echo "✅ 产物: $BUILD_DIR/$APP_NAME-adhoc.ipa ($(du -h "$BUILD_DIR/$APP_NAME-adhoc.ipa" | cut -f1))"
