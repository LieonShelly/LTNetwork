# LTNetwork

LTNetwork 是基于 Swift Concurrency 构建，提供 HTTP 请求发送、Dio 风格拦截器链、可取消的请求生命周期管理和 SSE 流式请求支持。

## 模块结构

```
core/Network/
├── Source/
│   ├── ApiClient.swift                    # 核心 HTTP 客户端
│   ├── RequestBuilder.swift               # URLRequest 构建器
│   ├── Interceptor/
│   │   ├── NetworkInterceptor.swift       # 拦截器协议（onRequest/onResponse/onError）
│   │   ├── InterceptorHandler.swift       # Handler 类型与 Result 枚举
│   │   └── InterceptorChain.swift         # 链式执行引擎
│   └── Model/
│       ├── NetworkTask.swift              # 可取消的请求句柄
│       ├── Request.swift                  # Request/EndPoint 协议
│       ├── Response.swift                 # HTTP 响应值类型
│       ├── AppNetworkError.swift          # 错误类型定义
│       ├── Environment.swift              # 环境枚举（dev/staging/release）
│       └── Encoder.swift                  # 编码工具
└── Tests/
    ├── DefaultInterceptorPassThroughTests.swift
    ├── InterceptorChainTests.swift
    ├── NetworkTaskTests.swift
    └── ApiClientTests.swift
```

## 核心概念

### ApiClient

`ApiClient` 是框架的入口，负责发送请求、执行拦截器链和管理重试逻辑。

```swift
let client = ApiClient(
    environment: .dev,
    interceptors: [authInterceptor, refreshTokenInterceptor, logoutInterceptor],
    maxRetryCount: 2
)
```

两种发送请求的方式：

```swift
// 方式一：async/await 便捷方法
let response = try await client.sendRequest(myRequest)

// 方式二：获取 NetworkTask 句柄，支持取消
let task = client.request(myRequest)
// ... 稍后取消
task.cancel()
// 或等待结果
let response = try await task.value
```

### NetworkTask

`NetworkTask` 包装 Swift `Task<Response, Error>`，提供请求生命周期控制：

- `value` — 异步获取响应结果
- `cancel()` — 取消请求，底层 URLSession 任务会被取消，结果以 `CancellationError` 完成
- `isCancelled` — 查询取消状态

### 拦截器（NetworkInterceptor）

采用 Dio 风格的三阶段拦截器设计，每个拦截器可选择性覆写关心的生命周期方法：

| 方法 | 触发时机 | Handler 操作 |
|------|----------|-------------|
| `onRequest` | 请求发送前 | `next(request)` 传递 / `reject(error)` 拒绝 |
| `onResponse` | 收到 2xx 响应后 | `next(response)` 传递 / `reject(error)` 转为错误 |
| `onError` | 请求出错后 | `next(error)` 传递 / `retry()` 触发重试 |

默认实现为透传（调用 `handler.next`），拦截器只需覆写关心的方法。

```swift
// 示例：添加认证头的拦截器
actor AuthInterceptor: NetworkInterceptor {
    private weak var tokenProvider: TokenProvider?

    func onRequest(_ request: URLRequest, handler: RequestInterceptorHandler) async -> RequestInterceptorResult {
        var request = request
        if let token = tokenProvider?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return handler.next(request)
    }
}

// 示例：401 自动刷新令牌的拦截器
actor RefreshTokenInterceptor: NetworkInterceptor {
    func onError(_ error: Error, request: URLRequest, handler: ErrorInterceptorHandler) async -> ErrorInterceptorResult {
        guard case AppNetworkError.httpError(statusCode: .unauthorized, _) = error as? AppNetworkError else {
            return handler.next(error)
        }
        do {
            try await refreshToken()
            return handler.retry()  // 重试会重新执行完整的 onRequest 链
        } catch {
            return handler.next(error)  // 刷新失败，传递错误到下一个拦截器
        }
    }
}
```

### 拦截器链执行顺序

拦截器按注册顺序正序执行，遇到 `reject` 或 `retry` 立即短路：

```
onRequest:  [Auth] → [Logging] → [Custom] → URLSession
onResponse: [Auth] → [Logging] → [Custom] → 返回调用方
onError:    [Auth] → [RefreshToken] → [Logout] → 抛出错误
```

### 重试机制

