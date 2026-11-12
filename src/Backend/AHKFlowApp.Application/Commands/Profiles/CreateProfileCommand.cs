using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record CreateProfileCommand(CreateProfileDto Input);

public sealed class CreateProfileCommandValidator : AbstractValidator<CreateProfileCommand>
{
    public CreateProfileCommandValidator()
    {
        RuleFor(x => x.Input.Name).ValidName();
        RuleFor(x => x.Input.HeaderTemplate).ValidHeaderTemplate();
        RuleFor(x => x.Input.FooterTemplate).ValidFooterTemplate();
    }
}

internal sealed class CreateProfileCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<CreateProfileCommand, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> ExecuteAsync(CreateProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateProfileDto input = request.Input;

        // The transaction needs the execution strategy, because the context retries on failure.
        // The strategy can run this delegate again, so every attempt starts from an empty tracker.
        IExecutionStrategy strategy = db.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async token =>
        {
            db.ClearTracking();
            await using IDbContextTransaction tx = await db.BeginTransactionAsync(token);

            bool nameTaken = await db.Profiles.AnyAsync(
                p => p.OwnerOid == ownerOid && p.Name == input.Name, token);
            if (nameTaken)
                return Result<ProfileDto>.Conflict($"A profile named '{input.Name}' already exists.");

            var profile = Profile.Create(
                ownerOid,
                input.Name,
                input.IsDefault,
                input.HeaderTemplate ?? DefaultProfileTemplates.Header,
                input.FooterTemplate ?? DefaultProfileTemplates.Footer,
                clock);

            try
            {
                // Save 1 clears the old default. The new profile is added only after it.
                if (input.IsDefault)
                    await ProfileDefaults.ClearOthersAsync(db, ownerOid, profile.Id, clock, token);

                db.Profiles.Add(profile);
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
