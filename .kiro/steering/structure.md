---
inclusion: always
---

# Project Structure

```
.
├── Package.swift                  # SPM package definition (LTNetwork library + LTNetworkTests)
├── project.yml                    # XcodeGen project config (used in monorepo context)
├── Source/                        # All production code
│   ├── ApiClient.swift            # Core HTTP client — entry point, retry loop, SSE support
│   ├── RequestBuilder.swift       # Builds URLRequest from Request protocol + environment
│   ├── Interceptor/               # Dio-style interceptor system
│   │   ├── NetworkInterceptor.swift   # Protocol with default pass-through implementations
│   │   ├── InterceptorHandler.swift   # Handler structs + Result enums for each phase
│   │   └── InterceptorChain.swift     # Sequential chain executor with short-circuit support
│   └── Model/                     # Data types and protocols
│       ├── Request.swift          # EndPoint + Request protocols, HttpMethod, HttpPayload enums
│       ├── Response.swift         # Response value type with JSON parsing extension
│       ├── AppNetworkError.swift  # Error enum, HttpErrorCode, ErrorModel
│       ├── NetworkTask.swift      # Cancellable request handle wrapping Task<Response, Error>
│       ├── Environment.swift      # AppEnvironment enum (dev/staging/release)
│       └── Encoder.swift          # Encodable → [String: Any] convenience extension
└── Tests/                         # Unit tests (XCTest)
    ├── ApiClientTests.swift       # ApiClient behavior: retry limits, status codes, error mapping, reject bypass
    ├── InterceptorChainTests.swift        # Chain ordering, short-circuit, modification accumulation
    ├── DefaultInterceptorPassThroughTests.swift  # Default protocol impl pass-through verification
    └── NetworkTaskTests.swift     # Cancel, isCancelled, success/failure lifecycle
```

# Architecture

- `ApiClient` is the public entry point; it owns a `URLSession`, an `InterceptorChain`, and the retry loop
- `InterceptorChain` is an internal struct that sequentially executes interceptors in registration order
- Interceptors conform to `NetworkInterceptor` protocol; default implementations pass through
- Each interceptor phase (request/response/error) has its own Handler struct and Result enum in `InterceptorHandler.swift`
- `RequestBuilder` translates the `Request` protocol into a concrete `URLRequest`
- Models in `Model/` are pure value types or protocols with no business logic beyond serialization
