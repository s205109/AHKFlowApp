# 033 - CLI retries unsafe HTTP methods

## Metadata

- **Epic**: CLI reliability
- **Type**: Bug
- **Interfaces**: CLI

## Summary

The CLI resilience pipeline retries every request up to 10 times regardless of HTTP method, so a
`POST` that the API already processed can be sent again — duplicate writes from a single command.
The Blazor clients were fixed centrally in `AddApiClient`; the CLI has its own pipeline and was
left untouched.

## User story

As a CLI user, I want `ahkflow hotstring new` to create exactly one hotstring so that a slow or
restarting API never leaves me with duplicates.

## Problem detail

`CliApiFailureDetector.ShouldRetry` is method-agnostic. It retries on `HttpRequestException`,
`TimeoutRejectedException`, and status 408 / 429 / 502 / 503 / 504. None of these prove the request
was *not* processed:

- **504 Gateway Timeout** — the gateway gave up; the origin may have committed the write.
- **`HttpRequestException` after send** — the connection dropped after the request left the client.

`AddCliApiResilience` is applied to three clients (`Program.cs:57,62,67`). Two of them issue unsafe
methods:

| Client | Unsafe methods | At risk |
|---|---|---|
| hotstrings | `POST` (`NewHotstringCommand`) | Yes — duplicate create |
| profiles | none today | Latent — pipeline permits it |
| downloads | none (GET-only) | No |

## Why the Blazor fix does not transfer

`options.Retry.DisableForUnsafeHttpMethods()` needs `HttpStandardResilienceOptions`. The CLI builds
a bespoke pipeline via `AddResilienceHandler` precisely because it needs the long warm-up retry
(10 × 2s) that wakes a stopped Azure App Service — including the 403-HTML "web app is stopped"
detection. Simply refusing to retry unsafe methods would restore correctness but break warm-up for
write commands: `ahkflow hotstring new` against a cold app would fail instead of waiting.

## Acceptance criteria

- [ ] `ahkflow hotstring new` never creates more than one hotstring, even when the first attempt
      returns 504 or the connection drops after send.
- [ ] Warm-up against a stopped/cold App Service still succeeds for write commands (no regression
      of the 10 × 2s wake behaviour).
- [ ] Read-only commands (`list`, downloads) keep their current retry behaviour unchanged.
- [ ] Chosen approach is covered by tests in `AHKFlowApp.CLI.Tests`, asserting behaviour (request
      count reaching the API) rather than pipeline wiring.

## Candidate approaches

1. **Idempotency key + server-side dedup** — CLI sends a per-command `Idempotency-Key`; API stores
   and replays the first result. Correct under all retry causes; costs an API change and storage.
2. **GET-only warm-up** — probe `/health` (safe, retried aggressively) until the app answers, then
   send the write once with retries disabled for unsafe methods. No API change; warm-up latency
   moves to the probe.
3. **Retry unsafe methods only on pre-send failures** — narrow `ShouldRetry` to causes that prove
   the request never reached the origin (connect failures, 403-HTML stopped-app page). Cheapest;
   leaves 504 correctly un-retried but relies on distinguishing pre- from post-send exceptions.

Approach 2 is the smallest correct change if no API work is in scope; approach 1 is the durable fix.

## Out of scope

- Blazor UI clients — fixed on `fix/wt-blazor-retry-unsafe-methods` via `DisableForUnsafeHttpMethods()`.
- Backend `EnableRetryOnFailure()` (EF Core) — separate concern, transactional and already safe.
- Reworking the CLI auth/token pipeline.

## Notes / dependencies

- `src/Tools/AHKFlowApp.CLI/Services/CliHttpClientBuilderExtensions.cs` — pipeline definition.
- `src/Tools/AHKFlowApp.CLI/Services/CliApiFailureDetector.cs` — `ShouldRetry` predicate.
- Raised in review of the Blazor retry fix; deliberately deferred rather than bundled into it.
