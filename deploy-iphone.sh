#!/usr/bin/env bash
# Builds Node Status and installs it on a paired iPhone (USB or Wi-Fi).
#
# One-time setup: sign in to Xcode with your Apple ID
#   Xcode → Settings → Accounts → + → Apple ID
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/ios/NodeStatus.xcodeproj"
SCHEME=NodeStatus

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }

DEVICE_ID="${1:-}"
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
    | awk '/available \(paired\)|connected/ {print $(NF-3); exit}')"
fi
[ -n "$DEVICE_ID" ] || { c "0;31" "✖ No paired iPhone found. Connect it, or pair it over Wi-Fi in Xcode → Devices."; exit 1; }

c "1" "Building for $DEVICE_ID"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphoneos -configuration Debug \
  -destination "id=$DEVICE_ID" -allowProvisioningUpdates \
  -derivedDataPath "$ROOT/ios/build" build

APP="$ROOT/ios/build/Build/Products/Debug-iphoneos/Node Status.app"
[ -d "$APP" ] || { c "0;31" "✖ Build output not found"; exit 1; }

c "1" "Installing"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

c "0;32" "✔ Installed. Open “Node Status” on your iPhone."
echo
echo "  First time on this device? Trust the developer certificate under"
echo "  Settings → General → VPN & Device Management."
echo
echo "  To pair a server, run on it:  sudo nodestatus-agent enroll --new"
echo "  and scan the QR code in the app."
