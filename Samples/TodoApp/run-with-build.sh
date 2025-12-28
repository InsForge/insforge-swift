#!/bin/bash

# TodoApp OAuth 测试脚本 - 先构建 .app 包，然后直接运行可执行文件查看日志

cd "$(dirname "$0")"

echo "🔨 构建 TodoApp.app..."
./build-app.sh

if [ $? -ne 0 ]; then
    echo "❌ 构建失败"
    exit 1
fi

echo ""
echo "🚀 启动应用（可以看到日志）..."
echo "💡 提示: 此模式下可以测试 OAuth 回调"
echo "         URL Scheme (todoapp://) 已注册"
echo ""

# 直接运行可执行文件，这样可以在终端看到日志
# 同时 URL scheme 也已经注册，可以接收 OAuth 回调
./TodoApp.app/Contents/MacOS/TodoApp
