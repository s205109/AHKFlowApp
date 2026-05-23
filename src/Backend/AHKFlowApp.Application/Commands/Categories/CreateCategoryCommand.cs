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

public sealed record CreateCategoryCommand(CreateCategoryDto Input) : IRequest<Result<CategoryDto>>;

public sealed class CreateCategoryCommandValidator : AbstractValidator<CreateCategoryCommand>
{
    public CreateCategoryCommandValidator()
    {
        RuleFor(x => x.Input.Name).ValidCategoryName();
    }
}

internal sealed class CreateCategoryCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<CreateCategoryCommand, Result<CategoryDto>>
{
    public async Task<Result<CategoryDto>> Handle(CreateCategoryCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        string name = request.Input.Name.Trim();

        bool nameTaken = await db.Categories.AnyAsync(
            c => c.OwnerOid == ownerOid && c.Name == name, ct);
        if (nameTaken)
            return Result.Conflict($"A category named '{name}' already exists.");

        var entity = Category.Create(ownerOid, name, clock);
        db.Categories.Add(entity);

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
