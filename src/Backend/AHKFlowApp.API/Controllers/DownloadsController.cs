using System.Text;
using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Downloads;
using Ardalis.Result;
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
public sealed class DownloadsController(
    IUseCase<GenerateProfileScriptQuery, Result<ProfileScript>> generateProfileScript,
    IUseCase<GetProfileScriptPreviewQuery, Result<ProfileScriptPreviewDto>> getProfileScriptPreview,
    IUseCase<GenerateAllProfileScriptsZipQuery, Result<ProfileScriptZip>> generateAllProfileScriptsZip) : ControllerBase
{
    private const string AhkContentType = "text/plain; charset=utf-8";
    private const string ZipContentType = "application/zip";

    /// <summary>Generated AHK v2 script for a single profile.</summary>
    [HttpGet("{profileId:guid}")]
    [Produces(AhkContentType)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetProfile(Guid profileId, CancellationToken ct)
    {
        Result<ProfileScript> result = await generateProfileScript.ExecuteAsync(new GenerateProfileScriptQuery(profileId), ct);
        if (!result.IsSuccess)
            return result.ToProblemActionResult(this).Result!;

        byte[] bytes = Encoding.UTF8.GetBytes(result.Value.Content);
        return File(bytes, AhkContentType, fileDownloadName: result.Value.FileName);
    }

    /// <summary>Generated AHK v2 script preview for a single profile.</summary>
    [HttpGet("{profileId:guid}/preview")]
    [ProducesResponseType(typeof(ProfileScriptPreviewDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ProfileScriptPreviewDto>> PreviewProfile(Guid profileId, CancellationToken ct)
    {
        Result<ProfileScriptPreviewDto> result =
            await getProfileScriptPreview.ExecuteAsync(new GetProfileScriptPreviewQuery(profileId), ct);

        return result.ToProblemActionResult(this);
    }

    /// <summary>Zip containing one .ahk per profile owned by the current user.</summary>
    [HttpGet("zip")]
    [Produces(ZipContentType)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAllZip(CancellationToken ct)
    {
        Result<ProfileScriptZip> result = await generateAllProfileScriptsZip.ExecuteAsync(new GenerateAllProfileScriptsZipQuery(), ct);
        if (!result.IsSuccess)
            return result.ToProblemActionResult(this).Result!;

        return File(result.Value.Content, ZipContentType, fileDownloadName: result.Value.FileName);
    }
}
