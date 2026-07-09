using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HotstringBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private bool _appliesToAllProfiles = true;
    private Guid[] _profileIds = [];
    private readonly List<Guid> _categoryIds = [];
    private string _trigger = "btw";
    private string _replacement = "by the way";
    private string? _description;
    private bool _isEndingCharacterRequired = true;
    private bool _isTriggerInsideWord = true;
    private HotstringKind _kind = HotstringKind.Text;
    private bool _isCaseSensitive;
    private bool _omitEndingCharacter;
    private string? _dateTimeFormat;
    private int? _dateOffsetAmount;
    private DateOffsetUnit? _dateOffsetUnit;
    private TimeProvider _clock = TimeProvider.System;

    public HotstringBuilder WithOwner(Guid ownerOid)
    {
        _ownerOid = ownerOid;
        return this;
    }

    public HotstringBuilder InProfile(Guid profileId)
    {
        _appliesToAllProfiles = false;
        _profileIds = [profileId];
        return this;
    }

    public HotstringBuilder WithProfiles(params Guid[] profileIds)
    {
        _appliesToAllProfiles = false;
        _profileIds = profileIds;
        return this;
    }

    public HotstringBuilder AppliesToAllProfiles(bool value = true)
    {
        _appliesToAllProfiles = value;
        return this;
    }

    public HotstringBuilder WithTrigger(string trigger)
    {
        _trigger = trigger;
        return this;
    }

    public HotstringBuilder WithReplacement(string replacement)
    {
        _replacement = replacement;
        return this;
    }

    public HotstringBuilder WithDescription(string? description)
    {
        _description = description;
        return this;
    }

    public HotstringBuilder WithEndingCharacterRequired(bool value)
    {
        _isEndingCharacterRequired = value;
        return this;
    }

    public HotstringBuilder WithTriggerInsideWord(bool value)
    {
        _isTriggerInsideWord = value;
        return this;
    }

    public HotstringBuilder WithKind(HotstringKind kind)
    {
        _kind = kind;
        return this;
    }

    public HotstringBuilder WithCaseSensitive(bool value)
    {
        _isCaseSensitive = value;
        return this;
    }

    public HotstringBuilder WithOmitEndingCharacter(bool value)
    {
        _omitEndingCharacter = value;
        return this;
    }

    public HotstringBuilder WithDateTimeFormat(string format)
    {
        _dateTimeFormat = format;
        return this;
    }

    public HotstringBuilder WithDateOffset(int amount, DateOffsetUnit unit)
    {
        _dateOffsetAmount = amount;
        _dateOffsetUnit = unit;
        return this;
    }

    public HotstringBuilder WithCategory(Guid categoryId)
    {
        _categoryIds.Add(categoryId);
        return this;
    }

    public HotstringBuilder WithCategories(params Guid[] categoryIds)
    {
        _categoryIds.Clear();
        _categoryIds.AddRange(categoryIds);
        return this;
    }

    public HotstringBuilder WithClock(TimeProvider clock)
    {
        _clock = clock;
        return this;
    }

    public Hotstring Build()
    {
        var entity = Hotstring.Create(
            _ownerOid,
            new HotstringDefinition(
                _trigger, _replacement, _description, _appliesToAllProfiles,
                _isEndingCharacterRequired, _isTriggerInsideWord,
                _kind, _isCaseSensitive, _omitEndingCharacter,
                _dateTimeFormat, _dateOffsetAmount, _dateOffsetUnit),
            _clock);

        foreach (Guid pid in _profileIds)
            entity.Profiles.Add(HotstringProfile.Create(entity.Id, pid));

        foreach (Guid cid in _categoryIds)
            entity.Categories.Add(HotstringCategory.Create(entity.Id, cid));

        return entity;
    }
}
