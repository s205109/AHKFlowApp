namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// Marks a test class that opens pages itself instead of through
/// <see cref="FirstPageLoad.OpenAsync(Microsoft.Playwright.IBrowserContext, string, string[])"/>.
///
/// Nothing reads this at run time. It exists so FirstPageLoadAdoptionTests can skip the class, and
/// so the reason sits beside the code rather than in a list somewhere else.
///
/// The name says what the class does, not why. A reader does not have to agree with one class's
/// reason to apply this correctly to another.
/// </summary>
/// <param name="reason">Why this class cannot use the helper. Written for a stranger.</param>
[AttributeUsage(AttributeTargets.Class)]
public sealed class OpensPagesWithoutDiagnosisAttribute(string reason) : Attribute
{
    public string Reason { get; } = reason;
}
