---
inclusion: always
---

# Product: LTNetwork

LTNetwork is the networking framework for the LittleThings iOS app. It provides:

- HTTP request sending via `ApiClient` built on Swift Concurrency (`async/await`)
- Dio-style interceptor chain with three phases: `onRequest`, `onResponse`, `onError`
- Cancellable request lifecycle via `NetworkTask` (wraps `Task<Response, Error>`)
- SSE (Server-Sent Events) streaming support
- Iterative retry mechanism with configurable max retry count
- Environment-based URL resolution (dev / staging / release)

The framework is a standalone Swift Package (`LTNetwork`) consumed as a module within the larger LittleThings iOS app monorepo.
