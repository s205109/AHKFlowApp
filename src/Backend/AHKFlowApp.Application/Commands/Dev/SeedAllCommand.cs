using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;
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

        // The DbContext is configured with EnableRetryOnFailure, so a manual
        // transaction must run inside an execution strategy — the strategy
        // re-runs the whole unit on a transient failure.
        IExecutionStrategy strategy = db.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async token =>
        {
            // `await using` rolls the transaction back if it is disposed without
            // a commit — including when a child step throws. Unexpected
            // exceptions are left to GlobalExceptionMiddleware; the handler
            // never swallows them.
            await using IDbContextTransaction tx = await db.BeginTransactionAsync(token);

            Result<IReadOnlyList<CategoryDto>> catResult = await mediator.Send(new SeedCategoriesCommand(request.Reset), token);
            if (!catResult.IsSuccess)
            {
                await tx.RollbackAsync(token);
                return Result.Error("seed-all: categories step failed");
            }

            Result<PagedList<HotstringDto>> hsResult = await mediator.Send(new SeedHotstringsCommand(request.Reset), token);
            if (!hsResult.IsSuccess)
            {
                await tx.RollbackAsync(token);
                return Result.Error("seed-all: hotstrings step failed");
            }

            Result<PagedList<HotkeyDto>> hkResult = await mediator.Send(new SeedHotkeysCommand(request.Reset), token);
            if (!hkResult.IsSuccess)
            {
                await tx.RollbackAsync(token);
                return Result.Error("seed-all: hotkeys step failed");
            }

            await tx.CommitAsync(token);

            return Result.Success(new SeedAllResultDto(
                CategoriesCount: catResult.Value.Count,
                HotstringsCount: hsResult.Value.TotalCount,
                HotkeysCount: hkResult.Value.TotalCount));
        }, ct);
    }
}
