using System.Reflection;
using AHKFlowApp.API.Controllers;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using Xunit;

namespace AHKFlowApp.API.Tests.OpenApi;

public sealed class ProducesResponseTypeCoverageTests
{
    [Fact]
    public void EveryControllerAction_DeclaresExplicit2xxProducesResponseType()
    {
        Assembly apiAssembly = typeof(HotstringsController).Assembly;

        var offenders = apiAssembly.GetTypes()
            .Where(t => typeof(ControllerBase).IsAssignableFrom(t) && !t.IsAbstract)
            .SelectMany(t => t
                .GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                .Where(m => m.GetCustomAttributes<HttpMethodAttribute>().Any())
                .Select(m => new { Controller = t.Name, Action = m }))
            .Where(x => !x.Action.GetCustomAttributes<ProducesResponseTypeAttribute>()
                .Any(attr => attr.StatusCode is >= 200 and <= 299))
            .Select(x => $"{x.Controller}.{x.Action.Name}")
            .ToList();

        offenders.Should().BeEmpty(
            "every controller action must carry an explicit method-level [ProducesResponseType] " +
            "with a 2xx status code; Swashbuckle's inferred 200 is not a substitute");
    }

    // Backlog 162 gave both Revert actions a new outcome: a stored Snapshot that the current
    // rules refuse returns Result.Invalid, which maps to 400. A generated client reading
    // /openapi has no 400 branch unless the action declares one, so a refused Revert would
    // reach it as an unhandled status.
    [Theory]
    [InlineData(typeof(HotstringsController))]
    [InlineData(typeof(HotkeysController))]
    public void RevertAction_DeclaresBadRequest(Type controller)
    {
        MethodInfo revert = controller
            .GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
            .Single(m => m.Name == "Revert");

        revert.GetCustomAttributes<ProducesResponseTypeAttribute>()
            .Select(attr => attr.StatusCode)
            .Should().Contain(StatusCodes.Status400BadRequest,
                "a Revert refused by the definition rule check returns 400");
    }
}
