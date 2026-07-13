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

public sealed record CreateHotstringCommand(CreateHotstringDto Input);

public sealed class CreateHotstringCommandValidator : AbstractValidator<CreateHotstringCommand>
{
    public CreateHotstringCommandValidator()
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

internal sealed class CreateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(CreateHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateHotstringDto input = request.Input;

        // Raw stores the verbatim definition and derives its trigger server-side; the client-sent
        // Trigger is ignored. Normalize first, then parse — the parsed trigger drives the duplicate
        // check and entity construction. Validation (ValidatingUseCase) already guaranteed a valid Raw.
        string trigger = input.Trigger;
        string replacement = input.Replacement;
        if (input.Kind == HotstringKind.Raw)
        {
            replacement = RawHotstringDefinitionParser.Normalize(input.Replacement);
            trigger = RawHotstringDefinitionParser.Parse(replacement).Trigger;
        }

        bool duplicate = await db.Hotstrings.AnyAsync(
            h => h.OwnerOid == ownerOid
                && h.Trigger == trigger
                && h.ContextMatchType == input.ContextMatchType
                && h.ContextValue == input.ContextValue, ct);
        if (duplicate)
            return Result.Conflict(HotstringConflictMessages.DuplicateTrigger);

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

        var entity = Hotstring.Create(
            ownerOid,
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

        db.Hotstrings.Add(entity);

        if (!input.AppliesToAllProfiles && distinctProfileIds.Length > 0)
        {
            foreach (Guid pid in distinctProfileIds)
                db.HotstringProfiles.Add(HotstringProfile.Create(entity.Id, pid));
        }

        foreach (Guid cid in distinctCategoryIds)
            db.HotstringCategories.Add(HotstringCategory.Create(entity.Id, cid));

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return Result.Conflict(HotstringConflictMessages.DuplicateTrigger);
        }

        await db.Entry(entity).Collection(h => h.Profiles).LoadAsync(ct);
        await db.Entry(entity).Collection(h => h.Categories).LoadAsync(ct);
        return Result.Success(entity.ToDto());
    }
}
