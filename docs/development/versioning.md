# Versioning with MinVer

AHKFlowApp uses [MinVer](https://github.com/adamralph/minver) for automated semantic versioning based on Git tags.

## Quick Start

### Create a Release Tag

1. **Tag the commit:**
   ```bash
   git tag v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```

2. **Build:**
   ```bash
   dotnet build -c Release
   ```

That's it! MinVer automatically calculates and injects the version.

## GitHub Release Process

Use this process after the release commit has been merged to `main`.

### 1. Choose the version

Use SemVer and the repository tag prefix `v`:

- `v1.0.1` for a bug fix.
- `v1.1.0` for a backward-compatible feature release.
- `v2.0.0` for a breaking release.

For a first public or early CLI release, prefer a conservative version such as `v0.1.0` unless the product is ready for `v1.0.0`.

### 2. Create and push the tag

```powershell
git switch main
git pull --ff-only origin main

$tag = "v0.1.0"

git tag -a $tag -m "Release $tag"
git push origin $tag
```

Pushing a `v*` tag triggers the release workflows that listen for version tags.

### 3. CLI release prerequisites

The `Release CLI` workflow packages `ahkflow-win-x64.zip` and creates or updates a GitHub Release. Before pushing the tag, confirm these production values are configured in GitHub:

- Repository secret: `AZURE_API_BASE_URL_PROD`
- Repository variable: `AZURE_AD_CLIENT_ID_PROD`
- Repository variable: `AZURE_AD_TENANT_ID_PROD`

The workflow injects these values into the packaged `appsettings.json`. Do not commit production values to source control.

### 4. Watch the workflow

```powershell
gh run list --workflow "Release CLI" --limit 5
gh run watch
```

When the workflow completes, open the release:

```powershell
gh release view $tag --web
```

The release should include `ahkflow-win-x64.zip`.

### 5. Manual release workflow rerun

If the tag already exists and you need to rebuild or re-upload the CLI asset, run the workflow manually with the same tag:

```powershell
gh workflow run "Release CLI" -f tag=$tag
gh run watch
```

The workflow validates that the tag exists and starts with `v`.

### 6. Smoke test the published CLI

After the GitHub Release asset is published:

1. Download `ahkflow-win-x64.zip` from the release.
2. Extract it on Windows.
3. Run:

   ```powershell
   .\ahkflow.exe --help
   .\ahkflow.exe login
   .\ahkflow.exe hotstring list
   .\ahkflow.exe logout
   ```

Expected results:

- `--help` exits successfully and lists the CLI commands.
- `login` completes device-code sign-in against production Entra configuration.
- `hotstring list` reaches the production API without local `AHKFLOW_` environment variables.
- `logout` clears local sign-in state.

## How It Works

MinVer reads Git tags (e.g., `v1.0.0`) and calculates the version during build:

- **Tagged commit**: `1.0.0`
- **After tag** (dev builds): `1.0.1-alpha.0.3+abc1234`
  - `3` = commits since last tag
  - `abc1234` = short commit SHA

### Version States

| State | Example version |
|---|---|
| No tags yet | `0.0.0-alpha.0.5+abc1234` |
| On tag `v1.0.0` | `1.0.0` |
| 3 commits after `v1.0.0` | `1.0.1-alpha.0.3+def5678` |

### No Tags?

MinVer defaults to `0.0.0-alpha.0.N+<sha>`. Create your first tag:

```bash
git tag v0.1.0 -m "Initial version"
git push origin v0.1.0
```

## Semantic Versioning

Follow [SemVer 2.0.0](https://semver.org/):

- **MAJOR** (`v2.0.0`): Breaking changes
- **MINOR** (`v1.1.0`): New features, backward compatible
- **PATCH** (`v1.0.1`): Bug fixes

## Checking the Version Locally

Use the `minver-cli` dotnet global tool to inspect the current version without building:

```powershell
# Install once
dotnet tool install --global minver-cli

# Run from the repo root
minver --tag-prefix v
```

## Checking the Version at Runtime

Once deployed, the version is available via the API:

```
GET /api/v1/version   → { "version": "<minver-version>" }
GET /api/v1/health    → { ..., "version": "<minver-version>", ... }
```

## References

- [MinVer GitHub](https://github.com/adamralph/minver)
- [Semantic Versioning](https://semver.org/)
