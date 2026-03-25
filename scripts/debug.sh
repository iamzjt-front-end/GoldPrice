#!/bin/bash
set -e

cd "$(dirname "$0")/.."

APP_NAME="GoldPrice"
APP_BUNDLE="Build/Debug/${APP_NAME}.app"
APP_EXEC="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

package_debug_app() {
    mkdir -p "${APP_BUNDLE}/Contents/"{MacOS,Resources}
    cp ".build/debug/${APP_NAME}" "${APP_EXEC}"
    cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
    cp Assets/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns"
    codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
}

echo "🔨 编译中..."
swift build 2>&1 | grep -E "Build complete|error:|warning:" || true

package_debug_app

pkill -f "${APP_EXEC}" 2>/dev/null && sleep 0.3 || true

echo "🚀 启动调试..."
"${APP_EXEC}" &
APP_PID=$!

echo "✅ 已启动 (PID: $APP_PID)"
echo "   按 Ctrl+C 停止"

trap "pkill -f \"${APP_EXEC}\" 2>/dev/null; echo '🛑 已停止'; exit 0" INT TERM
wait $APP_PID 2>/dev/null
