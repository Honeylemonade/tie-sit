#!/bin/bash
#
# TIE-SIT 构建脚本
#
# 用法：
#   ./build.sh              构建 .app 到 build/ 目录
#   ./build.sh --install    构建并安装到 /Applications，然后启动
#
# 需要：macOS 13+ 和 Xcode Command Line Tools（xcode-select --install）
# 不需要：完整 Xcode、Apple 开发者账号、任何第三方依赖

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TIE-SIT"
BUNDLE="build/${APP_NAME}.app"
BIN_NAME="TIESit"

# ---------- 环境检查 ----------

if ! command -v swiftc >/dev/null 2>&1; then
    echo ""
    echo "  ✗ 找不到 swiftc"
    echo ""
    echo "  需要先安装 Xcode Command Line Tools，在终端运行："
    echo ""
    echo "      xcode-select --install"
    echo ""
    echo "  在弹出的窗口点「安装」，等它下载完（约 1-2GB），再回来跑这个脚本。"
    echo ""
    exit 1
fi

echo "→ Swift: $(swiftc --version | head -1)"

# 检查 SDK
if ! xcrun --show-sdk-path >/dev/null 2>&1; then
    echo "  ✗ 找不到 macOS SDK。请先同意 Xcode 许可协议："
    echo "      sudo xcodebuild -license accept"
    exit 1
fi

SDK="$(xcrun --show-sdk-path)"
echo "→ SDK:   $SDK"

# ---------- 干净构建 ----------

rm -rf build
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

echo "→ 编译中…"

swiftc \
    -O \
    -sdk "$SDK" \
    -target "$(uname -m)-apple-macos13.0" \
    -parse-as-library \
    -o "$BUNDLE/Contents/MacOS/$BIN_NAME" \
    Sources/TIESit/*.swift

echo "→ 打包…"

cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# 星球纹理由代码生成并缓存，无外部素材依赖。

# ---------- 临时签名 ----------
#
# 自用 App 用 ad-hoc 签名就够。这不解决「无法验证开发者」提示
# （那个需要 99 美元/年的开发者账号做公证），但能让 App 正常启动。
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || {
    echo "  ! 签名跳过（不影响本机运行）"
}

# ---------- 装到 /Applications ----------

if [[ "${1:-}" == "--install" ]]; then
    echo "→ 安装到 /Applications…"
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$BUNDLE" "/Applications/${APP_NAME}.app"
    # 清掉隔离属性，避免首次打开被 Gatekeeper 拦
    xattr -dr com.apple.quarantine "/Applications/${APP_NAME}.app" 2>/dev/null || true
    echo "→ 启动…"
    open "/Applications/${APP_NAME}.app"
    echo ""
    echo "  ✓ 已安装到 /Applications/${APP_NAME}.app"
    echo "  菜单栏右上角会出现一个 TIE 战机图标。"
    echo ""
else
    echo ""
    echo "  ✓ 构建完成：$BUNDLE"
    echo ""
    echo "  直接运行：  open $BUNDLE"
    echo "  安装到系统：./build.sh --install"
    echo ""
fi