#!/usr/bin/env bash
# Собирает НЕПОДПИСАННЫЙ .ipa (Release, iphoneos). Подпись выполняет Sideloadly на вашем компьютере.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
BUILD="${GITHUB_RUN_NUMBER:-local}"
OUT="build/AmyWardrobe-${VERSION}-build${BUILD}.ipa"

xcodebuild \
  -project AmyWardrobe.xcodeproj -scheme AmyWardrobe \
  -configuration Release -sdk iphoneos \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  build | tee build/xcodebuild-release.log | (command -v xcbeautify >/dev/null && xcbeautify || cat)

APP="$(find build/DerivedData/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' | head -n1)"
[ -d "$APP" ] || { echo "::error::.app не найден после сборки"; exit 1; }

rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
( cd build/ipa && zip -qry "../$(basename "$OUT")" Payload )
echo "IPA: $OUT ($(du -h "$OUT" | cut -f1))"
echo "ipa_path=$OUT" >> "${GITHUB_OUTPUT:-/dev/null}"
