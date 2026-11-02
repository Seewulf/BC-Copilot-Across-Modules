namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.CRM.Team;
using Microsoft.Finance.GeneralLedger.Account;
using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Finance.GeneralLedger.Posting;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Sales.Receivables;
using Microsoft.Sales.Reminder;
using PrabinBhusal.ExplainResolve;

// Receivables scenarios for Plan collections, built with standard posting only. Customers get readable fictional names and
// numbers (EXR-C0001) and a salesperson of their own, so a run filtered on that salesperson never picks up CRONUS customers.
// Invoices and payments are posted as customer journal lines (Gen. Jnl.-Post Line), which gives the same customer ledger
// entries as posted sales invoices and runs much faster, but no posted sales invoice document to show or navigate to.
codeunit 58283 "EXR Collections Library"
{
    var
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        TemplatesLoaded: Boolean;
        CustomerPostingGroupCode: Code[20];
        GenBusPostingGroup: Code[20];
        VATBusPostingGroup: Code[20];
        GenProdPostingGroup: Code[20];
        VATProdPostingGroup: Code[20];
        BalanceAccountNo: Code[20];
        JournalTemplateName: Code[10];
        JournalBatchName: Code[10];
        CronusCustomerTok: Label '10000', Locked = true;
        CustomerPrefixTok: Label 'EXR-C', Locked = true;
        SalespersonPrefixTok: Label 'EXR-SP', Locked = true;
        PostingGroupPrefixTok: Label 'EXR-CPG', Locked = true;
        InvoicePrefixTok: Label 'EXR-SI', Locked = true;
        PaymentPrefixTok: Label 'EXR-PM', Locked = true;
        CreditMemoPrefixTok: Label 'EXR-CM', Locked = true;
        OnHoldCodeTok: Label 'HLD', Locked = true;
        FirstCounterTok: Label '0001', Locked = true;
        StartsWithTok: Label '%1*', Locked = true;
        SalespersonNameTok: Label 'Collections demo team', Locked = true;
        DisputeCodeTok: Label 'DISPUTE', Locked = true;
        DisputeDescriptionTok: Label 'Disputed by the customer', Locked = true;
        InvoiceDescriptionTok: Label 'Office furniture', Locked = true;
        PaymentDescriptionTok: Label 'Payment received', Locked = true;
        CreditMemoDescriptionTok: Label 'Invoice cancelled', Locked = true;
        AdatumTok: Label 'Adatum Interiors Ltd.', Locked = true;
        FabrikamTok: Label 'Fabrikam Office Supplies', Locked = true;
        LitwareTok: Label 'Litware Workspace Co.', Locked = true;
        TailspinTok: Label 'Tailspin Fit-Out Ltd.', Locked = true;
        WingtipTok: Label 'Wingtip Studios', Locked = true;
#pragma warning disable AA0240
        // a reserved example.com address for the demo customers, never a real one
        CustomerEmailTok: Label 'payables@example.com', Locked = true;
#pragma warning restore AA0240
        CustomerFilterTok: Label '%1|%2', Locked = true;
        EntryFingerprintTok: Label '%1|%2|%3|%4|%5|%6|%7|%8;', Locked = true;
        CustomerFingerprintTok: Label '%1|%2|%3;', Locked = true;
        LedgerFingerprintTok: Label 'customer entries %1, details %2, reminders %3, issued reminders %4', Locked = true;
        NoBalanceAccountErr: Label 'No direct-posting G/L account without a general posting type was found to balance the customer journal lines.', Locked = true;

    // A customer with the demo email address and a posting group copied from an existing customer.
    procedure CreateCustomer(Name: Text[100]; SalespersonCode: Code[20]): Code[20]
    var
        Customer: Record Customer;
    begin
        LoadTemplates();
        Customer.Init();
        Customer."No." := ScenarioLibrary.NextNo(Database::Customer, CustomerPrefixTok);
        Customer.Name := Name;
        Customer.Insert(true);
        Customer."Customer Posting Group" := CustomerPostingGroupCode;
        Customer."Gen. Bus. Posting Group" := GenBusPostingGroup;
        Customer."VAT Bus. Posting Group" := VATBusPostingGroup;
        Customer."Salesperson Code" := SalespersonCode;
        Customer."E-Mail" := CustomerEmailTok;
        Customer.Modify(true);
        exit(Customer."No.");
    end;

    procedure CreateSalesperson(): Code[20]
    var
        SalespersonPurchaser: Record "Salesperson/Purchaser";
    begin
        SalespersonPurchaser.Init();
        SalespersonPurchaser.Code := ScenarioLibrary.NextNo(Database::"Salesperson/Purchaser", SalespersonPrefixTok);
        SalespersonPurchaser.Name := SalespersonNameTok;
        SalespersonPurchaser.Insert(true);
        exit(SalespersonPurchaser.Code);
    end;

    // A copy of the template group, with the same accounts, so invoices still post.
    procedure CreateCustomerPostingGroup(): Code[20]
    var
        CopyFromGroup: Record "Customer Posting Group";
        CustomerPostingGroup: Record "Customer Posting Group";
    begin
        LoadTemplates();
        CopyFromGroup.Get(CustomerPostingGroupCode);
        CustomerPostingGroup := CopyFromGroup;
        CustomerPostingGroup.Code := ScenarioLibrary.NextNo(Database::"Customer Posting Group", PostingGroupPrefixTok);
        CustomerPostingGroup.Insert();
        exit(CustomerPostingGroup.Code);
    end;

    procedure SetCustomerPostingGroup(CustomerNo: Code[20]; PostingGroupCode: Code[20])
    var
        Customer: Record Customer;
    begin
        Customer.Get(CustomerNo);
        Customer."Customer Posting Group" := PostingGroupCode;
        Customer.Modify();
    end;

    procedure SetCreditLimit(CustomerNo: Code[20]; CreditLimit: Decimal)
    var
        Customer: Record Customer;
    begin
        Customer.Get(CustomerNo);
        Customer."Credit Limit (LCY)" := CreditLimit;
        Customer.Modify();
    end;

    // Days are relative to the work date: PostInvoice(No, -60, -30, 1000) posts 60 days ago, due 30 days ago.
    procedure PostInvoice(CustomerNo: Code[20]; PostingDays: Integer; DueDays: Integer; Amount: Decimal) DocumentNo: Code[20]
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
    begin
        DocumentNo := NextDocumentNo(InvoicePrefixTok);
        InitJournalLine(GenJournalLine, Enum::"Gen. Journal Document Type"::Invoice, DocumentNo, CustomerNo, WorkDate() + PostingDays, Amount);
        GenJournalLine.Description := InvoiceDescriptionTok;
        // also satisfies setups where the external document number is mandatory
        GenJournalLine."External Document No." := DocumentNo;
        GenJournalLine."Due Date" := WorkDate() + DueDays;
        GenJnlPostLine.RunWithCheck(GenJournalLine);
    end;

    // A payment applied to one invoice: the full amount closes it on the payment date, less leaves it open.
    // Without an invoice number the payment stays open, not yet applied.
    procedure PostPayment(CustomerNo: Code[20]; PostingDays: Integer; Amount: Decimal; InvoiceNo: Code[20])
    begin
        PostCredit(Enum::"Gen. Journal Document Type"::Payment, PaymentPrefixTok, PaymentDescriptionTok, CustomerNo, PostingDays, Amount, InvoiceNo);
    end;

    // A credit memo applied to one invoice, such as a cancelled invoice: it closes the invoice without a payment.
    procedure PostCreditMemo(CustomerNo: Code[20]; PostingDays: Integer; Amount: Decimal; InvoiceNo: Code[20])
    begin
        PostCredit(Enum::"Gen. Journal Document Type"::"Credit Memo", CreditMemoPrefixTok, CreditMemoDescriptionTok, CustomerNo, PostingDays, Amount, InvoiceNo);
    end;

    procedure PayInvoice(CustomerNo: Code[20]; InvoiceNo: Code[20]; PaymentDays: Integer)
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        FindInvoiceEntry(InvoiceNo, CustLedgerEntry);
        CustLedgerEntry.CalcFields("Remaining Amount");
        PostPayment(CustomerNo, PaymentDays, CustLedgerEntry."Remaining Amount", InvoiceNo);
    end;

    // Test data only: the app itself never writes to customer ledger entries.
    procedure SetPromisedPayDate(InvoiceNo: Code[20]; PromisedDays: Integer)
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        FindInvoiceEntry(InvoiceNo, CustLedgerEntry);
        CustLedgerEntry."Promised Pay Date" := WorkDate() + PromisedDays;
        CustLedgerEntry.Modify();
    end;

    procedure SetDisputed(InvoiceNo: Code[20])
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        FindInvoiceEntry(InvoiceNo, CustLedgerEntry);
        CustLedgerEntry."Dispute Status" := DisputeStatusCode();
        CustLedgerEntry.Modify();
    end;

    // On Hold stops the standard reminders for the entry, like a dispute.
    procedure SetOnHold(InvoiceNo: Code[20])
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        FindInvoiceEntry(InvoiceNo, CustLedgerEntry);
        CustLedgerEntry."On Hold" := OnHoldCodeTok;
        CustLedgerEntry.Modify();
    end;

    procedure DisputeStatusCode(): Code[10]
    var
        DisputeStatus: Record "Dispute Status";
    begin
        if not DisputeStatus.Get(DisputeCodeTok) then begin
            DisputeStatus.Init();
            DisputeStatus.Code := DisputeCodeTok;
            DisputeStatus.Description := DisputeDescriptionTok;
            DisputeStatus.Insert();
        end;
        exit(DisputeStatus.Code);
    end;

    // An open sales order with one G/L line, so the customer has an outstanding order amount.
    procedure CreateSalesOrder(CustomerNo: Code[20]; UnitPrice: Decimal)
    begin
        CreateSalesDocument(Enum::"Sales Document Type"::Order, CustomerNo, UnitPrice);
    end;

    // An open sales document with one G/L line, not posted, such as an invoice that counts against the credit limit.
    procedure CreateSalesDocument(DocumentType: Enum "Sales Document Type"; CustomerNo: Code[20]; UnitPrice: Decimal)
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        LoadTemplates();
        SalesHeader.Init();
        SalesHeader."Document Type" := DocumentType;
        SalesHeader.Insert(true);
        SalesHeader.SetHideValidationDialog(true);
        SalesHeader.Validate("Sell-to Customer No.", CustomerNo);
        SalesHeader.Modify(true);
        SalesLine.Init();
        SalesLine."Document Type" := SalesHeader."Document Type";
        SalesLine."Document No." := SalesHeader."No.";
        SalesLine."Line No." := 10000;
        SalesLine.Insert(true);
        SalesLine.SetHideValidationDialog(true);
        SalesLine.Validate(Type, SalesLine.Type::"G/L Account");
        SalesLine.Validate("No.", BalanceAccountNo);
        SalesLine.Validate("Gen. Prod. Posting Group", GenProdPostingGroup);
        SalesLine.Validate("VAT Prod. Posting Group", VATProdPostingGroup);
        SalesLine.Validate(Quantity, 1);
        SalesLine.Validate("Unit Price", UnitPrice);
        SalesLine.Modify(true);
    end;

    // The demo for a credit controller, as of the work date (W):
    // Adatum: a part-paid invoice due W-60 and one due W-45 whose promised payment date W-10 has passed; usually pays 20 days late.
    // Fabrikam: a disputed invoice due W-50 and one not due until W+10. Litware: invoices due W-55 and W-25, nothing special.
    // Tailspin: an invoice due W-40 and an open order that nearly use its 5,000 credit limit. Wingtip: posted W-45, not due yet.
    // Returns the salesperson the demo customers share, to filter the dialog on.
    procedure CreateDemoScenario(var CustomerFilter: Text) SalespersonCode: Code[20]
    var
        AdatumNo: Code[20];
        FabrikamNo: Code[20];
        LitwareNo: Code[20];
        TailspinNo: Code[20];
        WingtipNo: Code[20];
        InvoiceNo: Code[20];
    begin
        SalespersonCode := CreateSalesperson();
        AdatumNo := CreateCustomer(AdatumTok, SalespersonCode);
        InvoiceNo := PostInvoice(AdatumNo, -200, -170, 2400);
        PayInvoice(AdatumNo, InvoiceNo, -150);
        InvoiceNo := PostInvoice(AdatumNo, -90, -60, 4000);
        PostPayment(AdatumNo, -30, 1500, InvoiceNo);
        InvoiceNo := PostInvoice(AdatumNo, -75, -45, 1800);
        SetPromisedPayDate(InvoiceNo, -10);

        FabrikamNo := CreateCustomer(FabrikamTok, SalespersonCode);
        InvoiceNo := PostInvoice(FabrikamNo, -80, -50, 3200);
        SetDisputed(InvoiceNo);
        PostInvoice(FabrikamNo, -20, 10, 900);

        LitwareNo := CreateCustomer(LitwareTok, SalespersonCode);
        PostInvoice(LitwareNo, -85, -55, 1200);
        PostInvoice(LitwareNo, -55, -25, 2000);

        TailspinNo := CreateCustomer(TailspinTok, SalespersonCode);
        PostInvoice(TailspinNo, -70, -40, 4600);
        CreateSalesOrder(TailspinNo, 300);
        // after the order, so creating it raises no credit warning
        SetCreditLimit(TailspinNo, 5000);

        WingtipNo := CreateCustomer(WingtipTok, SalespersonCode);
        PostInvoice(WingtipNo, -45, 15, 2500);

        CustomerFilter := StrSubstNo(CustomerFilterTok, StrSubstNo(CustomerFilterTok, StrSubstNo(CustomerFilterTok, AdatumNo, FabrikamNo), StrSubstNo(CustomerFilterTok, LitwareNo, TailspinNo)), WingtipNo);
    end;

    procedure NewRun(SalespersonCode: Code[20]; var ExrRun: Record "EXR Run")
    begin
        Clear(ExrRun);
        ExrRun.Capability := ExrRun.Capability::Collections;
        ExrRun."Source Table No." := Database::Customer;
        ExrRun."Salesperson Code" := SalespersonCode;
        ExrRun."Max. Customers" := 10;
        ExrRun."Email Tone" := ExrRun."Email Tone"::Firm;
    end;

    // Runs the detectors only, without the AI service.
    procedure FindCollections(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary)
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

    procedure GetFinding(var TempFinding: Record "EXR Finding" temporary; CustomerNo: Code[20]): Boolean
    var
        Customer: Record Customer;
    begin
        Customer.SetLoadFields("No.");
        Customer.Get(CustomerNo);
        TempFinding.Reset();
        TempFinding.SetRange("Source System Id", Customer.SystemId);
        exit(TempFinding.FindFirst());
    end;

    // One finding of a reply in the per-customer schema; subject and body are empty unless the action is Email reminder.
    procedure FindingReply(FindingKey: Text; Explanation: Text; ActionName: Text; EmailSubject: Text; EmailBody: Text) Finding: JsonObject
    begin
        Finding.Add('key', FindingKey);
        Finding.Add('explanation', Explanation);
        Finding.Add('action', ActionName);
        Finding.Add('confidence', 'High');
        Finding.Add('emailSubject', EmailSubject);
        Finding.Add('emailBody', EmailBody);
    end;

    procedure Reply(Summary: Text; Findings: JsonArray) ReplyText: Text
    var
        ReplyJson: JsonObject;
    begin
        ReplyJson.Add('summary', Summary);
        ReplyJson.Add('findings', Findings);
        ReplyJson.WriteTo(ReplyText);
    end;

    procedure CustomerEmail(): Text
    begin
        exit(CustomerEmailTok);
    end;

    // Equal before and after a run proves that no ledger entry, promise, dispute, hold, credit limit or reminder changed.
    procedure CustomerFingerprint(CustomerNo: Code[20]) Fingerprint: Text
    var
        Customer: Record Customer;
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        Customer.SetLoadFields("Credit Limit (LCY)", Blocked, "Salesperson Code");
        Customer.Get(CustomerNo);
        Fingerprint := StrSubstNo(CustomerFingerprintTok, Customer."Credit Limit (LCY)", Customer.Blocked, Customer."Salesperson Code");
        CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        CustLedgerEntry.SetLoadFields("Entry No.", Open, "Due Date", "Promised Pay Date", "Dispute Status", "On Hold", "Closed at Date");
        CustLedgerEntry.SetAutoCalcFields("Remaining Amount");
        if CustLedgerEntry.FindSet() then
            repeat
                Fingerprint += StrSubstNo(EntryFingerprintTok, CustLedgerEntry."Entry No.", CustLedgerEntry.Open, CustLedgerEntry."Remaining Amount", CustLedgerEntry."Due Date",
                    CustLedgerEntry."Promised Pay Date", CustLedgerEntry."Dispute Status", CustLedgerEntry."On Hold", CustLedgerEntry."Closed at Date");
            until CustLedgerEntry.Next() = 0;
    end;

    procedure ReceivablesFingerprint(): Text
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        DetailedCustLedgEntry: Record "Detailed Cust. Ledg. Entry";
        ReminderHeader: Record "Reminder Header";
        IssuedReminderHeader: Record "Issued Reminder Header";
    begin
        exit(StrSubstNo(LedgerFingerprintTok, CustLedgerEntry.Count(), DetailedCustLedgEntry.Count(), ReminderHeader.Count(), IssuedReminderHeader.Count()));
    end;

    local procedure PostCredit(DocumentType: Enum "Gen. Journal Document Type"; Prefix: Text; Description: Text[100]; CustomerNo: Code[20]; PostingDays: Integer; Amount: Decimal; InvoiceNo: Code[20])
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
    begin
        InitJournalLine(GenJournalLine, DocumentType, NextDocumentNo(Prefix), CustomerNo, WorkDate() + PostingDays, -Amount);
        GenJournalLine.Description := Description;
        if InvoiceNo <> '' then begin
            GenJournalLine."Applies-to Doc. Type" := GenJournalLine."Applies-to Doc. Type"::Invoice;
            GenJournalLine."Applies-to Doc. No." := InvoiceNo;
        end;
        GenJnlPostLine.RunWithCheck(GenJournalLine);
    end;

    local procedure FindInvoiceEntry(InvoiceNo: Code[20]; var CustLedgerEntry: Record "Cust. Ledger Entry")
    begin
        CustLedgerEntry.SetCurrentKey("Document No.");
        CustLedgerEntry.SetRange("Document No.", InvoiceNo);
        CustLedgerEntry.SetRange("Document Type", CustLedgerEntry."Document Type"::Invoice);
        CustLedgerEntry.FindFirst();
    end;

    local procedure InitJournalLine(var GenJournalLine: Record "Gen. Journal Line"; DocumentType: Enum "Gen. Journal Document Type"; DocumentNo: Code[20]; CustomerNo: Code[20]; PostingDate: Date; Amount: Decimal)
    begin
        LoadTemplates();
        GenJournalLine.Init();
        GenJournalLine."Journal Template Name" := JournalTemplateName;
        GenJournalLine."Journal Batch Name" := JournalBatchName;
        GenJournalLine."Line No." := 10000;
        GenJournalLine.Validate("Posting Date", PostingDate);
        GenJournalLine.Validate("Document Type", DocumentType);
        GenJournalLine."Document No." := DocumentNo;
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Customer);
        GenJournalLine.Validate("Account No.", CustomerNo);
        GenJournalLine.Validate("Bal. Account Type", GenJournalLine."Bal. Account Type"::"G/L Account");
        GenJournalLine.Validate("Bal. Account No.", BalanceAccountNo);
        GenJournalLine.Validate(Amount, Amount);
    end;

    // Document numbers are unique per run too: EXR-SI0001, EXR-SI0002 and so on.
    local procedure NextDocumentNo(Prefix: Text): Code[20]
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        CustLedgerEntry.SetCurrentKey("Document No.");
        CustLedgerEntry.SetFilter("Document No.", StrSubstNo(StartsWithTok, Prefix));
        CustLedgerEntry.SetLoadFields("Document No.");
        if CustLedgerEntry.FindLast() then
            exit(CopyStr(IncStr(CustLedgerEntry."Document No."), 1, 20));
        exit(CopyStr(Prefix + FirstCounterTok, 1, 20));
    end;

    local procedure LoadTemplates()
    var
        Customer: Record Customer;
        GenJournalTemplate: Record "Gen. Journal Template";
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        if TemplatesLoaded then
            exit;
        ScenarioLibrary.GetPostingGroups(GenBusPostingGroup, VATBusPostingGroup, GenProdPostingGroup, VATProdPostingGroup);
        Customer.SetLoadFields("Customer Posting Group");
        if not Customer.Get(CronusCustomerTok) or (Customer."Customer Posting Group" = '') then begin
            Customer.Reset();
            Customer.SetFilter("Customer Posting Group", '<>%1', '');
            Customer.FindFirst();
        end;
        CustomerPostingGroupCode := Customer."Customer Posting Group";
        BalanceAccountNo := FindBalanceAccount();
        // some localisations require a journal template and batch on every line
        GenJournalTemplate.SetRange(Type, GenJournalTemplate.Type::General);
        GenJournalTemplate.SetRange(Recurring, false);
        if GenJournalTemplate.FindFirst() then begin
            JournalTemplateName := GenJournalTemplate.Name;
            GenJournalBatch.SetRange("Journal Template Name", GenJournalTemplate.Name);
            if GenJournalBatch.FindFirst() then
                JournalBatchName := GenJournalBatch.Name;
        end;
        TemplatesLoaded := true;
    end;

    // No general posting type, so the journal lines carry no VAT and the customer entry equals the amount.
    local procedure FindBalanceAccount(): Code[20]
    var
        GLAccount: Record "G/L Account";
    begin
        GLAccount.SetRange("Account Type", GLAccount."Account Type"::Posting);
        GLAccount.SetRange("Direct Posting", true);
        GLAccount.SetRange(Blocked, false);
        GLAccount.SetRange("Gen. Posting Type", GLAccount."Gen. Posting Type"::" ");
        GLAccount.SetRange("Income/Balance", GLAccount."Income/Balance"::"Income Statement");
        GLAccount.SetLoadFields("No.");
        if GLAccount.FindFirst() then
            exit(GLAccount."No.");
        GLAccount.SetRange("Income/Balance");
        if GLAccount.FindFirst() then
            exit(GLAccount."No.");
        Error(NoBalanceAccountErr);
    end;
}
