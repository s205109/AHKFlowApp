using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Trait("Category", "Unit")]
public sealed class HotstringSnapshotCompatibilityTests
{
    [Fact]
    public void Deserialize_LegacyJsonWithoutNewFields_DefaultsToTextKind()
    {
        // Pre-Phase-1 snapshot JSON — exactly the members EntityHistoryRecorder wrote before.
        const string legacyJson =
            """
            {"Trigger":"btw","Replacement":"by the way","Description":null,"AppliesToAllProfiles":true,"IsEndingCharacterRequired":true,"IsTriggerInsideWord":false,"ProfileIds":[],"CategoryIds":[],"CreatedAt":"2026-01-01T00:00:00+00:00","UpdatedAt":"2026-01-02T00:00:00+00:00"}
            """;

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(legacyJson);

        snapshot!.Kind.Should().Be(HotstringKind.Text);
        snapshot.IsCaseSensitive.Should().BeFalse();
        snapshot.OmitEndingCharacter.Should().BeFalse();
        snapshot.DateTimeFormat.Should().BeNull();
        snapshot.DateOffsetAmount.Should().BeNull();
        snapshot.DateOffsetUnit.Should().BeNull();
    }

    [Fact]
    public void Deserialize_LegacyJsonWithoutContextFields_DefaultsToNullContext()
    {
        // Pre-Phase-4 snapshot JSON — exactly the members EntityHistoryRecorder wrote before
        // window-context support (Phase 1-3 fields present, no ContextMatchType/ContextValue).
        const string legacyJson =
            """
            {"Trigger":"btw","Replacement":"by the way","Description":null,"AppliesToAllProfiles":true,"IsEndingCharacterRequired":true,"IsTriggerInsideWord":false,"ProfileIds":[],"CategoryIds":[],"CreatedAt":"2026-01-01T00:00:00+00:00","UpdatedAt":"2026-01-02T00:00:00+00:00","Kind":0,"IsCaseSensitive":false,"OmitEndingCharacter":false,"DateTimeFormat":null,"DateOffsetAmount":null,"DateOffsetUnit":null}
            """;

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(legacyJson);

        snapshot!.ContextMatchType.Should().BeNull();
        snapshot.ContextValue.Should().BeNull();
    }
}
