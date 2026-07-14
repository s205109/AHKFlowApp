using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Validation;

public sealed class HotstringEditModelTests
{
    private static HotstringDto MakeDto(
        string trigger = "btw",
        string replacement = "by the way",
        Guid[]? profileIds = null,
        bool appliesToAllProfiles = true,
        bool endingChar = true,
        bool insideWord = false,
        string? description = null)
        => new(Guid.NewGuid(), profileIds ?? [], appliesToAllProfiles, trigger, replacement, description, endingChar, insideWord,
               DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    [Fact]
    public void FromDto_MapsAllFields()
    {
        var profileId = Guid.NewGuid();
        HotstringDto dto = MakeDto(profileIds: [profileId], appliesToAllProfiles: false, endingChar: false, insideWord: true,
            description: "polite filler");

        var model = HotstringEditModel.FromDto(dto);

        model.Id.Should().Be(dto.Id);
        model.Trigger.Should().Be(dto.Trigger);
        model.Replacement.Should().Be(dto.Replacement);
        model.Description.Should().Be("polite filler");
        model.AppliesToAllProfiles.Should().BeFalse();
        model.ProfileIds.Should().HaveCount(1).And.Contain(profileId);
        model.IsEndingCharacterRequired.Should().BeFalse();
        model.IsTriggerInsideWord.Should().BeTrue();
    }

    [Fact]
    public void ToCreateDto_MapsAllFields()
    {
        var profileId = Guid.NewGuid();
        var categoryId = Guid.NewGuid();
        var model = new HotstringEditModel
        {
            Trigger = "btw",
            Replacement = "by the way",
            Description = "polite filler",
            AppliesToAllProfiles = false,
            ProfileIds = [profileId],
            CategoryIds = [categoryId],
            IsEndingCharacterRequired = true,
            IsTriggerInsideWord = false
        };

        CreateHotstringDto dto = model.ToCreateDto();

        dto.Trigger.Should().Be("btw");
        dto.Replacement.Should().Be("by the way");
        dto.Description.Should().Be("polite filler");
        dto.AppliesToAllProfiles.Should().BeFalse();
        dto.ProfileIds.Should().HaveCount(1).And.Contain(profileId);
        dto.CategoryIds.Should().HaveCount(1).And.Contain(categoryId);
        dto.IsEndingCharacterRequired.Should().BeTrue();
        dto.IsTriggerInsideWord.Should().BeFalse();
    }

    [Fact]
    public void Clone_CopiesEditableFields_WithoutSharingCollections()
    {
        var profileId = Guid.NewGuid();
        var categoryId = Guid.NewGuid();
        var model = new HotstringEditModel
        {
            Id = Guid.NewGuid(),
            Trigger = "btw",
            Replacement = "by the way",
            Description = "polite filler",
            AppliesToAllProfiles = false,
            ProfileIds = [profileId],
            CategoryIds = [categoryId],
            IsEndingCharacterRequired = true,
            IsTriggerInsideWord = false
        };

        HotstringEditModel clone = model.Clone();

        clone.Should().BeEquivalentTo(model);
        clone.ProfileIds.Should().NotBeSameAs(model.ProfileIds);
        clone.CategoryIds.Should().NotBeSameAs(model.CategoryIds);
    }

    [Fact]
    public void ToUpdateDto_MapsAllFields()
    {
        var model = new HotstringEditModel
        {
            Trigger = "omw",
            Replacement = "on my way",
            Description = "leaving note",
            AppliesToAllProfiles = true,
            ProfileIds = [],
            IsEndingCharacterRequired = false,
            IsTriggerInsideWord = true
        };

        UpdateHotstringDto dto = model.ToUpdateDto();

        dto.Trigger.Should().Be("omw");
        dto.Replacement.Should().Be("on my way");
        dto.Description.Should().Be("leaving note");
        dto.AppliesToAllProfiles.Should().BeTrue();
        dto.ProfileIds.Should().BeNull();
        dto.IsEndingCharacterRequired.Should().BeFalse();
        dto.IsTriggerInsideWord.Should().BeTrue();
    }

    [Fact]
    public void ExpandImmediately_InvertsEndingCharacterRequired()
    {
        HotstringEditModel model = new() { IsEndingCharacterRequired = true };

        model.ExpandImmediately.Should().BeFalse();

        model.ExpandImmediately = true;
        model.IsEndingCharacterRequired.Should().BeFalse();
    }

    [Fact]
    public void ToCreateDto_ThreadsKindAndNewFlags()
    {
        HotstringEditModel model = new()
        {
            Trigger = "btw",
            Replacement = "x",
            IsCaseSensitive = true,
            OmitEndingCharacter = true,
        };

        CreateHotstringDto dto = model.ToCreateDto();

        dto.Kind.Should().Be(HotstringKind.Text);
        dto.IsCaseSensitive.Should().BeTrue();
        dto.OmitEndingCharacter.Should().BeTrue();
    }

    [Fact]
    public void FromDto_AndClone_PreserveNewFields()
    {
        HotstringDto dto = new(Guid.NewGuid(), [], true, "btw", "x", null, true, false,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
            HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: true);

        HotstringEditModel clone = HotstringEditModel.FromDto(dto).Clone();

        clone.IsCaseSensitive.Should().BeTrue();
        clone.OmitEndingCharacter.Should().BeTrue();
    }

    [Fact]
    public void FromDto_AndClone_PreserveDateTimeFields()
    {
        HotstringDto dto = new(Guid.NewGuid(), [], true, "now", "", null, true, false,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
            HotstringKind.DateTime, DateTimeFormat: "yyyy-MM-dd", DateOffsetAmount: 3, DateOffsetUnit: DateOffsetUnit.Days);

        HotstringEditModel clone = HotstringEditModel.FromDto(dto).Clone();

        clone.Kind.Should().Be(HotstringKind.DateTime);
        clone.DateTimeFormat.Should().Be("yyyy-MM-dd");
        clone.DateOffsetAmount.Should().Be(3);
        clone.DateOffsetUnit.Should().Be(DateOffsetUnit.Days);
    }

    [Fact]
    public void ToCreateDto_And_ToUpdateDto_ThreadDateTimeFields()
    {
        HotstringEditModel model = new()
        {
            Trigger = "now",
            Kind = HotstringKind.DateTime,
            DateTimeFormat = "HH:mm",
            DateOffsetAmount = -1,
            DateOffsetUnit = DateOffsetUnit.Hours,
        };

        CreateHotstringDto createDto = model.ToCreateDto();
        UpdateHotstringDto updateDto = model.ToUpdateDto();

        createDto.DateTimeFormat.Should().Be("HH:mm");
        createDto.DateOffsetAmount.Should().Be(-1);
        createDto.DateOffsetUnit.Should().Be(DateOffsetUnit.Hours);
        updateDto.DateTimeFormat.Should().Be("HH:mm");
        updateDto.DateOffsetAmount.Should().Be(-1);
        updateDto.DateOffsetUnit.Should().Be(DateOffsetUnit.Hours);
    }

    [Fact]
    public void ToCreateDto_And_ToUpdateDto_ForceEmptyReplacement_ForDateTimeKind_EvenWithStaleText()
    {
        HotstringEditModel model = new()
        {
            Trigger = "now",
            Replacement = "stale leftover text",
            Kind = HotstringKind.DateTime,
            DateTimeFormat = "yyyy",
        };

        CreateHotstringDto createDto = model.ToCreateDto();
        UpdateHotstringDto updateDto = model.ToUpdateDto();

        createDto.Replacement.Should().BeEmpty();
        updateDto.Replacement.Should().BeEmpty();
        // The model's own Replacement is untouched — ToCreateDto/ToUpdateDto must not mutate it.
        model.Replacement.Should().Be("stale leftover text");
    }

    [Fact]
    public void ToCreateDto_DoesNotForceEmptyReplacement_ForTextKind()
    {
        HotstringEditModel model = new()
        {
            Trigger = "btw",
            Replacement = "by the way",
            Kind = HotstringKind.Text,
        };

        CreateHotstringDto dto = model.ToCreateDto();

        dto.Replacement.Should().Be("by the way");
    }

    [Theory]
    [InlineData(HotstringKind.Text, true)]
    [InlineData(HotstringKind.DateTime, false)]
    [InlineData(HotstringKind.Macro, false)]
    [InlineData(HotstringKind.Raw, false)]
    public void IsInlineEditable_OnlyTrueForTextKind(HotstringKind kind, bool expected)
    {
        HotstringEditModel model = new() { Kind = kind };

        model.IsInlineEditable.Should().Be(expected);
    }

    [Fact]
    public void DateTimeSummary_IsNull_ForNonDateTimeKind()
    {
        HotstringEditModel model = new() { Kind = HotstringKind.Text, DateTimeFormat = "yyyy" };

        model.DateTimeSummary.Should().BeNull();
    }

    [Fact]
    public void DateTimeSummary_IsEmDash_WhenFormatIsNull()
    {
        HotstringEditModel model = new() { Kind = HotstringKind.DateTime, DateTimeFormat = null };

        model.DateTimeSummary.Should().Be("—");
    }

    [Fact]
    public void DateTimeSummary_IsRawFormat_WhenNoOffset()
    {
        HotstringEditModel model = new() { Kind = HotstringKind.DateTime, DateTimeFormat = "yyyy-MM-dd" };

        model.DateTimeSummary.Should().Be("yyyy-MM-dd");
    }

    [Theory]
    [InlineData(1, DateOffsetUnit.Days, "yyyy-MM-dd (+1 day)")]
    [InlineData(-1, DateOffsetUnit.Days, "yyyy-MM-dd (-1 day)")]
    [InlineData(3, DateOffsetUnit.Days, "yyyy-MM-dd (+3 days)")]
    [InlineData(-3, DateOffsetUnit.Hours, "yyyy-MM-dd (-3 hours)")]
    [InlineData(0, DateOffsetUnit.Minutes, "yyyy-MM-dd (+0 minutes)")]
    public void DateTimeSummary_FormatsOffset_MatchingCliConvention(int amount, DateOffsetUnit unit, string expected)
    {
        HotstringEditModel model = new()
        {
            Kind = HotstringKind.DateTime,
            DateTimeFormat = "yyyy-MM-dd",
            DateOffsetAmount = amount,
            DateOffsetUnit = unit,
        };

        model.DateTimeSummary.Should().Be(expected);
    }

    [Fact]
    public void RawSummary_IsNull_ForNonRawKind()
    {
        HotstringEditModel model = new() { Kind = HotstringKind.Text, Replacement = "MsgBox 1" };

        model.RawSummary.Should().BeNull();
    }

    [Fact]
    public void RawSummary_SingleLine_ReturnsAsIs()
    {
        HotstringEditModel model = new() { Kind = HotstringKind.Raw, Replacement = ":K1000 SE*:ftw::for the win" };

        model.RawSummary.Should().Be(":K1000 SE*:ftw::for the win");
    }

    [Fact]
    public void RawSummary_MultilineBody_ReturnsFirstLineOnly()
    {
        HotstringEditModel model = new()
        {
            Kind = HotstringKind.Raw,
            Replacement = ":*:rng::\n{\nSend foo\n}",
        };

        model.RawSummary.Should().Be(":*:rng::");
    }

    [Fact]
    public void RawSummary_LeadingWhitespaceOnFirstLine_IsTrimmed()
    {
        HotstringEditModel model = new() { Kind = HotstringKind.Raw, Replacement = "  ::btw::hi  \nrest" };

        model.RawSummary.Should().Be("::btw::hi");
    }

    [Fact]
    public void SafePreview_ReturnsEmpty_ForNullOrEmptyFormat()
    {
        HotstringEditModel.SafePreview(null).Should().BeEmpty();
        HotstringEditModel.SafePreview("").Should().BeEmpty();
    }

    [Fact]
    public void SafePreview_MultiCharFormat_ProducesNonEmptyResult()
    {
        string preview = HotstringEditModel.SafePreview("yyyy-MM-dd");

        preview.Should().NotBeNullOrEmpty();
        preview.Should().NotBe("Invalid format");
    }

    [Fact]
    public void SafePreview_SingleCharFormat_UsesCustomSpecifier_NotStandardSpecifier()
    {
        string preview = HotstringEditModel.SafePreview("d");

        preview.Should().Be(DateTime.Now.ToString("%d"));
        preview.Should().NotContain("/");
    }

    [Fact]
    public void SafePreview_InvalidFormat_ReturnsInvalidMessage()
    {
        string preview = HotstringEditModel.SafePreview("yyyy-QQQQQQ-XY\\");

        preview.Should().Be("Invalid format");
    }

    [Fact]
    public void SafePreview_WithClock_IsDeterministic()
    {
        FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-07-10T08:30:00Z"));
        clock.SetLocalTimeZone(TimeZoneInfo.Utc);

        HotstringEditModel.SafePreview("yyyy-MM-dd HH:mm", clock: clock).Should().Be("2026-07-10 08:30");
    }

    [Fact]
    public void SafePreview_WithOffset_AppliesOffsetToClock()
    {
        FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-07-10T08:30:00Z"));
        clock.SetLocalTimeZone(TimeZoneInfo.Utc);

        HotstringEditModel.SafePreview("yyyy-MM-dd", 7, DateOffsetUnit.Days, clock).Should().Be("2026-07-17");
        HotstringEditModel.SafePreview("HH:mm", -2, DateOffsetUnit.Hours, clock).Should().Be("06:30");
    }

    [Fact]
    public void IsInlineEditable_TextKindWithContext_ReturnsFalse()
    {
        HotstringEditModel model = new() { Kind = HotstringKind.Text, ContextMatchType = WindowMatchType.Executable, ContextValue = "notepad.exe" };

        model.IsInlineEditable.Should().BeFalse();
    }

    [Fact]
    public void IsInlineEditable_TextKindNoContext_ReturnsTrue()
    {
        HotstringEditModel model = new() { Kind = HotstringKind.Text, ContextMatchType = null };

        model.IsInlineEditable.Should().BeTrue();
    }

    [Fact]
    public void ToCreateDto_WithContext_MapsContextFields()
    {
        HotstringEditModel model = new()
        {
            Trigger = "btw",
            Replacement = "by the way",
            ContextMatchType = WindowMatchType.WindowClass,
            ContextValue = "Chrome_WidgetWin_1",
        };

        CreateHotstringDto dto = model.ToCreateDto();

        dto.ContextMatchType.Should().Be(WindowMatchType.WindowClass);
        dto.ContextValue.Should().Be("Chrome_WidgetWin_1");
    }

    [Fact]
    public void FromDto_WithContext_PopulatesContextFields()
    {
        HotstringDto dto = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, false,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Text,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "- Visual Studio");

        var model = HotstringEditModel.FromDto(dto);

        model.ContextMatchType.Should().Be(WindowMatchType.TitleContains);
        model.ContextValue.Should().Be("- Visual Studio");
    }

