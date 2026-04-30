using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Preferences;

public sealed record UpdateUserPreferenceCommand(UpdateUserPreferenceDto Dto) : IRequest<Result<UserPreferenceDto>>;

public sealed class UpdateUserPreferenceCommandValidator : AbstractValidator<UpdateUserPreferenceCommand>
{
    private static readonly int[] ValidRowsPerPage = [2, 10, 25, 50, 100];

    public UpdateUserPreferenceCommandValidator()
    {
        RuleFor(x => x.Dto.RowsPerPage)
            .Must(v => ValidRowsPerPage.Contains(v))
            .WithMessage("RowsPerPage must be 2, 10, 25, 50, or 100.");
    }
}

internal sealed class UpdateUserPreferenceCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<UpdateUserPreferenceCommand, Result<UserPreferenceDto>>
{
    public async Task<Result<UserPreferenceDto>> Handle(UpdateUserPreferenceCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        UserPreference? pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);

        if (pref is null)
        {
            pref = UserPreference.CreateDefault(ownerOid, clock);
            pref.Update(request.Dto.RowsPerPage, request.Dto.DarkMode, clock);
            db.UserPreferences.Add(pref);
        }
        else
        {
            pref.Update(request.Dto.RowsPerPage, request.Dto.DarkMode, clock);
        }

        await db.SaveChangesAsync(ct);
        return Result.Success(pref.ToDto());
    }
}
