namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// Setup defaults, the https-only endpoint and the API key in isolated storage.
// RequiredTestIsolation = Codeunit rolls back the setup record and the isolated storage changes.
codeunit 58271 "EXR Setup Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure NewSetupHasDefaults()
    var
        Setup: Record "EXR Setup";
    begin
        // [GIVEN] no setup record
        Setup.DeleteAll();

        // [WHEN] the setup is created
        Setup.InsertIfMissing();

        // [THEN] it holds the Claude defaults and the limits
        Setup.Get();
        Assert.IsTrue(Setup.Provider = Setup.Provider::Claude, 'provider');
        Assert.AreEqual('claude-haiku-5-5', Setup.Model, 'model');
        Assert.AreEqual('https://api.anthropic.com/v1/messages', Setup.Endpoint, 'endpoint');
        Assert.AreEqual('2026-10-21', Setup."API Version", 'API version');
        Assert.IsTrue(Setup.Effort = Setup.Effort::Low, 'effort');
        Assert.AreEqual(8000, Setup."Max Output Tokens", 'max output tokens');
        Assert.AreEqual(50, Setup."Daily Calls per User", 'daily calls per user');
        Assert.AreEqual(500, Setup."Daily Calls per Company", 'daily calls per company');
    end;

    [Test]
    procedure EndpointMustUseHttps()
    var
        Setup: Record "EXR Setup";
    begin
        // [GIVEN] a setup record
        Setup.Init();

        // [WHEN] an https endpoint is entered, in any letter case
        Setup.Validate(Endpoint, 'HTTPS://proxy.example.com/v1/messages');

        // [THEN] it is accepted, and a plain http endpoint is refused
        Assert.AreEqual('HTTPS://proxy.example.com/v1/messages', Setup.Endpoint, 'https endpoint');
        asserterror Setup.Validate(Endpoint, 'http://api.anthropic.com/v1/messages');
        Assert.ExpectedError('https://');
    end;

    [Test]
    procedure ApiKeyCanBeSetCheckedAndRemoved()
    var
        Setup: Record "EXR Setup";
        EmptyKey: SecretText;
    begin
        // [GIVEN] no stored key (test isolation puts back a key already on the sandbox)
        Setup.RemoveApiKey();
        Assert.IsFalse(Setup.HasApiKey(), 'no key after remove');

        // [WHEN] a key is stored
        Setup.SetApiKey('sk-ant-test-' + Format(CreateGuid()));

        // [THEN] it is there, an empty key removes it, and removing twice is harmless
        Assert.IsTrue(Setup.HasApiKey(), 'key stored');
        Setup.SetApiKey(EmptyKey);
        Assert.IsFalse(Setup.HasApiKey(), 'empty key removes the key');
        Setup.RemoveApiKey();
        Assert.IsFalse(Setup.HasApiKey(), 'second remove');
    end;
}
