using System.Net;
using AHKFlowApp.UI.Blazor.Startup;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Startup;

public sealed class RequireApiConnectivityTests : BunitContext
{
    private const string ChildMarkup = "<div>app-content</div>";

    private readonly IHttpClientFactory _httpClientFactory = Substitute.For<IHttpClientFactory>();
    private readonly IWebAssemblyHostEnvironment _env = Substitute.For<IWebAssemblyHostEnvironment>();

    public RequireApiConnectivityTests()
    {
        JSInterop.Mode = JSRuntimeMode.Loose;
        Services.AddSingleton(_httpClientFactory);
        Services.AddSingleton(_env);
    }

    private void UseProbeHandler(Func<HttpRequestMessage, HttpResponseMessage> responder)
    {
        var client = new HttpClient(new StubHandler(responder)) { BaseAddress = new Uri("http://localhost/") };
        _httpClientFactory.CreateClient(RequireApiConnectivity.ProbeClientName).Returns(client);
    }

    [Fact]
    public void InDevelopment_WhenHealthOk_RendersChildContent()
    {
        _env.Environment.Returns("Development");
        UseProbeHandler(_ => new HttpResponseMessage(HttpStatusCode.OK));

        IRenderedComponent<RequireApiConnectivity> cut = Render<RequireApiConnectivity>(ps => ps
            .AddChildContent(ChildMarkup));

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("app-content"));
    }

    [Fact]
    public void InDevelopment_WhenHealthFails_RendersBackendUnreachable()
    {
        _env.Environment.Returns("Development");
        UseProbeHandler(_ => throw new HttpRequestException("CORS / connection refused"));

        IRenderedComponent<RequireApiConnectivity> cut = Render<RequireApiConnectivity>(ps => ps
            .AddChildContent(ChildMarkup));

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Can't reach the API"));
        cut.Markup.Should().NotContain("app-content");
    }

    [Fact]
    public void OutsideDevelopment_RendersChildContentWithoutProbing()
    {
        _env.Environment.Returns("Production");

        IRenderedComponent<RequireApiConnectivity> cut = Render<RequireApiConnectivity>(ps => ps
            .AddChildContent(ChildMarkup));

        cut.Markup.Should().Contain("app-content");
        _httpClientFactory.DidNotReceive().CreateClient(Arg.Any<string>());
    }

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(responder(request));
    }
}
