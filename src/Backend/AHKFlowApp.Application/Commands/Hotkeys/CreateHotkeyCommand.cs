using System.Diagnostics.CodeAnalysis;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record CreateHotkeyCommand(CreateHotkeyDto Input) : IRequest<Result<HotkeyDto>>;

public sealed class CreateHotkeyCommandValidator : AbstractValidator<CreateHotkeyCommand>
{
    public CreateHotkeyCommandValidator()
    {
        RuleFor(x => x.Input.Description).ValidDescription();
        RuleFor(x => x.Input.Key).ValidKey();
        RuleFor(x => x.Input.Parameters).ValidParameters();
        RuleFor(x => x.Input.Action).ValidAction();
        this.ValidProfileAssociation(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class CreateHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<CreateHotkeyCommand, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> Handle(CreateHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateHotkeyDto input = request.Input;

        bool duplicate = await db.Hotkeys.AnyAsync(
            h => h.OwnerOid == ownerOid
              && h.Key == input.Key
              && h.Ctrl == input.Ctrl
              && h.Alt == input.Alt
              && h.Shift == input.Shift
              && h.Win == input.Win,
            ct);

        if (duplicate)
            return Result.Conflict("A hotkey with this key + modifier combination already exists.");

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            int validCount = await db.Profiles
                .CountAsync(p => p.OwnerOid == ownerOid && input.ProfileIds.Contains(p.Id), ct);
            if (validCount != input.ProfileIds.Length)
                return Result.Invalid(new ValidationError("One or more ProfileIds do not exist for this user."));
        }

        var entity = Hotkey.Create(
            ownerOid,
            input.Description,
            input.Key,
            input.Ctrl,
            input.Alt,
            input.Shift,
            input.Win,
            input.Action,
            input.Parameters,
            input.AppliesToAllProfiles,
            clock);

        db.Hotkeys.Add(entity);

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            foreach (Guid pid in input.ProfileIds)
                db.HotkeyProfiles.Add(HotkeyProfile.Create(entity.Id, pid));
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotkey with this key + modifier combination already exists.");
        }

        await db.Entry(entity).Collection(h => h.Profiles).LoadAsync(ct);
        return Result.Success(entity.ToDto());
    }

    [ExcludeFromCodeCoverage]
    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
