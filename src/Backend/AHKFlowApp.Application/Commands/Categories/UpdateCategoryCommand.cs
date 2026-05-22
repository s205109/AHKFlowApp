using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Categories;

public sealed record UpdateCategoryCommand(Guid Id, UpdateCategoryDto Input) : IRequest<Result<CategoryDto>>;

public sealed class UpdateCategoryCommandValidator : AbstractValidator<UpdateCategoryCommand>
{
    public UpdateCategoryCommandValidator()
    {
        RuleFor(x => x.Input.Name).ValidCategoryName();
    }
}

internal sealed class UpdateCategoryCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<UpdateCategoryCommand, Result<CategoryDto>>
{
    public async Task<Result<CategoryDto>> Handle(UpdateCategoryCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Category? entity = await db.Categories
            .FirstOrDefaultAsync(c => c.Id == request.Id && c.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        string name = request.Input.Name.Trim();

        if (!string.Equals(entity.Name, name, StringComparison.OrdinalIgnoreCase))
        {
            bool nameTaken = await db.Categories.AnyAsync(
                c => c.OwnerOid == ownerOid && c.Id != entity.Id && c.Name == name, ct);
            if (nameTaken)
                return Result.Conflict($"A category named '{name}' already exists.");
        }

        entity.Update(name, clock);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return Result.Conflict($"A category named '{name}' already exists.");
        }

        return Result.Success(entity.ToDto());
    }
}