    [Fact]
    public void Clone_WithContext_CopiesContextFields()
    {
        HotstringEditModel model = new()
        {
            Trigger = "btw",
            ContextMatchType = WindowMatchType.Executable,
            ContextValue = "notepad.exe",
        };

        HotstringEditModel clone = model.Clone();

        clone.ContextMatchType.Should().Be(WindowMatchType.Executable);
        clone.ContextValue.Should().Be("notepad.exe");
    }

    [Theory]
    [InlineData(WindowMatchType.Executable, "notepad.exe", "exe:notepad.exe")]
    [InlineData(WindowMatchType.WindowClass, "Chrome_WidgetWin_1", "class:Chrome_WidgetWin_1")]
    [InlineData(WindowMatchType.TitleContains, "- Visual Studio", "title:- Visual Studio")]
    public void ContextSummary_WithContext_FormatsByMatchType(WindowMatchType matchType, string value, string expected)
    {
        HotstringEditModel model = new() { ContextMatchType = matchType, ContextValue = value };

        model.ContextSummary.Should().Be(expected);
    }

    [Fact]
    public void ContextSummary_NoContext_IsBlank()
    {
        HotstringEditModel model = new() { ContextMatchType = null };

        model.ContextSummary.Should().BeEmpty();
    }

    [Theory]
    [InlineData(HotstringKind.Text, HotstringDelivery.Type, 4_000)]
    [InlineData(HotstringKind.Text, HotstringDelivery.Auto, 100_000)]
    [InlineData(HotstringKind.Text, HotstringDelivery.ClipboardPaste, 100_000)]
    [InlineData(HotstringKind.Macro, HotstringDelivery.Auto, 4_000)]
    [InlineData(HotstringKind.Raw, HotstringDelivery.Auto, 4_200)]
    [InlineData(HotstringKind.DateTime, HotstringDelivery.Auto, 0)]
    public void ReplacementMaxLength_UsesKindAndDeliveryMatrix(
        HotstringKind kind,
        HotstringDelivery delivery,
        int expected)
    {
        HotstringEditModel model = new() { Kind = kind, Delivery = delivery };

        model.ReplacementMaxLength.Should().Be(expected);
    }

