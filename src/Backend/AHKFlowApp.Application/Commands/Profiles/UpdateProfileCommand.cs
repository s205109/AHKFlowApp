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

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record UpdateProfileCommand(Guid Id, UpdateProfileDto Input) : IRequest<Result<ProfileDto>>;

public sealed class UpdateProfileCommandValidator : AbstractValidator<UpdateProfileCommand>
{
    public UpdateProfileCommandValidator()
    {
        RuleFor(x => x.Input.Name).ValidName();
        RuleFor(x => x.Input.HeaderTemplate).ValidHeaderTemplate();
        RuleFor(x => x.Input.FooterTemplate).ValidFooterTemplate();
    }
}

internal sealed class UpdateProfileCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<UpdateProfileCommand, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> Handle(UpdateProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.FirstOrDefaultAsync(
            p => p.Id == request.Id && p.OwnerOid == ownerOid, ct);
        if (profile is null)
            return Result.NotFound();

        UpdateProfileDto input = request.Input;

        if (input.Name != profile.Name)
        {
            bool nameTaken = await db.Profiles.AnyAsync(
                p => p.OwnerOid == ownerOid && p.Id != profile.Id && p.Name == input.Name, ct);
            if (nameTaken)
                return Result.Conflict($"A profile named '{input.Name}' already exists.");
        }

        if (input.IsDefault && !profile.IsDefault)
        {
            await foreach (Profile other in db.Profiles
                .Where(p => p.OwnerOid == ownerOid && p.IsDefault && p.Id != profile.Id)
                .AsAsyncEnumerable()
                .WithCancellation(ct))
            {
                other.MarkDefault(false, clock);
            }
        }

        profile.Update(input.Name, input.HeaderTemplate, input.FooterTemplate, clock);
        if (input.IsDefault != profile.IsDefault)
            profile.MarkDefault(input.IsDefault, clock);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict($"A profile named '{input.Name}' already exists.");
        }

        return Result.Success(profile.ToDto());
    }

    [ExcludeFromCodeCoverage]
    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
