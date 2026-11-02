namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Purchases.Document;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// Human in the loop: Keep it writes only the run, the accepted findings, On Hold and the email draft; Discard writes only the run.
codeunit 58278 "EXR Keep Discard Tests"
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
        PriceKeyTok: Label 'PRICE_VS_PO-10000', Locked = true;
        DuplicateKeyTok: Label 'POSSIBLE_DUPLICATE-1', Locked = true;
        HoldActionTok: Label 'Hold until received', Locked = true;
        EmailSubjectTok: Label 'Query on invoice INV-4472', Locked = true;
        EmailBodyTok: Label 'Hello, please confirm the lines below.', Locked = true;
        TableBodyTok: Label 'Hello,{TABLE}Kind regards', Locked = true;
        KeptOnHoldTok: Label 'Review saved. Invoice %1 is on hold (QRY).', Locked = true;

    [Test]
    procedure KeepPutsInvoiceOnHoldAndPostsNothing()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        LedgersBefore: Text;
        LinesBefore: Text;
        KeptMessage: Text;
    begin
        // [GIVEN] a generated run on the demo invoice; every finding is accepted
        GenerateDemoRun(InvoiceHeader, ExrRun, TempFinding);
        LedgersBefore := ScenarioLibrary.LedgerFingerprint();
        LinesBefore := ScenarioLibrary.LinesFingerprint(InvoiceHeader);

        // [WHEN] the user keeps it with an edited email
        KeptMessage := Engine.Keep(ExrRun, TempFinding, EmailSubjectTok, EmailBodyTok);

        // [THEN] the user is told what was saved and how to see it, because the open invoice's panel does not refresh itself
        Assert.IsTrue(KeptMessage.StartsWith(StrSubstNo(KeptOnHoldTok, InvoiceHeader."No.")), 'confirmation');
        Assert.IsTrue(KeptMessage.Contains('Reopen the invoice'), 'how to see the review');

        // [THEN] the invoice is on hold with the setup code
        InvoiceHeader.Get(InvoiceHeader."Document Type", InvoiceHeader."No.");
        Assert.AreEqual('QRY', InvoiceHeader."On Hold", 'on hold');
        // [THEN] the run is kept with all six findings, the edited email with the table added, and the vendor's address
        ExrRun.Get(ExrRun."Entry No.");
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Kept, 'status');
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.AreEqual(6, Finding.Count(), 'findings kept');
        Assert.AreEqual(EmailSubjectTok, ExrRun."Email Subject", 'email subject');
        Assert.IsTrue(ExrRun.GetEmailBody().StartsWith(EmailBodyTok), 'edited email body');
        Assert.IsTrue(ExrRun.GetEmailBody().Contains('- Line 10000: '), 'table of disputed lines added');
        Assert.AreEqual(ScenarioLibrary.DemoVendorEmail(), ExrRun."Email To", 'email address filled in by AL');
        // [THEN] nothing was posted and the invoice lines are unchanged
        Assert.AreEqual(LedgersBefore, ScenarioLibrary.LedgerFingerprint(), 'no ledger entries');
        Assert.AreEqual(LinesBefore, ScenarioLibrary.LinesFingerprint(InvoiceHeader), 'invoice lines unchanged');
    end;

    [Test]
    procedure EmailListsOnlyAcceptedFindings()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        NotReceivedDetail: Text;
        PriceDetail: Text;
        EmailBody: Text;
    begin
        // [GIVEN] a generated run where the user unticks the missing-delivery finding
        GenerateDemoRun(InvoiceHeader, ExrRun, TempFinding);
        ScenarioLibrary.GetFinding(TempFinding, NotReceivedKeyTok);
        NotReceivedDetail := TempFinding.Detail;
        TempFinding.Accepted := false;
        TempFinding.Modify();
        ScenarioLibrary.GetFinding(TempFinding, PriceKeyTok);
        PriceDetail := TempFinding.Detail;
        TempFinding.Reset();

        // [WHEN] the user keeps it with {TABLE} in the body
        Engine.Keep(ExrRun, TempFinding, EmailSubjectTok, TableBodyTok);

        // [THEN] the table lists the accepted price finding but not the unticked one
        ExrRun.Get(ExrRun."Entry No.");
        EmailBody := ExrRun.GetEmailBody();
        Assert.IsTrue(EmailBody.Contains(PriceDetail), 'accepted finding listed');
        Assert.IsFalse(EmailBody.Contains(NotReceivedDetail), 'unticked finding not listed');
        Assert.IsFalse(EmailBody.Contains('{TABLE}'), 'placeholder replaced');
    end;

    [Test]
    procedure KeepWithoutVendorQueriesLeavesInvoiceAlone()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a generated run where the user accepts only the item charge and freight findings
        GenerateDemoRun(InvoiceHeader, ExrRun, TempFinding);
        TempFinding.Reset();
        TempFinding.SetFilter("Action", '<>%1', TempFinding."Action"::"Assign as item charge");
        TempFinding.ModifyAll(Accepted, false);
        TempFinding.Reset();

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, EmailSubjectTok, EmailBodyTok);

        // [THEN] only the two accepted findings are saved, the invoice is not put on hold and no vendor email is prepared
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.AreEqual(2, Finding.Count(), 'accepted findings only');
        Finding.SetRange("Action", Finding."Action"::"Assign as item charge");
        Assert.AreEqual(2, Finding.Count(), 'the accepted ones');
        InvoiceHeader.Get(InvoiceHeader."Document Type", InvoiceHeader."No.");
        Assert.AreEqual('', InvoiceHeader."On Hold", 'not on hold');
        ExrRun.Get(ExrRun."Entry No.");
        Assert.AreEqual('', ExrRun."Email To", 'no vendor email without a vendor query');
    end;

    [Test]
    procedure BlankHoldCodeNeverHolds()
    var
        Setup: Record "EXR Setup";
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a generated run and no hold code in the setup
        GenerateDemoRun(InvoiceHeader, ExrRun, TempFinding);
        Setup.Get();
        Setup."Hold Code" := '';
        Setup.Modify();

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, EmailSubjectTok, EmailBodyTok);

        // [THEN] the invoice is not on hold, but the vendor email is still prepared
        InvoiceHeader.Get(InvoiceHeader."Document Type", InvoiceHeader."No.");
        Assert.AreEqual('', InvoiceHeader."On Hold", 'not on hold');
        ExrRun.Get(ExrRun."Entry No.");
        Assert.AreEqual(ScenarioLibrary.DemoVendorEmail(), ExrRun."Email To", 'vendor email prepared');
    end;

    [Test]
    procedure ExistingHoldIsNotOverwritten()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a generated run on an invoice that someone already put on hold with another code
        GenerateDemoRun(InvoiceHeader, ExrRun, TempFinding);
        InvoiceHeader.Get(InvoiceHeader."Document Type", InvoiceHeader."No.");
        InvoiceHeader."On Hold" := 'ABC';
        InvoiceHeader.Modify();

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, EmailSubjectTok, EmailBodyTok);

        // [THEN] the existing hold code stays
        InvoiceHeader.Get(InvoiceHeader."Document Type", InvoiceHeader."No.");
        Assert.AreEqual('ABC', InvoiceHeader."On Hold", 'existing hold kept');
    end;

    [Test]
    procedure ModelCannotTurnADuplicateIntoAnAccept()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a reply that answers the possible duplicate with Accept within tolerance
        GenerateDemoRunWithReply(InvoiceHeader, ExrRun, TempFinding,
            ScenarioLibrary.Reply('Summary.', DuplicateKeyTok, 'Looks fine.', 'Accept within tolerance', 'High'));

        // [THEN] the duplicate keeps its own action
        ScenarioLibrary.GetFinding(TempFinding, DuplicateKeyTok);
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Query possible duplicate", 'action kept');

        // [WHEN] the user keeps only the duplicate
        TempFinding.Reset();
        TempFinding.SetFilter("Finding Key", '<>%1', DuplicateKeyTok);
        TempFinding.ModifyAll(Accepted, false);
        TempFinding.Reset();
        Engine.Keep(ExrRun, TempFinding, EmailSubjectTok, EmailBodyTok);

        // [THEN] the duplicate alone puts the invoice on hold
        InvoiceHeader.Get(InvoiceHeader."Document Type", InvoiceHeader."No.");
        Assert.AreEqual('QRY', InvoiceHeader."On Hold", 'on hold');
    end;

    local procedure GenerateDemoRun(var InvoiceHeader: Record "Purchase Header"; var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary)
    begin
        GenerateDemoRunWithReply(InvoiceHeader, ExrRun, TempFinding,
            ScenarioLibrary.Reply('Hold the invoice.', NotReceivedKeyTok, 'Two tables are missing.', HoldActionTok, 'High'));
    end;

    local procedure GenerateDemoRunWithReply(var InvoiceHeader: Record "Purchase Header"; var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; ReplyText: Text)
    begin
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);
        Commit();
        MockChatClient.QueueReply(ReplyText, 1000, 200, 1500);
        ScenarioLibrary.NewRun(InvoiceHeader, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Generated, 'generated');
    end;
}
