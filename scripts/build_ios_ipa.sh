#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ios/GoldPriceiOS.xcodeproj"
SCHEME="GoldPriceiOS"
BUILD_DIR="$ROOT_DIR/ios/build"
ARCHIVE_PATH="$BUILD_DIR/GoldPrice.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS_PATH="$BUILD_DIR/ExportOptions.plist"
TEAM_ID="${TEAM_ID:-}"

if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(python3 - <<'PY'
from pathlib import Path
pbxproj = Path("ios/GoldPriceiOS.xcodeproj/project.pbxproj")
team_id = ""
if pbxproj.exists():
    for line in pbxproj.read_text().splitlines():
        line = line.strip()
        if line.startswith("DEVELOPMENT_TEAM ="):
            value = line.split("=", 1)[1].strip().rstrip(";").strip('"')
            if value:
                team_id = value
                break
print(team_id)
PY
)"
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "TEAM_ID is required. Either:"
  echo "  1. open ios/GoldPriceiOS.xcodeproj in Xcode and set Signing -> Team once, or"
  echo "  2. pass it manually:"
  echo "     TEAM_ID=ABCDE12345 bash scripts/build_ios_ipa.sh"
  exit 1
fi

mkdir -p "$BUILD_DIR" "$EXPORT_PATH"

cat > "$EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>compileBitcode</key>
  <false/>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>development</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>thinning</key>
  <string>&lt;none&gt;</string>
</dict>
</plist>
EOF

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  clean archive

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
  -allowProvisioningUpdates

echo "IPA exported to:"
echo "  $EXPORT_PATH"
