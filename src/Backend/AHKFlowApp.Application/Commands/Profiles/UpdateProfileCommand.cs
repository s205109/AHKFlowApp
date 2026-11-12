using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record UpdateProfileCommand(Guid Id, UpdateProfileDto Input);

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
    : IUseCaseHandler<UpdateProfileCommand, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> ExecuteAsync(UpdateProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        UpdateProfileDto input = request.Input;

        // The transaction needs the execution strategy, because the context retries on failure.
        // The strategy can run this delegate again, so every attempt starts from an empty tracker.
        IExecutionStrategy strategy = db.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async token =>
        {
            db.ClearTracking();
            await using IDbContextTransaction tx = await db.BeginTransactionAsync(token);

            Profile? profile = await db.Profiles.FirstOrDefaultAsync(
                p => p.Id == request.Id && p.OwnerOid == ownerOid, token);
            if (profile is null)
                return Result<ProfileDto>.NotFound();

            if (input.Name != profile.Name)
            {
                bool nameTaken = await db.Profiles.AnyAsync(
                    p => p.OwnerOid == ownerOid && p.Id != profile.Id && p.Name == input.Name, token);
                if (nameTaken)
                    return Result<ProfileDto>.Conflict($"A profile named '{input.Name}' already exists.");
            }

            try
            {
                // Save 1 clears the old default. The target changes only after it,
                // so save 1 does not send the target too.
                if (input.IsDefault && !profile.IsDefault)
                    await ProfileDefaults.ClearOthersAsync(db, ownerOid, profile.Id, clock, token);

                profile.Update(input.Name, input.HeaderTemplate, input.FooterTemplate, clock);
                if (input.IsDefault != profile.IsDefault)
                    profile.MarkDefault(input.IsDefault, clock);

                await db.SaveChangesAsync(token);   // save 2
            }
            catch (DbUpdateException ex) when (ex.IsUniqueIndexViolation(ProfileIndexNames.OwnerDefault))
            {
                return Result<ProfileDto>.Conflict(ProfileDefaults.ChangedAtTheSameTime);
            }
            catch (DbUpdateException ex) when (ex.IsUniqueIndexViolation(ProfileIndexNames.OwnerName))
            {
                return Result<ProfileDto>.Conflict($"A profile named '{input.Name}' already exists.");
            }

            await tx.CommitAsync(token);
            return Result.Success(profile.ToDto());
        }, ct);
    }
}
