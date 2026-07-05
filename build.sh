#!/bin/zsh
set -e
cd "$(dirname "$0")"

swift build -c release

APP="Podium.app"
rm -rf "$APP" ScrollWM.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ScrollWM "$APP/Contents/MacOS/Podium"
cp bundle/Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/MenuIconTemplate.png assets/MenuIconTemplate@2x.png "$APP/Contents/Resources/"

# Signieren mit stabiler, selbstsignierter Identität, damit die designated
# requirement (und damit der Bedienungshilfen-Zugriff) über Rebuilds erhalten
# bleibt. Fallback auf Ad-hoc, falls die Identität fehlt.
IDENTITY="ScrollWM Local"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || true
else
    echo "⚠ Identität '$IDENTITY' fehlt – Ad-hoc-Signatur (Zugriff geht bei Rebuilds verloren)"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ Gebaut: $(pwd)/$APP"
