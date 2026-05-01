using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class ProfileBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private string _name = "Default";
    private bool _isDefault = true;
    private string _headerTemplate = "";
    private string _footerTemplate = "";
    private TimeProvider _clock = TimeProvider.System;

    public ProfileBuilder WithOwner(Guid ownerOid) { _ownerOid = ownerOid; return this; }
    public ProfileBuilder WithName(string name) { _name = name; return this; }
    public ProfileBuilder AsDefault(bool isDefault = true) { _isDefault = isDefault; return this; }
    public ProfileBuilder WithHeader(string header) { _headerTemplate = header; return this; }
    public ProfileBuilder WithFooter(string footer) { _footerTemplate = footer; return this; }
    public ProfileBuilder WithClock(TimeProvider clock) { _clock = clock; return this; }

    public Profile Build() => Profile.Create(
        _ownerOid, _name, _isDefault, _headerTemplate, _footerTemplate, _clock);
}
