#!/bin/bash

echo "🚀 正在打开 TodoApp..."
echo ""
echo "📋 提示："
echo "  1. 等待 Xcode 解析依赖（首次需要几分钟）"
echo "  2. 选择运行目标为 'My Mac'"
echo "  3. 按 ⌘R 运行应用"
echo ""

cd "$(dirname "$0")"

# 检查配置文件
if [ ! -f "Sources/Config.swift" ]; then
    echo "⚠️  警告: 未找到 Config.swift"
    echo ""
    echo "请先创建配置文件："
    echo "  cp Config.example.swift Sources/Config.swift"
    echo "  然后编辑 Sources/Config.swift 填入你的配置"
    echo ""
    exit 1
fi

echo "✅ 配置文件检查通过"
echo ""

open Package.swift
