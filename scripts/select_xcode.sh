#!/usr/bin/env bash
# Выбирает самую новую стабильную версию Xcode, установленную на runner'е.
# Beta/RC (с суффиксами в имени) пропускаются. Верхняя граница мажорной версии — MAX_XCODE_MAJOR.
set -euo pipefail
MAX_MAJOR="${MAX_XCODE_MAJOR:-26}"
best=""
best_key=0
for app in /Applications/Xcode_*.app; do
  [ -d "$app" ] || continue
  base="$(basename "$app" .app)"; ver="${base#Xcode_}"
  [[ "$ver" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || continue
  IFS=. read -r a b c <<<"$ver"; b="${b:-0}"; c="${c:-0}"
  [ "$a" -le "$MAX_MAJOR" ] || continue
  key=$(( a*1000000 + b*1000 + c ))
  if [ "$key" -gt "$best_key" ]; then best_key=$key; best="$app"; fi
done
if [ -z "$best" ]; then
  echo "::warning::Не найдена подходящая версия Xcode_*.app, использую Xcode по умолчанию"
  best="/Applications/Xcode.app"
fi
echo "Выбран Xcode: $best"
sudo xcode-select -s "$best/Contents/Developer"
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
