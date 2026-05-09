# 028 — CLI download command (`download ahk` + `download zip`) — Design

**Date:** 2026-05-09
**Epic:** Script generation & download
**Backlog item:** [028-cli-download-command.md](../../../.claude/backlog/028-cli-download-command.md)

## Overview

Implement `ahkflow download ahk --profile <name>` and `ahkflow download zip` to fetch generated AutoHotkey scripts via the CLI. Single-profile reads `GET /api/v1/downloads/{profileId}` (text/plain); zip reads `GET /api/v1/downloads/zip` (application/zip). Output defaults to current directory using the server-provided filename; `-o <path>` overrides; `-o -` writes raw bytes to stdout. Auth via `AHKFLOW_TOKEN` (per 018; MSAL deferred to 029).

The 028 backlog item as written covers only single-profile download. Zip is included here because (a) `IDownloadsApiClient` was scaffolded in 018 with both methods, (b) 027b shipped the `/zip` endpoint already, (c) the work shape is identical, and (d) UI/CLI symmetry is cheap to maintain. The backlog item gets one extra acceptance line during implementation.

## Architecture

### File structure

```
src/Tools/AHKFlowApp.CLI/
├── Program.cs                            (modify: register IDownloadsApiClient, BinaryStdout, WorkingDirectory)
├── Commands/
│   ├── RootCli.cs                        (modify: add DownloadCommand subcommand)
│   └── Downloads/
│       ├── DownloadCommand.cs            (verb group: `download`)
│       ├── AhkDownloadCommand.cs         (`ahkflow download ahk`)
│       └── ZipDownloadCommand.cs         (`ahkflow download zip`)
├── Services/
│   ├── IDownloadsApiClient.cs            (existing, unchanged)
│   ├── DownloadsApiClient.cs             (new — typed HttpClient impl)
│   ├── BinaryStdout.cs                   (new — injectable stdout Stream seam)
│   └── WorkingDirectory.cs               (new — injectable cwd seam)
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
│   └── CliTestHost.cs                    (modify: register IDownloadsApiClient + BinaryStdout + WorkingDirectory in WithFactory and WithFakes)
└── Integration/
    └── DownloadCliIntegrationTests.cs    (end-to-end via CustomWebApplicationFactory)
```

### Key design decisions

1. **Mirror 018's command idioms.** Static `Build(IServiceProvider) → Command`. Resolve clients inside the action via `services.GetRequiredService<>()`. Same exception-to-exit-code chain. Same `parseResult.InvocationConfiguration.Output / .Error` for text writers.

2. **Subcommands, not flags.** `ahkflow download ahk` and `ahkflow download zip` — matches the backlog wording (`download ahk`) and keeps each subcommand's option set focused. Zip takes no profile arg; flag-based design (`download --profile X` vs `download --all`) would conflate two different inputs.

3. **`IDownloadsApiClient` interface stays as-is.** Already declared with both methods returning `DownloadResult(byte[] Bytes, string FileName, string ContentType)`. We only add the impl.

4. **Server-provided filename is sanitised at the CLI boundary.** Even though the 027 server emits safe names (`ahkflow_<safe_stem>.ahk`, `ahkflow_scripts.zip`), `Content-Disposition` is still external input. The API client passes the raw header value through `SafeFileName(name, fallback)` before returning `DownloadResult.FileName`:

   - Strip directory components: `Path.GetFileName(name)`.
   - Reject empty / whitespace → fallback.
   - Reject any char in `Path.GetInvalidFileNameChars()` → fallback.
   - Reject rooted paths (`Path.IsPathRooted`) → fallback.

   Fallbacks are constants on the API client (`"profile.ahk"` / `"ahkflow_scripts.zip"`). The destination helper trusts what it receives.

5. **Output handling lives in one helper.** `DownloadDestination.Resolve(string? optionValue, string serverName, string baseDirectory) → DownloadTarget` returns either `DownloadTarget.Stdout` or `DownloadTarget.File(string path)`. The command resolves `baseDirectory` from a DI-registered `WorkingDirectory` wrapper around `Environment.CurrentDirectory` (symmetric with `BinaryStdout`); tests substitute a temp dir. No process-wide `Directory.SetCurrentDirectory` mutation — that breaks parallel xUnit collections.

6. **Stdout binary writes go through an injectable seam.** A small DI-registered service `BinaryStdout` wraps `() => Console.OpenStandardOutput()` in production and lets tests substitute a `MemoryStream`. `DownloadDestination.WriteAsync(target, bytes, binaryStdout, ct)` takes the seam as a parameter and never touches `Console` directly. This matches the rest of the CLI: text I/O via `parse.InvocationConfiguration.Output/.Error`, binary stdout via `BinaryStdout`. Pipes work cleanly (`ahkflow download zip -o - > out.zip`); tests assert against the captured stream.

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
3. Resolve target via `DownloadDestination.Resolve(option, result.FileName, workingDir.Get())`.
4. Write bytes via `DownloadDestination.WriteAsync(target, result.Bytes, binaryStdout, ct)`; if writing to a file, print `"Wrote <path> (<n> bytes)"` to stdout.

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

