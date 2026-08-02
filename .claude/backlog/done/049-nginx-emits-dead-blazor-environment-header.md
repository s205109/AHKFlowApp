# 049 - Decide what to do with the dead Blazor-Environment header in nginx

## Metadata

- **Epic**: Developer experience
- **Type**: Chore
- **Interfaces**: UI

## Summary

`src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf` still sends a `Blazor-Environment` header. In .NET 10 a standalone Blazor WebAssembly app does not read that header, so the setting does nothing. Decide whether to delete it or keep it with an accurate comment.

## User story

As a developer reading the nginx configuration, I want it to be clear whether the `Blazor-Environment` header does anything, so that I do not copy a setting that has no effect.

## Evidence

In .NET 10 the WebAssembly environment is fixed at build time by the `WasmApplicationEnvironmentName` MSBuild property. It is baked into `_framework/dotnet.js`. The `Blazor-Environment` HTTP header is no longer read. This was confirmed on the `fix/wt-no-auth-frontend-profile` branch, which corrected every document that claimed otherwise.

The nginx file emits the header at two places, `default.conf:10` and `:34`:

```
add_header Blazor-Environment "Local" always;
```

Nothing breaks today. The homelab container path works because `src/Frontend/AHKFlowApp.UI.Blazor/Dockerfile:25-26` copies `appsettings.Local.json` over `appsettings.json` before publish, so the configuration is baked into the image rather than selected by a header.

Two reviewers disagreed about whether this needs action:

- One judged the existing comment honest enough. It already says the header is *"kept as an explicit signal and for future use if standalone WASM honours it"*, which does not claim the header works.
- The other wanted the lines deleted, or a comment added stating plainly that .NET 10 ignores the header, on the grounds that a future reader will grep for `Blazor-Environment` and be misled.

That disagreement is why this is a decision to make rather than a defect to fix.

## Acceptance criteria

- [x] A decision is recorded: delete the two `add_header` lines, or keep them with a comment that states .NET 10 does not read the header
- [x] The chosen change is applied at both `default.conf:10` and `:34`
- [x] If the lines are deleted, the container path is verified to still serve the correct configuration

**Decision:** both `add_header` lines were deleted. Every other place in the
repository that mentions the header already says it is dead, so keeping it would
have left the nginx file as the only misleading text.

The .NET 10 release notes state the behaviour directly:
[Set the environment in standalone Blazor WebAssembly apps](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-10.0?view=aspnetcore-10.0#set-the-environment-in-standalone-blazor-webassembly-apps).
The Blazor environments page linked under **Notes / dependencies** also still shows
an nginx `add_header` recipe, but that section is version-gated to ASP.NET Core 3.1
through 9.0 and does not render on the .NET 10 view of the page.

## Out of scope

- Any change to how the WebAssembly environment is selected. That is settled: `WasmApplicationEnvironmentName` at build time.
- Any change to `Dockerfile` or to `appsettings.Local.json`.

## Notes / dependencies

- Related work: `docs/development/configuration-strategy.md` and `docs/environments.md` were corrected on the no-auth frontend branch. This nginx file was deliberately left out of that diff to keep it focused.
- Microsoft's guidance on the .NET 10 behaviour: [Blazor environments](https://learn.microsoft.com/aspnet/core/blazor/fundamentals/environments?view=aspnetcore-10.0).
