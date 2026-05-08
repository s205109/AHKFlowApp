using System.IO.Compression;
using System.Text;
using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Downloads;
using Ardalis.Result;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
[RequiredScope("access_as_user")]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status403Forbidden)]
public sealed class DownloadsController(IMediator mediator) : ControllerBase
{
    private const string AhkContentType = "text/plain; charset=utf-8";
    private const string ZipContentType = "application/zip";
    private const string ZipFileName = "ahkflow_scripts.zip";

    /// <summary>Generated AHK v2 script for a single profile.</summary>
    [HttpGet("{profileId:guid}")]
    [Produces(AhkContentType)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetProfile(Guid profileId, CancellationToken ct)
    {
        Result<ProfileScript> result = await mediator.Send(new GenerateProfileScriptQuery(profileId), ct);
        if (!result.IsSuccess)
            return result.ToProblemActionResult(this).Result!;

        byte[] bytes = Encoding.UTF8.GetBytes(result.Value.Content);
        return File(bytes, AhkContentType, fileDownloadName: result.Value.FileName);
    }

    /// <summary>Zip containing one .ahk per profile owned by the current user.</summary>
    [HttpGet("zip")]
    [Produces(ZipContentType)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAllZip(CancellationToken ct)
    {
        Result<IReadOnlyList<ProfileScript>> result = await mediator.Send(new GenerateAllProfileScriptsQuery(), ct);
        if (!result.IsSuccess)
            return result.ToProblemActionResult(this).Result!;

        byte[] zipBytes;
        using (MemoryStream ms = new())
        {
            using (ZipArchive archive = new(ms, ZipArchiveMode.Create, leaveOpen: true))
            {
                foreach (ProfileScript script in result.Value)
                {
                    ZipArchiveEntry entry = archive.CreateEntry(script.FileName, CompressionLevel.Optimal);
                    using Stream entryStream = entry.Open();
                    using StreamWriter writer = new(entryStream, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
                    await writer.WriteAsync(script.Content);
                }
            }
            zipBytes = ms.ToArray();
        }

        return File(zipBytes, ZipContentType, fileDownloadName: ZipFileName);
    }
}
