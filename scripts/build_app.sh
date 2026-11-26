#!/usr/bin/env bash
# Baut "FuFF AKM-Liste.app" (Universal: Apple Silicon + Intel), ab macOS 13.
# Läuft auf GitHub Actions (macOS). Lokal geht es genauso, wenn Xcode installiert ist.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="FuFF AKM-Liste"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
VERSION="${VERSION:-0.1.0}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Swift-Code kompilieren (Universal)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AKMListe"
lipo -info "$BIN"

echo "==> App-Paket zusammenbauen"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AKMListe"
cp Resources/ORF_AKMliste_Vorlage.xlsx "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> App-Icon erzeugen"
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signieren (nötig, damit es auf Apple Silicon startet)"
codesign --force --sign - "$APP"

echo "==> ZIP erstellen"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/FuFF-AKM-Liste.zip"
echo "Fertig: $BUILD_DIR/FuFF-AKM-Liste.zip"
