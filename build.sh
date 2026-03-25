#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🔨 编译中..."
swift build -c release 2>&1 | grep -E "Build complete|error:|warning:" || true

echo "📦 打包 .app..."
rm -rf Build/GoldPrice.app Build/dmg_temp Build/GoldPrice.dmg
mkdir -p Build/GoldPrice.app/Contents/{MacOS,Resources}
cp .build/release/GoldPrice Build/GoldPrice.app/Contents/MacOS/GoldPrice
cp Info.plist Build/GoldPrice.app/Contents/Info.plist
cp Assets/AppIcon.icns Build/GoldPrice.app/Contents/Resources/GoldPrice.icns

echo "💿 制作 DMG..."
mkdir -p Build/dmg_temp
cp -R Build/GoldPrice.app Build/dmg_temp/
ln -s /Applications Build/dmg_temp/Applications
hdiutil create -volname "GoldPrice" -srcfolder Build/dmg_temp -ov -format UDZO Build/GoldPrice.dmg 2>/dev/null
rm -rf Build/dmg_temp

SIZE=$(du -h Build/GoldPrice.dmg | cut -f1 | xargs)
echo "✅ 完成! Build/GoldPrice.dmg ($SIZE)"
