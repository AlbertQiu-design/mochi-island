#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build-app.sh"
APP="$ROOT/island/MochiIsland.app"
DMG="$ROOT/island/MochiIsland.dmg"
if [[ -z "${DEVELOPER_ID_APP:-}" ]]; then
  echo "DEVELOPER_ID_APP is not set. The app is ad-hoc signed for this Mac only."
  echo "To notarize: export DEVELOPER_ID_APP='Developer ID Application: Name (TEAMID)'"
  echo "and export NOTARY_PROFILE to a notarytool keychain profile, then run this script again."
  exit 0
fi
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP"
rm -f "$DMG"
hdiutil create -volname "Mochi Island" -srcfolder "$APP" -ov -format UDZO "$DMG"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "Notarized $DMG"
else
  echo "Signed $DMG. Set NOTARY_PROFILE to submit it to Apple."
fi
