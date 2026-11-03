#!/usr/bin/env bash
# Baut auf dem Mac eine DMG (macOS) und eine unsignierte IPA (iOS, zum Sideloaden).
# Aufruf:  bash scripts/build-release.sh [mac|ios|all]   (Standard: all)
# Ergebnis: Ergebnisse/Anamorphic.dmg und Ergebnisse/Anamorphic.ipa
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${1:-all}"

command -v xcodebuild >/dev/null || { echo "Xcode fehlt (xcodebuild nicht gefunden)."; exit 1; }
command -v xcodegen >/dev/null || brew install xcodegen

xcodegen generate

OUT="$PWD/Ergebnisse"
rm -rf "$OUT" build
mkdir -p "$OUT"

if [ "$TARGET" = "mac" ] || [ "$TARGET" = "all" ]; then
echo "== macOS: Release-Build (ad-hoc signiert) =="
xcodebuild -project Anamorphic.xcodeproj -scheme Anamorphic-macOS -configuration Release \
  -derivedDataPath build/mac \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  build

APP="build/mac/Build/Products/Release/Anamorphic.app"
[ -d "$APP" ] || { echo "Anamorphic.app wurde nicht gefunden."; exit 1; }

STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Anamorphic" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Anamorphic.dmg"
fi

if [ "$TARGET" = "ios" ] || [ "$TARGET" = "all" ]; then
echo "== iOS: Release-Build (unsigniert) =="
xcodebuild -project Anamorphic.xcodeproj -scheme Anamorphic-iOS -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/ios \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

IOSAPP="build/ios/Build/Products/Release-iphoneos/Anamorphic.app"
[ -d "$IOSAPP" ] || { echo "iOS-App wurde nicht gefunden."; exit 1; }
rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R "$IOSAPP" build/ipa/Payload/
(cd build/ipa && zip -qry "$OUT/Anamorphic.ipa" Payload)
fi

echo
echo "Fertig:"
ls -lh "$OUT"
echo "DMG: Rechtsklick > Öffnen beim ersten Start (nicht notarisiert)."
echo "IPA: mit AltStore oder Sideloadly und deiner Apple-ID signieren und aufs iPhone laden."
