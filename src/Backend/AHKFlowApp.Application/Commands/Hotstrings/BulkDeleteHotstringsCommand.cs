using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record BulkDeleteHotstringsCommand(BulkDeleteRequestDto Input)
   ;

public sealed class BulkDeleteHotstringsCommandValidator : AbstractValidator<BulkDeleteHotstringsCommand>
{
    private const int MaxBulkDeleteIds = 500;

    public BulkDeleteHotstringsCommandValidator()
    {
        RuleFor(x => x.Input.Ids)
            .Cascade(CascadeMode.Stop)
            .NotEmpty()
            .WithMessage("At least one id is required.")
            .Must(ids => ids.Length <= MaxBulkDeleteIds)
            .WithMessage($"Bulk delete supports at most {MaxBulkDeleteIds} ids.");
    }
}

internal sealed class BulkDeleteHotstringsCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<BulkDeleteHotstringsCommand, Result<BulkDeleteResultDto>>
{
    public async Task<Result<BulkDeleteResultDto>> ExecuteAsync(
        BulkDeleteHotstringsCommand request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Guid[] requestedIds = [.. request.Input.Ids.Distinct()];
        List<Hotstring> ownedRows = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid && requestedIds.Contains(h.Id))
            .ToListAsync(ct);

        Guid[] ownedIds = [.. ownedRows.Select(h => h.Id)];
        Guid[] missingIds = [.. requestedIds.Except(ownedIds)];

        if (ownedRows.Count > 0)
        {
            db.Hotstrings.RemoveRange(ownedRows);
            await db.SaveChangesAsync(ct);
        }

        return Result.Success(new BulkDeleteResultDto(ownedRows.Count, missingIds));
    }
}
