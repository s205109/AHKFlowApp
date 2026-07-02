using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Categories;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Categories;
using Ardalis.Result;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
[RequiredScope("access_as_user")]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status403Forbidden)]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class CategoriesController(
    IUseCase<ListCategoriesQuery, Result<PagedList<CategoryDto>>> listCategories,
    IUseCase<GetCategoryQuery, Result<CategoryDto>> getCategory,
    IUseCase<CreateCategoryCommand, Result<CategoryDto>> createCategory,
    IUseCase<UpdateCategoryCommand, Result<CategoryDto>> updateCategory,
    IUseCase<DeleteCategoryCommand, Result> deleteCategory) : ControllerBase
{
    /// <summary>List the current user's categories. Lazily seeds defaults on first call.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedList<CategoryDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PagedList<CategoryDto>>> List(
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default) =>
        (await listCategories.ExecuteAsync(new ListCategoriesQuery(search, page, pageSize), ct))
            .ToProblemActionResult(this);

    /// <summary>Get a category by id.</summary>
    [HttpGet("{id:guid}", Name = "GetCategory")]
    [ProducesResponseType(typeof(CategoryDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CategoryDto>> Get(Guid id, CancellationToken ct) =>
        (await getCategory.ExecuteAsync(new GetCategoryQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Create a new category for the current user.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(CategoryDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CategoryDto>> Create([FromBody] CreateCategoryDto dto, CancellationToken ct)
    {
        Result<CategoryDto> result = await createCategory.ExecuteAsync(new CreateCategoryCommand(dto), ct);
        return result.IsSuccess
            ? CreatedAtRoute("GetCategory", new { id = result.Value.Id }, result.Value)
            : result.ToProblemActionResult(this);
    }

    /// <summary>Update a category.</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(CategoryDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CategoryDto>> Update(Guid id, [FromBody] UpdateCategoryDto dto, CancellationToken ct) =>
        (await updateCategory.ExecuteAsync(new UpdateCategoryCommand(id, dto), ct)).ToProblemActionResult(this);

    /// <summary>Delete a category.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Delete(Guid id, CancellationToken ct)
    {
        Result result = await deleteCategory.ExecuteAsync(new DeleteCategoryCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }
}
