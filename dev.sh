#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "═══════════════════════════════════════════"
echo "  MotionDeskAgent - 开发模式"
echo "═══════════════════════════════════════════"

# 启动前端开发服务器（后台）
echo "▸ 启动前端开发服务器..."
cd "$PROJECT_DIR/frontend"

if [ ! -d "node_modules" ]; then
    echo "  安装依赖..."
    npm install
fi

npm run dev &
VITE_PID=$!
echo "  ✔ Vite dev server PID: $VITE_PID"

# 等待 Vite 启动
sleep 2

# 编译并运行 Swift 应用
echo ""
echo "▸ 编译并运行 Swift 应用..."
cd "$PROJECT_DIR"

# 设置环境变量指向前端开发服务器
export MOTIONDESK_PROJECT_PATH="$PROJECT_DIR"
export MOTIONDESK_FRONTEND_PATH="$PROJECT_DIR/frontend/dist"

swift run MotionDeskAgent 2>&1 &
SWIFT_PID=$!
echo "  ✔ Swift app PID: $SWIFT_PID"

# 清理
cleanup() {
    echo ""
    echo "▸ 停止服务..."
    kill $VITE_PID 2>/dev/null || true
    kill $SWIFT_PID 2>/dev/null || true
    echo "  ✔ 已停止"
}

trap cleanup EXIT INT TERM

echo ""
echo "═══════════════════════════════════════════"
echo "  开发模式运行中"
echo "  前端: http://localhost:5173"
echo "  按 Ctrl+C 停止"
echo "═══════════════════════════════════════════"

# 等待任一进程退出
wait
