using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.Downloads;

public sealed record GenerateProfileScriptQuery(Guid ProfileId);

internal sealed class GenerateProfileScriptQueryHandler(
    ProfileScriptLoader loader,
    ICurrentUser currentUser,
    AhkScriptGenerator generator)
    : IUseCaseHandler<GenerateProfileScriptQuery, Result<ProfileScript>>
{
    public async Task<Result<ProfileScript>> ExecuteAsync(GenerateProfileScriptQuery request, CancellationToken ct)
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
        string fileName = AhkFileNaming.FileName(loaded.Value.Profile.Name);
        return Result.Success(new ProfileScript(fileName, content));
    }
}
