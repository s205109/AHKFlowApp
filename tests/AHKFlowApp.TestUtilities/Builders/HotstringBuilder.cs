using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HotstringBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private bool _appliesToAllProfiles = true;
    private Guid[] _profileIds = [];
    private string _trigger = "btw";
    private string _replacement = "by the way";
    private bool _isEndingCharacterRequired = true;
    private bool _isTriggerInsideWord = true;
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

    public HotstringBuilder WithClock(TimeProvider clock)
    {
        _clock = clock;
        return this;
    }

    public Hotstring Build()
    {
        var entity = Hotstring.Create(
            _ownerOid, _trigger, _replacement, _appliesToAllProfiles,
            _isEndingCharacterRequired, _isTriggerInsideWord, _clock);

        foreach (Guid pid in _profileIds)
            entity.Profiles.Add(HotstringProfile.Create(entity.Id, pid));

        return entity;
    }
}
