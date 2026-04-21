using AHKFlowApp.API.Extensions;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Xunit;

namespace AHKFlowApp.API.Tests.Extensions;

public sealed class ProblemDetailsResultExtensionsTests
{
    private static ControllerBase NewController(string path = "/api/v1/hotstrings", string traceId = "trace-xyz")
    {
        var ctx = new DefaultHttpContext
        {
            TraceIdentifier = traceId
        };
        ctx.Request.Path = path;
        return new TestController { ControllerContext = new ControllerContext { HttpContext = ctx } };
    }

    private sealed class TestController : ControllerBase { }

    private static IActionResult Unwrap<T>(ActionResult<T> result) =>
        ((IConvertToActionResult)result).Convert();

    private static ProblemDetails ProblemOf(IActionResult result)
    {
        ObjectResult obj = result.Should().BeOfType<ObjectResult>().Subject;
        obj.ContentTypes.Should().Contain("application/problem+json");
        return obj.Value.Should().BeAssignableTo<ProblemDetails>().Subject;
    }

    [Fact]
    public void Success_WithValue_ReturnsOkObjectResult()
    {
        var result = Result<string>.Success("payload");

        IActionResult action = Unwrap(result.ToProblemActionResult(NewController()));

        OkObjectResult ok = action.Should().BeOfType<OkObjectResult>().Subject;
        ok.Value.Should().Be("payload");
    }

    [Fact]
    public void Success_NonGeneric_ReturnsOkResult()
    {
        ActionResult action = Result.Success().ToProblemActionResult(NewController());

        action.Should().BeOfType<OkResult>();
    }

    [Fact]
    public void NotFound_MapsTo404_WithStableTypeAndTitle()
    {
        ActionResult action = Result.NotFound().ToProblemActionResult(NewController());

        ProblemDetails pd = ProblemOf(action);
        pd.Status.Should().Be(StatusCodes.Status404NotFound);
        pd.Type.Should().Be(ProblemDetailsResultExtensions.TypeNotFound);
        pd.Title.Should().Be("Resource not found");
        pd.Instance.Should().Be("/api/v1/hotstrings");
        pd.Extensions["traceId"].Should().Be("trace-xyz");
    }

    [Fact]
    public void NotFound_WithMessage_PopulatesDetail()
    {
        ActionResult action = Result.NotFound("Hotstring 42 does not exist").ToProblemActionResult(NewController());

        ProblemDetails pd = ProblemOf(action);
        pd.Detail.Should().Be("Hotstring 42 does not exist");
    }

    [Fact]
    public void Conflict_MapsTo409_WithDetailFromErrors()
    {
        ActionResult action = Result
            .Conflict("A hotstring with this trigger already exists for the specified profile.")
            .ToProblemActionResult(NewController());

        ProblemDetails pd = ProblemOf(action);
        pd.Status.Should().Be(StatusCodes.Status409Conflict);
        pd.Type.Should().Be(ProblemDetailsResultExtensions.TypeConflict);
        pd.Title.Should().Be("Conflict");
        pd.Detail.Should().Contain("already exists");
    }

    [Fact]
    public void Unauthorized_MapsTo401()
    {
        ActionResult action = Result.Unauthorized().ToProblemActionResult(NewController());

        ProblemDetails pd = ProblemOf(action);
        pd.Status.Should().Be(StatusCodes.Status401Unauthorized);
        pd.Type.Should().Be(ProblemDetailsResultExtensions.TypeUnauthorized);
        pd.Title.Should().Be("Unauthorized");
    }

    [Fact]
    public void Forbidden_MapsTo403()
    {
        ActionResult action = Result.Forbidden().ToProblemActionResult(NewController());

        ProblemDetails pd = ProblemOf(action);
        pd.Status.Should().Be(StatusCodes.Status403Forbidden);
        pd.Type.Should().Be(ProblemDetailsResultExtensions.TypeForbidden);
        pd.Title.Should().Be("Forbidden");
    }

    [Fact]
    public void Invalid_MapsTo400_WithFieldLevelErrors()
    {
        var result = Result<string>.Invalid(
            new ValidationError { Identifier = "Trigger", ErrorMessage = "required" },
            new ValidationError { Identifier = "Trigger", ErrorMessage = "too short" },
            new ValidationError { Identifier = "Replacement", ErrorMessage = "required" });

        IActionResult action = Unwrap(result.ToProblemActionResult(NewController()));

        ValidationProblemDetails pd = ProblemOf(action).Should().BeOfType<ValidationProblemDetails>().Subject;
        pd.Status.Should().Be(StatusCodes.Status400BadRequest);
        pd.Type.Should().Be(ProblemDetailsResultExtensions.TypeBadRequest);
        pd.Title.Should().Be("Validation failed");
        pd.Errors["Trigger"].Should().BeEquivalentTo(new[] { "required", "too short" });
        pd.Errors["Replacement"].Should().BeEquivalentTo(new[] { "required" });
    }

    [Fact]
    public void Error_MapsTo500_WithDetailFromErrors()
    {
        var result = Result<string>.Error("Downstream dependency failed");

        IActionResult action = Unwrap(result.ToProblemActionResult(NewController()));

        ProblemDetails pd = ProblemOf(action);
        pd.Status.Should().Be(StatusCodes.Status500InternalServerError);
        pd.Type.Should().Be(ProblemDetailsResultExtensions.TypeServerError);
        pd.Title.Should().Be("An unexpected error occurred");
        pd.Detail.Should().Be("Downstream dependency failed");
    }
}
