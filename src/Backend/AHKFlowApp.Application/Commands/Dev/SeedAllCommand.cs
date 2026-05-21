using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore.Storage;

namespace AHKFlowApp.Application.Commands.Dev;

// Dev-only: runs the full seed pipeline (categories, hotstrings, hotkeys) inside
// a single transaction. Any failure rolls the whole pipeline back.
public sealed record SeedAllCommand(bool Reset) : IRequest<Result<SeedAllResultDto>>;

internal sealed class SeedAllCommandHandler(
    IAppDbContext db,
    IMediator mediator,
    AppEnvironment env)
    : IRequestHandler<SeedAllCommand, Result<SeedAllResultDto>>
{
    public async Task<Result<SeedAllResultDto>> Handle(SeedAllCommand request, CancellationToken ct)
    {
        if (!env.IsDevelopment)
            return Result.NotFound();

        // `await using` rolls the transaction back if it is disposed without a
        // commit — including when a child step throws. Unexpected exceptions are
        // left to GlobalExceptionMiddleware; the handler never swallows them.
        await using IDbContextTransaction tx = await db.BeginTransactionAsync(ct);

        Result<IReadOnlyList<CategoryDto>> catResult = await mediator.Send(new SeedCategoriesCommand(request.Reset), ct);
        if (!catResult.IsSuccess)
        {
            await tx.RollbackAsync(ct);
            return Result.Error("seed-all: categories step failed");
        }

        Result<PagedList<HotstringDto>> hsResult = await mediator.Send(new SeedHotstringsCommand(request.Reset), ct);
        if (!hsResult.IsSuccess)
        {
            await tx.RollbackAsync(ct);
            return Result.Error("seed-all: hotstrings step failed");
        }

        Result<PagedList<HotkeyDto>> hkResult = await mediator.Send(new SeedHotkeysCommand(request.Reset), ct);
        if (!hkResult.IsSuccess)
        {
            await tx.RollbackAsync(ct);
            return Result.Error("seed-all: hotkeys step failed");
        }

        await tx.CommitAsync(ct);

        return Result.Success(new SeedAllResultDto(
            CategoriesCount: catResult.Value.Count,
            HotstringsCount: hsResult.Value.TotalCount,
            HotkeysCount: hkResult.Value.TotalCount));
    }
}
