# 028 — CLI download command (`download ahk` + `download zip`) — Design

**Date:** 2026-05-09
**Epic:** Script generation & download
**Backlog item:** [028-cli-download-command.md](../../.claude/backlog/028-cli-download-command.md)

## Overview

Implement `ahkflow download ahk --profile <name>` and `ahkflow download zip` to fetch generated AutoHotkey scripts via the CLI. Single-profile reads `GET /api/v1/downloads/{profileId}` (text/plain); zip reads `GET /api/v1/downloads/zip` (application/zip). Output defaults to current directory using the server-provided filename; `-o <path>` overrides; `-o -` writes raw bytes to stdout. Auth via `AHKFLOW_TOKEN` (per 018; MSAL deferred to 029).

The 028 backlog item as written covers only single-profile download. Zip is included here because (a) `IDownloadsApiClient` was scaffolded in 018 with both methods, (b) 027b shipped the `/zip` endpoint already, (c) the work shape is identical, and (d) UI/CLI symmetry is cheap to maintain. The backlog item gets one extra acceptance line during implementation.

## Architecture

### File structure

```
src/Tools/AHKFlowApp.CLI/
├── Program.cs                            (modify: register IDownloadsApiClient)
├── Commands/
│   ├── RootCli.cs                        (modify: add DownloadCommand subcommand)
│   └── Downloads/
│       ├── DownloadCommand.cs            (verb group: `download`)
│       ├── AhkDownloadCommand.cs         (`ahkflow download ahk`)
│       └── ZipDownloadCommand.cs         (`ahkflow download zip`)
├── Services/
│   ├── IDownloadsApiClient.cs            (existing, unchanged)
│   └── DownloadsApiClient.cs             (new — typed HttpClient impl)
└── Output/
    └── DownloadDestination.cs            (new — resolves -o semantics + writes bytes)

tests/AHKFlowApp.CLI.Tests/
├── Commands/Downloads/
│   ├── AhkDownloadCommandTests.cs        (unit: parsing, -o variants, error mapping)
│   └── ZipDownloadCommandTests.cs        (unit: parsing, -o variants, error mapping)
├── Output/
│   └── DownloadDestinationTests.cs       (path resolution: dir / file / stdout / nested)
├── Services/
│   └── DownloadsApiClientTests.cs        (Content-Disposition parsing, fallbacks)
├── Infrastructure/
│   └── CliTestHost.cs                    (modify: also register IDownloadsApiClient in WithFactory + WithFakes)
└── Integration/
    └── DownloadCliIntegrationTests.cs    (end-to-end via CustomWebApplicationFactory)
```

### Key design decisions

1. **Mirror 018's command idioms.** Static `Build(IServiceProvider) → Command`. Resolve clients inside the action via `services.GetRequiredService<>()`. Same exception-to-exit-code chain. Same `parseResult.InvocationConfiguration.Output / .Error` for text writers.

2. **Subcommands, not flags.** `ahkflow download ahk` and `ahkflow download zip` — matches the backlog wording (`download ahk`) and keeps each subcommand's option set focused. Zip takes no profile arg; flag-based design (`download --profile X` vs `download --all`) would conflate two different inputs.

3. **`IDownloadsApiClient` interface stays as-is.** Already declared with both methods returning `DownloadResult(byte[] Bytes, string FileName, string ContentType)`. We only add the impl.

4. **Server-provided filename.** The 027 design locks the server filename format: `ahkflow_<safe_stem>.ahk` (per profile) and `ahkflow_scripts.zip` (zip). The CLI reads `Content-Disposition: attachment; filename=…` and uses that as-is — no client-side sanitisation. Falls back to `profile.ahk` / `ahkflow_scripts.zip` only if the header is missing or malformed.

5. **Output handling lives in one helper.** `DownloadDestination.Resolve(string? optionValue, string serverName) → DownloadTarget` returns either `DownloadTarget.Stdout` or `DownloadTarget.File(string path)`. `DownloadDestination.WriteAsync(target, bytes, ct)` does the I/O. The two commands share this verbatim.

6. **Stdout writes raw bytes.** `-o -` opens `Console.OpenStandardOutput()` directly and writes `bytes` to it — bypassing the parsed `TextWriter` so binary zips aren't UTF-8-mangled. Nothing else is printed when target is stdout (no "Wrote …" line). Pipes work cleanly: `ahkflow download zip -o - > out.zip`.

7. **Silent overwrite.** `File.WriteAllBytesAsync` to the resolved path. No `--force`. Server is the source of truth; matches `gh release download` and `cp` defaults.

8. **Profile name resolution mirrors `hotstring list`.** The download endpoint takes a profile id, so a `/profiles` call is required regardless. Mapping name → id client-side lets us emit a `"Profile '<n>' not found. Available: <comma-list>"` diagnostic instead of a bare server 404, matching the rest of the CLI.

