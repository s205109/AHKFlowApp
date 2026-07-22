using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class HotkeyTests
{
    private static HotkeyDefinition Definition() => new(
        Description: "Open Notepad",
        Key: "n",
        Ctrl: false,
        Alt: false,
        Shift: false,
        Win: true,
        ActionKind: HotkeyActionKind.Run,
        AppliesToAllProfiles: true,
        RunTarget: "notepad.exe",
        RunTargetKind: RunTargetKind.Application);

    [Fact]
    public void Create_FromDefinition_CopiesEveryField()
    {
        FakeTimeProvider clock = new();
        var owner = Guid.NewGuid();

        var hk = Hotkey.Create(owner, Definition(), clock);

        hk.OwnerOid.Should().Be(owner);
        hk.Description.Should().Be("Open Notepad");
        hk.Key.Should().Be("n");
        hk.Win.Should().BeTrue();
        hk.ActionKind.Should().Be(HotkeyActionKind.Run);
        hk.RunTarget.Should().Be("notepad.exe");
        hk.RunTargetKind.Should().Be(RunTargetKind.Application);
        hk.AppliesToAllProfiles.Should().BeTrue();
        hk.CreatedAt.Should().Be(clock.GetUtcNow());
        hk.UpdatedAt.Should().Be(clock.GetUtcNow());
    }

    [Fact]
    public void Update_FromDefinition_ReplacesFieldsAndAdvancesUpdatedAt()
    {
        FakeTimeProvider clock = new();
        var hk = Hotkey.Create(Guid.NewGuid(), Definition(), clock);
        DateTimeOffset created = hk.CreatedAt;
        clock.Advance(TimeSpan.FromMinutes(5));

        hk.Update(Definition() with { Key = "b", RunTarget = "calc.exe" }, clock);

        hk.Key.Should().Be("b");
        hk.RunTarget.Should().Be("calc.exe");
        hk.CreatedAt.Should().Be(created);
        hk.UpdatedAt.Should().Be(clock.GetUtcNow());
    }

    [Fact]
    public void Restore_FromDefinition_KeepsOriginalCreatedAt()
    {
        FakeTimeProvider clock = new();
        DateTimeOffset originallyCreated = clock.GetUtcNow().AddDays(-3);
        var id = Guid.NewGuid();

        var hk = Hotkey.Restore(id, Guid.NewGuid(), Definition(), originallyCreated, clock);

        hk.Id.Should().Be(id);
        hk.CreatedAt.Should().Be(originallyCreated);
        hk.UpdatedAt.Should().Be(clock.GetUtcNow());
    }
}
