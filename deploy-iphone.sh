#!/usr/bin/env bash
# Bouwt Server Info en installeert hem op een aangesloten iPhone.
#
# Eenmalig vooraf: log in Xcode in met je Apple ID
#   Xcode → Settings → Accounts → + → Apple ID → apple@merlinstoll.nl
# Daarna volstaat dit script.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios/ServerInfo.xcodeproj"
SCHEME=ServerInfo
BUNDLE=nl.merlinstoll.serverinfo

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }

DEVICE_ID="${1:-}"
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
    | awk '/available \(paired\)|connected/ {print $(NF-3); exit}')"
fi
[ -n "$DEVICE_ID" ] || { c "0;31" "✖ Geen gekoppelde iPhone gevonden. Sluit hem aan of koppel via wifi."; exit 1; }

c "1" "Bouwen voor $DEVICE_ID"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphoneos -configuration Debug \
  -destination "id=$DEVICE_ID" -allowProvisioningUpdates \
  -derivedDataPath "$(dirname "$PROJECT")/build" build

APP="$(dirname "$PROJECT")/build/Build/Products/Debug-iphoneos/Server Info.app"
[ -d "$APP" ] || { c "0;31" "✖ Build-output niet gevonden"; exit 1; }

c "1" "Installeren"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

c "0;32" "✔ Geïnstalleerd. Start 'Server Info' op je iPhone."
echo
echo "  Eerste keer op je toestel? Vertrouw het ontwikkelaarscertificaat via"
echo "  Instellingen → Algemeen → VPN en apparaatbeheer."
echo
echo "  Koppelen: draai op je server 'sudo serverinfo-agent enroll --new'"
echo "  en scan de QR in de app."