9. **Exit codes — same chart as 018:**

   | Code | Meaning |
   |------|---------|
   | `0` | Success |
   | `1` | Server/network/unhandled error (5xx, transport failure) |
   | `2` | User error (400, 404 from server, unknown profile name) |
   | `3` | Auth error (env var unset, 401 from API) |

   404 maps to exit 2 here (vs 018 which doesn't get 404s) because `GET /api/v1/downloads/{profileId}` returns 404 for "profile not found OR not yours" — that's a user-facing input error.

## Command surface

### `ahkflow download ahk`

**Purpose:** Download the generated `.ahk` for a single profile.

**Signature:**

```
ahkflow download ahk --profile <name> [-o <path>] [--verbose]
```

**Options:**

| Option | Alias | Required | Description |
|---|---|---|---|
| `--profile` | `-p` | yes | Profile name (case-insensitive). |
| `--output` | `-o` | no | Output path. See "Output handling". |

**Behaviour:**

1. Resolve `--profile` to a Guid via `IProfilesApiClient.ListAsync`. Unknown → exit 2.
2. Call `IDownloadsApiClient.GetProfileScriptAsync(profileId, ct)` → `DownloadResult`.
3. Resolve target via `DownloadDestination.Resolve(option, result.FileName)`.
4. Write bytes; if writing to a file, print `"Wrote <path> (<n> bytes)"` to stdout.

### `ahkflow download zip`

**Purpose:** Download a zip containing one `.ahk` per profile owned by the current user.

**Signature:**

```
ahkflow download zip [-o <path>] [--verbose]
```

**Options:**

| Option | Alias | Required | Description |
|---|---|---|---|
| `--output` | `-o` | no | Output path. See "Output handling". |

**Behaviour:**

1. Call `IDownloadsApiClient.GetAllProfileScriptsZipAsync(ct)` → `DownloadResult` (filename `ahkflow_scripts.zip`).
2. Resolve target.
3. Write bytes; on file target, print `"Wrote <path> (<n> bytes)"`.

No profile resolution and no `IProfilesApiClient` call — the server scopes to the authenticated user automatically.

## Output handling

`DownloadDestination.Resolve(string? optionValue, string serverFileName)`:

| Input | Result |
|---|---|
| `null` (option omitted) | `File(<cwd>/<serverFileName>)` |
| `"-"` | `Stdout` |
| existing directory path | `File(<path>/<serverFileName>)` |
| anything else | `File(<path>)` (treated as exact filename; parent dirs created if missing) |

Edge cases:

- A path like `out/scripts/work.ahk` where `out/scripts/` doesn't exist → `File.WriteAllBytesAsync` after `Directory.CreateDirectory(Path.GetDirectoryName(path))`.
- Trailing separator on a non-existent path → still treated as filename; the trailing separator just produces a file with an empty name, which would error on the OS. Not worth special-casing.
- Server returns an empty filename → fall back to `profile.ahk` / `ahkflow_scripts.zip` constant in the API client before reaching the destination helper.

`DownloadDestination.WriteAsync`:

```csharp
public static async Task WriteAsync(DownloadTarget target, byte[] bytes, CancellationToken ct)
{
    switch (target)
    {
        case DownloadTarget.StdoutTarget:
            await using Stream stdout = Console.OpenStandardOutput();
            await stdout.WriteAsync(bytes, ct);
            break;
        case DownloadTarget.FileTarget file:
            string? dir = Path.GetDirectoryName(file.Path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            await File.WriteAllBytesAsync(file.Path, bytes, ct);
            break;
    }
}
```

(Sketch — final shape may differ slightly; tests pin behaviour.)

## API client

`DownloadsApiClient(HttpClient http) : IDownloadsApiClient`:

```csharp
public async Task<DownloadResult> GetProfileScriptAsync(Guid profileId, CancellationToken ct)
{
    using HttpResponseMessage response = await http.GetAsync($"api/v1/downloads/{profileId}", ct);
    if (!response.IsSuccessStatusCode)
    {
        string body = await response.Content.ReadAsStringAsync(ct);
        throw new ApiException((int)response.StatusCode, body);
    }
    byte[] bytes = await response.Content.ReadAsByteArrayAsync(ct);
    string fileName = ExtractFileName(response.Content.Headers.ContentDisposition) ?? "profile.ahk";
    string contentType = response.Content.Headers.ContentType?.ToString() ?? "text/plain";
    return new DownloadResult(bytes, fileName, contentType);
}
```

Zip method is identical with `api/v1/downloads/zip`, fallback name `ahkflow_scripts.zip`, fallback type `application/zip`.

`ExtractFileName` prefers `ContentDisposition.FileNameStar` (RFC 5987 — what ASP.NET Core sends for non-ASCII names), falls back to `FileName`. Strips surrounding quotes if present. Returns `null` on missing/empty header.

DI registration in `Program.cs`:

```csharp
builder.Services.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();
```

## Errors & exit codes

Reused verbatim from 018's catch chain. Concrete mapping for downloads:

| Source | Exit | stderr content |
|---|---|---|
| `NotAuthenticatedException` (env var unset) | 3 | `"Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token."` |
| Unknown profile name (pre-flight) | 2 | `"Profile '<n>' not found. Available: <list>"` |
| `ApiException 400` | 2 | server `body` |
| `ApiException 401` | 3 | `"Not signed in…"` (same constant) |
| `ApiException 404` (profile id not found / not yours) | 2 | server `body` |
| `ApiException 409` | 2 | server `body` (defensive — downloads endpoint shouldn't emit 409 today) |
| Other `ApiException` | 1 | `body` or `"Server error (<code>)."` |
| `HttpRequestException` | 1 | `ex.Message` |

## Testing

Stays inside the existing `[Collection("CliWebApi")]` group to share the SQL Server Testcontainer.

### Unit tests

`DownloadDestinationTests.cs`:
- `null` → `File(<cwd>/<server>)`.
- `"-"` → `Stdout`.
- Existing dir path → `File(<dir>/<server>)`.
- Nested filename in non-existent subdir → `File(<exact path>)` and dirs are created on write.
- Nested-dir path that already exists as a file → currently a file write that overwrites; document, don't gate.

`AhkDownloadCommandTests.cs` / `ZipDownloadCommandTests.cs` (use `CliTestHost.WithFakes`):
- Happy path with fake clients writes expected file and prints `"Wrote …"`.
- Unknown profile name → exit 2 with stderr listing available names. (ahk only)
- `-o -` writes raw bytes to a captured `Stream` stdout (test substitutes the writer); no "Wrote" line.
- Token unset (stub auth) → exit 3.
- 404 / 401 / 500 from fake client → exit 2 / 3 / 1 respectively.

`DownloadsApiClientTests.cs`:
- Parses `filename=` and `filename*=UTF-8''…` headers correctly; prefers `filename*` when both present.
- Falls back to `profile.ahk` / `ahkflow_scripts.zip` when header missing.
- Non-2xx body becomes `ApiException` with status + body.

### Integration tests (`DownloadCliIntegrationTests`)

Seed a profile + a couple of hotstrings, hit the real `Program` API via `WebApplicationFactory<Program>`, verify CLI output:

| Test | Asserts |
|---|---|
| `Ahk_Default_WritesFileInCwd` | `ahkflow_<name>.ahk` exists in temp cwd; content non-empty; exit 0. |
| `Ahk_OutputDir_WritesFileInsideDir` | `-o <tmpdir>` writes inside it. |
| `Ahk_OutputFile_WritesExactPath` | `-o <tmpdir>/custom.ahk` writes that path. |
| `Ahk_OutputDash_WritesBytesToStdout` | `-o -` produces raw bytes on stdout, no log line, exit 0. |
| `Ahk_UnknownProfile_Exit2` | `"Profile 'missing' not found"` to stderr. |
| `Zip_Default_WritesValidZip` | `ahkflow_scripts.zip` in cwd; opens as a valid `ZipArchive` with one entry per seeded profile. |
| `Zip_OutputDash_WritesBytesToStdout` | Raw zip bytes on stdout. |
| `Auth_TokenUnset_Exit3` | `--profile X` with no token → exit 3, stderr `"Not signed in"`. |
| `Overwrite_Silent` | Pre-existing file at target path is replaced without warning. |

Each test that writes files uses a temp directory created in test setup (`Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString())`) and `Directory.SetCurrentDirectory` for cwd-relative writes (restored in teardown). This keeps test artefacts off the repo.

`CliTestHost.WithFactory` gets one extra block:

```csharp
IHttpClientBuilder dBuilder = services.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(c =>
        c.BaseAddress = new Uri("http://localhost"))
    .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
    .AddHttpMessageHandler<BearerTokenHandler>();
if (counter is not null) dBuilder.AddHttpMessageHandler(() => new CountingHandler(counter));
```

## Backlog AC update

Add one new AC line to `028-cli-download-command.md` during implementation:

- [ ] `ahkflow download zip` downloads a zip of all the user's profile scripts to cwd (or `-o`).

The other ACs already cover both subcommands implicitly (output path, auth, tests).

## Out of scope

- MSAL device-code login (item 029).
- Selective zip (`--profiles a,b,c`) — the server endpoint doesn't support it.
- Resume / partial downloads, retry overrides — `AddStandardResilienceHandler` already covers transient retries.
- Progress reporting — payloads are tiny.
- `--json` metadata output for downloads — no AC, no concrete consumer.

## Unresolved questions

None.
