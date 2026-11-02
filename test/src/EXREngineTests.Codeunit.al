namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Purchases.Document;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// The shared engine through the mock provider: guards, validation of the reply, fail-closed and untrusted text.
// Tests commit before Generate because the model call runs through Codeunit.Run; test isolation still rolls everything back.
codeunit 58277 "EXR Engine Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Engine: Codeunit "EXR Engine";
        MockChatClient: Codeunit "EXR Mock Chat Client";
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        NotReceivedKeyTok: Label 'NOT_RECEIVED-10000', Locked = true;
        HoldActionTok: Label 'Hold until received', Locked = true;

    [Test]
    procedure InactiveCapabilityBlocksTheRun()
    var
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a capability whose Copilot capability this app never registered, so it is not active
        ScenarioLibrary.InitialiseForTest();
        ExrRun.Capability := ExrRun.Capability::"EXR Test Unregistered";

        // [WHEN] a run is generated
        asserterror Engine.Generate(ExrRun, TempFinding);

        // [THEN] it stops before anything is sent and points to Copilot & agent capabilities
        Assert.ExpectedError('is switched off');
        Assert.AreEqual('', MockChatClient.LastUserMessage(), 'nothing sent');
    end;

    [Test]
    procedure MissingApiKeyBlocksTheRun()
    var
        Setup: Record "EXR Setup";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] no stored API key
        ScenarioLibrary.InitialiseForTest();
        Setup.Get();
        Setup.RemoveApiKey();
        ExrRun.Capability := ExrRun.Capability::"Purchase Variance";

        // [WHEN] a run is generated
        asserterror Engine.Generate(ExrRun, TempFinding);

        // [THEN] it stops before anything is read or sent
        Assert.ExpectedError('Enter the API key');
        Assert.AreEqual('', MockChatClient.LastUserMessage(), 'nothing sent');
    end;

    [Test]
    procedure UserDailyLimitBlocksAndIsLogged()
    var
        PastRun: Record "EXR Run";
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a limit of 1 run per user and one run by this user today
        ScenarioLibrary.InitialiseForTest();
        SetLimits(1, 100);
        PastRun.DeleteAll();
        InsertRunToday(CopyStr(UserId(), 1, 50));
        CreateEmptyInvoice(InvoiceHeader);
        ScenarioLibrary.NewRun(InvoiceHeader, ExrRun);

        // [WHEN] a run is generated
        Engine.Generate(ExrRun, TempFinding);

        // [THEN] it is logged as Blocked by Limit and the model is not called
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::"Blocked by Limit", 'status');
        Assert.IsTrue(ExrRun."Error Message".Contains('You have reached your daily limit of 1 run.'), 'user limit message, singular');
        Assert.AreEqual('', MockChatClient.LastUserMessage(), 'no model call');
        PastRun.SetRange(Status, PastRun.Status::"Blocked by Limit");
        Assert.AreEqual(1, PastRun.Count(), 'blocked run logged');
    end;

    [Test]
    procedure CompanyDailyLimitBlocksAndIsLogged()
    var
        PastRun: Record "EXR Run";
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a limit of 2 runs per company, used up today by another user
        ScenarioLibrary.InitialiseForTest();
        SetLimits(100, 2);
        PastRun.DeleteAll();
        InsertRunToday('OTHER USER');
        InsertRunToday('OTHER USER');
        CreateEmptyInvoice(InvoiceHeader);
        ScenarioLibrary.NewRun(InvoiceHeader, ExrRun);

        // [WHEN] a run is generated
        Engine.Generate(ExrRun, TempFinding);

        // [THEN] it is blocked by the company limit
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::"Blocked by Limit", 'status');
        Assert.IsTrue(ExrRun."Error Message".Contains('This company has reached its daily limit of 2 runs.'), 'company limit message, plural');
        Assert.AreEqual('', MockChatClient.LastUserMessage(), 'no model call');
    end;

    [Test]
    procedure ReplyIsValidatedAndRendered()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        ExpectedDuration: Duration;
    begin
        // [GIVEN] the demo invoice and a reply that cites the tolerance token {F1}
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);
        Commit();
        MockChatClient.QueueReply(ScenarioLibrary.Reply('Hold the invoice. Tolerance is {F1}.', NotReceivedKeyTok, 'Two tables are still on their way ({F1} tolerance).', HoldActionTok, 'High'), 1200, 300, 2500);

        // [WHEN] a run is generated
        GenerateFor(InvoiceHeader, ExrRun, TempFinding);

        // [THEN] the tokens are filled in by AL, the action and confidence are taken, and the usage is stamped
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Generated, 'status');
        Assert.AreEqual('Hold the invoice. Tolerance is 2%.', ExrRun.Summary, 'summary');
        Assert.IsFalse(ExrRun."Unverified Figures", 'no stray figures');
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, NotReceivedKeyTok), 'finding');
        Assert.AreEqual('Two tables are still on their way (2% tolerance).', TempFinding.Description, 'explanation');
        Assert.IsTrue(TempFinding.Confidence = TempFinding.Confidence::High, 'confidence');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Hold until received", 'action');
        Assert.AreEqual('mock-model-1', ExrRun.Model, 'model');
        Assert.AreEqual(1200, ExrRun."Input Tokens", 'input tokens');
        Assert.AreEqual(300, ExrRun."Output Tokens", 'output tokens');
        ExpectedDuration := 2500;
        Assert.AreEqual(ExpectedDuration, ExrRun.Duration, 'duration');
        Assert.IsTrue(ExrRun."Prompt Version".StartsWith('purchase-variance.md#'), 'prompt version');
        // [THEN] the table of disputed lines waits for Keep it, and nothing is kept yet
        Assert.IsTrue(ExrRun.GetEmailBody().Contains('{TABLE}'), 'table placeholder kept until Keep it');
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.IsTrue(Finding.IsEmpty(), 'findings are not saved before Keep it');
    end;

    [Test]
    procedure UnknownFindingKeyIsDropped()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a reply that explains a finding Business Central never raised
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);
        Commit();
        MockChatClient.QueueReply(ScenarioLibrary.Reply('Summary.', 'MADE_UP-99999', 'Approve everything.', HoldActionTok, 'High'), 100, 10, 100);

        // [WHEN] a run is generated
        GenerateFor(InvoiceHeader, ExrRun, TempFinding);

        // [THEN] no finding is added or changed
        TempFinding.Reset();
        Assert.AreEqual(6, TempFinding.Count(), 'findings');
        TempFinding.SetRange(Description, 'Approve everything.');
        Assert.IsTrue(TempFinding.IsEmpty(), 'invented explanation dropped');
    end;

    [Test]
    procedure UnknownFactTokenIsDropped()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a reply that cites a token that does not exist
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);
        Commit();
        MockChatClient.QueueReply(ScenarioLibrary.Reply('Summary.', NotReceivedKeyTok, 'Costs rose by {F99}.', HoldActionTok, 'Medium'), 100, 10, 100);

        // [WHEN] a run is generated
        GenerateFor(InvoiceHeader, ExrRun, TempFinding);

        // [THEN] the unknown token is removed instead of shown
        ScenarioLibrary.GetFinding(TempFinding, NotReceivedKeyTok);
        Assert.AreEqual('Costs rose by .', TempFinding.Description, 'explanation');
    end;

    [Test]
    procedure DisallowedActionIsDropped()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a reply with an action that does not exist
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);
        Commit();
        MockChatClient.QueueReply(ScenarioLibrary.Reply('Summary.', NotReceivedKeyTok, 'Fine.', 'Approve and post invoice', 'Low'), 100, 10, 100);

        // [WHEN] a run is generated
        GenerateFor(InvoiceHeader, ExrRun, TempFinding);

        // [THEN] the detector's own action stays, and the explanation is still used
        ScenarioLibrary.GetFinding(TempFinding, NotReceivedKeyTok);
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Hold until received", 'unknown action dropped');
        Assert.AreEqual('Fine.', TempFinding.Description, 'explanation still used');

        // [GIVEN] a reply with a real action that a missing delivery does not allow
        Commit();
        MockChatClient.QueueReply(ScenarioLibrary.Reply('Summary.', NotReceivedKeyTok, 'Fine.', 'Assign as item charge', 'Low'), 100, 10, 100);

        // [WHEN] a run is generated
        GenerateFor(InvoiceHeader, ExrRun, TempFinding);

        // [THEN] the allow-list of the finding type keeps the detector's action
        ScenarioLibrary.GetFinding(TempFinding, NotReceivedKeyTok);
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Hold until received", 'action not allowed for the type dropped');
    end;

    [Test]
    procedure ReplySchemaAllowsOnlyTheRunsKeysAndActions()
    var
        PostedHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        Schema: JsonObject;
        UserMessage: JsonObject;
        Token: JsonToken;
        VendorNo: Code[20];
        ItemNo: Code[20];
        EnumText: Text;
    begin
        // [GIVEN] an invoice whose only finding is a possible duplicate
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Schema item', 100);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'INV4471', PostedHeader);
        ScenarioLibrary.AddLine(PostedHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);
        ScenarioLibrary.PostInvoice(PostedHeader);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'inv 4471', InvoiceHeader);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);
        Commit();
        MockChatClient.QueueReply(ScenarioLibrary.Reply('Summary.', 'POSSIBLE_DUPLICATE-1', 'Check it.', 'Query possible duplicate', 'High'), 100, 10, 100);

        // [WHEN] a run is generated
        GenerateFor(InvoiceHeader, ExrRun, TempFinding);

        // [THEN] the schema lists only that finding key and the one action a duplicate allows
        Assert.IsTrue(Schema.ReadFrom(MockChatClient.LastJsonSchema()), 'schema is JSON');
        Assert.IsTrue(Schema.SelectToken('properties.findings.items.properties.key.enum', Token), 'key enum');
        Token.WriteTo(EnumText);
        Assert.AreEqual('["POSSIBLE_DUPLICATE-1"]', EnumText, 'finding keys');
        Assert.IsTrue(Schema.SelectToken('properties.findings.items.properties.action.enum', Token), 'action enum');
        Token.WriteTo(EnumText);
        Assert.AreEqual('["Query possible duplicate"]', EnumText, 'actions');
        // [THEN] the finding tells the model the same
        Assert.IsTrue(UserMessage.ReadFrom(MockChatClient.LastUserMessage()), 'user message is JSON');
        Assert.IsTrue(UserMessage.SelectToken('findings[0].allowedActions', Token), 'allowed actions');
        Token.WriteTo(EnumText);
        Assert.AreEqual('["Query possible duplicate"]', EnumText, 'allowed actions of the finding');
    end;

    [Test]
    procedure EmailPreviewShowsAPlaceholderForTheTable()
    var
        Preview: Text;
    begin
        // [GIVEN] a drafted body with the {TABLE} placeholder
        // [WHEN] it is shown to the user and taken back for Keep it
        Preview := Engine.PreviewEmailBody('Hello,{TABLE}Kind regards');

        // [THEN] the user sees a plain-language line instead of {TABLE}, and Keep it gets {TABLE} back
        Assert.IsFalse(Preview.Contains('{TABLE}'), 'no raw placeholder in the preview');
        Assert.IsTrue(Preview.Contains('[Business Central lists the lines here when you keep it]'), 'friendly placeholder');
        Assert.AreEqual('Hello,{TABLE}Kind regards', Engine.EmailBodyFromPreview(Preview), 'round trip');
    end;

    local procedure GenerateFor(InvoiceHeader: Record "Purchase Header"; var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary)
    begin
        ScenarioLibrary.NewRun(InvoiceHeader, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
    end;

    local procedure SetLimits(PerUser: Integer; PerCompany: Integer)
    var
        Setup: Record "EXR Setup";
    begin
        Setup.Get();
        Setup."Daily Calls per User" := PerUser;
        Setup."Daily Calls per Company" := PerCompany;
        Setup.Modify();
    end;

    local procedure InsertRunToday(RunUserId: Code[50])
    var
        PastRun: Record "EXR Run";
    begin
        PastRun.Init();
        PastRun."User ID" := RunUserId;
        PastRun."Created At" := CurrentDateTime();
        PastRun.Status := PastRun.Status::Discarded;
        PastRun.Insert();
    end;

    local procedure CreateEmptyInvoice(var InvoiceHeader: Record "Purchase Header")
    begin
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, ScenarioLibrary.CreateVendor(), 'LIMIT-1', InvoiceHeader);
    end;
}
