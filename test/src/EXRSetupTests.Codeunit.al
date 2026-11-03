namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;
using System.AI;
using System.TestLibraries.Utilities;
using System.Upgrade;

// Setup defaults, the https-only endpoint, the API key in isolated storage, and the 1.1 upgrade of the setup and capabilities.
// RequiredTestIsolation = Codeunit rolls back the setup record and the isolated storage changes.
codeunit 58271 "EXR Setup Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        AppIdTxt: Label 'fd0480a3-8f77-4e94-8c93-afbff2a5c456', Locked = true;

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

    [Test]
    procedure NewSetupHasPaymentRunDefaults()
    var
        Setup: Record "EXR Setup";
    begin
        // [GIVEN] no setup record
        Setup.DeleteAll();

        // [WHEN] the setup is created
        Setup.InsertIfMissing();

        // [THEN] Check payment run has its windows and threshold
        Setup.Get();
        Assert.AreEqual(60, Setup."Duplicate Window Days", 'duplicate window');
        Assert.AreEqual(30, Setup."Bank Change Window Days", 'bank-change window');
        Assert.AreEqual(100, Setup."Unusual Amount %", 'unusual amount threshold');
        Assert.AreEqual('QRY', Setup."Hold Code", 'hold code');
    end;

    [Test]
    procedure UpgradeFillsOnlyThePaymentRunFields()
    var
        Setup: Record "EXR Setup";
        Upgrade: Codeunit "EXR Upgrade";
    begin
        // [GIVEN] a 1.0 setup: its own hold code, tolerance and model, and the 1.1 fields still 0
        Setup.InsertIfMissing();
        Setup."Hold Code" := 'ABC';
        Setup."Variance Tolerance %" := 5;
        Setup.Model := 'claude-test-model';
        Setup."Duplicate Window Days" := 0;
        Setup."Bank Change Window Days" := 0;
        Setup."Unusual Amount %" := 0;
        Setup.Modify();

        // [WHEN] the upgrade fills the defaults
        Upgrade.FillPaymentRunDefaults();

        // [THEN] the 1.1 fields get their defaults and every value the company set stays
        Setup.Get();
        Assert.AreEqual(60, Setup."Duplicate Window Days", 'duplicate window');
        Assert.AreEqual(30, Setup."Bank Change Window Days", 'bank-change window');
        Assert.AreEqual(100, Setup."Unusual Amount %", 'unusual amount threshold');
        Assert.AreEqual('ABC', Setup."Hold Code", 'hold code kept');
        Assert.AreEqual(5, Setup."Variance Tolerance %", 'tolerance kept');
        Assert.AreEqual('claude-test-model', Setup.Model, 'model kept');
    end;

    [Test]
    procedure UpgradeRunsOncePerCompany()
    var
        Setup: Record "EXR Setup";
        Install: Codeunit "EXR Install";
        Upgrade: Codeunit "EXR Upgrade";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        // [GIVEN] a company that installed or upgraded to 1.1, and payment run values the users chose later
        Assert.IsTrue(UpgradeTag.HasUpgradeTag(Install.PaymentRunDefaultsTag()), 'tag set by install or upgrade');
        Setup.InsertIfMissing();
        Setup."Duplicate Window Days" := 7;
        Setup."Bank Change Window Days" := 3;
        Setup."Unusual Amount %" := 50;
        Setup.Modify();

        // [WHEN] the upgrade runs again
        Upgrade.UpgradePaymentRunDefaults();

        // [THEN] it changes nothing
        Setup.Get();
        Assert.AreEqual(7, Setup."Duplicate Window Days", 'duplicate window kept');
        Assert.AreEqual(3, Setup."Bank Change Window Days", 'bank-change window kept');
        Assert.AreEqual(50, Setup."Unusual Amount %", 'threshold kept');
    end;

    [Test]
    procedure PaymentRunTagsAreRegistered()
    var
        Install: Codeunit "EXR Install";
        UpgradeTag: Codeunit "Upgrade Tag";
        PerCompanyTags: List of [Code[250]];
        PerDatabaseTags: List of [Code[250]];
    begin
        // [GIVEN] the app is installed
        // [WHEN] the upgrade tags for new companies and for the database are listed
        UpgradeTag.GetPerCompanyUpgradeTags(PerCompanyTags);
        UpgradeTag.GetPerDatabaseUpgradeTags(PerDatabaseTags);

        // [THEN] a new company never gets the 1.0 setup upgraded, and the capability step runs once per database
        Assert.IsTrue(PerCompanyTags.Contains(Install.PaymentRunDefaultsTag()), 'per company');
        Assert.IsTrue(PerCompanyTags.Contains(Install.ReviewDefaultsTag()), 'per company, 1.0');
        Assert.IsTrue(PerDatabaseTags.Contains(Install.PaymentRunCapabilityTag()), 'per database');
    end;

    [Test]
    procedure PaymentRunCapabilityIsRegistered()
    var
        CopilotCapability: Codeunit "Copilot Capability";
        AppId: Guid;
    begin
        // [GIVEN] the app is installed or upgraded to 1.1
        // [WHEN] the Copilot capabilities are read
        // [THEN] Check payment run is registered next to the 1.0 capabilities
        // asked for the main app: without an app id the check looks under the test app
        Evaluate(AppId, AppIdTxt);
        Assert.IsTrue(CopilotCapability.IsCapabilityRegistered(Enum::"Copilot Capability"::"EXR Payment Run", AppId), 'payment run');
        Assert.IsTrue(CopilotCapability.IsCapabilityRegistered(Enum::"Copilot Capability"::"EXR Collections", AppId), 'collections');
    end;
}
