namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Purchases.Payables;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// Human in the loop for Check payment run: Keep it saves the run and, for each accepted Hold only, deletes that payment line and
// puts its invoice at risk on hold through Vend. Entry-Edit, after checking the line again. Nothing is posted; Discard writes only the run.
// What a Hold puts on hold for a summarised line, and the checks before writing, are in EXR Payment Run Hold Tests.
codeunit 58290 "EXR Payment Run Keep Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Engine: Codeunit "EXR Engine";
        MockChatClient: Codeunit "EXR Mock Chat Client";
        PaymentRunLibrary: Codeunit "EXR Payment Run Library";
        VendorNameTok: Label 'Proseware Office Supplies', Locked = true;
        ChangedLineErr: Label 'changed or left the journal after the check, so nothing was kept', Locked = true;
        LatestNoteTok: Label 'The latest check of this batch.', Locked = true;

    [Test]
    procedure KeepHoldsTheInvoiceAndRemovesOnlyThatLine()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
        FirstLineId: Guid;
        SecondLineId: Guid;
        OtherLineId: Guid;
        LedgerBefore: Text;
        OtherLinesBefore: Text;
        KeptMessage: Text;
    begin
        // [GIVEN] lines for INV-4471 and INV4471 and a usual payment; the reply asks the vendor about the first and holds the second
        CreateDuplicateRun(GenJournalBatch, FirstInvoiceNo, SecondInvoiceNo, FirstLineId, SecondLineId, OtherLineId);
        MockChatClient.QueueReply(TwoLineReply('Ask vendor to confirm duplicate', 'Hold'), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Generated, 'generated');
        LedgerBefore := PaymentRunLibrary.LedgerFingerprint();
        OtherLinesBefore := PaymentRunLibrary.JournalFingerprint(GenJournalBatch, SecondLineId);

        // [WHEN] the user keeps it
        KeptMessage := Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] the held line is gone and its invoice is on hold with the setup's hold code
        Assert.IsFalse(PaymentRunLibrary.LineExists(SecondLineId), 'held line deleted');
        Assert.AreEqual('QRY', PaymentRunLibrary.InvoiceOnHold(SecondInvoiceNo), 'invoice on hold');
        // [THEN] the line the vendor is asked about stays in the journal and its invoice is not on hold; the other lines are unchanged
        Assert.IsTrue(PaymentRunLibrary.LineExists(FirstLineId), 'asked line stays');
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(FirstInvoiceNo), 'asked invoice not on hold');
        Assert.AreEqual(OtherLinesBefore, PaymentRunLibrary.JournalFingerprint(GenJournalBatch, SecondLineId), 'other lines unchanged');
        // [THEN] nothing was posted, and the run is kept as evidence with both findings
        Assert.AreEqual(LedgerBefore, PaymentRunLibrary.LedgerFingerprint(), 'nothing posted');
        ExrRun.Get(ExrRun."Entry No.");
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Kept, 'kept');
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.AreEqual(2, Finding.Count(), 'both findings kept');
        Finding.SetRange("Action", Finding."Action"::Hold);
        Assert.IsTrue(Finding.FindFirst(), 'held finding kept');
        Assert.AreEqual(EntryNo(SecondInvoiceNo), Finding."Ledger Entry No.", 'the held entry is on the evidence');
        Assert.IsTrue(Finding.Detail.EndsWith('Put on hold: INV4471.'), 'the hold is listed on the evidence');
        Assert.IsTrue(KeptMessage.EndsWith(': 1.'), 'one payment line held');
    end;

    [Test]
    procedure OnlyHoldChangesAnything()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
        FirstLineId: Guid;
        SecondLineId: Guid;
        OtherLineId: Guid;
        NullGuid: Guid;
        JournalBefore: Text;
        VendorBefore: Text;
        KeptMessage: Text;
    begin
        // [GIVEN] the first line set to verify the bank details by phone; the copy, which may only be held, is unticked
        CreateDuplicateRun(GenJournalBatch, FirstInvoiceNo, SecondInvoiceNo, FirstLineId, SecondLineId, OtherLineId);
        MockChatClient.QueueReply(TwoLineReply('Verify bank details by phone', 'Ask vendor to confirm duplicate'), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        TempFinding.SetRange("Finding Key", 'LINE-2');
        TempFinding.FindFirst();
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::Hold, 'the copy stays held');
        TempFinding.ModifyAll(Accepted, false);
        TempFinding.Reset();
        JournalBefore := PaymentRunLibrary.JournalFingerprint(GenJournalBatch, NullGuid);
        VendorBefore := VendorFingerprint(TempFinding);

        // [WHEN] the user keeps it
        KeptMessage := Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] no line and no vendor ledger entry changed
        Assert.AreEqual(JournalBefore, PaymentRunLibrary.JournalFingerprint(GenJournalBatch, NullGuid), 'journal unchanged');
        Assert.AreEqual(VendorBefore, VendorFingerprint(TempFinding), 'vendor entries unchanged');
        Assert.AreEqual('Review saved as payment run evidence. No payment was held.', KeptMessage, 'message');
    end;

    [Test]
    procedure UntickedHoldIsNotKept()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
        FirstLineId: Guid;
        SecondLineId: Guid;
        OtherLineId: Guid;
    begin
        // [GIVEN] both lines held by the model; the user unticks the second
        CreateDuplicateRun(GenJournalBatch, FirstInvoiceNo, SecondInvoiceNo, FirstLineId, SecondLineId, OtherLineId);
        MockChatClient.QueueReply(TwoLineReply('Hold', 'Hold'), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        TempFinding.SetRange("Finding Key", 'LINE-2');
        TempFinding.ModifyAll(Accepted, false);
        TempFinding.Reset();

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] only the ticked line is held; the unticked one stays as it was
        Assert.IsFalse(PaymentRunLibrary.LineExists(FirstLineId), 'ticked line deleted');
        Assert.AreEqual('QRY', PaymentRunLibrary.InvoiceOnHold(FirstInvoiceNo), 'ticked invoice on hold');
        Assert.IsTrue(PaymentRunLibrary.LineExists(SecondLineId), 'unticked line stays');
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(SecondInvoiceNo), 'unticked invoice not on hold');
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.AreEqual(1, Finding.Count(), 'accepted finding only');
    end;

    [Test]
    procedure ChangedLineStopsKeepIt()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
        FirstLineId: Guid;
        SecondLineId: Guid;
        OtherLineId: Guid;
    begin
        // [GIVEN] both lines held, and the second line's amount changed after the check
        CreateDuplicateRun(GenJournalBatch, FirstInvoiceNo, SecondInvoiceNo, FirstLineId, SecondLineId, OtherLineId);
        MockChatClient.QueueReply(TwoLineReply('Hold', 'Hold'), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        PaymentRunLibrary.ChangeLineAmount(SecondLineId, 1000);

        // [WHEN] the user keeps it
        asserterror Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] it is refused and nothing is kept: the first line, already handled, is back and its invoice is not on hold
        Assert.ExpectedError(ChangedLineErr);
        Assert.IsTrue(PaymentRunLibrary.LineExists(FirstLineId), 'first line rolled back');
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(FirstInvoiceNo), 'first hold rolled back');
        Assert.IsTrue(PaymentRunLibrary.LineExists(SecondLineId), 'changed line not deleted');
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(SecondInvoiceNo), 'changed line''s invoice not on hold');
        ExrRun.Get(ExrRun."Entry No.");
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Generated, 'run not kept');
    end;

    [Test]
    procedure LineThatLeftTheJournalStopsKeepIt()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
        FirstLineId: Guid;
        SecondLineId: Guid;
        OtherLineId: Guid;
    begin
        // [GIVEN] the first line held, and then deleted from the journal by someone else
        CreateDuplicateRun(GenJournalBatch, FirstInvoiceNo, SecondInvoiceNo, FirstLineId, SecondLineId, OtherLineId);
        MockChatClient.QueueReply(TwoLineReply('Hold', 'Verify bank details by phone'), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        GenJournalLine.GetBySystemId(FirstLineId);
        GenJournalLine.Delete(true);

        // [WHEN] the user keeps it
        asserterror Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] it is refused and the invoice is not put on hold
        Assert.ExpectedError(ChangedLineErr);
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(FirstInvoiceNo), 'invoice not on hold');
    end;

    [Test]
    procedure InvoiceAlreadyOnHoldKeepsItsCode()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        Findings: JsonArray;
        VendorNo: Code[20];
        InvoiceNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] a line paying an invoice someone put on hold with ABC, and a reply that holds it
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        InvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-8101', -5, 1000);
        PaymentRunLibrary.SetOnHold(InvoiceNo, 'ABC');
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, InvoiceNo);
        Commit();
        Findings.Add(PaymentRunLibrary.FindingReply('LINE-1', 'Someone stopped it.', 'Hold'));
        MockChatClient.QueueReply(PaymentRunLibrary.Reply('Keep the invoice on hold.', Findings), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] the line leaves the journal and the invoice keeps its own hold code
        Assert.IsFalse(PaymentRunLibrary.LineExists(LineId), 'line deleted');
        Assert.AreEqual('ABC', PaymentRunLibrary.InvoiceOnHold(InvoiceNo), 'existing code kept');
    end;

    [Test]
    procedure BlankHoldCodeRefusesAHold()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
        FirstLineId: Guid;
        SecondLineId: Guid;
        OtherLineId: Guid;
    begin
        // [GIVEN] a held line and no Hold Code in the setup
        CreateDuplicateRun(GenJournalBatch, FirstInvoiceNo, SecondInvoiceNo, FirstLineId, SecondLineId, OtherLineId);
        MockChatClient.QueueReply(TwoLineReply('Hold', 'Ask vendor to confirm duplicate'), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        PaymentRunLibrary.SetHoldCode('');

        // [WHEN] the user keeps it
        asserterror Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] it is refused with a clear message, and the line stays
        Assert.ExpectedError('Enter a Hold Code on the Explain and Resolve Setup page before you keep a Hold.');
        Assert.IsTrue(PaymentRunLibrary.LineExists(FirstLineId), 'line stays');
    end;

    [Test]
    procedure DiscardWritesOnlyTheRunRow()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
        FirstLineId: Guid;
        SecondLineId: Guid;
        OtherLineId: Guid;
        NullGuid: Guid;
        JournalBefore: Text;
        VendorBefore: Text;
    begin
        // [GIVEN] a generated payment run that holds both lines
        CreateDuplicateRun(GenJournalBatch, FirstInvoiceNo, SecondInvoiceNo, FirstLineId, SecondLineId, OtherLineId);
        MockChatClient.QueueReply(TwoLineReply('Hold', 'Hold'), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        JournalBefore := PaymentRunLibrary.JournalFingerprint(GenJournalBatch, NullGuid);
        VendorBefore := VendorFingerprint(TempFinding);

        // [WHEN] the user discards it
        Engine.Discard(ExrRun);

        // [THEN] only the run row changes, to Discarded
        ExrRun.Get(ExrRun."Entry No.");
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Discarded, 'discarded');
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.IsTrue(Finding.IsEmpty(), 'no findings saved');
        Assert.AreEqual(JournalBefore, PaymentRunLibrary.JournalFingerprint(GenJournalBatch, NullGuid), 'journal unchanged');
        Assert.AreEqual(VendorBefore, VendorFingerprint(TempFinding), 'vendor entries unchanged');
    end;

    [Test]
    procedure BatchPanelShowsTheLatestKeptCheck()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        FirstRun: Record "EXR Run";
        SecondRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        Findings: JsonArray;
        RunFactBox: TestPage "EXR Run FactBox";
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
        FirstLineId: Guid;
        SecondLineId: Guid;
        OtherLineId: Guid;
    begin
        // [GIVEN] two kept checks of the same batch, the second with another note
        CreateDuplicateRun(GenJournalBatch, FirstInvoiceNo, SecondInvoiceNo, FirstLineId, SecondLineId, OtherLineId);
        MockChatClient.QueueReply(TwoLineReply('Ask vendor to confirm duplicate', 'Ask vendor to confirm duplicate'), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, FirstRun);
        Engine.Generate(FirstRun, TempFinding);
        Engine.Keep(FirstRun, TempFinding, '', '');
        Commit();
        Findings.Add(PaymentRunLibrary.FindingReply('LINE-1', 'Asked.', 'Ask vendor to confirm duplicate'));
        MockChatClient.QueueReply(PaymentRunLibrary.Reply(LatestNoteTok, Findings), 100, 10, 100);
        PaymentRunLibrary.NewRun(GenJournalBatch, SecondRun);
        Engine.Generate(SecondRun, TempFinding);
        Engine.Keep(SecondRun, TempFinding, '', '');

        // [WHEN] the panel opens with the Payment Journal's link
        RunFactBox.OpenView();
        RunFactBox.Filter.SetFilter("Journal Template Name", GenJournalBatch."Journal Template Name");
        RunFactBox.Filter.SetFilter("Journal Batch Name", GenJournalBatch.Name);

        // [THEN] it shows the note of the second check
        Assert.AreEqual(LatestNoteTok, RunFactBox.Summary.Value(), 'latest check in the panel');
        RunFactBox.Close();
    end;

    // A vendor with its usual payments, a bank account added today and INV-4471 and INV4471 for 1,280, one line each
    // (LINE-1 DUPLICATE+BANK, LINE-2 the copy, DUP_COPY+BANK), plus a usual payment to another vendor with no signal. Committed, ready to generate.
    local procedure CreateDuplicateRun(var GenJournalBatch: Record "Gen. Journal Batch"; var FirstInvoiceNo: Code[20]; var SecondInvoiceNo: Code[20]; var FirstLineId: Guid; var SecondLineId: Guid; var OtherLineId: Guid)
    var
        VendorNo: Code[20];
        OtherVendorNo: Code[20];
    begin
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.AddBankAccount(VendorNo);
        FirstInvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-4471', -10, 1280);
        SecondInvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -10, 1280);
        OtherVendorNo := CreateUsualVendor();
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        FirstLineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, FirstInvoiceNo);
        SecondLineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, SecondInvoiceNo);
        OtherLineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, OtherVendorNo, PaymentRunLibrary.PostInvoice(OtherVendorNo, 'WW-2211', -15, 980));
        Commit();
    end;

    local procedure CreateUsualVendor() VendorNo: Code[20]
    begin
        VendorNo := PaymentRunLibrary.CreateVendor(VendorNameTok);
        PaymentRunLibrary.PostUsualHistory(VendorNo);
    end;

    local procedure TwoLineReply(FirstAction: Text; SecondAction: Text): Text
    var
        Findings: JsonArray;
    begin
        Findings.Add(PaymentRunLibrary.FindingReply('LINE-1', 'Possibly the same invoice.', FirstAction));
        Findings.Add(PaymentRunLibrary.FindingReply('LINE-2', 'Possibly the same invoice.', SecondAction));
        exit(PaymentRunLibrary.Reply('Check the two Proseware payments.', Findings));
    end;

    local procedure VendorFingerprint(var TempFinding: Record "EXR Finding" temporary): Text
    begin
        TempFinding.Reset();
        TempFinding.FindFirst();
        exit(PaymentRunLibrary.VendorFingerprint(TempFinding."Account No."));
    end;

    local procedure EntryNo(InvoiceNo: Code[20]): Integer
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        VendorLedgerEntry.SetRange("Document No.", InvoiceNo);
        VendorLedgerEntry.SetRange("Document Type", VendorLedgerEntry."Document Type"::Invoice);
        VendorLedgerEntry.FindFirst();
        exit(VendorLedgerEntry."Entry No.");
    end;
}
