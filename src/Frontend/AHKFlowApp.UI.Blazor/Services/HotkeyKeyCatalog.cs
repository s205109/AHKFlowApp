using System.Text.RegularExpressions;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <inheritdoc cref="IHotkeyKeyCatalog"/>
public sealed partial class HotkeyKeyCatalog(IHotkeysApiClient api) : IHotkeyKeyCatalog
{
    // Copied from AHKFlowApp.Application.Constants.HotkeyKeys — vk is two hex digits, sc is
    // three. Anchored \A..\z, not ^..$: .NET's $ also matches before a trailing newline, so
    // "vk1\n" would otherwise pass and split the emitted left-hand side across two lines.
    [GeneratedRegex(@"\Avk[0-9a-f]{1,2}\z", RegexOptions.IgnoreCase)]
    private static partial Regex VirtualKey();

    [GeneratedRegex(@"\Asc[0-9a-f]{1,3}\z", RegexOptions.IgnoreCase)]
    private static partial Regex ScanCode();

    private readonly SemaphoreSlim _gate = new(1, 1);
    private HotkeyKeyCatalogDto? _catalog;

    // Built once on load. IsValidKey runs per grid row per render and GroupOf runs per rendered
    // picker item, so neither may scan the ~100-entry list. Both maps are OrdinalIgnoreCase,
    // which also matches the server's case-insensitive alias and name lookups — System.Text.Json
    // would otherwise hand back an ordinal dictionary in which "esc" misses and "Esc" hits.
    private Dictionary<string, HotkeyKeyDto> _byName = new(StringComparer.OrdinalIgnoreCase);
    private Dictionary<string, string> _aliases = new(StringComparer.OrdinalIgnoreCase);

    // Per-role projections, memoized. MudAutocomplete calls SearchFunc on every keystroke, and
    // each call reaches ForRoleAsync — without this, every keystroke re-filters and re-sorts the
    // whole ~110-entry registry, per open picker.
    private readonly Dictionary<string, IReadOnlyList<HotkeyKeyDto>> _byRole = new(StringComparer.Ordinal);

    public bool IsLoaded => throw new NotImplementedException();

    public async ValueTask<IReadOnlyList<HotkeyKeyDto>> ForRoleAsync(string role, CancellationToken ct = default)
    {
        if (_byRole.TryGetValue(role, out IReadOnlyList<HotkeyKeyDto>? cached))
            return cached;

        HotkeyKeyCatalogDto catalog = await LoadAsync(ct);

        IReadOnlyList<HotkeyKeyDto> keys =
        [
            .. catalog.Keys
                .Where(k => k.Roles.Contains(role, StringComparer.Ordinal))
                .OrderBy(k => k.Group, StringComparer.Ordinal)
                .ThenBy(k => k.Canonical, StringComparer.OrdinalIgnoreCase)
        ];

        // Only a successful fetch is memoized — the empty list a failed one yields must not
        // become the answer for the rest of the session. Same reasoning as LoadAsync.
        if (_catalog is not null)
            _byRole[role] = keys;

        return keys;
    }

    public bool IsValidKey(string? key)
    {
        // Optimistic before load: see the interface remark.
        if (_catalog is null)
            return true;

        if (string.IsNullOrWhiteSpace(key))
            return false;

        if (_aliases.ContainsKey(key) || _byName.ContainsKey(key))
            return true;

        // A code naming no key (vk00, sc000) is rejected server-side; the digit-count regex
        // cannot express "hex, but not all zero", so it is checked separately here too.
        if (IsCode(key))
            return key[2..].Any(c => c != '0');

        return false;
    }

    public string? GroupOf(string? canonical) =>
        canonical is not null && _byName.TryGetValue(canonical, out HotkeyKeyDto? entry) ? entry.Group : null;

    public bool RequiresBracesInSend(string? canonical)
    {
        if (canonical is null)
            return false;

        if (_byName.TryGetValue(canonical, out HotkeyKeyDto? entry))
            return entry.RequiresBracesInSend;

        // Off-registry values reaching a Send token are vk/sc codes, which AHK requires braced:
        // Send "vk1B" types the four literal characters, Send "{vk1B}" presses the key.
        return IsCode(canonical);
    }

    private static bool IsCode(string value) => VirtualKey().IsMatch(value) || ScanCode().IsMatch(value);

    private async ValueTask<HotkeyKeyCatalogDto> LoadAsync(CancellationToken ct)
    {
        if (_catalog is { } cached)
            return cached;

        await _gate.WaitAsync(ct);
        try
        {
            if (_catalog is { } raced)
                return raced;

            ApiResult<HotkeyKeyCatalogDto> result = await api.GetKeysAsync(ct);

            // A failed fetch is not cached: the picker renders empty and the next dialog
            // open retries, rather than permanently offering no keys for the session.
            if (!result.IsSuccess || result.Value is null)
                return new HotkeyKeyCatalogDto([], new Dictionary<string, string>());

            _catalog = result.Value;
            _byName = result.Value.Keys.ToDictionary(k => k.Canonical, StringComparer.OrdinalIgnoreCase);
            _aliases = new Dictionary<string, string>(result.Value.Aliases, StringComparer.OrdinalIgnoreCase);
            return _catalog;
        }
        finally
        {
            _gate.Release();
        }
    }
}
