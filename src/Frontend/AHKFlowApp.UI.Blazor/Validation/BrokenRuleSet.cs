using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

/// <summary>
/// The rules a stored item broke when it was loaded (backlog 175), with the value each named
/// field held then. Immutable, so <c>Clone</c> on an edit model shares one instance.
/// </summary>
/// <remarks>
/// A rule is live while its field still holds the value it held at load. Once the Owner changes
/// the field, the rule no longer describes it, so it stops showing.
/// </remarks>
public sealed class BrokenRuleSet
{
    private readonly IReadOnlyDictionary<string, object?> _valueAtLoad;

    private BrokenRuleSet(IReadOnlyList<BrokenRuleDto> rules, IReadOnlyDictionary<string, object?> valueAtLoad)
    {
        Rules = rules;
        _valueAtLoad = valueAtLoad;
    }

    /// <summary>The set for an item that broke no rules.</summary>
    public static BrokenRuleSet None { get; } = new([], new Dictionary<string, object?>());

    /// <summary>Every rule the item broke at load, in the order the server sent them.</summary>
    public IReadOnlyList<BrokenRuleDto> Rules { get; }

    /// <summary>True when the item broke at least one rule at load.</summary>
    public bool Any => Rules.Count > 0;

    /// <summary>
    /// Records <paramref name="valueOf"/> once for each distinct field the rules name. Returns
    /// <see cref="None"/> for null or empty <paramref name="rules"/>.
    /// </summary>
    public static BrokenRuleSet Capture(IReadOnlyList<BrokenRuleDto>? rules, Func<string, object?> valueOf)
    {
        if (rules is null or { Count: 0 })
            return None;

        Dictionary<string, object?> valueAtLoad = [];
        foreach (string field in rules.Select(r => r.Field).Distinct())
            valueAtLoad[field] = valueOf(field);

        return new([.. rules], valueAtLoad);
    }

    /// <summary>
    /// The messages of the live rules for <paramref name="field"/>, in order, joined with one
    /// space. Null when there are none.
    /// </summary>
    public string? TextFor(string field, Func<string, object?> valueOf)
    {
        if (!Any)
            return null;

        string[] messages = [.. LiveRules(valueOf).Where(r => r.Field == field).Select(r => r.Message)];
        return messages.Length == 0 ? null : string.Join(' ', messages);
    }

    /// <summary>
    /// The messages of the live rules whose field <paramref name="isOnScreen"/> rejects, in order.
    /// </summary>
    public IReadOnlyList<string> NotShown(Func<string, bool> isOnScreen, Func<string, object?> valueOf) =>
        !Any ? [] : [.. LiveRules(valueOf).Where(r => !isOnScreen(r.Field)).Select(r => r.Message)];

    private IEnumerable<BrokenRuleDto> LiveRules(Func<string, object?> valueOf) =>
        Rules.Where(r => Equals(valueOf(r.Field), _valueAtLoad[r.Field]));
}
