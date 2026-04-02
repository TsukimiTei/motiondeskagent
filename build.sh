#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MotionDeskAgent"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "═══════════════════════════════════════════"
echo "  Building MotionDeskAgent"
echo "═══════════════════════════════════════════"

# ─── Step 1: 构建前端 ───
echo ""
echo "▸ [1/3] 构建前端..."
cd "$PROJECT_DIR/frontend"

if [ ! -d "node_modules" ]; then
    echo "  安装依赖..."
    npm install
fi

npm run build
echo "  ✔ 前端构建完成"

# ─── Step 2: 编译 Swift ───
echo ""
echo "▸ [2/3] 编译 Swift..."
cd "$PROJECT_DIR"

swift build -c release 2>&1 | tail -5
SWIFT_BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
echo "  ✔ Swift 编译完成"

# ─── Step 3: 打包 .app bundle ───
echo ""
echo "▸ [3/3] 打包 .app bundle..."

# 清理旧的构建
rm -rf "$APP_BUNDLE"

# 创建 .app 目录结构
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/frontend"

# 复制可执行文件
cp "$SWIFT_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 复制 Info.plist
cp "$PROJECT_DIR/resources/Info.plist" "$APP_BUNDLE/Contents/"

# 复制前端构建产物
cp -r "$PROJECT_DIR/frontend/dist/"* "$APP_BUNDLE/Contents/Resources/frontend/"

# 复制配置文件
cp "$PROJECT_DIR/config/states.json" "$APP_BUNDLE/Contents/Resources/"

# 复制 clips 目录（如果有内容）
if [ -d "$PROJECT_DIR/clips" ]; then
    cp -r "$PROJECT_DIR/clips" "$APP_BUNDLE/Contents/Resources/"
fi

echo "  ✔ .app bundle 打包完成"

echo ""
echo "═══════════════════════════════════════════"
echo "  构建成功！"
echo "  输出: $APP_BUNDLE"
echo ""
echo "  运行方式："
echo "    open $APP_BUNDLE"
echo "  或:"
echo "    $APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo ""
echo "  开发模式（使用 Vite dev server）："
echo "    cd frontend && npm run dev"
echo "    然后运行 Swift 应用"
echo "═══════════════════════════════════════════"
