using FluentAssertions;
using Microsoft.Playwright;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed record ActionsCellLayout(LocatorBoundingBoxResult Cell, IReadOnlyList<LocatorBoundingBoxResult> Buttons);

// Measures the row buttons in a grid's Actions cell. Backlogs 185 and 190 found the last button
// cut off on the hotstrings and the hotkeys grid. Both grid tests use this check.
public static class ActionsCell
{
    public static async Task<ActionsCellLayout> MeasureAsync(IPage page, ILocator row, string buttonInCell)
    {
        ILocator cell = row.Locator("td").Filter(new() { Has = page.Locator(buttonInCell) });
        LocatorBoundingBoxResult cellBox = await cell.BoundingBoxAsync()
            ?? throw new InvalidOperationException($"The Actions cell that holds {buttonInCell} is not visible.");

        List<LocatorBoundingBoxResult> buttonBoxes = [];
        foreach (ILocator button in await cell.Locator("button").AllAsync())
        {
            buttonBoxes.Add(await button.BoundingBoxAsync()
                ?? throw new InvalidOperationException($"A button in the Actions cell that holds {buttonInCell} is not visible."));
        }

        return new ActionsCellLayout(cellBox, buttonBoxes);
    }

    public static void AssertInsideItsCellOnOneLine(string state, ActionsCellLayout layout, int expectedButtons)
    {
        layout.Buttons.Should().HaveCount(expectedButtons, $"{state} shows {expectedButtons} row buttons");
        float cellRight = layout.Cell.X + layout.Cell.Width;
        foreach (LocatorBoundingBoxResult button in layout.Buttons)
        {
            button.X.Should().BeGreaterThanOrEqualTo(layout.Cell.X, $"{state}: a button must not start before its cell");
            (button.X + button.Width).Should().BeLessThanOrEqualTo(cellRight, $"{state}: a button must not end past its cell");
            button.Y.Should().BeApproximately(layout.Buttons[0].Y, 0.5f, $"{state}: the row buttons share one line");
        }
    }
}
