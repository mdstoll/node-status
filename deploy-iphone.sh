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

# Note: xcodebuild wants the hardware UDID, which is not the CoreDevice
# identifier that `devicectl list devices` prints. Ask xcodebuild itself.
DEVICE_ID="${1:-}"
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | grep 'platform:iOS, arch' | grep -v Simulator \
    | sed -n 's/.*id:\([0-9A-Fa-f-]*\).*/\1/p' | head -1)"
fi
[ -n "$DEVICE_ID" ] || { c "0;31" "✖ No paired iPhone found. Connect it, or pair it over Wi-Fi in Xcode → Window → Devices."; exit 1; }
NAME="$(xcrun devicectl list devices 2>/dev/null | awk -F'   +' '/available|connected/ {print $1; exit}')"

c "1" "Building for ${NAME:-$DEVICE_ID}"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphoneos -configuration Debug \
  -destination "id=$DEVICE_ID" -allowProvisioningUpdates \
  -derivedDataPath "$ROOT/ios/build" build

APP="$ROOT/ios/build/Build/Products/Debug-iphoneos/Node Status.app"
[ -d "$APP" ] || { c "0;31" "✖ Build output not found"; exit 1; }

c "1" "Installing"
DEVICE_UUID="$(xcrun devicectl list devices 2>/dev/null | awk '/available|connected/ {print $(NF-2); exit}')"
xcrun devicectl device install app --device "${DEVICE_UUID:-$DEVICE_ID}" "$APP"

c "0;32" "✔ Installed. Open “Node Status” on your iPhone."
echo
echo "  First time on this device? Trust the developer certificate under"
echo "  Settings → General → VPN & Device Management."
echo
echo "  To pair a server, run on it:  sudo nodestatus-agent enroll --new"
echo "  and scan the QR code in the app."