- 基于迭代 `while` 循环，非递归调用
- 拦截器在 `onError` 中返回 `handler.retry()` 触发重试
- 每次重试重新执行完整的 `onRequest` 拦截器链（确保使用最新令牌）
- `maxRetryCount` 限制最大重试次数，耗尽后抛出最后一次错误
- 每次循环检查 `Task.checkCancellation()`，已取消的请求立即退出

## 请求流程

```
调用方 → sendRequest / request()
         │
         ▼
    ┌─ while 循环 ──────────────────────────────┐
    │  Task.checkCancellation()                  │
    │  onRequest 链 → reject? → 直接抛出错误     │
    │       │                                    │
    │       ▼                                    │
    │  URLSession.data(for:)                     │
    │       │                                    │
    │  ┌─ 2xx ──┐    ┌─ 非2xx ──┐               │
    │  │onResponse│   │ onError  │               │
    │  │  链     │   │   链     │               │
    │  └─ 返回 ──┘   │          │               │
    │                │ retry? ──→ retryCount++   │
    │                │ next?  ──→ 抛出错误       │
    └────────────────────────────────────────────┘
```

## 错误处理

| 场景 | 错误类型 |
|------|----------|
| HTTP 非 2xx | `AppNetworkError.httpError(statusCode:body:)` |
| 网络连接失败 | `AppNetworkError.networkError(debugDescription:errorCode:)` |
| 请求被取消 | `CancellationError` |
| onRequest 拦截器拒绝 | 拦截器返回的原始错误（不触发重试） |
| 响应数据异常 | `AppNetworkError.dataError(debugDescription:)` |

## SSE 流式请求

```swift
let (stream, task): (AsyncThrowingStream<MyModel, Error>, NetworkTask) = client.sendSSERequest(sseRequest)

// 消费流
for try await event in stream {
    print(event)
}

// 随时取消
task.cancel()
```

SSE 请求同样经过 `onRequest` 拦截器链，返回的 `NetworkTask` 可用于取消底层字节流连接。

## 定义请求

```swift
enum UserEndPoint: EndPoint {
    case profile

    func absoluteUrl(_ environment: AppEnvironment) -> URL {
        URL(string: "https://api.example.com/user/profile")!
    }
}

struct FetchProfileRequest: Request {
    var endPoint: EndPoint { UserEndPoint.profile }
    var method: HttpMethod { .get }
    var payload: HttpPayload { .empty }
}

// 发送
let response = try await client.sendRequest(FetchProfileRequest())
let profile: ProfileDTO = try response.parseJson()
```

## SPM 集成

### 通过 Xcode 添加

1. 在 Xcode 中选择 **File → Add Package Dependencies...**
2. 输入仓库地址：`https://github.com/LieonShelly/LTNetwork.git`
3. 选择版本规则（如 **Branch: main**），点击 **Add Package**
4. 在目标 target 中勾选 `LTNetwork`

### 通过 Package.swift 添加

```swift
dependencies: [
    .package(url: "https://github.com/LieonShelly/LTNetwork.git", branch: "main"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "LTNetwork", package: "LTNetwork"),
        ]
    ),
]
```

### 导入使用

```swift
import LTNetwork

let client = ApiClient(
    environment: .dev,
    interceptors: [authInterceptor],
    maxRetryCount: 2
)
let response = try await client.sendRequest(myRequest)
```

> **要求：** Swift 5.9+、iOS 17+。本库无第三方依赖。

## 测试

测试位于 `core/Network/Tests/`，通过 Xcode 的 `LTNetworkTests` target 运行：


测试覆盖：
- 默认拦截器透传
- 拦截器链执行顺序与短路行为
- NetworkTask 取消与生命周期
- ApiClient 重试上限、onRequest 重执行、状态码映射、网络错误映射、reject 绕过重试

## 并发安全

所有公开类型遵循 `Sendable`：
- `NetworkInterceptor` 协议要求 `Sendable`
- `NetworkTask` 是 `final class` + `Sendable`
- `Response`、`AppNetworkError`、`HttpErrorCode` 均为值类型 + `Sendable`
- `ApiClient` 使用 `@unchecked Sendable`（内部状态通过 URLSession 和不可变属性保证安全）
- 拦截器推荐使用 `actor` 隔离（如 `AuthInterceptor`、`RefreshTokenInterceptor`）
