# Search semantics

## Where this applies

`ListHotstringsQuery` and `ListHotkeysQuery` (Application layer). The CLI `ahkflow hotstring list --search` / `--grep` and the Blazor UI search boxes route through these handlers.

## How matching works

Both handlers use `EF.Functions.Like(field, "%term%")` on the searchable columns:

- Hotstrings: `Trigger`, `Replacement`.
- Hotkeys: `Description`, `Key`, and the free-text action columns `RunTarget`, `Text`, `SendKeysContent`, `Body`.

The `LIKE` predicate inherits the SQL Server column collation. The application's default collation is `SQL_Latin1_General_CP1_CI_AS` (case-insensitive, accent-sensitive), so `BTW` matches `btw` without any application-level normalization.

## Why there is no `ignoreCase` flag

We deliberately do **not** expose an `ignoreCase` query parameter on the API or a `--ignore-case` flag on the CLI:

- Case-insensitive matching is the user-facing default we want.
- A no-op flag (that accepts `ignoreCase=false` but returns CI results anyway) would mislead callers.
- True case-sensitive search would require pushing a `COLLATE SQL_Latin1_General_CP1_CS_AS` clause into every search predicate. There is no current user need for that, and it would tie application code to a SQL Server collation literal.
- An earlier review note (backlog 023) referred to an `ignoreCase` query param as a "known no-op". That param was never actually shipped — the note has been removed.

## If case-sensitive search becomes a requirement

Add a `COLLATE`-aware override to the search predicate (e.g. `EF.Functions.Collate(h.Trigger, "SQL_Latin1_General_CP1_CS_AS")`), gate it on a `CaseSensitive` flag on the query record, and expose it through the controller and CLI together. Update this doc when you do.
