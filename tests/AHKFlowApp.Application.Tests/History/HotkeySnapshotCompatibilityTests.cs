using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Trait("Category", "Unit")]
public sealed class HotkeySnapshotCompatibilityTests
{
    [Fact]
    public void Deserialize_TypedJsonWithoutContextFields_DefaultsToNullContext()
    {
        // A W1 snapshot written before window-context support: every typed member, no context pair.
        const string typedJson =
            """
            {"Description":"Open Notepad","Key":"n","Ctrl":true,"Alt":false,"Shift":false,"Win":false,"AppliesToAllProfiles":true,"ProfileIds":[],"CategoryIds":[],"CreatedAt":"2026-01-01T00:00:00+00:00","UpdatedAt":"2026-01-02T00:00:00+00:00","ActionKind":2,"Text":null,"SendKeysContent":null,"RunTarget":"notepad.exe","RunTargetKind":0,"WindowOp":null,"RemapDest":null,"Body":null,"Action":null,"Parameters":null}
            """;

        HotkeySnapshot? snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(typedJson);

        snapshot!.ContextMatchType.Should().BeNull();
        snapshot.ContextValue.Should().BeNull();
    }

    [Fact]
    public void Deserialize_PreW1JsonWithoutContextFields_RestoresAsGlobalHotkey()
    {
        // A pre-W1 snapshot: the legacy Action / Parameters pair, no typed members, no context.
        const string legacyJson =
            """
            {"Description":"Open Notepad","Key":"n","Ctrl":true,"Alt":false,"Shift":false,"Win":false,"AppliesToAllProfiles":true,"ProfileIds":[],"CategoryIds":[],"CreatedAt":"2026-01-01T00:00:00+00:00","UpdatedAt":"2026-01-02T00:00:00+00:00","Action":1,"Parameters":"notepad.exe"}
            """;

        HotkeySnapshot snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(legacyJson)!;
        HotkeyDefinition definition = LegacyHotkeySnapshotConverter.ToDefinition(snapshot);

        snapshot.ContextMatchType.Should().BeNull();
        snapshot.ContextValue.Should().BeNull();
        definition.ContextMatchType.Should().BeNull();
        definition.ContextValue.Should().BeNull();
    }
}
