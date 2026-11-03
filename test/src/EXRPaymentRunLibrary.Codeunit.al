namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Bank.Ledger;
using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Finance.GeneralLedger.Ledger;
using Microsoft.Purchases.Payables;
using Microsoft.Purchases.Vendor;
using PrabinBhusal.ExplainResolve;

// Payables scenarios for Check payment run. Vendor invoices and payments are posted as vendor journal lines (Gen. Jnl.-Post Line),
// which gives the same vendor ledger entries as posted purchase invoices, but no posted purchase invoice document.
// The payment journal lines are created directly, as Suggest Vendor Payments would create them, one line per invoice.
codeunit 58287 "EXR Payment Run Library"
{
    var
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        CollectionsLibrary: Codeunit "EXR Collections Library";
        InvoicePrefixTok: Label 'EXR-PI', Locked = true;
        CreditMemoPrefixTok: Label 'EXR-PC', Locked = true;
        PaymentPrefixTok: Label 'EXR-PP', Locked = true;
        JournalPaymentPrefixTok: Label 'EXR-JP', Locked = true;
        BatchPrefixTok: Label 'EXR-PR', Locked = true;
        PaymentTemplateTok: Label 'EXR-PAY', Locked = true;
        FirstCounterTok: Label '0001', Locked = true;
        FirstBatchCounterTok: Label '001', Locked = true;
        StartsWithTok: Label '%1*', Locked = true;
        HistoryNoTok: Label 'H-%1', Locked = true;
        BatchDescriptionTok: Label 'Payment run demo', Locked = true;
        BankAccountCodeTok: Label 'MAIN', Locked = true;
        DuplicateVendorTok: Label 'Proseware Office Supplies', Locked = true;
        NormalVendorTok: Label 'Wide World Paper Co.', Locked = true;
        FirstTimeVendorTok: Label 'Lucerne Print Studio', Locked = true;
        DemoInvoiceTok: Label 'INV-4471', Locked = true;
        DemoDuplicateTok: Label 'INV4471', Locked = true;
        DemoNormalInvoiceTok: Label 'WW-2211', Locked = true;
        DemoFirstInvoiceTok: Label 'LPS-0001', Locked = true;
#pragma warning disable AA0240
        // the published example IBAN and made-up bank details, never a real account
        IbanTok: Label 'GB29NWBK60161331926819', Locked = true;
        BankAccountNoTok: Label '31926819', Locked = true;
        SwiftTok: Label 'NWBKGB2L', Locked = true;
        BankNameTok: Label 'Northwind Savings Bank', Locked = true;
#pragma warning restore AA0240
        LedgerFingerprintTok: Label 'G/L %1, vendor %2, vendor details %3, bank %4', Locked = true;
        LineFingerprintTok: Label '%1|%2|%3|%4|%5|%6;', Locked = true;

    // Test setup: the shared one, plus fixed payment run settings.
    procedure Initialise()
    var
        Setup: Record "EXR Setup";
    begin
        ScenarioLibrary.InitialiseForTest();
        Setup.Get();
        Setup."Duplicate Window Days" := 60;
        Setup."Bank Change Window Days" := 30;
        Setup."Unusual Amount %" := 100;
        Setup.Modify();
    end;

    procedure SetUnusualAmountPct(UnusualAmountPct: Decimal)
    var
        Setup: Record "EXR Setup";
    begin
        Setup.Get();
        Setup."Unusual Amount %" := UnusualAmountPct;
        Setup.Modify();
    end;

    procedure SetHoldCode(HoldCode: Code[3])
    var
        Setup: Record "EXR Setup";
    begin
        Setup.Get();
        Setup."Hold Code" := HoldCode;
        Setup.Modify();
    end;

    procedure CreateVendor(Name: Text[100]) VendorNo: Code[20]
    var
        Vendor: Record Vendor;
    begin
        VendorNo := ScenarioLibrary.CreateVendor();
        Vendor.Get(VendorNo);
        Vendor.Name := Name;
        Vendor.Modify();
    end;

    // Days are relative to the work date. Returns the posted document number; the entry has the vendor invoice number.
    procedure PostInvoice(VendorNo: Code[20]; VendorInvoiceNo: Code[35]; PostingDays: Integer; Amount: Decimal) DocumentNo: Code[20]
    begin
        DocumentNo := NextDocumentNo(InvoicePrefixTok);
        CollectionsLibrary.PostVendorLine(Enum::"Gen. Journal Document Type"::Invoice, DocumentNo, VendorInvoiceNo, VendorNo, WorkDate() + PostingDays, -Amount, '');
    end;

    // A credit memo applied to the invoice, as Cancel or Create Corrective Credit Memo does; without an invoice number it stays open.
    procedure PostCreditMemo(VendorNo: Code[20]; PostingDays: Integer; Amount: Decimal; InvoiceNo: Code[20]) DocumentNo: Code[20]
    begin
        DocumentNo := NextDocumentNo(CreditMemoPrefixTok);
        CollectionsLibrary.PostVendorLine(Enum::"Gen. Journal Document Type"::"Credit Memo", DocumentNo, '', VendorNo, WorkDate() + PostingDays, Amount, InvoiceNo);
    end;

    // A payment applied to the invoice; without an invoice number it stays open, not applied.
    procedure PostPayment(VendorNo: Code[20]; PostingDays: Integer; Amount: Decimal; InvoiceNo: Code[20])
    begin
        CollectionsLibrary.PostVendorLine(Enum::"Gen. Journal Document Type"::Payment, NextDocumentNo(PaymentPrefixTok), '', VendorNo, WorkDate() + PostingDays, Amount, InvoiceNo);
    end;

    // Paid invoices in the last 12 months, one per amount, so the vendor has a payment pattern.
    procedure PostPaymentHistory(VendorNo: Code[20]; Amounts: List of [Decimal])
    var
        Amount: Decimal;
        Index: Integer;
        InvoiceNo: Code[20];
    begin
        foreach Amount in Amounts do begin
            Index += 1;
            InvoiceNo := PostInvoice(VendorNo, CopyStr(StrSubstNo(HistoryNoTok, NextDocumentNo(InvoicePrefixTok)), 1, 35), -330 + Index * 60, Amount);
            PostPayment(VendorNo, -320 + Index * 60, Amount, InvoiceNo);
        end;
    end;

    // Four paid invoices of 900, 1,000, 1,100 and 1,200: the median payment is 1,050.
    procedure PostUsualHistory(VendorNo: Code[20])
    var
        Amounts: List of [Decimal];
    begin
        Amounts.Add(1000);
        Amounts.Add(1200);
        Amounts.Add(900);
        Amounts.Add(1100);
        PostPaymentHistory(VendorNo, Amounts);
    end;

    // Test data only: the app itself sets On Hold only through Vend. Entry-Edit on Keep it.
    procedure SetOnHold(InvoiceNo: Code[20]; HoldCode: Code[3])
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        FindEntry(InvoiceNo, VendorLedgerEntry);
        VendorLedgerEntry."On Hold" := HoldCode;
        VendorLedgerEntry.Modify();
    end;

    // A bank account added now, so its SystemModifiedAt is today. It carries example bank details that must never be sent.
    procedure AddBankAccount(VendorNo: Code[20])
    var
        VendorBankAccount: Record "Vendor Bank Account";
    begin
        VendorBankAccount.Init();
        VendorBankAccount."Vendor No." := VendorNo;
        VendorBankAccount.Code := BankAccountCodeTok;
        VendorBankAccount.Name := BankNameTok;
        VendorBankAccount.IBAN := IbanTok;
        VendorBankAccount."Bank Account No." := BankAccountNoTok;
        VendorBankAccount."SWIFT Code" := SwiftTok;
        VendorBankAccount.Insert();
    end;

    procedure BankAccountCode(): Code[20]
    begin
        exit(BankAccountCodeTok);
    end;

    procedure Iban(): Text
    begin
        exit(IbanTok);
    end;

    procedure BankAccountNo(): Text
    begin
        exit(BankAccountNoTok);
    end;

    procedure Swift(): Text
    begin
        exit(SwiftTok);
    end;

    procedure BankName(): Text
    begin
        exit(BankNameTok);
    end;

    // A new batch of a payments template, with the balancing account of an existing batch of that template when there is one.
    procedure CreatePaymentBatch(var GenJournalBatch: Record "Gen. Journal Batch")
    var
        GenJournalTemplate: Record "Gen. Journal Template";
        CopyFromBatch: Record "Gen. Journal Batch";
    begin
        GenJournalTemplate.SetRange(Type, GenJournalTemplate.Type::Payments);
        GenJournalTemplate.SetRange(Recurring, false);
        if not GenJournalTemplate.FindFirst() then begin
            GenJournalTemplate.Init();
            GenJournalTemplate.Name := PaymentTemplateTok;
            GenJournalTemplate.Validate(Type, GenJournalTemplate.Type::Payments);
            GenJournalTemplate.Insert(true);
        end;
        GenJournalBatch.Init();
        GenJournalBatch."Journal Template Name" := GenJournalTemplate.Name;
        GenJournalBatch.Name := NextBatchName(GenJournalTemplate.Name);
        GenJournalBatch.Description := BatchDescriptionTok;
        CopyFromBatch.SetRange("Journal Template Name", GenJournalTemplate.Name);
        CopyFromBatch.SetFilter("Bal. Account No.", '<>%1', '');
        if CopyFromBatch.FindFirst() then begin
            GenJournalBatch."Bal. Account Type" := CopyFromBatch."Bal. Account Type";
            GenJournalBatch."Bal. Account No." := CopyFromBatch."Bal. Account No.";
        end;
        GenJournalBatch.Insert(true);
    end;

    // A payment line for one invoice, as Suggest Vendor Payments makes it: the remaining amount, applied to the invoice.
    procedure AddPaymentLine(GenJournalBatch: Record "Gen. Journal Batch"; VendorNo: Code[20]; InvoiceNo: Code[20]) LineSystemId: Guid
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        FindEntry(InvoiceNo, VendorLedgerEntry);
        VendorLedgerEntry.CalcFields("Remaining Amount");
        InitPaymentLine(GenJournalBatch, VendorNo, -VendorLedgerEntry."Remaining Amount", GenJournalLine);
        GenJournalLine."Applies-to Doc. Type" := GenJournalLine."Applies-to Doc. Type"::Invoice;
        GenJournalLine."Applies-to Doc. No." := InvoiceNo;
        GenJournalLine.Modify(true);
        exit(GenJournalLine.SystemId);
    end;

    // One line that pays several invoices, and any credit memos given, through an Applies-to ID, as Suggest Vendor Payments
    // does with Summarize per Vendor.
    procedure AddSummarisedPaymentLine(GenJournalBatch: Record "Gen. Journal Batch"; VendorNo: Code[20]; InvoiceNos: List of [Code[20]]) LineSystemId: Guid
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        GenJournalLine: Record "Gen. Journal Line";
        InvoiceNo: Code[20];
        Total: Decimal;
    begin
        InitPaymentLine(GenJournalBatch, VendorNo, 0, GenJournalLine);
        foreach InvoiceNo in InvoiceNos do begin
            FindEntry(InvoiceNo, VendorLedgerEntry);
            VendorLedgerEntry.CalcFields("Remaining Amount");
            Total -= VendorLedgerEntry."Remaining Amount";
            VendorLedgerEntry."Applies-to ID" := GenJournalLine."Document No.";
            VendorLedgerEntry.Modify();
        end;
        GenJournalLine.Validate(Amount, Total);
        GenJournalLine."Applies-to ID" := GenJournalLine."Document No.";
        GenJournalLine.Modify(true);
        exit(GenJournalLine.SystemId);
    end;

    // Someone marks one more invoice for a summarised line after the check; the line amount stays as it was.
    procedure AddToSummarisedLine(LineSystemId: Guid; InvoiceNo: Code[20])
    var
        GenJournalLine: Record "Gen. Journal Line";
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        GenJournalLine.GetBySystemId(LineSystemId);
        FindEntry(InvoiceNo, VendorLedgerEntry);
        VendorLedgerEntry."Applies-to ID" := GenJournalLine."Applies-to ID";
        VendorLedgerEntry.Modify();
    end;

    // As Export Payments to File leaves the line.
    procedure MarkExported(LineSystemId: Guid)
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.GetBySystemId(LineSystemId);
        GenJournalLine."Exported to Payment File" := true;
        GenJournalLine.Modify();
    end;

    // A vendor payment keyed the other way round: a G/L line with the vendor as balancing account. Test data only.
    procedure AddBalancingVendorLine(GenJournalBatch: Record "Gen. Journal Batch"; VendorNo: Code[20]; Amount: Decimal)
    var
        LastLine: Record "Gen. Journal Line";
        GenJournalLine: Record "Gen. Journal Line";
    begin
        LastLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        LastLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        if not LastLine.FindLast() then
            LastLine."Line No." := 0;
        GenJournalLine.Init();
        GenJournalLine."Journal Template Name" := GenJournalBatch."Journal Template Name";
        GenJournalLine."Journal Batch Name" := GenJournalBatch.Name;
        GenJournalLine."Line No." := LastLine."Line No." + 10000;
        GenJournalLine."Posting Date" := WorkDate();
        GenJournalLine."Document Type" := GenJournalLine."Document Type"::Payment;
        GenJournalLine."Document No." := NextJournalDocumentNo();
        GenJournalLine."Account Type" := GenJournalLine."Account Type"::"G/L Account";
        GenJournalLine."Bal. Account Type" := GenJournalLine."Bal. Account Type"::Vendor;
        GenJournalLine."Bal. Account No." := VendorNo;
        GenJournalLine.Amount := -Amount;
        GenJournalLine."Amount (LCY)" := -Amount;
        GenJournalLine.Insert();
    end;

    procedure EntryNo(DocumentNo: Code[20]): Integer
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        FindEntry(DocumentNo, VendorLedgerEntry);
        exit(VendorLedgerEntry."Entry No.");
    end;

    // The demo for the controller who approves the payment run, as of the work date (W):
    // Proseware has two open invoices INV-4471 and INV4471 for 1,280 posted on W-10 and a bank account added today.
    // Wide World is paid about 1,050 a month and has one open invoice for 980. Lucerne has never been paid.
    procedure CreateDemoScenario(var GenJournalBatch: Record "Gen. Journal Batch")
    var
        DuplicateVendorNo: Code[20];
        NormalVendorNo: Code[20];
        FirstTimeVendorNo: Code[20];
        FirstInvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
    begin
        DuplicateVendorNo := CreateVendor(DuplicateVendorTok);
        PostUsualHistory(DuplicateVendorNo);
        FirstInvoiceNo := PostInvoice(DuplicateVendorNo, DemoInvoiceTok, -10, 1280);
        SecondInvoiceNo := PostInvoice(DuplicateVendorNo, DemoDuplicateTok, -10, 1280);
        AddBankAccount(DuplicateVendorNo);

        NormalVendorNo := CreateVendor(NormalVendorTok);
        PostUsualHistory(NormalVendorNo);
        FirstTimeVendorNo := CreateVendor(FirstTimeVendorTok);

        CreatePaymentBatch(GenJournalBatch);
        AddPaymentLine(GenJournalBatch, DuplicateVendorNo, FirstInvoiceNo);
        AddPaymentLine(GenJournalBatch, DuplicateVendorNo, SecondInvoiceNo);
        AddPaymentLine(GenJournalBatch, NormalVendorNo, PostInvoice(NormalVendorNo, DemoNormalInvoiceTok, -15, 980));
        AddPaymentLine(GenJournalBatch, FirstTimeVendorNo, PostInvoice(FirstTimeVendorNo, DemoFirstInvoiceTok, -5, 2400));
    end;

    procedure NewRun(GenJournalBatch: Record "Gen. Journal Batch"; var ExrRun: Record "EXR Run")
    begin
        Clear(ExrRun);
        ExrRun.Capability := ExrRun.Capability::"Payment Run";
        ExrRun."Source Table No." := Database::"Gen. Journal Line";
        ExrRun."Journal Template Name" := GenJournalBatch."Journal Template Name";
        ExrRun."Journal Batch Name" := GenJournalBatch.Name;
        ExrRun."Duplicate Window Days" := 60;
        ExrRun."Bank Change Window Days" := 30;
    end;

    // Runs the detectors only, without the AI service.
    procedure FindSignals(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary)
    var
        RunContext: Codeunit "EXR Run Context";
        Handler: Interface "EXR Capability Handler";
    begin
        TempFinding.Reset();
        TempFinding.DeleteAll();
        RunContext.StartRun();
        Handler := ExrRun.Capability;
        Handler.BuildFacts(ExrRun, TempFinding, RunContext);
    end;

    procedure GetFinding(var TempFinding: Record "EXR Finding" temporary; VendorNo: Code[20]): Boolean
    begin
        TempFinding.Reset();
        TempFinding.SetRange("Account No.", VendorNo);
        exit(TempFinding.FindFirst());
    end;

    procedure GetFindingForLine(var TempFinding: Record "EXR Finding" temporary; LineSystemId: Guid): Boolean
    begin
        TempFinding.Reset();
        TempFinding.SetRange("Source System Id", LineSystemId);
        exit(TempFinding.FindFirst());
    end;

    procedure FindingReply(FindingKey: Text; Explanation: Text; ActionName: Text) Finding: JsonObject
    begin
        Finding.Add('key', FindingKey);
        Finding.Add('explanation', Explanation);
        Finding.Add('action', ActionName);
        Finding.Add('confidence', 'High');
    end;

    procedure Reply(Summary: Text; Findings: JsonArray) ReplyText: Text
    var
        ReplyJson: JsonObject;
    begin
        ReplyJson.Add('summary', Summary);
        ReplyJson.Add('findings', Findings);
        ReplyJson.WriteTo(ReplyText);
    end;

    // A reply that gives every finding of the run the same action.
    procedure ReplyForAll(var TempFinding: Record "EXR Finding" temporary; ActionName: Text): Text
    var
        Findings: JsonArray;
    begin
        TempFinding.Reset();
        if TempFinding.FindSet() then
            repeat
                Findings.Add(FindingReply(TempFinding."Finding Key", 'Explained.', ActionName));
            until TempFinding.Next() = 0;
        exit(Reply('Check these payments before the run.', Findings));
    end;

    // The hold code of a posted invoice or credit memo.
    procedure InvoiceOnHold(InvoiceNo: Code[20]): Code[3]
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        FindEntry(InvoiceNo, VendorLedgerEntry);
        exit(VendorLedgerEntry."On Hold");
    end;

    procedure EntryOnHold(LedgerEntryNo: Integer): Code[3]
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        VendorLedgerEntry.Get(LedgerEntryNo);
        exit(VendorLedgerEntry."On Hold");
    end;

    procedure LineExists(LineSystemId: Guid): Boolean
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        exit(GenJournalLine.GetBySystemId(LineSystemId));
    end;

    procedure ChangeLineAmount(LineSystemId: Guid; NewAmount: Decimal)
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.GetBySystemId(LineSystemId);
        GenJournalLine.Validate(Amount, NewAmount);
        GenJournalLine.Modify(true);
    end;

    // Equal before and after a run proves that nothing was posted.
    procedure LedgerFingerprint(): Text
    var
        GLEntry: Record "G/L Entry";
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        DetailedVendorLedgEntry: Record "Detailed Vendor Ledg. Entry";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
    begin
        exit(StrSubstNo(LedgerFingerprintTok, GLEntry.Count(), VendorLedgerEntry.Count(), DetailedVendorLedgEntry.Count(), BankAccountLedgerEntry.Count()));
    end;

    // The lines of the batch, except the one left out, as they were: number, vendor, amount and what they apply to.
    procedure JournalFingerprint(GenJournalBatch: Record "Gen. Journal Batch"; LeaveOutSystemId: Guid) Fingerprint: Text
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        if GenJournalLine.FindSet() then
            repeat
                if GenJournalLine.SystemId <> LeaveOutSystemId then
                    Fingerprint += StrSubstNo(LineFingerprintTok, GenJournalLine."Line No.", GenJournalLine."Account No.", GenJournalLine.Amount,
                        GenJournalLine."Applies-to Doc. No.", GenJournalLine."Applies-to ID", GenJournalLine."Recipient Bank Account");
            until GenJournalLine.Next() = 0;
    end;

    // Equal before and after proves that no vendor ledger entry of the vendor changed: hold, application, due date, amounts.
    procedure VendorFingerprint(VendorNo: Code[20]) Fingerprint: Text
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        VendorLedgerEntry.SetRange("Vendor No.", VendorNo);
        VendorLedgerEntry.SetAutoCalcFields("Remaining Amount");
        if VendorLedgerEntry.FindSet() then
            repeat
                Fingerprint += StrSubstNo(LineFingerprintTok, VendorLedgerEntry."Entry No.", VendorLedgerEntry.Open, VendorLedgerEntry."Remaining Amount",
                    VendorLedgerEntry."On Hold", VendorLedgerEntry."Applies-to ID", VendorLedgerEntry."Due Date");
            until VendorLedgerEntry.Next() = 0;
    end;

    local procedure InitPaymentLine(GenJournalBatch: Record "Gen. Journal Batch"; VendorNo: Code[20]; Amount: Decimal; var GenJournalLine: Record "Gen. Journal Line")
    var
        LastLine: Record "Gen. Journal Line";
    begin
        LastLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        LastLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        if not LastLine.FindLast() then
            LastLine."Line No." := 0;
        GenJournalLine.Init();
        GenJournalLine."Journal Template Name" := GenJournalBatch."Journal Template Name";
        GenJournalLine."Journal Batch Name" := GenJournalBatch.Name;
        GenJournalLine."Line No." := LastLine."Line No." + 10000;
        GenJournalLine.Insert(true);
        GenJournalLine.Validate("Posting Date", WorkDate());
        GenJournalLine.Validate("Document Type", GenJournalLine."Document Type"::Payment);
        GenJournalLine."Document No." := NextJournalDocumentNo();
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Vendor);
        GenJournalLine.Validate("Account No.", VendorNo);
        if GenJournalBatch."Bal. Account No." <> '' then begin
            GenJournalLine.Validate("Bal. Account Type", GenJournalBatch."Bal. Account Type");
            GenJournalLine.Validate("Bal. Account No.", GenJournalBatch."Bal. Account No.");
        end;
        if Amount <> 0 then
            GenJournalLine.Validate(Amount, Amount);
        GenJournalLine.Modify(true);
    end;

    // Document numbers are unique here: invoices EXR-PI, credit memos EXR-PC, payments EXR-PP.
    local procedure FindEntry(DocumentNo: Code[20]; var VendorLedgerEntry: Record "Vendor Ledger Entry")
    begin
        VendorLedgerEntry.SetCurrentKey("Document No.");
        VendorLedgerEntry.SetRange("Document No.", DocumentNo);
        VendorLedgerEntry.FindFirst();
    end;

    // Unique per run: EXR-PI0001, EXR-PI0002 and so on.
    local procedure NextDocumentNo(Prefix: Text): Code[20]
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        VendorLedgerEntry.SetCurrentKey("Document No.");
        VendorLedgerEntry.SetFilter("Document No.", StrSubstNo(StartsWithTok, Prefix));
        VendorLedgerEntry.SetLoadFields("Document No.");
        if VendorLedgerEntry.FindLast() then
            exit(CopyStr(IncStr(VendorLedgerEntry."Document No."), 1, 20));
        exit(CopyStr(Prefix + FirstCounterTok, 1, 20));
    end;

    local procedure NextJournalDocumentNo(): Code[20]
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.SetCurrentKey("Document No.");
        GenJournalLine.SetFilter("Document No.", StrSubstNo(StartsWithTok, JournalPaymentPrefixTok));
        GenJournalLine.SetLoadFields("Document No.");
        if GenJournalLine.FindLast() then
            exit(CopyStr(IncStr(GenJournalLine."Document No."), 1, 20));
        exit(CopyStr(JournalPaymentPrefixTok + FirstCounterTok, 1, 20));
    end;

    local procedure NextBatchName(TemplateName: Code[10]): Code[10]
    var
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        GenJournalBatch.SetRange("Journal Template Name", TemplateName);
        GenJournalBatch.SetFilter(Name, StrSubstNo(StartsWithTok, BatchPrefixTok));
        if GenJournalBatch.FindLast() then
            exit(CopyStr(IncStr(GenJournalBatch.Name), 1, 10));
        exit(CopyStr(BatchPrefixTok + FirstBatchCounterTok, 1, 10));
    end;
}
