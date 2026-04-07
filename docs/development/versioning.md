# Versioning with MinVer

AHKFlowApp uses [MinVer](https://github.com/adamralph/minver) for automated semantic versioning based on Git tags.

## Quick Start

### View Current Version

```bash
dotnet minver -t v
```

### Create a Release

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

## How It Works

MinVer reads Git tags (e.g., `v1.0.0`) and calculates the version during build:

- **Tagged commit**: `1.0.0`
- **After tag** (dev builds): `1.0.1-alpha.0.3+abc1234`
  - `3` = commits since last tag
  - `abc1234` = short commit SHA

### No Tags?

MinVer defaults to `0.0.0-alpha.0`. Create your first tag:

```bash
git tag v0.1.0 -m "Initial version"
git push origin v0.1.0
```

## Semantic Versioning

Follow [SemVer 2.0.0](https://semver.org/):

- **MAJOR** (`v2.0.0`): Breaking changes
- **MINOR** (`v1.1.0`): New features, backward compatible
- **PATCH** (`v1.0.1`): Bug fixes

## References

- [MinVer GitHub](https://github.com/adamralph/minver)
- [Semantic Versioning](https://semver.org/)
