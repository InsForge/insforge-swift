#!/bin/bash

set -e

echo "📦 构建 TodoApp.app 应用包..."
echo ""

cd "$(dirname "$0")"

# 检查配置文件
if [ ! -f "Sources/Config.swift" ]; then
    echo "⚠️  错误: 未找到 Config.swift"
    echo ""
    echo "请先创建配置文件："
    echo "  cp Config.example.swift Sources/Config.swift"
    echo "  然后编辑 Sources/Config.swift"
    echo ""
    exit 1
fi

# 清理旧的构建
rm -rf TodoApp.app

# 构建 release 版本
echo "🔨 编译应用..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ 构建失败"
    exit 1
fi

# 创建 .app 包结构
echo "📁 创建应用包结构..."
mkdir -p TodoApp.app/Contents/MacOS
mkdir -p TodoApp.app/Contents/Resources

# 复制可执行文件
echo "📋 复制可执行文件..."
cp .build/release/TodoApp TodoApp.app/Contents/MacOS/

# 创建 Info.plist
echo "📄 创建 Info.plist..."
cat > TodoApp.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>TodoApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.insforge.todoapp</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TodoApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.insforge.todoapp</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>todoapp</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# 注册 URL scheme
echo "🔗 注册 URL scheme (todoapp://)..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(pwd)/TodoApp.app"

echo ""
echo "✅ TodoApp.app 创建成功！"
echo ""
echo "🚀 运行方式:"
echo "   方式 1: 双击 TodoApp.app"
echo "   方式 2: open TodoApp.app"
echo "   方式 3: ./TodoApp.app/Contents/MacOS/TodoApp"
echo ""
echo "📦 应用位置:"
echo "   $(pwd)/TodoApp.app"
echo ""
echo "💡 提示:"
echo "   - 这是一个真正的 macOS 应用"
echo "   - 窗口会正常激活，可以使用 ⌘Tab 切换"
echo "   - 可以拖到应用程序文件夹"
echo "   - 键盘输入应该正常工作了！"
echo "   - 已注册 URL scheme: todoapp://"
echo "   - 支持 OAuth 登录回调"
echo ""
