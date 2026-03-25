#!/bin/bash
cd "$(dirname "$0")/.."

APP_PID=""
LAST_HASH=""
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

cleanup() {
    [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null
    pkill -f "$APP_EXEC" 2>/dev/null || true
    echo "🛑 已停止"
    exit 0
}
trap cleanup INT TERM

build_and_run() {
    [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null && sleep 0.3
    pkill -f "$APP_EXEC" 2>/dev/null || true
    echo ""
    echo "🔨 编译中..."
    if swift build 2>&1 | grep -E "Build complete|error:|warning:"; then
        package_debug_app
        echo "🚀 重新启动..."
        "$APP_EXEC" &
        APP_PID=$!
        echo "✅ 已启动 (PID: $APP_PID)"
    else
        echo "❌ 编译失败，等待修复..."
        APP_PID=""
    fi
}

get_hash() {
    find Sources -name "*.swift" -exec stat -f "%m %N" {} \; 2>/dev/null | sort | md5
}

echo "👀 监听 Sources/ 文件变化中..."
echo "   保存文件后自动重编译重启"
echo "   按 Ctrl+C 停止"

build_and_run
LAST_HASH=$(get_hash)

while true; do
    sleep 1
    CURRENT_HASH=$(get_hash)
    if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
        LAST_HASH="$CURRENT_HASH"
        echo ""
        echo "📝 检测到文件变化..."
        build_and_run
    fi
done
