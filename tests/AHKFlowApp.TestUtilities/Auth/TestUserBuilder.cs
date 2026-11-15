using System.Net.Http.Headers;

namespace AHKFlowApp.TestUtilities.Auth;

public sealed class TestUserBuilder
{
    private Guid _oid = new("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private string _email = "test@example.com";
    private string _name = "Test User";
    private string? _scope = "access_as_user";
    private bool _authenticateByDefault;

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

    internal TestUserBuilder AuthenticateByDefault()
    {
        _authenticateByDefault = true;
        return this;
    }

    // Writes this user as the X-Test-* headers that TestAuthHandler reads on each request.
    public void ApplyTo(HttpRequestHeaders headers)
    {
        headers.Add("X-Test-Auth", "true");
        headers.Add("X-Test-Oid", _oid.ToString());
        headers.Add("X-Test-Email", _email);
        headers.Add("X-Test-Name", _name);

        if (_scope is null)
            headers.Add("X-Test-Without-Scope", "true");
        else
            headers.Add("X-Test-Scope", _scope);
    }

    internal Guid DefaultOid => _oid;
    internal string DefaultEmail => _email;
    internal string DefaultName => _name;
    internal string? DefaultScope => _scope;
    internal bool DefaultAuthenticate => _authenticateByDefault;
}
