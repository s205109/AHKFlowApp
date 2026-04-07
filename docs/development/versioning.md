# Versioning

AHKFlowApp uses [MinVer](https://github.com/adamralph/minver) for automatic semantic versioning based on git tags. MinVer is a build-only tool (no runtime dependency) applied to `AHKFlowApp.API` and `AHKFlowApp.UI.Blazor`.

## How it works

MinVer runs during the build and sets the assembly version from the nearest reachable git tag using [Semantic Versioning 2.0](https://semver.org/).

| State | Example version |
|---|---|
| No tags yet | `0.0.0-alpha.0.5+abc1234` |
| On tag `v1.0.0` | `1.0.0` |
| 3 commits after `v1.0.0` | `1.0.1-alpha.0.3+def5678` |

The `+<sha>` suffix is the short git commit hash.

## Creating a release

```bash
git tag v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

The next build on or after that tag will produce version `1.0.0`.

## Checking the version

At runtime, the version is available from:
- `GET /api/v1/version` — returns `{ "version": "..." }`
- `GET /api/v1/health` — includes `"version"` in the response body