`DownloadDestination.Resolve(string? optionValue, string serverFileName, string baseDirectory)`:

| Input | Result |
|---|---|
| `null` (option omitted) | `File(<baseDirectory>/<serverFileName>)` |
| `"-"` | `Stdout` |
| ends with `/` or `\` | `File(<path>/<serverFileName>)`; dirs created if missing |
| existing directory | `File(<path>/<serverFileName>)`; dirs created if missing |
| anything else | `File(<path>)` (treated as exact filename; parent dirs created if missing) |

Order matters: trailing-separator and existing-directory checks run **before** the "anything else" fallback so `-o out/scripts/` and `-o out/scripts` (when `out/scripts/` exists) both resolve to the same place.

Edge cases:

- `out/scripts/work.ahk` where `out/scripts/` doesn't exist → directory created, then file written.
- `-o out/` where `out/` doesn't exist → treated as directory: created, then `<serverFileName>` written inside.
- Path that resolves to an existing file (and isn't a directory) → silent overwrite per decision 7.
- Server returns an empty / unsafe filename → API client falls back to the safe constant before the destination helper sees it (per decision 4).

`DownloadDestination.WriteAsync`:

```csharp
public static async Task WriteAsync(
    DownloadTarget target, byte[] bytes, BinaryStdout binaryStdout, CancellationToken ct)
{
    switch (target)
    {
        case DownloadTarget.StdoutTarget:
        {
            Stream stdout = binaryStdout.Open();
            await stdout.WriteAsync(bytes, ct);
            await stdout.FlushAsync(ct);
            // Don't dispose — caller owns lifetime (mirrors Console.OpenStandardOutput convention).
            break;
        }
        case DownloadTarget.FileTarget file:
        {
            string? dir = Path.GetDirectoryName(file.Path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            await File.WriteAllBytesAsync(file.Path, bytes, ct);
            break;
        }
    }
}
```

`BinaryStdout` (in `Services/`):

```csharp
public sealed class BinaryStdout(Func<Stream>? factory = null)
{
    private readonly Func<Stream> _factory = factory ?? Console.OpenStandardOutput;
    public Stream Open() => _factory();
}
```

Registered in `Program.cs`: `builder.Services.AddSingleton<BinaryStdout>();`. Tests inject `new BinaryStdout(() => memStream)`; the helper does not dispose what `Open()` returns, so the `MemoryStream` stays open for `ToArray()` after the command returns.

`WorkingDirectory` (in `Services/`) — symmetric:

```csharp
public sealed class WorkingDirectory(Func<string>? factory = null)
{
    private readonly Func<string> _factory = factory ?? (() => Environment.CurrentDirectory);
    public string Get() => _factory();
}
```

Registered alongside: `builder.Services.AddSingleton<WorkingDirectory>();`. Tests inject `new WorkingDirectory(() => tempDir)`. The command does `string baseDir = services.GetRequiredService<WorkingDirectory>().Get();` and passes it into `Resolve`.

(Sketches — final shape may differ slightly; tests pin behaviour.)

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
    string raw = ExtractFileName(response.Content.Headers.ContentDisposition);
    string fileName = SafeFileName(raw, fallback: "profile.ahk");
    string contentType = response.Content.Headers.ContentType?.ToString() ?? "text/plain";
    return new DownloadResult(bytes, fileName, contentType);
}
```

Zip method is identical with `api/v1/downloads/zip`, fallback name `ahkflow_scripts.zip`, fallback type `application/zip`.

`ExtractFileName` prefers `ContentDisposition.FileNameStar` (RFC 5987 — what ASP.NET Core sends for non-ASCII names), falls back to `FileName`. Strips surrounding quotes if present. Returns empty string on missing header.

`SafeFileName(string raw, string fallback)`:

```csharp
private static string SafeFileName(string raw, string fallback)
{
    if (string.IsNullOrWhiteSpace(raw)) return fallback;
    if (Path.IsPathRooted(raw)) return fallback;
    string basename = Path.GetFileName(raw);
    if (string.IsNullOrWhiteSpace(basename)) return fallback;
    if (basename.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return fallback;
    return basename;
}
```

Treats Content-Disposition as untrusted external input at the boundary; `DownloadDestination` downstream trusts whatever it receives.

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

`DownloadDestinationTests.cs` — pass an explicit `baseDirectory` (a per-test temp dir); never mutate `Environment.CurrentDirectory`:

- `null` → `File(<baseDir>/<server>)`.
- `"-"` → `Stdout`.
- Path ending in `/` (or `\` on Windows) → `File(<dir>/<server>)`; dirs created on write.
- Existing-directory path → `File(<dir>/<server>)`.
- Nested filename in non-existent subdir → `File(<exact path>)` and dirs are created on write.
- Path equal to an existing file → silent overwrite (per decision 7).

`AhkDownloadCommandTests.cs` / `ZipDownloadCommandTests.cs` (use `CliTestHost.WithFakes` extended to register `IDownloadsApiClient` + a `BinaryStdout` backed by a `MemoryStream`):

- Happy path with fake clients writes expected file and prints `"Wrote …"`.
- Unknown profile name → exit 2 with stderr listing available names. (ahk only)
- `-o -` writes raw bytes to the injected `MemoryStream`; no `"Wrote"` line on the parsed text stdout.
- Token unset (stub auth) → exit 3.
- 404 / 401 / 500 from fake client → exit 2 / 3 / 1 respectively.

`DownloadsApiClientTests.cs`:
- Parses `filename=` and `filename*=UTF-8''…` headers correctly; prefers `filename*` when both present.
- Falls back to `profile.ahk` / `ahkflow_scripts.zip` when header is missing, empty, contains path separators, contains invalid filename chars, or is rooted.
- Non-2xx body becomes `ApiException` with status + body.

### Integration tests (`DownloadCliIntegrationTests`)

Seed a profile + a couple of hotstrings, hit the real `Program` API via `WebApplicationFactory<Program>`, verify CLI output:

Tests inject `WorkingDirectory(() => tempDir)` (per-test temp dir from `Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString())`, deleted in teardown) and `BinaryStdout(() => memStream)`. **No `Directory.SetCurrentDirectory`** — process-wide cwd mutation breaks parallel xUnit collections.

| Test | Asserts |
|---|---|
| `Ahk_Default_WritesFileInBaseDir` | `ahkflow_<name>.ahk` exists in temp baseDir; content non-empty; exit 0. |
| `Ahk_OutputDir_WritesFileInsideDir` | `-o <tmpdir>` (existing) writes inside it. |
| `Ahk_OutputDirTrailingSep_CreatesAndWrites` | `-o <new-dir>/` creates the dir and writes server filename inside. |
| `Ahk_OutputFile_WritesExactPath` | `-o <tmpdir>/custom.ahk` writes that path. |
| `Ahk_OutputDash_WritesBytesToInjectedStream` | `-o -` writes raw bytes to the injected `BinaryStdout` `MemoryStream`; nothing on parsed text stdout; exit 0. |
| `Ahk_UnknownProfile_Exit2` | `"Profile 'missing' not found"` to stderr. |
| `Zip_Default_WritesValidZip` | `ahkflow_scripts.zip` in baseDir; opens as a valid `ZipArchive` with one entry per seeded profile. |
| `Zip_OutputDash_WritesBytesToInjectedStream` | Raw zip bytes captured in injected `MemoryStream`; bytes parse as a valid zip. |
| `Auth_TokenUnset_Exit3` | `--profile X` with no token → exit 3, stderr `"Not signed in"`. |
| `Overwrite_Silent` | Pre-existing file at target path is replaced without warning. |

`CliTestHost.WithFactory` gets the new client + the two seams:

```csharp
IHttpClientBuilder dBuilder = services.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(c =>
        c.BaseAddress = new Uri("http://localhost"))
    .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
    .AddHttpMessageHandler<BearerTokenHandler>();
if (counter is not null) dBuilder.AddHttpMessageHandler(() => new CountingHandler(counter));

services.AddSingleton(new BinaryStdout(() => testStdoutStream));
services.AddSingleton(new WorkingDirectory(() => testBaseDir));
```

`testStdoutStream` and `testBaseDir` are passed in by the test (new optional `WithFactory` parameters); production `Program.cs` registers the parameterless defaults.

## Backlog AC update

Two changes to `028-cli-download-command.md` during implementation:

1. Add one new acceptance criterion line:
   - [ ] `ahkflow download zip` downloads a zip of all the user's profile scripts to cwd (or `-o`).

2. Adjust the existing out-of-scope line — `028.md:27` currently reads "Downloading additional artifacts." That conflicts with adding zip here. Replace with: "Downloading artifacts other than per-profile `.ahk` and the all-profiles zip (e.g., compiled `.exe`, signed bundles)."

The other ACs already cover both subcommands implicitly (output path, auth, tests).

## Out of scope

- MSAL device-code login (item 029).
- Selective zip (`--profiles a,b,c`) — the server endpoint doesn't support it.
- Resume / partial downloads, retry overrides — `AddStandardResilienceHandler` already covers transient retries.
- Progress reporting — payloads are tiny.
- `--json` metadata output for downloads — no AC, no concrete consumer.

## Unresolved questions

None.
