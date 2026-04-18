using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class ApiErrorMessageFactoryTests
{
    [Fact]
    public void Build_ForValidationWithErrors_FlattensFieldMessages()
    {
        var problem = new ApiProblemDetails(null, "Validation failed", 400, null, null,
            new Dictionary<string, string[]> { ["Trigger"] = ["must not be empty"], ["Replacement"] = ["must not be empty"] });

        string msg = ApiErrorMessageFactory.Build(ApiResultStatus.Validation, problem);

        msg.Should().Contain("Trigger: must not be empty");
        msg.Should().Contain("Replacement: must not be empty");
    }

    [Fact]
    public void Build_ForConflict_UsesProblemDetailOrFallback()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists for this profile", null, null);
        ApiErrorMessageFactory.Build(ApiResultStatus.Conflict, problem).Should().Be("Trigger already exists for this profile");
    }

    [Fact]
    public void Build_ForNetworkError_ReturnsGenericMessage()
    {
        ApiErrorMessageFactory.Build(ApiResultStatus.NetworkError, null).Should().Contain("Unable to reach the API");
    }
}
