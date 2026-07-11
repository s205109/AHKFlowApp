using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotstrings;

[Collection("WebApi")]
public sealed class HotstringPreviewEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    [Fact]
    public async Task Preview_TextKind_ReturnsExactSnippet()
    {
        using HttpClient client = CreateAuthed();
        var dto = new HotstringPreviewRequestDto(
            HotstringKind.Text,
            "btw",
            "by the way",
            IsCaseSensitive: false,
            OmitEndingCharacter: false,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings/preview", dto);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringPreviewDto? body = await response.Content.ReadFromJsonAsync<HotstringPreviewDto>();
        body!.Snippet.Should().Be(":T:btw::by the way");
    }

    [Fact]
    public async Task Preview_DateTimeKind_ReturnsExactSnippet()
    {
        using HttpClient client = CreateAuthed();
        var dto = new HotstringPreviewRequestDto(
            HotstringKind.DateTime,
            "ddate",
            string.Empty,
            IsCaseSensitive: false,
            OmitEndingCharacter: false,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false,
            DateTimeFormat: "yyyy-MM-dd");

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings/preview", dto);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringPreviewDto? body = await response.Content.ReadFromJsonAsync<HotstringPreviewDto>();
        body!.Snippet.Should().Be(":X:ddate::SendText(FormatTime(A_Now, \"yyyy-MM-dd\"))");
    }

    [Fact]
    public async Task Preview_MacroKind_WithEscapedLiteralAndTokens_ReturnsExactSnippet()
    {
        using HttpClient client = CreateAuthed();
        var dto = new HotstringPreviewRequestDto(
            HotstringKind.Macro,
            "mgreet",
            "Hi {{{{first_name}}}},{{key:Enter}}{{cursor}}",
            IsCaseSensitive: false,
            OmitEndingCharacter: false,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings/preview", dto);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringPreviewDto? body = await response.Content.ReadFromJsonAsync<HotstringPreviewDto>();
        body!.Snippet.Should().Be(
            "::mgreet::\n{\n\tSendText \"Hi {{first_name}},\"\n\tSend \"{Enter}\"\n}");
    }

    [Fact]
    public async Task Preview_InvalidMacroToken_Returns400WithParserMessage()
    {
        using HttpClient client = CreateAuthed();
        var dto = new HotstringPreviewRequestDto(
            HotstringKind.Macro,
            "mbad",
            "{{key:Escape}}",
            IsCaseSensitive: false,
            OmitEndingCharacter: false,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings/preview", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;
        root.GetProperty("title").GetString().Should().Be("Validation failed");
        JsonElement errors = root.GetProperty("errors");
        errors.TryGetProperty("Input.Replacement", out JsonElement replacementErrors).Should().BeTrue();
        replacementErrors.EnumerateArray().Select(e => e.GetString()).Should().Contain(
            "Unknown token '{{key:Escape}}'. Allowed: {{cursor}}, {{key:Enter}}, {{key:Tab}}.");
    }

    [Fact]
    public async Task Preview_InvalidMacroToken_MatchesCreateEndpointErrorMessage()
    {
        using HttpClient client = CreateAuthed();
        const string invalidReplacement = "{{key:Escape}}";

        HttpResponseMessage previewResponse = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/preview",
            new HotstringPreviewRequestDto(
                HotstringKind.Macro,
                "mbad2",
                invalidReplacement,
                IsCaseSensitive: false,
                OmitEndingCharacter: false,
                IsEndingCharacterRequired: true,
                IsTriggerInsideWord: false));
        HttpResponseMessage createResponse = await client.PostAsJsonAsync(
            "/api/v1/hotstrings",
            new CreateHotstringDto("mbad2", invalidReplacement, Kind: HotstringKind.Macro));

        previewResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        createResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        using var previewDoc = JsonDocument.Parse(await previewResponse.Content.ReadAsStringAsync());
        using var createDoc = JsonDocument.Parse(await createResponse.Content.ReadAsStringAsync());

        string? previewMessage = previewDoc.RootElement.GetProperty("errors")
            .GetProperty("Input.Replacement")[0].GetString();
        string? createMessage = createDoc.RootElement.GetProperty("errors")
            .GetProperty("Input.Replacement")[0].GetString();

        previewMessage.Should().Be(createMessage);
    }

    [Fact]
    public async Task Preview_Unauthenticated_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/preview",
            new HotstringPreviewRequestDto(
                HotstringKind.Text,
                "btw",
                "by the way",
                IsCaseSensitive: false,
                OmitEndingCharacter: false,
                IsEndingCharacterRequired: true,
                IsTriggerInsideWord: false));

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
