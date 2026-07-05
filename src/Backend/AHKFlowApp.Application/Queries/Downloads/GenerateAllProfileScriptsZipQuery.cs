using System.IO.Compression;
using System.Text;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.Downloads;

public sealed record GenerateAllProfileScriptsZipQuery;

internal sealed class GenerateAllProfileScriptsZipQueryHandler(
    IUseCase<GenerateAllProfileScriptsQuery, Result<IReadOnlyList<ProfileScript>>> generateAllProfileScripts)
    : IUseCaseHandler<GenerateAllProfileScriptsZipQuery, Result<ProfileScriptZip>>
{
    private const string ZipFileName = "ahkflow_scripts.zip";

    public async Task<Result<ProfileScriptZip>> ExecuteAsync(
        GenerateAllProfileScriptsZipQuery request, CancellationToken ct)
    {
        Result<IReadOnlyList<ProfileScript>> scripts =
            await generateAllProfileScripts.ExecuteAsync(new GenerateAllProfileScriptsQuery(), ct);

        if (!scripts.IsSuccess)
        {
            return scripts.Status switch
            {
                ResultStatus.Unauthorized => Result.Unauthorized(),
                _ => Result.Error(scripts.Errors.FirstOrDefault() ?? "Failed to generate profile scripts."),
            };
        }

        byte[] zipBytes;
        using (MemoryStream ms = new())
        {
            using (ZipArchive archive = new(ms, ZipArchiveMode.Create, leaveOpen: true))
            {
                foreach (ProfileScript script in scripts.Value)
                {
                    ZipArchiveEntry entry = archive.CreateEntry(script.FileName, CompressionLevel.Optimal);
                    using Stream entryStream = await entry.OpenAsync();
                    using StreamWriter writer = new(entryStream, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
                    await writer.WriteAsync(script.Content);
                }
            }
            zipBytes = ms.ToArray();
        }

        return Result.Success(new ProfileScriptZip(zipBytes, ZipFileName));
    }
}
