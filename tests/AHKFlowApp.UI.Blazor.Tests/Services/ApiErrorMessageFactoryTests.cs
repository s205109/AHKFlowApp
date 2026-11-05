using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class ApiErrorMessageFactoryTests
{
    [Fact]
    public void Build_ForValidationWithErrors_JoinsTheMessagesWithASpace()
    {
        // Every rule message ends in a period, so one space joins them into readable sentences.
        var problem = new ApiProblemDetails(null, "Validation failed", 400, null, null,
            new Dictionary<string, string[]> { ["Trigger"] = ["Trigger is required."], ["Replacement"] = ["Replacement is required."] });

        string msg = ApiErrorMessageFactory.Build(ApiResultStatus.Validation, problem);

        msg.Should().BeOneOf(
            "Trigger is required. Replacement is required.",
            "Replacement is required. Trigger is required.");
    }

    [Fact]
    public void Build_ForValidation_ShowsNoKeyPrefix()
    {
        // Each message names its own field by the label the owner sees. A key prefix such as
        // "ProfileIds:" only repeats it, in the form of a C# property name.
        var problem = new ApiProblemDetails(null, "Validation failed", 400, null, null,
            new Dictionary<string, string[]>
            {
                ["Input.ProfileIds"] = ["Choose at least one profile in Profiles, or turn on Apply to all profiles."],
            });

        string msg = ApiErrorMessageFactory.Build(ApiResultStatus.Validation, problem);

        msg.Should().Be("Choose at least one profile in Profiles, or turn on Apply to all profiles.");
    }

    [Fact]
    public void Build_ForNotFoundWithoutDetail_NamesNoEntity()
    {
        // Every page shares this helper, so the fallback must not name one entity.
        string msg = ApiErrorMessageFactory.Build(ApiResultStatus.NotFound, null);

        msg.Should().NotContain("otstring");
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
