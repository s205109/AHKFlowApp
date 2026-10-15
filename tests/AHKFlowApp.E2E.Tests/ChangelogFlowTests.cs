using System.Text.Json;
using System.Text.RegularExpressions;
using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.UI.Blazor.DTOs;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// Backlog 176. The page used to print each entry as plain text, so the backticks and ** markers of
// CHANGELOG.md showed on screen.
//
// Two rules, kept apart. The renderer handles any text, and ChangelogTextTests covers it. The real
// changelog keeps a narrower format, because the page must show no backtick at all: a code span
// holds no backtick and no **, a ** span holds no backtick and no *, no backtick or * appears
// outside a span, and two spans of the same kind never touch. This test checks the published
// changelog.json against that format first. Then it builds the expected page from the file with
// its own regex, never with ChangelogText, so a parser mistake cannot pass its own test. A new
// entry inside the format never breaks this test. An entry outside it fails the format check, and
// the message names the entry.
[Collection(E2ECollectionC.Name)]
public sealed class ChangelogFlowTests(StackFixtureC fixture)
{
    private const string ItemSelector = "[data-test=\"changelog-item\"]";

    // Group 1 is the content of a code span, group 2 the content of a ** span. The lookarounds keep
    // a delimiter from touching another marker of its kind, so `a``b` is not two code spans. The
    // renderer reads whole marker runs, and it reads that entry as one code span.
    private static readonly Regex SpanPattern = new(
        @"(?<!`)`([^`]+)`(?!`)|(?<!\*)\*\*([^`*]+)\*\*(?!\*)",
        RegexOptions.CultureInvariant);

    [Fact]
    public async Task ChangelogPage_RendersEveryEntryInOrder_WithSpansAndNoMarkers()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await FirstPageLoad.OpenAsync(context, $"{fixture.Spa.BaseUrl}/changelog");

        string json = await page.EvaluateAsync<string>(
            "url => fetch(url).then(response => response.text())",
            $"{fixture.Spa.BaseUrl}/changelog.json");
        ChangelogDocumentDto document = JsonSerializer.Deserialize<ChangelogDocumentDto>(json, JsonSerializerOptions.Web)
            ?? throw new InvalidOperationException("changelog.json deserialized to null.");
        string[] items = [.. document.Entries
            .SelectMany(entry => entry.Sections)
            .SelectMany(section => section.Items)];

        string[] outsideFormat = [.. items.Where(item => !IsInFormat(item))];
        Assert.True(
            outsideFormat.Length == 0,
            "These changelog entries are outside the format this test covers. Reword each entry, "
                + "or extend the test: " + string.Join(" | ", outsideFormat));

        string[] expectedTexts = [.. items.Select(item => SpanPattern.Replace(item, "$1$2"))];
        Match[] spans = [.. items.SelectMany(item => SpanPattern.Matches(item))];
        string[] expectedCodes = [.. spans.Where(match => match.Groups[1].Success).Select(match => match.Groups[1].Value)];
        string[] expectedStrongs = [.. spans.Where(match => match.Groups[2].Success).Select(match => match.Groups[2].Value)];

        ILocator rendered = page.Locator(ItemSelector);
        await rendered.First.WaitForAsync();

        Assert.Equal(expectedTexts, await rendered.AllTextContentsAsync());
        Assert.Equal(expectedCodes, await page.Locator($"{ItemSelector} code").AllTextContentsAsync());
        Assert.Equal(expectedStrongs, await page.Locator($"{ItemSelector} strong").AllTextContentsAsync());
    }

    private static bool IsInFormat(string item) =>
        !SpanPattern.Matches(item).Any(match => match.Groups[1].Value.Contains("**", StringComparison.Ordinal))
        && SpanPattern.Replace(item, "").IndexOfAny(['`', '*']) < 0;
}
