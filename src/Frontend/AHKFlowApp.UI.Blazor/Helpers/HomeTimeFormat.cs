namespace AHKFlowApp.UI.Blazor.Helpers;

public static class HomeTimeFormat
{
    public static string Relative(DateTimeOffset utcNow, DateTimeOffset occurredAt)
    {
        TimeSpan delta = utcNow - occurredAt;
        if (delta < TimeSpan.FromMinutes(1)) return "just now";
        if (delta < TimeSpan.FromHours(1)) return $"{(int)delta.TotalMinutes} min ago";
        if (delta < TimeSpan.FromDays(1)) return $"{(int)delta.TotalHours} h ago";
        if (occurredAt.UtcDateTime.Date == utcNow.UtcDateTime.AddDays(-1).Date) return "Yesterday";
        return occurredAt.ToString("yyyy-MM-dd");
    }
}
