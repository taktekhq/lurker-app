#!/bin/bash
# Archive the app and upload it to App Store Connect (TestFlight) from this Mac, signing with an
# App Store Connect API key. No GitHub Actions, no simulator, no Apple ID in Xcode needed.
#
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_TEAM_ID=... ASC_KEY_PATH=/path/AuthKey_<id>.p8 scripts/archive.sh [--export-only]
#
# The key needs the App Manager (or Admin) role. The app record must already exist in App Store
# Connect (Apple's API can't create one); the bundle id must be registered, along with the
# group.io.taktek.lurker App Group. The build number is the current UTC time (yyyymmddHHMM), so
# every upload is new. --export-only stops after making the .ipa.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}" "${ASC_TEAM_ID:?set ASC_TEAM_ID}"
ASC_KEY_PATH=${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}
[ -f "$ASC_KEY_PATH" ] || { echo "no API key at $ASC_KEY_PATH" >&2; exit 1; }

OUT=${OUT:-$(mktemp -d /tmp/lurker-archive.XXXX)}
BUILD=$(date -u +%Y%m%d%H%M)
DEST=upload; [ "${1:-}" = "--export-only" ] && DEST=export
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

[ -f Team.xcconfig ] || printf 'DEVELOPMENT_TEAM = %s\n' "$ASC_TEAM_ID" > Team.xcconfig
xcodegen generate -q

xcodebuild -project Lurker.xcodeproj -scheme Lurker -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Lurker.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD" DEVELOPMENT_TEAM="$ASC_TEAM_ID" \
  "${AUTH[@]}" archive

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$DEST</string>
<key>teamID</key><string>$ASC_TEAM_ID</string>
<key>signingStyle</key><string>automatic</string>
<key>uploadSymbols</key><true/>
</dict></plist>
EOF

xcodebuild -exportArchive -archivePath "$OUT/Lurker.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" "${AUTH[@]}"

echo "==> build $BUILD ($DEST), files in $OUT"
