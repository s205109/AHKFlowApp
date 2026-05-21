using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class CategoryBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private string _name = "Email";
    private TimeProvider _clock = TimeProvider.System;

    public CategoryBuilder WithOwner(Guid ownerOid)
    {
        _ownerOid = ownerOid;
        return this;
    }

    public CategoryBuilder Named(string name)
    {
        _name = name;
        return this;
    }

    public CategoryBuilder WithClock(TimeProvider clock)
    {
        _clock = clock;
        return this;
    }

    public Category Build() => Category.Create(_ownerOid, _name, _clock);
}
