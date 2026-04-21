namespace AHKFlowApp.TestUtilities.Auth;

public sealed class TestUserBuilder
{
    private Guid _oid = new("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private string _email = "test@example.com";
    private string _name = "Test User";
    private string? _scope = "access_as_user";

    public TestUserBuilder WithOid(Guid oid)
    {
        _oid = oid;
        return this;
    }

    public TestUserBuilder WithEmail(string email)
    {
        _email = email;
        return this;
    }

    public TestUserBuilder WithName(string name)
    {
        _name = name;
        return this;
    }

    public TestUserBuilder WithScope(string scope)
    {
        _scope = scope;
        return this;
    }

    public TestUserBuilder WithoutScope()
    {
        _scope = null;
        return this;
    }

    internal Guid DefaultOid => _oid;
    internal string DefaultEmail => _email;
    internal string DefaultName => _name;
    internal string? DefaultScope => _scope;
}
