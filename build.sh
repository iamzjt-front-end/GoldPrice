#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="GoldPrice"
DMG_VOLUME="GoldPrice"
DMG_FINAL="Build/${APP_NAME}.dmg"
DMG_TEMP="Build/${APP_NAME}_rw.dmg"
DMG_STAGING="Build/dmg_temp"
BG_IMG="Assets/dmg_bg.png"

echo "🔨 编译中..."
swift build -c release 2>&1 | grep -E "Build complete|error:|warning:" || true

echo "📦 打包 .app..."
rm -rf "Build/${APP_NAME}.app" "$DMG_STAGING" "$DMG_FINAL" "$DMG_TEMP"
mkdir -p "Build/${APP_NAME}.app/Contents/"{MacOS,Resources}
cp ".build/release/${APP_NAME}" "Build/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
cp Info.plist "Build/${APP_NAME}.app/Contents/Info.plist"
cp Assets/AppIcon.icns "Build/${APP_NAME}.app/Contents/Resources/${APP_NAME}.icns"

echo "🔏 Ad-hoc 签名..."
codesign --force --deep --sign - "Build/${APP_NAME}.app"

echo "💿 制作 DMG..."
mkdir -p "$DMG_STAGING/.background"
cp -R "Build/${APP_NAME}.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
cp "$BG_IMG" "$DMG_STAGING/.background/bg.png"

hdiutil create -volname "$DMG_VOLUME" -srcfolder "$DMG_STAGING" -ov -format UDRW "$DMG_TEMP" 2>/dev/null

MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" 2>/dev/null | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$DMG_VOLUME"
        open
        delay 2
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 820, 580}
        delay 1
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set background picture of theViewOptions to file ".background:bg.png"
        set position of item "${APP_NAME}.app" of container window to {180, 260}
        set position of item "Applications" of container window to {540, 260}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

chmod -Rf go-w "$MOUNT_DIR" 2>/dev/null || true
sync
hdiutil detach "$MOUNT_DIR" 2>/dev/null
hdiutil convert "$DMG_TEMP" -format UDZO -o "$DMG_FINAL" 2>/dev/null
rm -f "$DMG_TEMP"
rm -rf "$DMG_STAGING"

SIZE=$(du -h "$DMG_FINAL" | cut -f1 | xargs)
echo "✅ 完成! $DMG_FINAL ($SIZE)"
