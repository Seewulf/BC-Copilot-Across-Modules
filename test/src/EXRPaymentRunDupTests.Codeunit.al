namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Finance.GeneralLedger.Journal;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// Check payment run duplicates, without the AI service: the copy and the first invoice, matching digits, the window,
// a line that pays both copies, a copy already cancelled or paid, and what the model is told about the order and the run.
codeunit 58291 "EXR Payment Run Dup. Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        PaymentRunLibrary: Codeunit "EXR Payment Run Library";
        VendorNameTok: Label 'Proseware Office Supplies', Locked = true;
        MatchFactTok: Label 'how the vendor invoice numbers match, as a full sentence', Locked = true;
        GapFactTok: Label 'when the two invoices were posted, as a phrase', Locked = true;
        StatusFactTok: Label 'whether the possible duplicate is still open, as a full sentence', Locked = true;
        OrderFactTok: Label 'which of the two invoices was entered first, as a full sentence', Locked = true;
        RunFactTok: Label 'whether the possible duplicate is also paid in this run, as a full sentence', Locked = true;
        EnteredLaterTok: Label 'This invoice was entered after the possible duplicate', Locked = true;
        EnteredFirstTok: Label 'This invoice was entered before the possible duplicate', Locked = true;
        NotInRunTok: Label 'The possible duplicate is not paid in this payment run', Locked = true;
        ClosedTok: Label 'The possible duplicate is already closed, so it was paid or settled', Locked = true;

    [Test]
    procedure SameNumberWrittenDifferentlyIsAHighDuplicate()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        FirstLineId: Guid;
        LineId: Guid;
    begin
        // [GIVEN] a vendor with its usual payments and two open invoices INV-4471 and INV4471 for the same amount on the same day,
        // both in the payment run
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        FirstLineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'INV-4471', -10, 1280));
        LineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -10, 1280));

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] the line paying INV4471, entered later, is the High copy that defaults to Hold
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'finding for the line');
        Assert.AreEqual('DUP_COPY', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::High, 'severity');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::Hold, 'default action');
        Assert.AreEqual(1280, TempFinding."Amount (LCY)", 'payment amount');
        Assert.AreEqual('The vendor invoice numbers are the same once spaces and symbols are removed', ScenarioLibrary.FactValue(TempFinding."Finding Key", MatchFactTok), 'match');
        Assert.AreEqual('on the same day', ScenarioLibrary.FactValue(TempFinding."Finding Key", GapFactTok), 'posted the same day');
        Assert.AreEqual('The possible duplicate is still open', ScenarioLibrary.FactValue(TempFinding."Finding Key", StatusFactTok), 'still open');
        Assert.AreEqual(EnteredLaterTok, ScenarioLibrary.FactValue(TempFinding."Finding Key", OrderFactTok), 'entered later');
        Assert.AreEqual('Another line of this payment run pays the possible duplicate', ScenarioLibrary.FactValue(TempFinding."Finding Key", RunFactTok), 'twin in the run');
        Assert.IsTrue(TempFinding.Detail.Contains('INV-4471'), 'the other invoice is named');

        // [THEN] the line paying INV-4471, entered first, is flagged too but stays in the journal until the vendor confirms
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, FirstLineId), 'finding for the first line');
        Assert.AreEqual('DUPLICATE', TempFinding."Finding Type", 'type of the first line');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Ask vendor to confirm duplicate", 'first line default action');
        Assert.AreEqual(EnteredFirstTok, ScenarioLibrary.FactValue(TempFinding."Finding Key", OrderFactTok), 'entered first');
    end;

    [Test]
    procedure MatchingDigitsAreANearDuplicate()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        PaidInvoiceNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] INV4471, already paid, and an open 4471/A for the same amount three days later
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaidInvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -13, 1280);
        PaymentRunLibrary.PostPayment(VendorNo, -11, 1280, PaidInvoiceNo);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, '4471/A', -10, 1280));

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] only the digits match, so it is Medium and the model judges it: the vendor is asked, even though the other was paid
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'finding for the line');
        Assert.AreEqual('NEAR_DUP', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::Medium, 'severity');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Ask vendor to confirm duplicate", 'default action');
        Assert.AreEqual('Only the digits of the vendor invoice numbers match', ScenarioLibrary.FactValue(TempFinding."Finding Key", MatchFactTok), 'match');
        Assert.AreEqual('3 days apart', ScenarioLibrary.FactValue(TempFinding."Finding Key", GapFactTok), 'gap');
        Assert.AreEqual(ClosedTok, ScenarioLibrary.FactValue(TempFinding."Finding Key", StatusFactTok), 'already paid');
        Assert.AreEqual(NotInRunTok, ScenarioLibrary.FactValue(TempFinding."Finding Key", RunFactTok), 'twin not in the run');
    end;

    [Test]
    procedure DuplicateWindowEdges()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
    begin
        // [GIVEN] INV-5001 and INV5001 for the same amount, posted 20 days apart
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.PostInvoice(VendorNo, 'INV-5001', -40, 1500);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'INV5001', -20, 1500));
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);

        // [WHEN] the window is 20 days [THEN] the pair is flagged
        ExrRun."Duplicate Window Days" := 20;
        PaymentRunLibrary.FindSignals(ExrRun, TempFinding);
        Assert.IsTrue(PaymentRunLibrary.GetFinding(TempFinding, VendorNo), 'inside a 20-day window');
        Assert.AreEqual('20 days apart', ScenarioLibrary.FactValue(TempFinding."Finding Key", GapFactTok), 'gap');

        // [WHEN] the window is 19 days, or 0 [THEN] it is not
        ExrRun."Duplicate Window Days" := 19;
        PaymentRunLibrary.FindSignals(ExrRun, TempFinding);
        Assert.IsFalse(PaymentRunLibrary.GetFinding(TempFinding, VendorNo), 'outside a 19-day window');
        ExrRun."Duplicate Window Days" := 0;
        PaymentRunLibrary.FindSignals(ExrRun, TempFinding);
        Assert.IsFalse(PaymentRunLibrary.GetFinding(TempFinding, VendorNo), '0 turns the check off');
    end;

    [Test]
    procedure OtherNumbersOrAmountsAreNotDuplicates()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
    begin
        // [GIVEN] INV-6001 and INV6002 for the same amount, INV6003 and INV 6003 for different amounts, and A-12 and B12
        // (fewer than 3 digits) for the same amount, on the same day
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.PostInvoice(VendorNo, 'INV-6001', -10, 1500);
        PaymentRunLibrary.PostInvoice(VendorNo, 'INV6003', -10, 1600);
        PaymentRunLibrary.PostInvoice(VendorNo, 'A-12', -10, 1700);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'INV6002', -10, 1500));
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'INV 6003', -10, 1500));
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'B12', -10, 1700));

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] no line is flagged
        TempFinding.Reset();
        Assert.IsTrue(TempFinding.IsEmpty(), 'no duplicates');
    end;

    [Test]
    procedure LinePayingBothCopiesHoldsTheCopy()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        InvoiceNos: List of [Code[20]];
        VendorNo: Code[20];
        CopyNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] one summarised line that pays both INV-4471 and INV4471 (2,560, more than twice the usual 1,050)
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        InvoiceNos.Add(PaymentRunLibrary.PostInvoice(VendorNo, 'INV-4471', -10, 1280));
        CopyNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -10, 1280);
        InvoiceNos.Add(CopyNo);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddSummarisedPaymentLine(GenJournalBatch, VendorNo, InvoiceNos);

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] the line is about INV4471, the copy, and defaults to Hold; a line of several invoices is not an unusual amount
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'finding for the line');
        Assert.AreEqual('DUP_COPY', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::Hold, 'default action');
        Assert.IsTrue(TempFinding.Subject.EndsWith('INV4471'), 'about the copy');
        Assert.AreEqual(PaymentRunLibrary.EntryNo(CopyNo), TempFinding."Ledger Entry No.", 'the copy is the entry to hold');
        Assert.AreEqual(2, TempFinding."Applied Entries", 'both entries recorded for the check before writing');
        Assert.AreEqual('This payment line pays both invoices', ScenarioLibrary.FactValue(TempFinding."Finding Key", RunFactTok), 'pays both');
        Assert.AreEqual(EnteredLaterTok, ScenarioLibrary.FactValue(TempFinding."Finding Key", OrderFactTok), 'the copy was entered later');
    end;

    [Test]
    procedure CopyCancelledWithACreditMemoIsNoDuplicate()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        CancelledNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] INV4471, cancelled with a credit memo applied to it, and the genuine INV-4471 in the payment run
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        CancelledNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -12, 1280);
        PaymentRunLibrary.PostCreditMemo(VendorNo, -11, 1280, CancelledNo);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'INV-4471', -10, 1280));

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] the cancelled copy is not a duplicate, so the genuine invoice is not held
        Assert.IsFalse(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'no finding');
    end;

    [Test]
    procedure PaidCopyIsHeldWhicheverCameFirst()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        LaterNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] INV-4471 entered first and still open, and INV4471 entered later and already paid by hand
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'INV-4471', -12, 1280));
        LaterNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -10, 1280);
        PaymentRunLibrary.PostPayment(VendorNo, -9, 1280, LaterNo);

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] the invoice was probably paid once already, so it is held, and the model is told the true order
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'finding for the line');
        Assert.AreEqual('DUP_COPY', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::Hold, 'default action');
        Assert.AreEqual(ClosedTok, ScenarioLibrary.FactValue(TempFinding."Finding Key", StatusFactTok), 'already paid');
        Assert.AreEqual(EnteredFirstTok, ScenarioLibrary.FactValue(TempFinding."Finding Key", OrderFactTok), 'entered first');
        Assert.AreEqual(NotInRunTok, ScenarioLibrary.FactValue(TempFinding."Finding Key", RunFactTok), 'twin not in the run');
    end;

    local procedure CreateUsualVendor() VendorNo: Code[20]
    begin
        VendorNo := PaymentRunLibrary.CreateVendor(VendorNameTok);
        PaymentRunLibrary.PostUsualHistory(VendorNo);
    end;

    local procedure FindSignals(GenJournalBatch: Record "Gen. Journal Batch"; var TempFinding: Record "EXR Finding" temporary)
    var
        ExrRun: Record "EXR Run";
    begin
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        PaymentRunLibrary.FindSignals(ExrRun, TempFinding);
    end;
}
