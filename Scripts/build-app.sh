#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product MochiIsland
swift build -c release --product MochiHookCLI
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/island/MochiIsland.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Web/pets/cursor" "$APP/Contents/Resources/Web/status"
cp "$BIN/MochiIsland" "$BIN/MochiHookCLI" "$APP/Contents/MacOS/"
cp "$ROOT/island/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/island/AppIcon.icns" ]]; then
  cp "$ROOT/island/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cp "$ROOT/web/island.html" "$ROOT/web/island.css" "$ROOT/web/island.js" "$APP/Contents/Resources/Web/"
cp "$ROOT/web/pets/"*.png "$APP/Contents/Resources/Web/pets/"
cp "$ROOT/web/pets/cursor/"*.svg "$APP/Contents/Resources/Web/pets/cursor/"
cp "$ROOT/web/status/"*.gif "$APP/Contents/Resources/Web/status/"
chmod +x "$APP/Contents/MacOS/MochiIsland" "$APP/Contents/MacOS/MochiHookCLI"
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
