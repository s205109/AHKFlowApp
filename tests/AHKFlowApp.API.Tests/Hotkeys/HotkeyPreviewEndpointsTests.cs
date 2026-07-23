using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotkeys;

[Collection("WebApi")]
public sealed class HotkeyPreviewEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    [Fact]
    public async Task Preview_RunKind_ReturnsExactSnippet()
    {
        using HttpClient client = CreateAuthed();
        var dto = new HotkeyPreviewRequestDto(
            "Open Notepad", "n", HotkeyActionKind.Run, Win: true,
            RunTarget: "notepad", RunTargetKind: RunTargetKind.Application);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys/preview", dto);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyPreviewDto? body = await response.Content.ReadFromJsonAsync<HotkeyPreviewDto>();
        body!.Snippet.Should().Be("; Open Notepad\n#n::Run(\"notepad\")");
    }

    // The emitter throws InvalidOperationException on a null RemapDest — kind-conditional
    // validation must reject this before the handler ever runs, so the boundary sees a
    // ValidationException (-> 400 ProblemDetails), never an unhandled 500.
    [Fact]
    public async Task Preview_RemapWithoutDest_Returns400NotServerError()
    {
        using HttpClient client = CreateAuthed();
        var dto = new HotkeyPreviewRequestDto("Bad remap", "CapsLock", HotkeyActionKind.Remap);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys/preview", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("title").GetString().Should().Be("Validation failed");
        doc.RootElement.GetProperty("errors").TryGetProperty("RemapDest", out _).Should().BeTrue();
    }

    // Same guard for Window: the emitter throws on a null WindowOp.
    [Fact]
    public async Task Preview_WindowWithoutOp_Returns400NotServerError()
    {
        using HttpClient client = CreateAuthed();
        var dto = new HotkeyPreviewRequestDto("Bad window", "F6", HotkeyActionKind.Window);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys/preview", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        doc.RootElement.GetProperty("title").GetString().Should().Be("Validation failed");
        doc.RootElement.GetProperty("errors").TryGetProperty("WindowOp", out _).Should().BeTrue();
    }

    [Fact]
    public async Task Preview_MalformedInput_MatchesCreateEndpointErrorMessage()
    {
        using HttpClient client = CreateAuthed();
        var previewDto = new HotkeyPreviewRequestDto("Bad remap", "CapsLock", HotkeyActionKind.Remap);
        var createDto = new CreateHotkeyDto("Bad remap", "CapsLock", HotkeyActionKind.Remap, AppliesToAllProfiles: true);

        HttpResponseMessage previewResponse = await client.PostAsJsonAsync("/api/v1/hotkeys/preview", previewDto);
        HttpResponseMessage createResponse = await client.PostAsJsonAsync("/api/v1/hotkeys", createDto);

        previewResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        createResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        using var previewDoc = JsonDocument.Parse(await previewResponse.Content.ReadAsStringAsync());
        using var createDoc = JsonDocument.Parse(await createResponse.Content.ReadAsStringAsync());

        string? previewMessage = previewDoc.RootElement.GetProperty("errors")
            .GetProperty("RemapDest")[0].GetString();
        string? createMessage = createDoc.RootElement.GetProperty("errors")
            .GetProperty("RemapDest")[0].GetString();

        previewMessage.Should().Be(createMessage);
    }

    [Fact]
    public async Task Preview_Unauthenticated_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotkeys/preview",
            new HotkeyPreviewRequestDto("Disable F13", "F13", HotkeyActionKind.Disable));

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
