namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Purchases.Document;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// Human in the loop: a failed or blocked Regenerate keeps the current run, Discard writes only the run, a second Keep it changes nothing.
codeunit 58282 "EXR Regenerate Tests"
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
        EmailSubjectTok: Label 'Query on invoice INV-4472', Locked = true;
        EmailBodyTok: Label 'Hello, please confirm the lines below.', Locked = true;

    [Test]
    procedure BlockedRegenerateKeepsTheCurrentRun()
    var
        Setup: Record "EXR Setup";
        OtherRun: Record "EXR Run";
        InvoiceHeader: Record "Purchase Header";
        CurrentRun: Record "EXR Run";
        NewRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        FirstEntryNo: Integer;
    begin
        // [GIVEN] a generated run in the dialog that used up the user's last run of the day
        GenerateDemoRun(InvoiceHeader, CurrentRun, TempFinding);
        FirstEntryNo := CurrentRun."Entry No.";
        OtherRun.SetFilter("Entry No.", '<>%1', FirstEntryNo);
        OtherRun.DeleteAll();
        Setup.Get();
        Setup."Daily Calls per User" := 1;
        Setup.Modify();

        // [WHEN] the user regenerates
        ScenarioLibrary.NewRun(InvoiceHeader, NewRun);
        asserterror Engine.Regenerate(CurrentRun, TempFinding, NewRun);

        // [THEN] the limit is reported and the current run and its findings are still there to keep
        Assert.ExpectedError('You have reached your daily limit of 1 run.');
        Assert.AreEqual(FirstEntryNo, CurrentRun."Entry No.", 'current run');
        TempFinding.Reset();
        Assert.AreEqual(6, TempFinding.Count(), 'findings');
        Engine.Keep(CurrentRun, TempFinding, EmailSubjectTok, EmailBodyTok);
        Finding.SetRange("Run Entry No.", FirstEntryNo);
        Assert.AreEqual(6, Finding.Count(), 'findings kept');
    end;

    [Test]
    procedure FailedRegenerateKeepsTheCurrentRun()
    var
        Setup: Record "EXR Setup";
        InvoiceHeader: Record "Purchase Header";
        CurrentRun: Record "EXR Run";
        NewRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        FirstEntryNo: Integer;
    begin
        // [GIVEN] a generated run in the dialog, and then the API key is removed
        GenerateDemoRun(InvoiceHeader, CurrentRun, TempFinding);
        FirstEntryNo := CurrentRun."Entry No.";
        Commit();
        Setup.Get();
        Setup.RemoveApiKey();

        // [WHEN] the user regenerates
        ScenarioLibrary.NewRun(InvoiceHeader, NewRun);
        asserterror Engine.Regenerate(CurrentRun, TempFinding, NewRun);

        // [THEN] the error is shown and the current run can still be kept
        Assert.ExpectedError('Enter the API key');
        Assert.AreEqual(FirstEntryNo, CurrentRun."Entry No.", 'current run');
        TempFinding.Reset();
        Assert.AreEqual(6, TempFinding.Count(), 'findings');
        Engine.Keep(CurrentRun, TempFinding, EmailSubjectTok, EmailBodyTok);
        CurrentRun.Get(FirstEntryNo);
        Assert.IsTrue(CurrentRun.Status = CurrentRun.Status::Kept, 'kept');
    end;

    [Test]
    procedure AiFailureOnRegenerateKeepsTheCurrentRun()
    var
        FailedRun: Record "EXR Run";
        InvoiceHeader: Record "Purchase Header";
        CurrentRun: Record "EXR Run";
        NewRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        FirstEntryNo: Integer;
    begin
        // [GIVEN] a generated run in the dialog, and an AI service that fails on the next call
        GenerateDemoRun(InvoiceHeader, CurrentRun, TempFinding);
        FirstEntryNo := CurrentRun."Entry No.";
        Commit();
        MockChatClient.QueueError('The Claude API is overloaded at the moment. Try again in a few minutes.');

        // [WHEN] the user regenerates
        ScenarioLibrary.NewRun(InvoiceHeader, NewRun);
        asserterror Engine.Regenerate(CurrentRun, TempFinding, NewRun);

        // [THEN] the failure is shown, the failed call stays as the usage record, and the current run can still be kept
        Assert.ExpectedError('A new result could not be created, so the previous one is kept.');
        FailedRun.SetFilter("Entry No.", '>%1', FirstEntryNo);
        FailedRun.SetRange(Status, FailedRun.Status::Failed);
        Assert.IsFalse(FailedRun.IsEmpty(), 'failed call logged');
        Assert.AreEqual(FirstEntryNo, CurrentRun."Entry No.", 'current run');
        TempFinding.Reset();
        Assert.AreEqual(6, TempFinding.Count(), 'findings');
        Engine.Keep(CurrentRun, TempFinding, EmailSubjectTok, EmailBodyTok);
        CurrentRun.Get(FirstEntryNo);
        Assert.IsTrue(CurrentRun.Status = CurrentRun.Status::Kept, 'kept');
    end;

    [Test]
    procedure DiscardWritesOnlyTheRunRow()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        LedgersBefore: Text;
        LinesBefore: Text;
    begin
        // [GIVEN] a generated run
        GenerateDemoRun(InvoiceHeader, ExrRun, TempFinding);
        LedgersBefore := ScenarioLibrary.LedgerFingerprint();
        LinesBefore := ScenarioLibrary.LinesFingerprint(InvoiceHeader);

        // [WHEN] the user discards it
        Engine.Discard(ExrRun);

        // [THEN] only the run row changes, to Discarded
        ExrRun.Get(ExrRun."Entry No.");
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Discarded, 'status');
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.IsTrue(Finding.IsEmpty(), 'no findings saved');
        InvoiceHeader.Get(InvoiceHeader."Document Type", InvoiceHeader."No.");
        Assert.AreEqual('', InvoiceHeader."On Hold", 'not on hold');
        Assert.AreEqual(LedgersBefore, ScenarioLibrary.LedgerFingerprint(), 'no ledger entries');
        Assert.AreEqual(LinesBefore, ScenarioLibrary.LinesFingerprint(InvoiceHeader), 'invoice lines unchanged');
    end;

    [Test]
    procedure SecondKeepChangesNothing()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a run that was kept once
        GenerateDemoRun(InvoiceHeader, ExrRun, TempFinding);
        Engine.Keep(ExrRun, TempFinding, EmailSubjectTok, EmailBodyTok);

        // [WHEN] Keep it runs again with another email
        Engine.Keep(ExrRun, TempFinding, 'Another subject', 'Another body');

        // [THEN] the findings are not doubled and the first email stays
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.AreEqual(6, Finding.Count(), 'findings not doubled');
        ExrRun.Get(ExrRun."Entry No.");
        Assert.AreEqual(EmailSubjectTok, ExrRun."Email Subject", 'first email kept');
        InvoiceHeader.Get(InvoiceHeader."Document Type", InvoiceHeader."No.");
        Assert.AreEqual('QRY', InvoiceHeader."On Hold", 'still on hold');
    end;

    [Test]
    procedure KeptSubjectKeepsTheVendorInvoiceNo()
    var
        InvoiceHeader: Record "Purchase Header";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a generated run where the user removed the vendor invoice number from the subject
        GenerateDemoRun(InvoiceHeader, ExrRun, TempFinding);

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, 'Query on your invoice', EmailBodyTok);

        // [THEN] the kept subject has the number again
        ExrRun.Get(ExrRun."Entry No.");
        Assert.AreEqual('Query on your invoice INV-4472', ExrRun."Email Subject", 'number added on Keep it');
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
