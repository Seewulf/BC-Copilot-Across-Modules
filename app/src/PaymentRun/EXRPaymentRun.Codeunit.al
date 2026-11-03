namespace PrabinBhusal.ExplainResolve;

using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Purchases.Payables;
using Microsoft.Purchases.Vendor;
using System.AI;

// Check payment run: AL screens the vendor payment lines of one payment journal batch, and the invoices they pay, in LCY.
// One finding per line with a signal. Keep it may only delete held lines and put their invoices at risk on hold.
// Bank account numbers, IBAN, SWIFT codes and bank names are never read: only the date a bank account changed.
codeunit 58208 "EXR Payment Run" implements "EXR Capability Handler"
{
    Access = Internal;
    // users get indirect delete only, for the lines that a kept Hold removes
    Permissions = tabledata "Gen. Journal Line" = d;

    var
        PurchVariance: Codeunit "EXR Purch. Variance";
        DuplicateWindowDays: Integer;
        BankWindowDays: Integer;
        UnusualAmountPct: Decimal;
        AsOfDate: Date;
        PromptTok: Label 'payment-run.md', Locked = true;
        FindingKeyTok: Label 'LINE-%1', Locked = true;
        SignalSeparatorTok: Label '+', Locked = true;
        PaidTok: Label 'PAID', Locked = true;
        DupCopyTok: Label 'DUP_COPY', Locked = true;
        DuplicateTok: Label 'DUPLICATE', Locked = true;
        NearDupTok: Label 'NEAR_DUP', Locked = true;
        BankTok: Label 'BANK', Locked = true;
        OnHoldTok: Label 'ON_HOLD', Locked = true;
        AmountTok: Label 'AMOUNT', Locked = true;
        FirstTok: Label 'FIRST', Locked = true;
        DigitsTok: Label '0123456789', Locked = true;
        SentenceTok: Label '%1 %2', Locked = true;
        ListSeparatorTok: Label ', ', Locked = true;
        // fact captions are read by the model only
        AsOfFactTok: Label 'as-of date of the payment history', Locked = true;
        LinesCheckedFactTok: Label 'vendor payment lines checked, as a phrase', Locked = true;
        LinesClearFactTok: Label 'payment lines with no signal, which stay in the journal to be paid, as a phrase', Locked = true;
        NotCheckedFactTok: Label 'vendor payment lines entered with the vendor as balancing account, which were not checked, as a phrase', Locked = true;
        TotalCheckedFactTok: Label 'total of the payment lines checked', Locked = true;
        TotalFlaggedFactTok: Label 'total of the payment lines with a signal', Locked = true;
        DuplicateWindowFactTok: Label 'duplicate window, as a phrase', Locked = true;
        BankWindowFactTok: Label 'bank-change window, as a phrase', Locked = true;
        ThresholdFactTok: Label 'unusual amount threshold above the median', Locked = true;
        PaymentAmountFactTok: Label 'payment amount', Locked = true;
        InvoiceDateFactTok: Label 'posting date of the invoice this line pays', Locked = true;
        InvoiceCountFactTok: Label 'invoices this line pays, as a phrase', Locked = true;
        PaidFactTok: Label 'what is still open on the entries this line pays, as a full sentence', Locked = true;
        LineAmountFactTok: Label 'payment amount in the currency of the line', Locked = true;
        OpenAmountFactTok: Label 'amount still open on the entries this line pays, in the currency of the line', Locked = true;
        IssuedFactTok: Label 'whether the payment already left Business Central, as a full sentence', Locked = true;
        DuplicateDateFactTok: Label 'posting date of the possible duplicate', Locked = true;
        DuplicateGapFactTok: Label 'when the two invoices were posted, as a phrase', Locked = true;
        DuplicateAmountFactTok: Label 'amount of each of the two invoices', Locked = true;
        DuplicateMatchFactTok: Label 'how the vendor invoice numbers match, as a full sentence', Locked = true;
        DuplicateStatusFactTok: Label 'whether the possible duplicate is still open, as a full sentence', Locked = true;
        DuplicateOrderFactTok: Label 'which of the two invoices was entered first, as a full sentence', Locked = true;
        DuplicateRunFactTok: Label 'whether the possible duplicate is also paid in this run, as a full sentence', Locked = true;
        BankDateFactTok: Label 'date a bank account of this vendor was last changed', Locked = true;
        BankAgoFactTok: Label 'how long ago that was, as a phrase', Locked = true;
        BankTargetFactTok: Label 'which bank account this payment goes to, as a full sentence', Locked = true;
        MedianFactTok: Label 'median payment to this vendor in the last 12 months', Locked = true;
        PaymentCountFactTok: Label 'payments to this vendor in the last 12 months, as a phrase', Locked = true;
        AboveMedianFactTok: Label 'how far the payment is above the median', Locked = true;
        VendorCreatedFactTok: Label 'date the vendor card was created', Locked = true;
        ExactMatchLbl: Label 'The vendor invoice numbers are the same once spaces and symbols are removed';
        DigitsMatchLbl: Label 'Only the digits of the vendor invoice numbers match';
        DuplicateOpenLbl: Label 'The possible duplicate is still open';
        DuplicateClosedLbl: Label 'The possible duplicate is already closed, so it was paid or settled';
        EnteredLaterLbl: Label 'This invoice was entered after the possible duplicate';
        EnteredFirstLbl: Label 'This invoice was entered before the possible duplicate';
        PaysBothLbl: Label 'This payment line pays both invoices';
        OtherLineLbl: Label 'Another line of this payment run pays the possible duplicate';
        NotInRunLbl: Label 'The possible duplicate is not paid in this payment run';
        NothingOpenLbl: Label 'Nothing that this line pays is still open, so it was already paid or settled';
        OverpaysLbl: Label 'The line pays more than is still open on the entries it pays';
        IssuedLbl: Label 'The line was already exported to a payment file or its check was printed, so it can no longer be held here';
        PaysChangedLbl: Label 'This payment goes to a bank account that changed';
        PaysOtherLbl: Label 'This payment goes to a bank account that did not change';
        NoRecipientLbl: Label 'The payment line names no bank account';
        SameDayLbl: Label 'on the same day';
        OneDayApartLbl: Label '%1 day apart', Comment = '%1 = number of days (1)';
        DaysApartLbl: Label '%1 days apart', Comment = '%1 = number of days';
        TodayLbl: Label 'today';
        OneDayAgoLbl: Label '%1 day ago', Comment = '%1 = number of days (1)';
        DaysAgoLbl: Label '%1 days ago', Comment = '%1 = number of days';
        OneDayLbl: Label '%1 day', Comment = '%1 = number of days (1)';
        DaysLbl: Label '%1 days', Comment = '%1 = number of days';
        OnePaymentLbl: Label '%1 payment', Comment = '%1 = number of payments (1)';
        PaymentsLbl: Label '%1 payments', Comment = '%1 = number of payments';
        OneLineLbl: Label '%1 payment line', Comment = '%1 = number of payment lines (1)';
        LinesLbl: Label '%1 payment lines', Comment = '%1 = number of payment lines';
        OneInvoiceLbl: Label '%1 invoice', Comment = '%1 = number of invoices (1)';
        InvoicesLbl: Label '%1 invoices', Comment = '%1 = number of invoices';
        SubjectLbl: Label '%1 %2: payment %3', Comment = '%1 = vendor number, %2 = vendor name, %3 = document number of the payment line';
        SubjectInvoiceLbl: Label '%1 %2: payment %3 of vendor invoice %4', Comment = '%1 = vendor number, %2 = vendor name, %3 = document number of the payment line, %4 = vendor invoice number';
        ReferenceLbl: Label 'payment %1', Comment = '%1 = document number of the payment line';
        ReferenceInvoiceLbl: Label 'payment %1 of vendor invoice %2', Comment = '%1 = document number of the payment line, %2 = vendor invoice number';
        PaidDetailLbl: Label 'Nothing this line pays is still open.';
        OverpaidDetailLbl: Label 'The line pays %1, but only %2 is still open.', Comment = '%1 = amount of the payment line, %2 = amount still open';
        IssuedDetailLbl: Label 'Already exported to a payment file or check printed.';
        DuplicateDetailLbl: Label 'Possible duplicate of vendor invoice %1, posted %2 for the same amount.', Comment = '%1 = vendor invoice number, %2 = date';
        BankDetailLbl: Label 'A bank account of the vendor changed on %1.', Comment = '%1 = date';
        OnHoldDetailLbl: Label 'The invoice is already on hold (%1).', Comment = '%1 = On Hold code';
        AmountDetailLbl: Label '%1 is %2 above the median payment of %3.', Comment = '%1 = payment amount, %2 = percentage, %3 = amount';
        FirstDetailLbl: Label 'First payment to this vendor.';
        HeldDetailLbl: Label 'Put on hold: %1.', Comment = '%1 = list of vendor invoice numbers';
        KeptMsg: Label 'Review saved as payment run evidence. No payment was held.';
        KeptHeldMsg: Label 'Review saved as payment run evidence. Payment lines removed from the payment journal, with their invoices at risk put on hold: %1.', Comment = '%1 = number of payment lines';
        NoBatchErr: Label 'Open Check payment run from a payment journal batch.';
        NoHoldCodeErr: Label 'Enter a Hold Code on the Explain and Resolve Setup page before you keep a Hold. Nothing was kept.';
        LineChangedErr: Label 'The payment line %1 changed or left the journal after the check, so nothing was kept. Choose Regenerate to check the journal again.', Comment = '%1 = vendor and payment line, for example 10000 Fabrikam: payment G00001';
        LineIssuedErr: Label 'The payment line %1 was already exported to a payment file or its check was printed, so nothing was kept. Void the payment file or the check first, then choose Regenerate.', Comment = '%1 = vendor and payment line, for example 10000 Fabrikam: payment G00001';

    procedure CopilotCapability(): Enum "Copilot Capability"
    begin
        exit(Enum::"Copilot Capability"::"EXR Payment Run");
    end;

    procedure PromptResourceName(): Text
    begin
        exit(PromptTok);
    end;

    procedure UsesTolerance(): Boolean
    begin
        exit(false);
    end;

    // The batch comes with the run, not a single source record.
    procedure ReviewsSelection(): Boolean
    begin
        exit(true);
    end;

    procedure DraftsEmailPerFinding(): Boolean
    begin
        exit(false);
    end;

    // The summary is the note for the approver; no email is drafted.
    procedure DraftsEmail(): Boolean
    begin
        exit(false);
    end;

    procedure UsesPaymentWindows(): Boolean
    begin
        exit(true);
    end;

    // The type lists the line's signals, such as DUP_COPY+BANK. An action is allowed when one signal allows it, but Pay only
    // when every signal allows it, and a hold-only signal (PAID, DUP_COPY, ON_HOLD) leaves Hold as the only choice.
    procedure IsActionAllowed(FindingType: Code[30]; FindingAction: Enum "EXR Action") Allowed: Boolean
    var
        Signal: Text;
    begin
        foreach Signal in Signals(FindingType) do
            if SignalAllows(Signal, FindingAction) then
                Allowed := true
            else
                if (FindingAction = Enum::"EXR Action"::Pay) or IsHoldOnly(Signal) then
                    exit(false);
    end;

    // One finding per vendor payment line with a signal. Lines without one are only counted: they stay in the journal to be paid.
    procedure BuildFacts(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        Setup: Record "EXR Setup";
        GenJournalLine: Record "Gen. Journal Line";
        LinesChecked: Integer;
        NotChecked: Integer;
        TotalChecked: Decimal;
        TotalFlagged: Decimal;
    begin
        if (ExrRun."Journal Template Name" = '') or (ExrRun."Journal Batch Name" = '') then
            Error(NoBatchErr);
        Setup.GetSetup();
        UnusualAmountPct := Setup."Unusual Amount %";
        DuplicateWindowDays := Bounded(ExrRun."Duplicate Window Days");
        BankWindowDays := Bounded(ExrRun."Bank Change Window Days");
        AsOfDate := WorkDate();
        ExrRun."Source No." := ExrRun."Journal Batch Name";
        RunContext.AddContext('journalBatch', ExrRun."Journal Batch Name");
        RunContext.AddDate('', AsOfFactTok, AsOfDate);
        RunContext.AddPhrase('', DuplicateWindowFactTok, RunContext.CountPhrase(DuplicateWindowDays, OneDayLbl, DaysLbl));
        RunContext.AddPhrase('', BankWindowFactTok, RunContext.CountPhrase(BankWindowDays, OneDayLbl, DaysLbl));
        RunContext.AddPercent('', ThresholdFactTok, UnusualAmountPct);

        // a check that feeds no write: read committed; Keep it reads each held line again with a lock
        GenJournalLine.ReadIsolation := IsolationLevel::ReadCommitted;
        GenJournalLine.SetRange("Journal Template Name", ExrRun."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", ExrRun."Journal Batch Name");
        // vendor payments keyed the other way round (vendor as balancing account) are counted, not checked
        GenJournalLine.SetRange("Bal. Account Type", GenJournalLine."Bal. Account Type"::Vendor);
        GenJournalLine.SetFilter("Bal. Account No.", '<>%1', '');
        GenJournalLine.SetFilter("Amount (LCY)", '<0');
        NotChecked := GenJournalLine.Count();
        GenJournalLine.SetRange("Bal. Account Type");
        GenJournalLine.SetRange("Bal. Account No.");
        GenJournalLine.SetRange("Account Type", GenJournalLine."Account Type"::Vendor);
        GenJournalLine.SetFilter("Account No.", '<>%1', '');
        GenJournalLine.SetFilter("Amount (LCY)", '>0');
        GenJournalLine.SetLoadFields("Account No.", "Document No.", "Currency Code", Amount, "Amount (LCY)", "Applies-to Doc. Type", "Applies-to Doc. No.", "Applies-to ID",
            "Recipient Bank Account", "Exported to Payment File", "Check Printed", "Check Exported", "Check Transmitted");
        if GenJournalLine.FindSet() then
            repeat
                LinesChecked += 1;
                TotalChecked += GenJournalLine."Amount (LCY)";
                RunContext.AddCurrency(GenJournalLine."Currency Code");
                if CheckLine(GenJournalLine, TempFinding, RunContext) then
                    TotalFlagged += GenJournalLine."Amount (LCY)";
            until GenJournalLine.Next() = 0;
        TempFinding.Reset();
        RunContext.AddPhrase('', LinesCheckedFactTok, RunContext.CountPhrase(LinesChecked, OneLineLbl, LinesLbl));
        RunContext.AddPhrase('', LinesClearFactTok, RunContext.CountPhrase(LinesChecked - TempFinding.Count(), OneLineLbl, LinesLbl));
        if NotChecked > 0 then
            RunContext.AddPhrase('', NotCheckedFactTok, RunContext.CountPhrase(NotChecked, OneLineLbl, LinesLbl));
        RunContext.AddAmount('', TotalCheckedFactTok, TotalChecked);
        RunContext.AddAmount('', TotalFlaggedFactTok, TotalFlagged);
    end;

    procedure BuildEmailTable(var TempFinding: Record "EXR Finding" temporary): Text
    begin
        exit('');
    end;

    // The only writes: for each accepted Hold, the line is checked again, deleted from the journal and its invoices at risk
    // are put on hold, so the next Suggest Vendor Payments skips them. One error rolls back the whole Keep it.
    procedure ApplyKeep(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary): Text
    var
        Setup: Record "EXR Setup";
        Held: Integer;
    begin
        Held := 0;
        if TempFinding.FindSet() then
            repeat
                if TempFinding."Action" = Enum::"EXR Action"::Hold then begin
                    if Held = 0 then begin
                        Setup.GetSetup();
                        if Setup."Hold Code" = '' then
                            Error(NoHoldCodeErr);
                    end;
                    HoldPayment(ExrRun, TempFinding, Setup."Hold Code");
                    Held += 1;
                end;
            until TempFinding.Next() = 0;
        if Held = 0 then
            exit(KeptMsg);
        exit(StrSubstNo(KeptHeldMsg, Held));
    end;

    // Returns whether the line has a signal; it then becomes a finding.
    local procedure CheckLine(GenJournalLine: Record "Gen. Journal Line"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context"): Boolean
    var
        Vendor: Record Vendor;
        AppliedEntry: Record "Vendor Ledger Entry";
        InvoiceEntry: Record "Vendor Ledger Entry";
        CandidateEntry: Record "Vendor Ledger Entry";
        DuplicateEntry: Record "Vendor Ledger Entry";
        FindingSeverity: Enum "EXR Severity";
        FindingAction: Enum "EXR Action";
        EntryNos: List of [Integer];
        EntryNo: Integer;
        PaymentCount: Integer;
        OnHoldCode: Code[3];
        BankChangedOn: Date;
        Median: Decimal;
        OpenAmount: Decimal;
        FindingKey: Text;
        FindingType: Text;
        DuplicateSignal: Text;
        Detail: Text;
        IsApplied: Boolean;
        SameCurrency: Boolean;
        IsPaid: Boolean;
        HasDuplicate: Boolean;
        DuplicateExact: Boolean;
        Exact: Boolean;
        PaysBoth: Boolean;
        IsCopy: Boolean;
        PaysChangedAccount: Boolean;
        IsUnusual: Boolean;
        IsFirst: Boolean;
    begin
        OnHoldCode := '';
        IsApplied := FindAppliedEntries(GenJournalLine, EntryNos, OpenAmount, SameCurrency);
        // applied, but nothing is open any more or the line pays more than is open: paid since the line was made
        IsPaid := IsApplied and ((EntryNos.Count() = 0) or (SameCurrency and (GenJournalLine.Amount > -OpenAmount)));
        foreach EntryNo in EntryNos do begin
            ReadEntry(EntryNo, AppliedEntry);
            if InvoiceEntry."Entry No." = 0 then
                InvoiceEntry := AppliedEntry;
            if (OnHoldCode = '') and (AppliedEntry."On Hold" <> '') then
                OnHoldCode := AppliedEntry."On Hold";
            // an exact match wins over a match on the digits only
            if not DuplicateExact then
                if FindDuplicate(AppliedEntry, CandidateEntry, Exact) then
                    if Exact or not HasDuplicate then begin
                        HasDuplicate := true;
                        DuplicateExact := Exact;
                        InvoiceEntry := AppliedEntry;
                        DuplicateEntry := CandidateEntry;
                    end;
        end;
        // a summarised line that pays both copies: the finding is about the copy entered later
        PaysBoth := HasDuplicate and EntryNos.Contains(DuplicateEntry."Entry No.");
        if PaysBoth and (InvoiceEntry."Entry No." < DuplicateEntry."Entry No.") then begin
            AppliedEntry := InvoiceEntry;
            InvoiceEntry := DuplicateEntry;
            DuplicateEntry := AppliedEntry;
        end;
        IsCopy := HasDuplicate and DuplicateExact and IsLaterCopy(InvoiceEntry, DuplicateEntry);
        BankChangedOn := LatestBankChange(GenJournalLine, PaysChangedAccount);
        Median := MedianPayment(GenJournalLine."Account No.", PaymentCount);
        // a line that pays several invoices is not compared with single payments
        IsUnusual := (EntryNos.Count() <= 1) and (UnusualAmountPct > 0) and (Median > 0) and (GenJournalLine."Amount (LCY)" > Median * (1 + UnusualAmountPct / 100));
        IsFirst := (PaymentCount = 0) and not HasPayment(GenJournalLine."Account No.");
        if not (IsPaid or HasDuplicate or (BankChangedOn <> 0D) or (OnHoldCode <> '') or IsUnusual or IsFirst) then
            exit(false);

        // hold-only signals first, so a type cut at 30 characters never loses one
        DuplicateSignal := NearDupTok;
        if DuplicateExact then
            DuplicateSignal := DuplicateTok;
        if IsCopy then
            DuplicateSignal := DupCopyTok;
        AddSignal(FindingType, PaidTok, IsPaid);
        AddSignal(FindingType, DuplicateSignal, HasDuplicate);
        AddSignal(FindingType, OnHoldTok, OnHoldCode <> '');
        AddSignal(FindingType, BankTok, BankChangedOn <> 0D);
        AddSignal(FindingType, AmountTok, IsUnusual);
        AddSignal(FindingType, FirstTok, IsFirst);
        TempFinding.Reset();
        FindingKey := StrSubstNo(FindingKeyTok, Format(TempFinding.Count() + 1, 0, 9));
        RunContext.AddAmount(FindingKey, PaymentAmountFactTok, GenJournalLine."Amount (LCY)");
        if EntryNos.Count() > 1 then
            RunContext.AddPhrase(FindingKey, InvoiceCountFactTok, RunContext.CountPhrase(EntryNos.Count(), OneInvoiceLbl, InvoicesLbl));
        if InvoiceEntry."Entry No." <> 0 then begin
            RunContext.AddDate(FindingKey, InvoiceDateFactTok, InvoiceEntry."Posting Date");
            RunContext.AddFindingContext(FindingKey, 'vendorInvoiceNo', InvoiceEntry."External Document No.");
            RunContext.AddFindingContext(FindingKey, 'invoiceDescription', InvoiceEntry.Description);
        end;
        if IsPaid then
            AddPaidFacts(FindingKey, GenJournalLine, EntryNos.Count(), OpenAmount, RunContext, Detail);
        if HasDuplicate then
            AddDuplicateFacts(FindingKey, GenJournalLine, InvoiceEntry, DuplicateEntry, DuplicateExact, PaysBoth, RunContext, Detail);
        if OnHoldCode <> '' then begin
            RunContext.AddFindingContext(FindingKey, 'onHoldCode', OnHoldCode);
            AddSentence(Detail, StrSubstNo(OnHoldDetailLbl, OnHoldCode));
        end;
        if BankChangedOn <> 0D then
            AddBankFacts(FindingKey, GenJournalLine, BankChangedOn, PaysChangedAccount, RunContext, Detail);
        if IsUnusual then
            AddAmountFacts(FindingKey, GenJournalLine."Amount (LCY)", Median, PaymentCount, RunContext, Detail);
        Vendor.SetLoadFields(Name, SystemCreatedAt);
        if not Vendor.Get(GenJournalLine."Account No.") then
            Clear(Vendor);
        if IsFirst then begin
            if Vendor.SystemCreatedAt <> 0DT then
                RunContext.AddDate(FindingKey, VendorCreatedFactTok, DT2Date(Vendor.SystemCreatedAt));
            AddSentence(Detail, FirstDetailLbl);
        end;
        // Keep it refuses to hold such a line, so the approver and the model learn it here
        if IsIssued(GenJournalLine) then begin
            RunContext.AddPhrase(FindingKey, IssuedFactTok, IssuedLbl);
            AddSentence(Detail, IssuedDetailLbl);
        end;

        // AL sets the severity and the default action. A paid line, an exact duplicate or a changed bank account is High.
        // A paid line, the later copy of a duplicate and a held invoice default to Hold; the earlier copy stays to be asked about.
        FindingSeverity := Enum::"EXR Severity"::Medium;
        if IsPaid or DuplicateExact or (BankChangedOn <> 0D) then
            FindingSeverity := Enum::"EXR Severity"::High;
        case true of
            IsPaid or IsCopy or (OnHoldCode <> ''):
                FindingAction := Enum::"EXR Action"::Hold;
            BankChangedOn <> 0D:
                FindingAction := Enum::"EXR Action"::"Verify bank details by phone";
            HasDuplicate:
                FindingAction := Enum::"EXR Action"::"Ask vendor to confirm duplicate";
            IsUnusual:
                FindingAction := Enum::"EXR Action"::Hold;
            else
                FindingAction := Enum::"EXR Action"::"Verify bank details by phone";
        end;

        TempFinding.Init();
        TempFinding."Line No." := (TempFinding.Count() + 1) * 10000;
        TempFinding."Finding Key" := CopyStr(FindingKey, 1, MaxStrLen(TempFinding."Finding Key"));
        TempFinding."Finding Type" := CopyStr(FindingType, 1, MaxStrLen(TempFinding."Finding Type"));
        TempFinding.Severity := FindingSeverity;
        TempFinding.Subject := CopyStr(LineSubject(GenJournalLine, Vendor, InvoiceEntry), 1, MaxStrLen(TempFinding.Subject));
        // the approver note names a line by its payment, not the whole subject with the vendor
        RunContext.AddFindingReference(FindingKey, LineReference(GenJournalLine, InvoiceEntry));
        TempFinding.Detail := CopyStr(Detail, 1, MaxStrLen(TempFinding.Detail));
        TempFinding.Description := TempFinding.Detail;
        TempFinding."Action" := FindingAction;
        TempFinding."Amount (LCY)" := GenJournalLine."Amount (LCY)";
        if InvoiceEntry."Entry No." <> 0 then
            TempFinding."Source Record ID" := InvoiceEntry.RecordId()
        else
            TempFinding."Source Record ID" := Vendor.RecordId();
        // what Keep it checks again before it holds the payment
        TempFinding."Source System Id" := GenJournalLine.SystemId;
        TempFinding."Account No." := GenJournalLine."Account No.";
        TempFinding."Ledger Entry No." := InvoiceEntry."Entry No.";
        TempFinding."Applied Entries" := EntryNos.Count();
        TempFinding."Applied Entry Checksum" := Checksum(EntryNos);
        TempFinding.Accepted := true;
        TempFinding.Insert();
        exit(true);
    end;

    // The open entries the line pays: one through Applies-to Doc. No., or several through Applies-to ID (Summarize per Vendor).
    // Returns whether the line is applied at all. OpenAmount is what is still open on them, in their own currency;
    // SameCurrency says whether they are all in the line's currency, so the two can be compared.
    local procedure FindAppliedEntries(GenJournalLine: Record "Gen. Journal Line"; var EntryNos: List of [Integer]; var OpenAmount: Decimal; var SameCurrency: Boolean): Boolean
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        Clear(EntryNos);
        OpenAmount := 0;
        SameCurrency := true;
        VendorLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        case true of
            GenJournalLine."Applies-to Doc. No." <> '':
                begin
                    VendorLedgerEntry.SetCurrentKey("Document No.");
                    VendorLedgerEntry.SetRange("Document No.", GenJournalLine."Applies-to Doc. No.");
                    VendorLedgerEntry.SetRange("Document Type", GenJournalLine."Applies-to Doc. Type");
                end;
            GenJournalLine."Applies-to ID" <> '':
                begin
                    VendorLedgerEntry.SetCurrentKey("Vendor No.", "Applies-to ID", Open, Positive, "Due Date");
                    VendorLedgerEntry.SetRange("Applies-to ID", GenJournalLine."Applies-to ID");
                end;
            else
                exit(false);
        end;
        VendorLedgerEntry.SetRange("Vendor No.", GenJournalLine."Account No.");
        VendorLedgerEntry.SetRange(Open, true);
        VendorLedgerEntry.SetLoadFields("Entry No.", "Currency Code");
        VendorLedgerEntry.SetAutoCalcFields("Remaining Amount");
        if VendorLedgerEntry.FindSet() then
            repeat
                EntryNos.Add(VendorLedgerEntry."Entry No.");
                OpenAmount += VendorLedgerEntry."Remaining Amount";
                if VendorLedgerEntry."Currency Code" <> GenJournalLine."Currency Code" then
                    SameCurrency := false;
            until VendorLedgerEntry.Next() = 0;
        exit(true);
    end;

    local procedure ReadEntry(EntryNo: Integer; var VendorLedgerEntry: Record "Vendor Ledger Entry")
    begin
        VendorLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        VendorLedgerEntry.SetLoadFields("Vendor No.", "Document Type", "Document No.", "External Document No.", Description, "Posting Date", "Currency Code", "On Hold", Open,
            "Applies-to ID", "Closed by Entry No.");
        VendorLedgerEntry.SetAutoCalcFields(Amount, "Amount (LCY)");
        VendorLedgerEntry.Get(EntryNo);
    end;

    // Another posted invoice of the vendor, in the same currency and for the same amount, posted within the window, whose
    // vendor invoice number is the same once normalised (Exact) or has the same digits, at least 3 (INV4471 and 4471/A).
    // A copy already cancelled with a credit memo is left out. The model judges the rest.
    local procedure FindDuplicate(Invoice: Record "Vendor Ledger Entry"; var Candidate: Record "Vendor Ledger Entry"; var Exact: Boolean): Boolean
    var
        NearEntry: Record "Vendor Ledger Entry";
        Normalised: Text;
        CandidateNormalised: Text;
        Digits: Text;
        Found: Boolean;
    begin
        Exact := false;
        if (DuplicateWindowDays = 0) or (Invoice."Document Type" <> Invoice."Document Type"::Invoice) then
            exit(false);
        Normalised := PurchVariance.NormaliseInvoiceNo(Invoice."External Document No.");
        if Normalised = '' then
            exit(false);
        Digits := DigitsOnly(Normalised);
        Candidate.ReadIsolation := IsolationLevel::ReadCommitted;
        Candidate.SetCurrentKey("Vendor No.", "Posting Date", "Applies-to ID");
        Candidate.SetRange("Vendor No.", Invoice."Vendor No.");
        Candidate.SetRange("Posting Date", Invoice."Posting Date" - DuplicateWindowDays, Invoice."Posting Date" + DuplicateWindowDays);
        Candidate.SetRange("Document Type", Candidate."Document Type"::Invoice);
        Candidate.SetRange("Currency Code", Invoice."Currency Code");
        Candidate.SetRange(Reversed, false);
        Candidate.SetFilter("Entry No.", '<>%1', Invoice."Entry No.");
        Candidate.SetLoadFields("Vendor No.", "Document Type", "Document No.", "External Document No.", Description, "Posting Date", "Currency Code", "On Hold", Open,
            "Applies-to ID", "Closed by Entry No.");
        Candidate.SetAutoCalcFields(Amount, "Amount (LCY)");
        if Candidate.FindSet() then
            repeat
                if Candidate.Amount = Invoice.Amount then
                    if not IsCancelled(Candidate) then begin
                        CandidateNormalised := PurchVariance.NormaliseInvoiceNo(Candidate."External Document No.");
                        if CandidateNormalised = Normalised then begin
                            Exact := true;
                            exit(true);
                        end;
                        if not Found and (StrLen(Digits) >= 3) and (DigitsOnly(CandidateNormalised) = Digits) then begin
                            Found := true;
                            NearEntry := Candidate;
                        end;
                    end;
            until Candidate.Next() = 0;
        if Found then
            Candidate := NearEntry;
        exit(Found);
    end;

    // Closed by a credit memo, as Cancel or Create Corrective Credit Memo does, from either side of the application.
    local procedure IsCancelled(Candidate: Record "Vendor Ledger Entry"): Boolean
    var
        ClosingEntry: Record "Vendor Ledger Entry";
        CreditMemoEntry: Record "Vendor Ledger Entry";
    begin
        if Candidate.Open then
            exit(false);
        ClosingEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        ClosingEntry.SetLoadFields("Document Type");
        if ClosingEntry.Get(Candidate."Closed by Entry No.") then
            if ClosingEntry."Document Type" = ClosingEntry."Document Type"::"Credit Memo" then
                exit(true);
        CreditMemoEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        CreditMemoEntry.SetCurrentKey("Closed by Entry No.");
        CreditMemoEntry.SetRange("Closed by Entry No.", Candidate."Entry No.");
        CreditMemoEntry.SetRange("Document Type", CreditMemoEntry."Document Type"::"Credit Memo");
        exit(not CreditMemoEntry.IsEmpty());
    end;

    // Whether another vendor line of the batch pays the possible duplicate, through Applies-to Doc. No. or its Applies-to ID.
    local procedure PaidByOtherLine(GenJournalLine: Record "Gen. Journal Line"; Duplicate: Record "Vendor Ledger Entry"): Boolean
    var
        OtherLine: Record "Gen. Journal Line";
    begin
        OtherLine.ReadIsolation := IsolationLevel::ReadCommitted;
        OtherLine.SetRange("Journal Template Name", GenJournalLine."Journal Template Name");
        OtherLine.SetRange("Journal Batch Name", GenJournalLine."Journal Batch Name");
        OtherLine.SetFilter("Line No.", '<>%1', GenJournalLine."Line No.");
        OtherLine.SetRange("Account Type", OtherLine."Account Type"::Vendor);
        OtherLine.SetRange("Account No.", Duplicate."Vendor No.");
        OtherLine.SetRange("Applies-to Doc. Type", Duplicate."Document Type");
        OtherLine.SetRange("Applies-to Doc. No.", Duplicate."Document No.");
        if not OtherLine.IsEmpty() then
            exit(true);
        if Duplicate."Applies-to ID" = '' then
            exit(false);
        OtherLine.SetRange("Applies-to Doc. Type");
        OtherLine.SetRange("Applies-to Doc. No.");
        OtherLine.SetRange("Applies-to ID", Duplicate."Applies-to ID");
        exit(not OtherLine.IsEmpty());
    end;

    // The latest change inside the window to one of the vendor's bank accounts, from SystemModifiedAt (also set when an
    // account is added). Counted from today, because that is the clock it is stamped with. 0D when there is none.
    local procedure LatestBankChange(GenJournalLine: Record "Gen. Journal Line"; var PaysChangedAccount: Boolean) ChangedOn: Date
    var
        VendorBankAccount: Record "Vendor Bank Account";
        ModifiedOn: Date;
    begin
        PaysChangedAccount := false;
        if BankWindowDays = 0 then
            exit(0D);
        VendorBankAccount.ReadIsolation := IsolationLevel::ReadCommitted;
        VendorBankAccount.SetRange("Vendor No.", GenJournalLine."Account No.");
        // the code and the change time only: never the account number, IBAN, SWIFT code or bank name
        VendorBankAccount.SetLoadFields(Code, SystemModifiedAt);
        if VendorBankAccount.FindSet() then
            repeat
                ModifiedOn := DT2Date(VendorBankAccount.SystemModifiedAt);
                if ModifiedOn > Today() - BankWindowDays then begin
                    if ModifiedOn > ChangedOn then
                        ChangedOn := ModifiedOn;
                    if VendorBankAccount.Code = GenJournalLine."Recipient Bank Account" then
                        PaysChangedAccount := true;
                end;
            until VendorBankAccount.Next() = 0;
    end;

    // The median of the vendor's payments (not invoices) posted in the 12 months up to the as-of date, in LCY.
    // 0 when there are fewer than 3, which is too few for a pattern.
    // Limit: sorted by insertion, fine for a year of payments to one vendor; use a query ordered by amount if vendors are paid daily
    local procedure MedianPayment(VendorNo: Code[20]; var PaymentCount: Integer): Decimal
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        Amounts: List of [Decimal];
        Amount: Decimal;
        Index: Integer;
        Middle: Integer;
    begin
        VendorLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        VendorLedgerEntry.SetCurrentKey("Vendor No.", "Posting Date", "Applies-to ID");
        VendorLedgerEntry.SetRange("Vendor No.", VendorNo);
        VendorLedgerEntry.SetRange("Posting Date", CalcDate('<-12M>', AsOfDate), AsOfDate);
        VendorLedgerEntry.SetRange("Document Type", VendorLedgerEntry."Document Type"::Payment);
        VendorLedgerEntry.SetRange(Reversed, false);
        VendorLedgerEntry.SetLoadFields("Entry No.");
        VendorLedgerEntry.SetAutoCalcFields("Amount (LCY)");
        if VendorLedgerEntry.FindSet() then
            repeat
                Amount := Abs(VendorLedgerEntry."Amount (LCY)");
                Index := 1;
                // AL evaluates both sides of "and", so the bound is checked before Get
                while Index <= Amounts.Count() do begin
                    if Amounts.Get(Index) >= Amount then
                        break;
                    Index += 1;
                end;
                if Index > Amounts.Count() then
                    Amounts.Add(Amount)
                else
                    Amounts.Insert(Index, Amount);
            until VendorLedgerEntry.Next() = 0;
        PaymentCount := Amounts.Count();
        if PaymentCount < 3 then
            exit(0);
        Middle := (PaymentCount + 1) div 2;
        if PaymentCount mod 2 = 1 then
            exit(Amounts.Get(Middle));
        exit(Round((Amounts.Get(Middle) + Amounts.Get(Middle + 1)) / 2));
    end;

    local procedure HasPayment(VendorNo: Code[20]): Boolean
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        VendorLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        VendorLedgerEntry.SetCurrentKey("Vendor No.", "Posting Date", "Applies-to ID");
        VendorLedgerEntry.SetRange("Vendor No.", VendorNo);
        VendorLedgerEntry.SetRange("Document Type", VendorLedgerEntry."Document Type"::Payment);
        VendorLedgerEntry.SetRange(Reversed, false);
        exit(not VendorLedgerEntry.IsEmpty());
    end;

    // Amounts in the line's own currency: the open amount can only be compared there.
    local procedure AddPaidFacts(FindingKey: Text; GenJournalLine: Record "Gen. Journal Line"; EntryCount: Integer; OpenAmount: Decimal; var RunContext: Codeunit "EXR Run Context"; var Detail: Text)
    var
        LineAmount: Text;
        StillOpen: Text;
    begin
        if EntryCount = 0 then begin
            RunContext.AddPhrase(FindingKey, PaidFactTok, NothingOpenLbl);
            AddSentence(Detail, PaidDetailLbl);
            exit;
        end;
        LineAmount := RunContext.FormatCurrencyAmount(GenJournalLine.Amount, GenJournalLine."Currency Code");
        StillOpen := RunContext.FormatCurrencyAmount(-OpenAmount, GenJournalLine."Currency Code");
        RunContext.AddPhrase(FindingKey, PaidFactTok, OverpaysLbl);
        RunContext.AddPhrase(FindingKey, LineAmountFactTok, LineAmount);
        RunContext.AddPhrase(FindingKey, OpenAmountFactTok, StillOpen);
        AddSentence(Detail, StrSubstNo(OverpaidDetailLbl, LineAmount, StillOpen));
    end;

    local procedure AddDuplicateFacts(FindingKey: Text; GenJournalLine: Record "Gen. Journal Line"; Invoice: Record "Vendor Ledger Entry"; Duplicate: Record "Vendor Ledger Entry"; Exact: Boolean; PaysBoth: Boolean; var RunContext: Codeunit "EXR Run Context"; var Detail: Text)
    var
        DaysApart: Integer;
    begin
        DaysApart := Abs(Duplicate."Posting Date" - Invoice."Posting Date");
        RunContext.AddDate(FindingKey, DuplicateDateFactTok, Duplicate."Posting Date");
        case DaysApart of
            0:
                RunContext.AddPhrase(FindingKey, DuplicateGapFactTok, SameDayLbl);
            else
                RunContext.AddPhrase(FindingKey, DuplicateGapFactTok, RunContext.CountPhrase(DaysApart, OneDayApartLbl, DaysApartLbl));
        end;
        RunContext.AddAmount(FindingKey, DuplicateAmountFactTok, Abs(Invoice."Amount (LCY)"));
        if Exact then
            RunContext.AddPhrase(FindingKey, DuplicateMatchFactTok, ExactMatchLbl)
        else
            RunContext.AddPhrase(FindingKey, DuplicateMatchFactTok, DigitsMatchLbl);
        if Duplicate.Open then
            RunContext.AddPhrase(FindingKey, DuplicateStatusFactTok, DuplicateOpenLbl)
        else
            RunContext.AddPhrase(FindingKey, DuplicateStatusFactTok, DuplicateClosedLbl);
        // the entry order only: whether the duplicate is closed is a fact of its own
        if Invoice."Entry No." > Duplicate."Entry No." then
            RunContext.AddPhrase(FindingKey, DuplicateOrderFactTok, EnteredLaterLbl)
        else
            RunContext.AddPhrase(FindingKey, DuplicateOrderFactTok, EnteredFirstLbl);
        case true of
            PaysBoth:
                RunContext.AddPhrase(FindingKey, DuplicateRunFactTok, PaysBothLbl);
            PaidByOtherLine(GenJournalLine, Duplicate):
                RunContext.AddPhrase(FindingKey, DuplicateRunFactTok, OtherLineLbl);
            else
                RunContext.AddPhrase(FindingKey, DuplicateRunFactTok, NotInRunLbl);
        end;
        RunContext.AddFindingContext(FindingKey, 'possibleDuplicateVendorInvoiceNo', Duplicate."External Document No.");
        RunContext.AddFindingContext(FindingKey, 'possibleDuplicateDescription', Duplicate.Description);
        RunContext.AddFindingContext(FindingKey, 'possibleDuplicateDocumentNo', Duplicate."Document No.");
        AddSentence(Detail, StrSubstNo(DuplicateDetailLbl, Duplicate."External Document No.", RunContext.FormatDate(Duplicate."Posting Date")));
    end;

    // Only the date and whether the payment goes to a changed account; the account itself is never named.
    local procedure AddBankFacts(FindingKey: Text; GenJournalLine: Record "Gen. Journal Line"; ChangedOn: Date; PaysChangedAccount: Boolean; var RunContext: Codeunit "EXR Run Context"; var Detail: Text)
    var
        DaysAgo: Integer;
    begin
        DaysAgo := Today() - ChangedOn;
        RunContext.AddDate(FindingKey, BankDateFactTok, ChangedOn);
        case DaysAgo of
            0:
                RunContext.AddPhrase(FindingKey, BankAgoFactTok, TodayLbl);
            else
                RunContext.AddPhrase(FindingKey, BankAgoFactTok, RunContext.CountPhrase(DaysAgo, OneDayAgoLbl, DaysAgoLbl));
        end;
        case true of
            PaysChangedAccount:
                RunContext.AddPhrase(FindingKey, BankTargetFactTok, PaysChangedLbl);
            GenJournalLine."Recipient Bank Account" = '':
                RunContext.AddPhrase(FindingKey, BankTargetFactTok, NoRecipientLbl);
            else
                RunContext.AddPhrase(FindingKey, BankTargetFactTok, PaysOtherLbl);
        end;
        AddSentence(Detail, StrSubstNo(BankDetailLbl, RunContext.FormatDate(ChangedOn)));
    end;

    local procedure AddAmountFacts(FindingKey: Text; Amount: Decimal; Median: Decimal; PaymentCount: Integer; var RunContext: Codeunit "EXR Run Context"; var Detail: Text)
    var
        AbovePct: Decimal;
    begin
        AbovePct := (Amount - Median) / Median * 100;
        RunContext.AddAmount(FindingKey, MedianFactTok, Median);
        RunContext.AddPhrase(FindingKey, PaymentCountFactTok, RunContext.CountPhrase(PaymentCount, OnePaymentLbl, PaymentsLbl));
        RunContext.AddPercent(FindingKey, AboveMedianFactTok, AbovePct);
        AddSentence(Detail, StrSubstNo(AmountDetailLbl, RunContext.FormatAmount(Amount), RunContext.FormatPercent(AbovePct), RunContext.FormatAmount(Median)));
    end;

    // Checks the line again right before writing: still in the batch, the same vendor and amount, the same open entries,
    // and not yet exported or printed. Then deletes it and holds what the finding is about; the kept Detail lists the holds.
    local procedure HoldPayment(ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; HoldCode: Code[3])
    var
        GenJournalLine: Record "Gen. Journal Line";
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        VendEntryEdit: Codeunit "Vend. Entry-Edit";
        EntryNos: List of [Integer];
        EntryNo: Integer;
        OpenAmount: Decimal;
        HeldInvoices: Text;
        Detail: Text;
        SameCurrency: Boolean;
        HoldsWholeLine: Boolean;
        HoldsDuplicate: Boolean;
    begin
        // read and then delete the same line: lock it
        GenJournalLine.ReadIsolation := IsolationLevel::UpdLock;
        if not GenJournalLine.GetBySystemId(TempFinding."Source System Id") then
            Error(LineChangedErr, TempFinding.Subject);
        FindAppliedEntries(GenJournalLine, EntryNos, OpenAmount, SameCurrency);
        if (GenJournalLine."Journal Template Name" <> ExrRun."Journal Template Name") or
           (GenJournalLine."Journal Batch Name" <> ExrRun."Journal Batch Name") or
           (GenJournalLine."Account Type" <> GenJournalLine."Account Type"::Vendor) or
           (GenJournalLine."Account No." <> TempFinding."Account No.") or
           (GenJournalLine."Amount (LCY)" <> TempFinding."Amount (LCY)") or
           (EntryNos.Count() <> TempFinding."Applied Entries") or
           (Checksum(EntryNos) <> TempFinding."Applied Entry Checksum")
        then
            Error(LineChangedErr, TempFinding.Subject);
        // the bank may already have the payment: deleting the line would only lose its record
        if IsIssued(GenJournalLine) then
            Error(LineIssuedErr, TempFinding.Subject);
        // the line's own delete trigger clears its application on the entries, as deleting it on the page does
        GenJournalLine.Delete(true);

        // a bank change, an unusual amount or a first payment concerns the whole line: every invoice it pays is held.
        // Otherwise only the possible duplicate is; a held invoice or a paid line needs no new hold. Credit memos never are.
        HoldsWholeLine := HasSignal(TempFinding."Finding Type", BankTok) or HasSignal(TempFinding."Finding Type", AmountTok) or HasSignal(TempFinding."Finding Type", FirstTok);
        HoldsDuplicate := HasSignal(TempFinding."Finding Type", DupCopyTok) or HasSignal(TempFinding."Finding Type", DuplicateTok) or HasSignal(TempFinding."Finding Type", NearDupTok);
        foreach EntryNo in EntryNos do
            if HoldsWholeLine or (HoldsDuplicate and (EntryNo = TempFinding."Ledger Entry No.")) then begin
                // the whole entry, read with a lock: Vend. Entry-Edit writes it back
                Clear(VendorLedgerEntry);
                VendorLedgerEntry.ReadIsolation := IsolationLevel::UpdLock;
                VendorLedgerEntry.Get(EntryNo);
                // an entry that is already on hold keeps its code
                if (VendorLedgerEntry."Document Type" = VendorLedgerEntry."Document Type"::Invoice) and (VendorLedgerEntry."On Hold" = '') then begin
                    VendEntryEdit.SetOnHold(VendorLedgerEntry, HoldCode);
                    if HeldInvoices <> '' then
                        HeldInvoices += ListSeparatorTok;
                    if VendorLedgerEntry."External Document No." <> '' then
                        HeldInvoices += VendorLedgerEntry."External Document No."
                    else
                        HeldInvoices += VendorLedgerEntry."Document No.";
                end;
            end;
        if HeldInvoices = '' then
            exit;
        Detail := TempFinding.Detail;
        AddSentence(Detail, StrSubstNo(HeldDetailLbl, HeldInvoices));
        TempFinding.Detail := CopyStr(Detail, 1, MaxStrLen(TempFinding.Detail));
        TempFinding.Modify();
    end;

    local procedure SignalAllows(Signal: Text; FindingAction: Enum "EXR Action"): Boolean
    begin
        case Signal of
            PaidTok, DupCopyTok, OnHoldTok:
                exit(FindingAction = Enum::"EXR Action"::Hold);
            DuplicateTok:
                exit(FindingAction in [Enum::"EXR Action"::Hold, Enum::"EXR Action"::"Ask vendor to confirm duplicate"]);
            NearDupTok:
                exit(FindingAction in [Enum::"EXR Action"::Pay, Enum::"EXR Action"::Hold, Enum::"EXR Action"::"Ask vendor to confirm duplicate"]);
            BankTok:
                exit(FindingAction in [Enum::"EXR Action"::Hold, Enum::"EXR Action"::"Verify bank details by phone"]);
            AmountTok:
                exit(FindingAction in [Enum::"EXR Action"::Pay, Enum::"EXR Action"::Hold]);
            FirstTok:
                exit(FindingAction in [Enum::"EXR Action"::Pay, Enum::"EXR Action"::Hold, Enum::"EXR Action"::"Verify bank details by phone"]);
        end;
        exit(false);
    end;

    // A paid line, the later copy of a duplicate and an invoice someone put on hold may only be held.
    local procedure IsHoldOnly(Signal: Text): Boolean
    begin
        exit(Signal in [PaidTok, DupCopyTok, OnHoldTok]);
    end;

    local procedure Signals(FindingType: Code[30]): List of [Text]
    var
        TypeText: Text;
    begin
        TypeText := FindingType;
        exit(TypeText.Split(SignalSeparatorTok));
    end;

    local procedure HasSignal(FindingType: Code[30]; Signal: Text): Boolean
    begin
        exit(Signals(FindingType).Contains(Signal));
    end;

    local procedure AddSignal(var FindingType: Text; Signal: Text; IsRaised: Boolean)
    begin
        if not IsRaised then
            exit;
        if FindingType <> '' then
            FindingType += SignalSeparatorTok;
        FindingType += Signal;
    end;

    local procedure AddSentence(var Detail: Text; Sentence: Text)
    begin
        if Detail = '' then
            Detail := Sentence
        else
            Detail := StrSubstNo(SentenceTok, Detail, Sentence);
    end;

    local procedure LineSubject(GenJournalLine: Record "Gen. Journal Line"; Vendor: Record Vendor; InvoiceEntry: Record "Vendor Ledger Entry"): Text
    begin
        if InvoiceEntry."External Document No." = '' then
            exit(StrSubstNo(SubjectLbl, GenJournalLine."Account No.", Vendor.Name, GenJournalLine."Document No."));
        exit(StrSubstNo(SubjectInvoiceLbl, GenJournalLine."Account No.", Vendor.Name, GenJournalLine."Document No.", InvoiceEntry."External Document No."));
    end;

    local procedure LineReference(GenJournalLine: Record "Gen. Journal Line"; InvoiceEntry: Record "Vendor Ledger Entry"): Text
    begin
        if InvoiceEntry."External Document No." = '' then
            exit(StrSubstNo(ReferenceLbl, GenJournalLine."Document No."));
        exit(StrSubstNo(ReferenceInvoiceLbl, GenJournalLine."Document No.", InvoiceEntry."External Document No."));
    end;

    // Entered after its possible duplicate, or the duplicate is already paid: this one is the copy.
    local procedure IsLaterCopy(Invoice: Record "Vendor Ledger Entry"; Duplicate: Record "Vendor Ledger Entry"): Boolean
    begin
        exit((not Duplicate.Open) or (Invoice."Entry No." > Duplicate."Entry No."));
    end;

    // In a payment file or on a printed check: the bank may pay it whatever happens to the line.
    local procedure IsIssued(GenJournalLine: Record "Gen. Journal Line"): Boolean
    begin
        exit(GenJournalLine."Exported to Payment File" or GenJournalLine."Check Printed" or GenJournalLine."Check Exported" or GenJournalLine."Check Transmitted");
    end;

    // With the count, shows that the line still pays the same entries as when it was checked.
    local procedure Checksum(EntryNos: List of [Integer]) Sum: BigInteger
    var
        EntryNo: Integer;
    begin
        foreach EntryNo in EntryNos do
            Sum += EntryNo;
    end;

    local procedure DigitsOnly(Value: Text): Text
    begin
        exit(DelChr(Value, '=', DelChr(Value, '=', DigitsTok)));
    end;

    // MinValue and MaxValue are checked only through Validate, so the bounds are applied here too.
    local procedure Bounded(Days: Integer): Integer
    begin
        if Days < 0 then
            exit(0);
        if Days > 3650 then
            exit(3650);
        exit(Days);
    end;
}
