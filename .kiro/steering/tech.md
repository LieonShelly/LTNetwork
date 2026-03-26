---
inclusion: always
---

# Tech Stack

- Language: Swift 5.9+
- Platform: iOS 17+
- Concurrency: Swift Concurrency (async/await, Task, AsyncThrowingStream)
- Networking: Foundation URLSession
- Testing: XCTest
- Build systems:
  - Swift Package Manager (Package.swift) — primary, defines `LTNetwork` library target and `LTNetworkTests` test target
  - XcodeGen (project.yml) — generates the Xcode project; references shared settings from the parent monorepo via `../../fastlane/project/settings.yml`
- No third-party dependencies

# Common Commands

```bash
# Build the package
swift build

# Run tests via SPM
swift test

# Generate Xcode project (requires XcodeGen + monorepo context)
bundle exec fastlane generate_project

# Run tests in Xcode (after project generation)
# Use Cmd+U in Xcode on the LTNetworkTests scheme
```

# Key Conventions

- All public types conform to `Sendable`
- Interceptors should be implemented as `actor` for isolation safety
- `ApiClient` uses `@unchecked Sendable` with safety guaranteed by immutable properties and URLSession
- Result types (`RequestInterceptorResult`, etc.) use `@unchecked Sendable` because they wrap `Error`
- Every source file begins with the copyright header: `// LTApp, This code is protected by intellectual property rights.`
- Tests use `MockURLProtocol` injected via `URLSessionConfiguration.ephemeral` to avoid real network calls
- Test classes are organized by property/behavior being validated, with doc comments linking to requirements
