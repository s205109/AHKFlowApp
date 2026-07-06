using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Trait("Category", "Unit")]
public sealed class HotstringImportClassifierTests
{
    private static HotstringImportRowDto Row(string trigger, HotstringImportRowStatus status = HotstringImportRowStatus.Ready) =>
        new(1, trigger, "x", true, false, [], status, null);

    [Fact]
    public void MarkDuplicates_ExistingTrigger_MarkedDuplicate_CaseInsensitive()
    {
        IReadOnlySet<string> existing = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "BTW" };

        IReadOnlyList<HotstringImportRowDto> result =
            HotstringImportClassifier.MarkDuplicates([Row("btw")], existing);

        result[0].Status.Should().Be(HotstringImportRowStatus.Duplicate);
        result[0].Reason.Should().Be(HotstringImportClassifier.DuplicateReason);
    }

    [Fact]
    public void MarkDuplicates_InFileRepeat_KeepsFirstMarksRest()
    {
        IReadOnlyList<HotstringImportRowDto> result = HotstringImportClassifier.MarkDuplicates(
            [Row("btw"), Row("BTW")], new HashSet<string>());

        result[0].Status.Should().Be(HotstringImportRowStatus.Ready);
        result[1].Status.Should().Be(HotstringImportRowStatus.Duplicate);
    }

    [Fact]
    public void MarkDuplicates_InvalidRow_LeftUntouchedAndDoesNotClaimTrigger()
    {
        IReadOnlyList<HotstringImportRowDto> result = HotstringImportClassifier.MarkDuplicates(
            [Row("btw", HotstringImportRowStatus.Invalid), Row("btw")], new HashSet<string>());

        result[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        result[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void MarkDuplicates_WarningRow_StaysWarningWhenUnique()
    {
        IReadOnlyList<HotstringImportRowDto> result = HotstringImportClassifier.MarkDuplicates(
            [Row("btw", HotstringImportRowStatus.Warning)], new HashSet<string>());

        result[0].Status.Should().Be(HotstringImportRowStatus.Warning);
    }
}
