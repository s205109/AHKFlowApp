using System.Diagnostics.CodeAnalysis;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record CreateProfileCommand(CreateProfileDto Input) : IRequest<Result<ProfileDto>>;

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
    : IRequestHandler<CreateProfileCommand, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> Handle(CreateProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateProfileDto input = request.Input;

        bool nameTaken = await db.Profiles.AnyAsync(
            p => p.OwnerOid == ownerOid && p.Name == input.Name, ct);
        if (nameTaken)
            return Result.Conflict($"A profile named '{input.Name}' already exists.");

        if (input.IsDefault)
        {
            await foreach (Profile existing in db.Profiles
                .Where(p => p.OwnerOid == ownerOid && p.IsDefault)
                .AsAsyncEnumerable()
                .WithCancellation(ct))
            {
                existing.MarkDefault(false, clock);
            }
        }

        var profile = Profile.Create(
            ownerOid,
            input.Name,
            input.IsDefault,
            input.HeaderTemplate ?? DefaultProfileTemplates.Header,
            input.FooterTemplate ?? DefaultProfileTemplates.Footer,
            clock);

        db.Profiles.Add(profile);

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
