using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record PreviewHotstringImportCommand(string Script);

public sealed class PreviewHotstringImportCommandValidator : AbstractValidator<PreviewHotstringImportCommand>
{
    public PreviewHotstringImportCommandValidator()
    {
        RuleFor(x => x.Script)
            .Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("Script is required.")
            .MaximumLength(HotstringImportRules.MaxScriptLength)
            .WithMessage($"Script must be {HotstringImportRules.MaxScriptLength} characters or fewer.");
    }
}

internal sealed class PreviewHotstringImportCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<PreviewHotstringImportCommand, Result<HotstringImportPreviewDto>>
{
    public async Task<Result<HotstringImportPreviewDto>> ExecuteAsync(
        PreviewHotstringImportCommand request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        IReadOnlyList<HotstringImportRowDto> parsed = AhkHotstringParser.Parse(request.Script);
        if (parsed.Count > HotstringImportRules.MaxRows)
            return Result.Invalid(new ValidationError
            {
                Identifier = nameof(PreviewHotstringImportCommand.Script),
                ErrorMessage = $"Import supports at most {HotstringImportRules.MaxRows} hotstrings per file.",
            });

        // Imported rows are always global (no context), so they only ever collide with existing
        // global rows under the composite unique index — a contexted "btw" must never block
        // importing a global "btw".
        List<string> existing = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid && h.ContextMatchType == null && h.ContextValue == null)
            .Select(h => h.Trigger)
            .ToListAsync(ct);
        HashSet<string> existingSet = new(existing, StringComparer.OrdinalIgnoreCase);

        IReadOnlyList<HotstringImportRowDto> rows = HotstringImportClassifier.MarkDuplicates(parsed, existingSet);

        return Result.Success(new HotstringImportPreviewDto(
            [.. rows],
            ReadyCount: rows.Count(r => r.Status == HotstringImportRowStatus.Ready),
            WarningCount: rows.Count(r => r.Status == HotstringImportRowStatus.Warning),
            DuplicateCount: rows.Count(r => r.Status == HotstringImportRowStatus.Duplicate),
            InvalidCount: rows.Count(r => r.Status == HotstringImportRowStatus.Invalid)));
    }
}
