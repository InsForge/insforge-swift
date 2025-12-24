# TodoApp 配置说明

## 🔐 安全的配置方式

为了保护你的 API 密钥不被泄露到 Git 仓库，本项目采用了配置文件分离的方式。

## 📁 配置文件说明

```
TodoApp/
├── Config.example.swift        # 示例配置（会提交到 Git）
├── Sources/
│   └── Config.swift           # 你的实际配置（在 .gitignore 中，不会提交）
└── .gitignore                 # 包含 Config.swift
```

## 🚀 快速配置

### 1. 复制示例配置

```bash
cd /Users/fengjunwen/Projects/InsFg/insforge-swift/Samples/TodoApp
cp Config.example.swift Sources/Config.swift
```

### 2. 编辑实际配置

打开 `Sources/Config.swift`，替换为你的真实信息：

```swift
enum Config {
    // 替换为你的 InsForge 实例 URL
    static let insForgeURL = "https://your-project.insforge.com"

    // 替换为你的 API 密钥
    static let apiKey = "your-api-key-here"
}
```

### 3. 验证配置

```bash
swift build
```

如果看到 "Build complete!"，说明配置正确。

## 🔒 安全性说明

### ✅ 安全的做法

- `Config.swift` 包含真实的 API 密钥，已添加到 `.gitignore`
- `Config.example.swift` 只是模板，可以安全地提交到 Git
- InsForgeService 从 `Config.swift` 读取配置

### ❌ 不安全的做法（已避免）

- ~~直接在代码中硬编码 API 密钥~~
- ~~修改 SDK 源代码来配置连接~~
- ~~将包含密钥的文件提交到 Git~~

## 📝 配置文件内容

### Config.swift（你的实际配置）

```swift
import Foundation

enum Config {
    static let insForgeURL = "https://my-app.insforge.com"
    static let apiKey = "sk_live_xxxxxxxxxxxxxxxxxxxxx"
}
```

这个文件：
- ✅ 存放在 `Sources/Config.swift`
- ✅ 包含你的真实 API 密钥
- ✅ 在 `.gitignore` 中，不会被提交
- ✅ 只在你的本地存在

### Config.example.swift（示例模板）

```swift
import Foundation

enum Config {
    static let insForgeURL = "https://your-project.insforge.com"
    static let apiKey = "your-api-key-here"
}
```

这个文件：
- ✅ 存放在项目根目录
- ✅ 包含示例值，不含真实密钥
- ✅ 会被提交到 Git
- ✅ 供其他开发者参考

## 🔄 多环境配置（可选）

如果你需要支持开发环境和生产环境：

```swift
enum Config {
    #if DEBUG
    static let insForgeURL = "https://dev.insforge.com"
    static let apiKey = "sk_test_xxxxx"
    #else
    static let insForgeURL = "https://prod.insforge.com"
    static let apiKey = "sk_live_xxxxx"
    #endif
}
```

## 📋 检查清单

首次配置时，请确认：

- [ ] 已复制 `Config.example.swift` 到 `Sources/Config.swift`
- [ ] 已编辑 `Sources/Config.swift` 中的 URL 和 API Key
- [ ] 运行 `swift build` 无错误
- [ ] 确认 `Sources/Config.swift` 在 `.gitignore` 中
- [ ] 确认 `git status` 不显示 `Config.swift`

## ❓ 常见问题

### Q: 为什么要分离配置文件？

A: 为了防止 API 密钥泄露。如果直接在代码中写密钥，提交到 GitHub 后，任何人都能看到你的密钥。

### Q: Config.swift 丢失了怎么办？

A: 重新从 `Config.example.swift` 复制一份，然后填入你的配置即可。

### Q: 团队协作时如何共享配置？

A:
1. 不要通过 Git 共享 `Config.swift`
2. 通过安全的渠道（如加密聊天）分享配置值
3. 每个团队成员各自创建自己的 `Sources/Config.swift`

### Q: 可以直接修改 InsForgeService.swift 吗？

A: 不推荐。使用配置文件的方式更清晰、更安全、更易维护。

## 🎯 下一步

配置完成后：
1. 查看 [QUICKSTART.md](QUICKSTART.md) 了解如何运行应用
2. 查看 [README.md](README.md) 了解完整功能
3. 开始使用 TodoApp！
