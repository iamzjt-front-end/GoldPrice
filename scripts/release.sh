#!/bin/bash
set -e

cd "$(dirname "$0")/.."

REPO_ROOT=$(pwd)
APP_NAME="GoldPrice"
DMG_FILE="Build/${APP_NAME}.dmg"
PLIST="Info.plist"
BRANCH="main"

# ── 颜色 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
fail()  { echo -e "${RED}❌ $1${NC}"; exit 1; }

# ── 前置检查 ──
command -v gh   >/dev/null 2>&1 || fail "未安装 gh CLI，请先 brew install gh"
command -v swift >/dev/null 2>&1 || fail "未安装 swift，请先安装 Xcode Command Line Tools"

gh auth status >/dev/null 2>&1 || fail "gh 未登录，请先执行: gh auth login"

if [[ -n $(git status --porcelain -- ':!Info.plist') ]]; then
    warn "工作区有未提交的改动（Info.plist 除外）："
    git status --short -- ':!Info.plist'
    echo ""
    read -rp "是否继续？(y/N) " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 0
fi

# ── 版本号输入 ──
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
info "当前版本: ${YELLOW}${CURRENT_VERSION}${NC}"
echo ""

read -rp "请输入新版本号 (格式 X.Y.Z): " NEW_VERSION

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "版本号格式不正确，需要 X.Y.Z (如 2.1.0)"
fi

TAG="v${NEW_VERSION}"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    fail "Tag ${TAG} 已存在，请使用其他版本号"
fi

echo ""
info "即将发布: ${YELLOW}${TAG}${NC}"
echo ""

# ── 更新 Info.plist ──
info "更新 ${PLIST} 版本号..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "$PLIST"
ok "Info.plist 已更新为 ${NEW_VERSION}"

# ── 编译打包 DMG ──
info "开始编译打包..."
echo ""
bash scripts/build.sh
echo ""

if [[ ! -f "$DMG_FILE" ]]; then
    fail "DMG 文件未生成: ${DMG_FILE}"
fi

DMG_SIZE=$(du -h "$DMG_FILE" | cut -f1 | xargs)
ok "DMG 已就绪: ${DMG_FILE} (${DMG_SIZE})"
echo ""

# ── 确认发布 ──
echo -e "${CYAN}────────────────────────────────────${NC}"
echo -e "  版本:  ${YELLOW}${TAG}${NC}"
echo -e "  DMG:   ${DMG_FILE} (${DMG_SIZE})"
echo -e "  分支:  ${BRANCH}"
echo -e "${CYAN}────────────────────────────────────${NC}"
echo ""
read -rp "确认推送到 GitHub 并创建 Release？(y/N) " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { warn "已取消"; exit 0; }
echo ""

# ── Git commit & tag ──
info "提交版本变更..."
git add "$PLIST"
git commit -m "chore: release ${TAG}"
ok "已提交: chore: release ${TAG}"

info "创建 tag ${TAG}..."
git tag "$TAG"
ok "Tag ${TAG} 已创建"

# ── Push ──
info "推送到远程仓库..."
git push origin "$BRANCH" --tags
ok "已推送到 origin/${BRANCH}"

# ── GitHub Release ──
info "创建 GitHub Release..."
RELEASE_URL=$(gh release create "$TAG" "$DMG_FILE" \
    --title "${TAG}" \
    --generate-notes \
    2>&1 | tail -1)

echo ""
echo -e "${GREEN}════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Release ${TAG} 发布成功！${NC}"
echo -e "${GREEN}════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}${RELEASE_URL}${NC}"
echo ""
