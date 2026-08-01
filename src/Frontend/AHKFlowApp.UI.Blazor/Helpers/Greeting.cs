namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// Builds a time-of-day greeting for the app bar, e.g. "Good morning, Test User".
/// </summary>
public static class Greeting
{
    public static string? Build(TimeProvider clock, string? name) => Build(clock.GetLocalNow(), name);

    public static string? Build(DateTimeOffset localNow, string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return null;
        }

        string timeOfDay = localNow.Hour switch
        {
            < 12 => "morning",
            < 18 => "afternoon",
            _ => "evening",
        };

        return $"Good {timeOfDay}, {name}";
    }
}
