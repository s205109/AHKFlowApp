using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record UpdateHotstringCommand(Guid Id, UpdateHotstringDto Input);

public sealed class UpdateHotstringCommandValidator : AbstractValidator<UpdateHotstringCommand>
{
    public UpdateHotstringCommandValidator()
    {
        // Raw derives its trigger server-side (the client field is hidden), so the client-trigger
        // rules are gated off for Raw — the parsed trigger is validated by AddRawKindRules instead.
        RuleFor(x => x.Input.Trigger).ValidTrigger()
            .When(x => x.Input.Kind != HotstringKind.Raw);
        RuleFor(x => x.Input.Description)
            .MaximumLength(HotstringRules.DescriptionMaxLength)
            .WithMessage($"Description must be {HotstringRules.DescriptionMaxLength} characters or fewer.");
        RuleFor(x => x.Input.Kind)
            .Must(k => k is HotstringKind.Text or HotstringKind.DateTime or HotstringKind.Macro or HotstringKind.Raw)
            .WithMessage("Only Text, Date & time, Macro and Raw hotstrings are supported.");
        this.AddProfileAssociationRules(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
        this.AddDateTimeKindRules(
            x => x.Input.Kind,
            x => x.Input.Replacement,
            x => x.Input.DateTimeFormat,
            x => x.Input.DateOffsetAmount,
            x => x.Input.DateOffsetUnit);
        this.AddMacroKindRules(
            x => x.Input.Kind,
            x => x.Input.Replacement);
        this.AddRawKindRules(
            x => x.Input.Kind,
            x => x.Input.Replacement);
        this.AddWindowContextRules(
            x => x.Input.ContextMatchType,
            x => x.Input.ContextValue);
    }
}

internal sealed class UpdateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    IEntityHistoryRecorder recorder)
    : IUseCaseHandler<UpdateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(UpdateHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        UpdateHotstringDto input = request.Input;

        // Raw stores the verbatim definition and derives its trigger server-side; the client-sent
        // Trigger is ignored. Normalize first, then parse. Validation already guaranteed a valid Raw.
        string trigger = input.Trigger;
        string replacement = input.Replacement;
        if (input.Kind == HotstringKind.Raw)
        {
            replacement = RawHotstringDefinitionParser.Normalize(input.Replacement);
            trigger = RawHotstringDefinitionParser.Parse(replacement).Trigger;
        }

        Guid[] distinctProfileIds = input.ProfileIds?.Distinct().ToArray() ?? [];
        if (!input.AppliesToAllProfiles)
        {
            ValidationError? profileError = await OwnedIdsValidation.CheckOwnedIdsAsync(
                db.Profiles, p => p.OwnerOid == ownerOid && distinctProfileIds.Contains(p.Id),
                distinctProfileIds, "ProfileIds", ct);
            if (profileError is not null)
                return Result.Invalid(profileError);
        }

        string? description = string.IsNullOrWhiteSpace(input.Description) ? null : input.Description.Trim();

        Guid[] distinctCategoryIds = input.CategoryIds?.Distinct().ToArray() ?? [];
        ValidationError? categoryError = await OwnedIdsValidation.CheckOwnedIdsAsync(
            db.Categories, c => c.OwnerOid == ownerOid && distinctCategoryIds.Contains(c.Id),
            distinctCategoryIds, "CategoryIds", ct);
        if (categoryError is not null)
            return Result.Invalid(categoryError);

        EntityHistory historyEntry = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, ct);

        entity.Update(
            new HotstringDefinition(
                trigger,
                replacement,
                description,
                input.AppliesToAllProfiles,
                input.IsEndingCharacterRequired,
                input.IsTriggerInsideWord,
                input.Kind,
                input.IsCaseSensitive,
                input.OmitEndingCharacter,
                input.DateTimeFormat,
                input.DateOffsetAmount,
                input.DateOffsetUnit,
                input.ContextMatchType,
                input.ContextValue),
            clock);

        // Replace junction rows via the navigation collections only; adding to the
        // DbSet as well would double-add through EF navigation fixup
        db.HotstringProfiles.RemoveRange(entity.Profiles);
        entity.Profiles.Clear();

        if (!input.AppliesToAllProfiles && distinctProfileIds.Length > 0)
        {
            foreach (Guid pid in distinctProfileIds)
                entity.Profiles.Add(HotstringProfile.Create(entity.Id, pid));
        }

        db.HotstringCategories.RemoveRange(entity.Categories);
        entity.Categories.Clear();

        foreach (Guid cid in distinctCategoryIds)
            entity.Categories.Add(HotstringCategory.Create(entity.Id, cid));

        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntry, ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return ex.IsHistoryVersionConflict()
                ? Result.Conflict("The item was modified concurrently. Retry the operation.")
                : Result.Conflict(HotstringConflictMessages.DuplicateTrigger);
        }

        return Result.Success(entity.ToDto());
    }
}
