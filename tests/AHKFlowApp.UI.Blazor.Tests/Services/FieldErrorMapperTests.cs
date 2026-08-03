using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class FieldErrorMapperTests
{
    private static readonly HashSet<string> KnownFields =
        new(["Trigger", "Replacement"], StringComparer.OrdinalIgnoreCase);

    private static Dictionary<string, string> NewTarget() =>
        new(StringComparer.OrdinalIgnoreCase);

    [Fact]
    public void Map_DottedPropertyPath_UsesTheLastSegment()
    {
        Dictionary<string, string> target = NewTarget();

        string? unmapped = FieldErrorMapper.Map(
            new Dictionary<string, string[]> { ["Input.Replacement"] = ["Braces must balance."] },
            KnownFields,
            target);

        target.Should().ContainKey("Replacement").WhoseValue.Should().Be("Braces must balance.");
        unmapped.Should().BeNull();
    }

    [Fact]
    public void Map_LowercaseKey_StillLandsOnItsField()
    {
        // FluentValidation and the server may spell the path in a different case than the model
        // property. A case-sensitive lookup would push this into the generic alert instead.
        Dictionary<string, string> target = NewTarget();

        string? unmapped = FieldErrorMapper.Map(
            new Dictionary<string, string[]> { ["input.replacement"] = ["Braces must balance."] },
            KnownFields,
            target);

        target.Should().ContainKey("Replacement").WhoseValue.Should().Be("Braces must balance.");
        unmapped.Should().BeNull();
    }

    [Fact]
    public void Map_UnknownField_IsReturnedAsUnmapped()
    {
        Dictionary<string, string> target = NewTarget();

        string? unmapped = FieldErrorMapper.Map(
            new Dictionary<string, string[]> { ["Input.Mystery"] = ["Something else."] },
            KnownFields,
            target);

        target.Should().BeEmpty();
        unmapped.Should().Be("Something else.");
    }

    [Fact]
    public void Map_SeveralMessagesForOneField_KeepsTheFirst()
    {
        Dictionary<string, string> target = NewTarget();

        FieldErrorMapper.Map(
            new Dictionary<string, string[]> { ["Trigger"] = ["First.", "Second."] },
            KnownFields,
            target);

        target["Trigger"].Should().Be("First.");
    }

    [Fact]
    public void Map_EmptyMessageArray_IsSkipped()
    {
        Dictionary<string, string> target = NewTarget();

        string? unmapped = FieldErrorMapper.Map(
            new Dictionary<string, string[]> { ["Trigger"] = [] },
            KnownFields,
            target);

        target.Should().BeEmpty();
        unmapped.Should().BeNull();
    }

    [Fact]
    public void Map_ReplacesWhateverTheTargetHeldBefore()
    {
        Dictionary<string, string> target = NewTarget();
        target["Trigger"] = "Stale message.";

        FieldErrorMapper.Map(
            new Dictionary<string, string[]> { ["Replacement"] = ["Fresh message."] },
            KnownFields,
            target);

        target.Should().NotContainKey("Trigger");
        target.Should().ContainKey("Replacement");
    }
}
