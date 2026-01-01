# TodoApp 架构说明

## 🏗️ InsForgeClient 初始化流程

### 调用链路

```
TodoApp 启动
    ↓
ContentView (TodoApp.swift:17)
    ↓
InsForgeService.shared (单例模式)
    ↓
InsForgeService.init() (InsForgeService.swift:15)
    ↓
读取 Config.insForgeURL 和 Config.anonKey (Config.swift)
    ↓
调用 InsForgeClient(baseURL:anonKey:) (InsForgeClient.swift:49)
    ↓
创建 InsForgeClient 实例
    ↓
初始化 AuthClient (立即创建)
    ↓
其他客户端 (database, storage 等) 懒加载
```

## 📝 详细代码流程

### 1. 应用启动入口

**文件：** `Sources/TodoApp.swift`

```swift
@main
struct TodoApp: App {
    @StateObject private var service = InsForgeService.shared  // 👈 获取单例

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
        }
    }
}
```

### 2. InsForgeService 单例

**文件：** `Sources/Services/InsForgeService.swift`

```swift
@MainActor
class InsForgeService: ObservableObject {
    static let shared = InsForgeService()  // 👈 单例实例

    private let client: InsForgeClient     // 👈 持有 InsForgeClient

    private init() {                       // 👈 私有初始化器
        // 从 Config.swift 读取配置
        guard let url = URL(string: Config.insForgeURL) else {
            fatalError("Invalid InsForge URL")
        }

        // 👇 在这里调用 InsForgeClient.init()
        self.client = InsForgeClient(
            baseURL: url,
            anonKey: Config.anonKey
        )
    }

    // 通过 client 访问各种功能
    func signIn(...) async throws {
        try await client.auth.signIn(...)  // 👈 使用 client.auth
    }

    func fetchTodos() async throws -> [Todo] {
        try await client.database          // 👈 使用 client.database
            .from("todos")
            .select()
            .execute()
    }
}
```

### 3. Config 配置

**文件：** `Sources/Config.swift`（你需要创建）

```swift
enum Config {
    static let insForgeURL = "https://your-project.insforge.com"
    static let anonKey = "your-api-key-here"
}
```

### 4. InsForgeClient 初始化

**文件：** `Sources/InsForge/InsForgeClient.swift`（SDK 代码）

```swift
public final class InsForgeClient: Sendable {
    public let baseURL: URL
    public let anonKey: String

    // 👇 这是被 InsForgeService 调用的初始化方法
    public init(
        baseURL: URL,
        anonKey: String,
        options: InsForgeClientOptions = .init()
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.options = options

        // 构建请求头
        var headers = options.global.headers
        headers["apikey"] = anonKey
        headers["Authorization"] = "Bearer \(anonKey)"

        // 立即初始化 AuthClient
        self._auth = AuthClient(
            url: baseURL.appendingPathComponent("api/auth"),
            headers: headers,
            options: options.auth
        )
    }

    // 其他客户端采用懒加载
    public var database: DatabaseClient {
        // 第一次访问时才创建
        mutableState.withValue { state in
            if state.database == nil {
                state.database = DatabaseClient(...)
            }
            return state.database!
        }
    }
}
```

## 🔄 完整时序图

```
用户启动 App
    ↓
@main TodoApp.body 执行
    ↓
@StateObject var service = InsForgeService.shared
    ↓
[首次访问] InsForgeService.shared 触发初始化
    ↓
InsForgeService.init()
    ↓
读取 Config.insForgeURL → "https://my-app.insforge.com"
读取 Config.anonKey     → "sk_live_xxxxx"
    ↓
创建 InsForgeClient
  - baseURL: https://my-app.insforge.com
  - anonKey: sk_live_xxxxx
    ↓
InsForgeClient.init() 执行
  - 设置 headers["apikey"] = anonKey
  - 设置 headers["Authorization"] = "Bearer {anonKey}"
  - 创建 AuthClient (立即)
    ↓
InsForgeService.client 准备就绪
    ↓
用户调用 service.signIn()
    ↓
service.client.auth.signIn()
    ↓
发送 HTTP 请求到 https://my-app.insforge.com/api/auth
```

## 🎯 关键点说明

### 1. 单例模式 (Singleton)

```swift
static let shared = InsForgeService()
```

- `InsForgeService` 只会被创建一次
- 第一次访问 `InsForgeService.shared` 时，`init()` 才会执行
- 之后所有访问都返回同一个实例

### 2. 私有初始化器

```swift
private init() { ... }
```

- 防止外部直接创建 `InsForgeService()` 实例
- 确保只能通过 `shared` 访问

### 3. 配置文件读取

```swift
guard let url = URL(string: Config.insForgeURL) else {
    fatalError("Invalid InsForge URL")
}

self.client = InsForgeClient(
    baseURL: url,
    anonKey: Config.anonKey
)
```

- 从 `Config` 枚举读取静态属性
- 编译时就确定值（不是运行时读取文件）
- 如果 URL 无效，应用会在启动时崩溃并提示错误

### 4. 懒加载 (Lazy Loading)

```swift
public var database: DatabaseClient {
    mutableState.withValue { state in
        if state.database == nil {           // 👈 检查是否已创建
            state.database = DatabaseClient(...) // 👈 首次访问时创建
        }
        return state.database!
    }
}
```

- `database`、`storage` 等客户端不会在初始化时立即创建
- 只有当你第一次访问 `client.database` 时才会创建
- 节省内存和启动时间

## 📊 内存布局

```
TodoApp (应用)
    └── InsForgeService.shared (单例)
            └── client: InsForgeClient
                    ├── baseURL: URL
                    ├── anonKey: String
                    ├── _auth: AuthClient (立即创建)
                    └── mutableState
                            ├── database: DatabaseClient? (懒加载)
                            ├── storage: StorageClient?   (懒加载)
                            ├── functions: FunctionsClient? (懒加载)
                            ├── ai: AIClient?             (懒加载)
                            └── realtime: RealtimeClient?  (懒加载)
```

## 🔍 如何验证

### 在 InsForgeService.init() 中添加日志：

```swift
private init() {
    print("🔧 InsForgeService 正在初始化...")

    guard let url = URL(string: Config.insForgeURL) else {
        fatalError("Invalid InsForge URL")
    }

    print("📍 InsForge URL: \(url)")
    print("🔑 API Key: \(Config.anonKey.prefix(10))...")

    self.client = InsForgeClient(
        baseURL: url,
        anonKey: Config.anonKey
    )

    print("✅ InsForgeClient 初始化完成")
}
```

运行应用时，控制台会输出：

```
🔧 InsForgeService 正在初始化...
📍 InsForge URL: https://my-app.insforge.com
🔑 API Key: sk_live_ab...
✅ InsForgeClient 初始化完成
```

## 📚 相关文件

- **SDK 初始化**: `Sources/InsForge/InsForgeClient.swift:49`
- **服务封装**: `Sources/Services/InsForgeService.swift:15`
- **配置文件**: `Sources/Config.swift`
- **应用入口**: `Sources/TodoApp.swift:17`

## 💡 设计模式

1. **单例模式**: `InsForgeService.shared`
2. **外观模式**: `InsForgeService` 封装 `InsForgeClient`
3. **懒加载**: `database`、`storage` 等客户端
4. **配置外部化**: `Config.swift` 分离配置

这种设计的好处：
- ✅ 配置集中管理
- ✅ 避免重复创建客户端
- ✅ 延迟初始化节省资源
- ✅ 易于测试和替换
