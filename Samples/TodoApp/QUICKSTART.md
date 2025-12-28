# TodoApp 快速开始指南

## ✅ 构建成功！

应用已成功编译。现在可以运行了！

## 🚀 运行应用

### 方法 1: 命令行运行

```bash
cd /Users/fengjunwen/Projects/InsFg/insforge-swift/Samples/TodoApp
swift run
```

### 方法 2: 使用 Xcode

```bash
cd /Users/fengjunwen/Projects/InsFg/insforge-swift/Samples/TodoApp
open Package.swift
```

然后按 `⌘R` 运行。

## ⚙️ 配置 InsForge 连接

**重要：** 在运行应用之前，需要配置 InsForge 连接。

### 步骤 1: 创建配置文件

```bash
cd /Users/fengjunwen/Projects/InsFg/insforge-swift/Samples/TodoApp
cp Config.example.swift Sources/Config.swift
```

### 步骤 2: 编辑配置

编辑 `Sources/Config.swift`，替换为你的实际配置：

```swift
enum Config {
    static let insForgeURL = "https://your-project.insforge.com"  // 👈 替换这里
    static let insForgeKey = "your-api-key-here"                       // 👈 和这里
}
```

**注意：** `Config.swift` 已添加到 `.gitignore`，不会被提交到 Git，保护你的 API 密钥安全。

## 📊 设置数据库

在 InsForge 后台创建 `todos` 表：

```sql
CREATE TABLE todos (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    is_completed BOOLEAN DEFAULT FALSE,
    due_date TIMESTAMP,
    reminder_date TIMESTAMP,
    user_id TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 添加索引
CREATE INDEX idx_todos_user_id ON todos(user_id);

-- 启用行级安全
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

-- RLS 策略
CREATE POLICY "Users can view their own todos"
ON todos FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own todos"
ON todos FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own todos"
ON todos FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own todos"
ON todos FOR DELETE
USING (auth.uid() = user_id);
```

## 📱 使用应用

### 首次使用

1. **注册账户**
   - 输入邮箱、密码、姓名
   - 点击 "Sign Up"

2. **允许通知**（可选）
   - 用于提醒功能
   - 在系统弹窗中点击"允许"

### 创建 Todo

1. 点击右上角 **+** 按钮
2. 输入标题（必填）
3. 可选：添加描述、截止日期、提醒时间
4. 点击 "Add Todo"

### 管理 Todo

- **标记完成**：点击左侧圆圈图标
- **查看详情**：点击列表中的 todo
- **编辑**：在详情页点击铅笔图标
- **删除**：在详情页点击垃圾桶图标

### 提醒功能

- 为 todo 设置提醒时间后，会在指定时间收到 macOS 通知
- 确保提醒时间在未来
- 删除 todo 会自动取消提醒

## 🏗️ 项目结构

```
TodoApp/
├── Sources/
│   ├── Models/
│   │   └── Todo.swift              # Todo 数据模型
│   ├── Services/
│   │   ├── InsForgeService.swift   # InsForge SDK 封装
│   │   └── ReminderService.swift   # 通知管理
│   ├── Views/
│   │   ├── AuthView.swift          # 登录/注册
│   │   ├── TodoListView.swift      # 主列表
│   │   ├── TodoDetailView.swift    # 详情/编辑
│   │   └── AddTodoView.swift       # 创建表单
│   └── TodoApp.swift               # 入口
└── Package.swift
```

## 🔧 故障排除

### 构建错误

如果遇到构建错误：

```bash
# 清理构建缓存
swift package clean

# 重新构建
swift build
```

### 无法连接到 InsForge

1. 检查 URL 和 API Key 是否正确
2. 确保网络连接正常
3. 验证 InsForge 实例是否运行

### 通知不工作

1. 检查系统设置 → 通知 → TodoApp
2. 确保通知已启用
3. 验证提醒时间在未来

### 数据库错误

1. 确认 `todos` 表已创建
2. 检查 RLS 策略是否正确
3. 确保用户已登录

## 📚 更多信息

详细文档请查看 [README.md](README.md)

## 🎯 下一步

1. 配置 InsForge 连接
2. 创建数据库表
3. 运行应用并注册账户
4. 开始管理你的 Todo List！

---

**需要帮助？** 查看完整的 [README.md](README.md) 或提交 Issue。
