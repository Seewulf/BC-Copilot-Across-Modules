namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Purchases.Payables;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Customer;
using PrabinBhusal.ExplainResolve;
using System.Diagnostics;
using System.Security.AccessControl;
using System.TestLibraries.Utilities;

// What a kept Hold puts on hold: every invoice of a line for a line-level signal, only the copy for a duplicate, never a
// credit memo. The checks before writing (exported lines, invoices added after the check) and the permissions Keep it needs.
codeunit 58292 "EXR Payment Run Hold Tests"
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
        IssuedLineErr: Label 'was already exported to a payment file or its check was printed, so nothing was kept', Locked = true;

    [Test]
    procedure BankChangeHoldsEveryInvoiceButNoCreditMemo()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        DocumentNos: List of [Code[20]];
        DocumentNo: Code[20];
        CreditMemoNo: Code[20];
        VendorNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] a vendor whose bank account was added today, and one summarised line for two invoices and an open credit memo
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.AddBankAccount(VendorNo);
        DocumentNos.Add(PaymentRunLibrary.PostInvoice(VendorNo, 'INV-8201', -8, 700));
        DocumentNos.Add(PaymentRunLibrary.PostInvoice(VendorNo, 'INV-8202', -6, 400));
        CreditMemoNo := PaymentRunLibrary.PostCreditMemo(VendorNo, -7, 100, '');
        DocumentNos.Add(CreditMemoNo);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddSummarisedPaymentLine(GenJournalBatch, VendorNo, DocumentNos);
        Commit();
        QueueHold(1);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'one finding for the summarised line');
        Assert.AreEqual('BANK', TempFinding."Finding Type", 'a bank change only');
        Assert.AreEqual(1000, TempFinding."Amount (LCY)", 'the line pays both invoices less the credit memo');

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] the line is gone, both invoices are on hold and the credit memo is not; none is marked for this payment any more
        Assert.IsFalse(PaymentRunLibrary.LineExists(LineId), 'line deleted');
        foreach DocumentNo in DocumentNos do begin
            if DocumentNo = CreditMemoNo then
                Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(DocumentNo), 'credit memo not on hold')
            else
                Assert.AreEqual('QRY', PaymentRunLibrary.InvoiceOnHold(DocumentNo), 'invoice on hold');
            VendorLedgerEntry.Get(PaymentRunLibrary.EntryNo(DocumentNo));
            Assert.AreEqual('', VendorLedgerEntry."Applies-to ID", 'application cleared by the line''s delete');
        end;
        // [THEN] the evidence lists what was put on hold
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Finding.FindFirst();
        Assert.IsTrue(Finding.Detail.EndsWith('Put on hold: INV-8201, INV-8202.'), 'held invoices on the evidence');
    end;

    [Test]
    procedure DuplicateOnASummarisedLineHoldsOnlyTheCopy()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        InvoiceNos: List of [Code[20]];
        InvoiceNo: Code[20];
        FirstNo: Code[20];
        CopyNo: Code[20];
        OtherNo: Code[20];
        VendorNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] one summarised line that pays INV-4471, its copy INV4471 and another invoice
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        FirstNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-4471', -10, 1280);
        CopyNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -10, 1280);
        OtherNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-5555', -10, 500);
        InvoiceNos.Add(FirstNo);
        InvoiceNos.Add(CopyNo);
        InvoiceNos.Add(OtherNo);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddSummarisedPaymentLine(GenJournalBatch, VendorNo, InvoiceNos);
        Commit();
        QueueHold(1);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'finding for the line');
        Assert.AreEqual('DUP_COPY', TempFinding."Finding Type", 'type');

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] the line is gone and only the copy is on hold: the next Suggest Vendor Payments proposes the other two again
        Assert.IsFalse(PaymentRunLibrary.LineExists(LineId), 'line deleted');
        Assert.AreEqual('QRY', PaymentRunLibrary.InvoiceOnHold(CopyNo), 'copy on hold');
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(FirstNo), 'first invoice not on hold');
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(OtherNo), 'other invoice not on hold');
        foreach InvoiceNo in InvoiceNos do begin
            VendorLedgerEntry.Get(PaymentRunLibrary.EntryNo(InvoiceNo));
            Assert.AreEqual('', VendorLedgerEntry."Applies-to ID", 'no longer marked for this payment');
        end;
    end;

    [Test]
    procedure ExportedLineStopsKeepIt()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        CopyNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] the line for the copy INV4471, already exported to a payment file
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.PostInvoice(VendorNo, 'INV-4471', -10, 1280);
        CopyNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -10, 1280);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, CopyNo);
        PaymentRunLibrary.MarkExported(LineId);
        Commit();
        QueueHold(1);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'finding for the line');
        Assert.IsTrue(TempFinding.Detail.Contains('Already exported'), 'the approver is told');
        // asserterror rolls back to here, so the run must outlive the refused Keep
        Commit();

        // [WHEN] the user keeps the Hold
        asserterror Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] it is refused with a clear message: the line stays, the invoice is not put on hold and nothing is kept
        Assert.ExpectedError(IssuedLineErr);
        Assert.IsTrue(PaymentRunLibrary.LineExists(LineId), 'line stays');
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(CopyNo), 'invoice not on hold');
        ExrRun.Get(ExrRun."Entry No.");
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Generated, 'run not kept');
    end;

    [Test]
    procedure InvoiceAddedAfterTheCheckStopsKeepIt()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        InvoiceNos: List of [Code[20]];
        InvoiceNo: Code[20];
        AddedNo: Code[20];
        VendorNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] a summarised line for two invoices of a vendor whose bank account was added today, checked and held
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.AddBankAccount(VendorNo);
        InvoiceNos.Add(PaymentRunLibrary.PostInvoice(VendorNo, 'INV-8301', -8, 300));
        InvoiceNos.Add(PaymentRunLibrary.PostInvoice(VendorNo, 'INV-8302', -6, 400));
        AddedNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-8303', -4, 200);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddSummarisedPaymentLine(GenJournalBatch, VendorNo, InvoiceNos);
        Commit();
        QueueHold(1);
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        // [GIVEN] after the check, one more invoice is marked for the line; its amount stays as it was
        PaymentRunLibrary.AddToSummarisedLine(LineId, AddedNo);

        // [WHEN] the user keeps it
        asserterror Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] it is refused, so no invoice that was never reviewed is put on hold
        Assert.ExpectedError(ChangedLineErr);
        Assert.IsTrue(PaymentRunLibrary.LineExists(LineId), 'line stays');
        foreach InvoiceNo in InvoiceNos do
            Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(InvoiceNo), 'invoice not on hold');
        Assert.AreEqual('', PaymentRunLibrary.InvoiceOnHold(AddedNo), 'added invoice not on hold');
    end;

    [Test]
    procedure UserSetCoversTheKeepWrites()
    var
        ExpandedPermission: Record "Expanded Permission";
    begin
        // [GIVEN] the Explain and Resolve - User permission set
        // [WHEN] its expanded permissions are read
        // [THEN] Keep it can delete the line and Vend. Entry-Edit can set On Hold, both through indirect permissions
        // read from the permission set itself, so the test needs no Permissions Mock app in the sandbox
        Assert.IsTrue(HasPermission(Database::"Gen. Journal Line", ExpandedPermission.FieldNo("Delete Permission")), 'delete journal line');
        Assert.IsTrue(HasPermission(Database::"Vendor Ledger Entry", ExpandedPermission.FieldNo("Modify Permission")), 'modify vendor ledger entry');
        Assert.IsTrue(HasPermission(Database::"Detailed Vendor Ledg. Entry", ExpandedPermission.FieldNo("Modify Permission")), 'modify detailed vendor entry');
        Assert.IsTrue(HasPermission(Database::"Change Log Entry", ExpandedPermission.FieldNo("Insert Permission")), 'insert change log entry');
        Assert.IsTrue(HasPermission(Database::"Vendor Bank Account", ExpandedPermission.FieldNo("Read Permission")), 'read bank account change time');
    end;

    local procedure HasPermission(TableNo: Integer; PermissionFieldNo: Integer): Boolean
    var
        ExpandedPermission: Record "Expanded Permission";
        RecRef: RecordRef;
    begin
        ExpandedPermission.SetRange("Role ID", 'EXR USER');
        ExpandedPermission.SetRange("Object Type", ExpandedPermission."Object Type"::"Table Data");
        ExpandedPermission.SetRange("Object ID", TableNo);
        if not ExpandedPermission.FindFirst() then
            exit(false);
        RecRef.GetTable(ExpandedPermission);
        // the option is blank when the set grants nothing; Yes or Indirect both let the app's own code write
        exit(Format(RecRef.Field(PermissionFieldNo).Value()) <> '');
    end;

    local procedure CreateUsualVendor() VendorNo: Code[20]
    begin
        VendorNo := PaymentRunLibrary.CreateVendor(VendorNameTok);
        PaymentRunLibrary.PostUsualHistory(VendorNo);
    end;

    // A reply that holds LINE-1 up to LINE-n.
    local procedure QueueHold(FindingCount: Integer)
    var
        Findings: JsonArray;
        Index: Integer;
    begin
        for Index := 1 to FindingCount do
            Findings.Add(PaymentRunLibrary.FindingReply('LINE-' + Format(Index), 'Hold this payment.', 'Hold'));
        MockChatClient.QueueReply(PaymentRunLibrary.Reply('Hold these payments.', Findings), 100, 10, 100);
    end;
}
