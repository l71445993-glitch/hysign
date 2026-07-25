#!/usr/bin/env bash
# 在 Mac 本机打包未签名 IPA（华阳签）供 TrollStore / ios-mcp 安装
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null || { echo "请先: brew install xcodegen"; exit 1; }

xcodegen generate
rm -rf build Payload HuaYangSign.ipa

xcodebuild \
  -project HuaYangSign.xcodeproj \
  -scheme HuaYangSign \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  build

APP=$(find build/Build/Products/Release-iphoneos -name "*.app" -maxdepth 1 | head -1)
mkdir Payload
cp -R "$APP" Payload/
zip -qr HuaYangSign.ipa Payload
echo "已生成: $ROOT/HuaYangSign.ipa"
ls -lh HuaYangSign.ipa
