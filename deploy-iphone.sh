#!/usr/bin/env bash
# Builds Node Status and installs it on a paired iPhone, over USB or Wi-Fi.
#
# One-time setup: open ios/NodeStatus.xcodeproj in Xcode, select your iPhone and
# press Run once. That creates the provisioning profile. After that this script
# works on its own — it reads the team and profile straight from that file, so
# it does not depend on xcodebuild being able to reach your Apple account.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/ios/NodeStatus.xcodeproj"
SCHEME=NodeStatus
BUNDLE=nl.merlinstoll.nodestatus

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
die(){ c "0;31" "✖ $1"; exit 1; }

# ---------- device ----------
xcrun devicectl list devices --json-output /tmp/nodestatus-devices.json >/dev/null 2>&1 \
  || die "devicectl failed — is Xcode installed and selected?"

IFS=$'\t' read -r DEVICE_ID DEVICE_UDID DEVICE_NAME <<<"$(python3 - <<'PY'
import json
d = json.load(open('/tmp/nodestatus-devices.json'))
for x in d.get('result', {}).get('devices', []):
    props = x.get('connectionProperties', {})
    if props.get('pairingState') == 'paired' or props.get('tunnelState') in ('connected', 'available'):
        hw = x.get('hardwareProperties', {})
        print("\t".join([x['identifier'], hw.get('udid', ''), x.get('deviceProperties', {}).get('name', 'iPhone')]))
        break
PY
)"
[ -n "${DEVICE_ID:-}" ] || die "No paired iPhone found. Connect it, or pair over Wi-Fi in Xcode → Window → Devices."

# ---------- signing ----------
# Read team and profile from the installed provisioning profile rather than
# hardcoding them: a free Apple account regenerates the profile every 7 days,
# and the team id is the OU of the certificate, not the code in its name.
# Tab-separated: profile names contain spaces, so word splitting will not do.
IFS=$'\t' read -r TEAM PROFILE_NAME PROFILE_EXPIRY <<<"$(python3 - "$DEVICE_UDID" "$BUNDLE" <<'PY'
import glob, os, plistlib, subprocess, sys, datetime
udid, bundle = sys.argv[1], sys.argv[2]
best = None
paths = glob.glob(os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision"))
paths += glob.glob(os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles/*.mobileprovision"))
for p in paths:
    raw = subprocess.run(["security", "cms", "-D", "-i", p], capture_output=True).stdout
    if not raw:
        continue
    try:
        d = plistlib.loads(raw)
    except Exception:
        continue
    appid = d.get("Entitlements", {}).get("application-identifier", "")
    if not appid.endswith("." + bundle):
        continue
    if udid and udid not in (d.get("ProvisionedDevices") or []):
        continue
    exp = d.get("ExpirationDate")
    if exp and exp < datetime.datetime.now():
        continue
    if best is None or (exp and exp > best[2]):
        best = (d.get("TeamIdentifier", [""])[0], d.get("Name", ""), exp)
if best:
    print("\t".join([best[0], best[1], best[2].strftime("%Y-%m-%d") if best[2] else "?"]))
PY
)"

if [ -z "${TEAM:-}" ]; then
  die "No usable provisioning profile for $BUNDLE and this device.
  Open $PROJECT in Xcode, select your iPhone and press Run once.
  Xcode will create the profile; after that this script works on its own."
fi

c "1" "Building for $DEVICE_NAME"
printf '  team %s · profile "%s" · expires %s\n' "$TEAM" "$PROFILE_NAME" "$PROFILE_EXPIRY"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphoneos -configuration Debug \
  -destination "id=$DEVICE_UDID" -derivedDataPath "$ROOT/ios/build" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  build

APP="$ROOT/ios/build/Build/Products/Debug-iphoneos/Node Status.app"
[ -d "$APP" ] || die "Build output not found"

c "1" "Installing"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >/dev/null

c "0;32" "✔ Installed. Open “Node Status” on your iPhone."
echo
echo "  First time on this device? Trust the developer certificate under"
echo "  Settings → General → VPN & Device Management."
echo
echo "  To pair a server, run on it:  sudo nodestatus-agent enroll --new"
echo "  and scan the QR code in the app."
echo
if [ "$PROFILE_EXPIRY" != "?" ]; then
  echo "  Note: with a free Apple account the profile expires $PROFILE_EXPIRY."
  echo "  After that, press Run once in Xcode again to refresh it."
fi
