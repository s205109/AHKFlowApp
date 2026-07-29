using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.KnownShortcuts;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.KnownShortcuts;
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
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class KnownShortcutsController(
    IUseCase<ListManagedKnownShortcutsQuery, Result<ManagedKnownShortcutCatalogDto>> list,
    IUseCase<CreateCustomKnownShortcutCommand, Result<ManagedKnownShortcutCatalogDto>> create,
    IUseCase<DeleteCustomKnownShortcutCommand, Result> delete,
    IUseCase<IgnoreKnownShortcutCommand, Result> ignore,
    IUseCase<RestoreKnownShortcutCommand, Result> restore) : ControllerBase
{
    /// <summary>Every known shortcut, ignored uses included so they can be brought back.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(ManagedKnownShortcutCatalogDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<ManagedKnownShortcutCatalogDto>> List(CancellationToken ct) =>
        (await list.ExecuteAsync(new ListManagedKnownShortcutsQuery(), ct)).ToProblemActionResult(this);

    /// <summary>Record something the owner knows uses a combination.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(ManagedKnownShortcutCatalogDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ManagedKnownShortcutCatalogDto>> Create(
        [FromBody] CreateCustomKnownShortcutDto input, CancellationToken ct) =>
        (await create.ExecuteAsync(new CreateCustomKnownShortcutCommand(input), ct)).ToProblemActionResult(this);

    /// <summary>Remove one of the owner's own records.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Delete(Guid id, CancellationToken ct)
    {
        // The success branch is written by hand: on the non-generic Result, ToProblemActionResult
        // returns 200, and these three routes advertise 204.
        Result result = await delete.ExecuteAsync(new DeleteCustomKnownShortcutCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }

    /// <summary>Stop warning about one built-in use. The others on the same keys still warn.</summary>
    [HttpPost("ignore")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Ignore([FromBody] KnownShortcutUseRefDto input, CancellationToken ct)
    {
        Result result = await ignore.ExecuteAsync(
            new IgnoreKnownShortcutCommand(input.ShortcutId, input.UsedBy), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }

    /// <summary>Warn about a built-in use again.</summary>
    [HttpPost("restore")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Restore([FromBody] KnownShortcutUseRefDto input, CancellationToken ct)
    {
        Result result = await restore.ExecuteAsync(
            new RestoreKnownShortcutCommand(input.ShortcutId, input.UsedBy), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }
}
