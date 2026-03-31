---
alwaysApply: true
description: >
  Performance best practices for .NET: async patterns, resource management, hot-path optimizations.
---

# Performance Rules

- Always propagate `CancellationToken` through the entire call chain.
- Async all the way — no `.Result` or `.Wait()`. Only exception: `Program.cs` top-level statements.
- `TimeProvider` over `DateTime.Now` / `DateTime.UtcNow` — injectable and testable.
- `IHttpClientFactory` over `new HttpClient()` — prevents socket exhaustion.
- `ArrayPool<T>` / `MemoryPool<T>` for buffer-heavy operations.
- Compiled queries (`EF.CompileAsyncQuery`) for hot-path EF Core queries.
- `ValueTask<T>` over `Task<T>` for high-throughput paths that often complete synchronously.
