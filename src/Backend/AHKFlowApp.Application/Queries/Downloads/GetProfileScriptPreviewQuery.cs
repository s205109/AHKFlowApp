using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.Downloads;

public sealed record GetProfileScriptPreviewQuery(Guid ProfileId);

internal sealed class GetProfileScriptPreviewQueryHandler(
    ProfileScriptLoader loader,
    ICurrentUser currentUser,
    AhkScriptGenerator generator,
    TimeProvider clock)
    : IUseCaseHandler<GetProfileScriptPreviewQuery, Result<ProfileScriptPreviewDto>>
{
    public async Task<Result<ProfileScriptPreviewDto>> ExecuteAsync(
        GetProfileScriptPreviewQuery request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Result<ProfileScriptLoader.LoadedProfile> loaded =
            await loader.LoadAsync(request.ProfileId, ownerOid, ct);
        if (!loaded.IsSuccess)
            return Result.NotFound();

        string content = generator.Generate(
            loaded.Value.Profile,
            loaded.Value.Hotstrings,
            loaded.Value.Hotkeys);

        return Result.Success(new ProfileScriptPreviewDto(
            content,
            loaded.Value.Hotstrings.Count,
            loaded.Value.Hotkeys.Count,
            clock.GetUtcNow()));
    }
}