    [Theory]
    [InlineData(HotstringKind.Text, HotstringDelivery.Type, 4_001, false)]
    [InlineData(HotstringKind.Text, HotstringDelivery.Auto, 4_001, true)]
    [InlineData(HotstringKind.Text, HotstringDelivery.ClipboardPaste, 100_000, true)]
    [InlineData(HotstringKind.Text, HotstringDelivery.ClipboardPaste, 100_001, false)]
    [InlineData(HotstringKind.Macro, HotstringDelivery.Auto, 4_001, false)]
    [InlineData(HotstringKind.Raw, HotstringDelivery.Auto, 4_201, false)]
    public void ValidateReplacement_UsesKindAndDeliveryMatrix(
        HotstringKind kind,
        HotstringDelivery delivery,
        int length,
        bool expectedValid)
    {
        HotstringEditModel model = new() { Kind = kind, Delivery = delivery };

        string? error = model.ValidateReplacement(new string('x', length));

        (error is null).Should().Be(expectedValid);
    }

    [Fact]
    public void Delivery_RoundTripsThroughDtoAndClone()
    {
        HotstringDto dto = MakeDto() with
        {
            Delivery = HotstringDelivery.ClipboardPaste,
            ReplacementIsTruncated = true,
        };

        HotstringEditModel model = HotstringEditModel.FromDto(dto).Clone();

        model.Delivery.Should().Be(HotstringDelivery.ClipboardPaste);
        model.ReplacementIsTruncated.Should().BeTrue();
        model.ToCreateDto().Delivery.Should().Be(HotstringDelivery.ClipboardPaste);
        model.ToUpdateDto().Delivery.Should().Be(HotstringDelivery.ClipboardPaste);
    }
}
