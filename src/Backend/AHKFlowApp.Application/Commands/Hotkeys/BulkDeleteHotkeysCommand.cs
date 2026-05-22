using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record BulkDeleteHotkeysCommand(BulkDeleteRequestDto Input)
    : IRequest<Result<BulkDeleteResultDto>>;

public sealed class BulkDeleteHotkeysCommandValidator : AbstractValidator<BulkDeleteHotkeysCommand>
{
    private const int MaxBulkDeleteIds = 500;

    public BulkDeleteHotkeysCommandValidator()
    {
        RuleFor(x => x.Input.Ids)
            .Cascade(CascadeMode.Stop)
            .NotEmpty()
            .WithMessage("At least one id is required.")
            .Must(ids => ids.Length <= MaxBulkDeleteIds)
            .WithMessage($"Bulk delete supports at most {MaxBulkDeleteIds} ids.");
    }
}

internal sealed class BulkDeleteHotkeysCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<BulkDeleteHotkeysCommand, Result<BulkDeleteResultDto>>
{
    public async Task<Result<BulkDeleteResultDto>> Handle(
        BulkDeleteHotkeysCommand request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Guid[] requestedIds = [.. request.Input.Ids.Distinct()];
        List<Hotkey> ownedRows = await db.Hotkeys
            .Where(h => h.OwnerOid == ownerOid && requestedIds.Contains(h.Id))
            .ToListAsync(ct);

        Guid[] ownedIds = [.. ownedRows.Select(h => h.Id)];
        Guid[] missingIds = [.. requestedIds.Except(ownedIds)];

        if (ownedRows.Count > 0)
        {
            db.Hotkeys.RemoveRange(ownedRows);
            await db.SaveChangesAsync(ct);
        }

        return Result.Success(new BulkDeleteResultDto(ownedRows.Count, missingIds));
    }
}
