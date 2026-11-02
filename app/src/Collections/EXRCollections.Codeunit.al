namespace PrabinBhusal.ExplainResolve;

using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Sales.Receivables;
using System.AI;

// Plan collections: AL ranks the customers with overdue entries as of the work date, in LCY, by a priority score.
// Keep it saves the reviewed worklist and the reminder drafts. Ledger entries, promises, disputes and credit limits are never changed.
codeunit 58207 "EXR Collections" implements "EXR Capability Handler"
{
    Access = Internal;

    var
        PromptTok: Label 'collections.md', Locked = true;
        FindingKeyTok: Label '%1-%2', Locked = true;
        SubjectTok: Label '%1 %2', Locked = true;
        SentenceTok: Label '%1 %2', Locked = true;
        OverdueTok: Label 'OVERDUE', Locked = true;
        PromiseBrokenTok: Label 'PROMISE_BROKEN', Locked = true;
        PromisePendingTok: Label 'PROMISE_PENDING', Locked = true;
        DisputeTok: Label 'DISPUTE', Locked = true;
        CreditRiskTok: Label 'CREDIT_RISK', Locked = true;
        // fact captions are read by the model only
        AsOfFactTok: Label 'as-of date', Locked = true;
        CustomersFoundFactTok: Label 'customers with overdue entries, as a phrase', Locked = true;
        CustomersShownFactTok: Label 'customers in this plan, as a phrase', Locked = true;
        PlanOverdueFactTok: Label 'total overdue of the customers in this plan', Locked = true;
        RankFactTok: Label 'rank in this plan', Locked = true;
        ScoreFactTok: Label 'priority score', Locked = true;
        Bucket1FactTok: Label 'overdue 1-30 days', Locked = true;
        Bucket2FactTok: Label 'overdue 31-60 days', Locked = true;
        Bucket3FactTok: Label 'overdue 61-90 days', Locked = true;
        Bucket4FactTok: Label 'overdue more than 90 days', Locked = true;
        TotalOverdueFactTok: Label 'total overdue', Locked = true;
        OverdueCountFactTok: Label 'overdue documents, as a phrase', Locked = true;
        OldestDueFactTok: Label 'oldest due date', Locked = true;
        OldestDaysFactTok: Label 'days the oldest document is overdue, as a phrase', Locked = true;
        AverageLateFactTok: Label 'usual delay: average days late on invoices paid in the last 12 months, as a phrase', Locked = true;
        PaidCountFactTok: Label 'invoices paid in the last 12 months, as a phrase', Locked = true;
        BrokenDateFactTok: Label 'promised payment date that has passed', Locked = true;
        BrokenAmountFactTok: Label 'amount that was promised and not paid', Locked = true;
        PendingDateFactTok: Label 'promised payment date still to come', Locked = true;
        PendingAmountFactTok: Label 'amount promised', Locked = true;
        DisputedFactTok: Label 'amount disputed or on hold', Locked = true;
        CreditLimitFactTok: Label 'credit limit', Locked = true;
        CreditUsedFactTok: Label 'credit limit used, including sales orders, shipments and invoices not yet posted', Locked = true;
        OpenOrdersFactTok: Label 'open sales orders', Locked = true;
        UnappliedFactTok: Label 'payments and credit memos not yet applied', Locked = true;
        OneDocumentLbl: Label '%1 document', Comment = '%1 = number of documents (1)';
        DocumentsLbl: Label '%1 documents', Comment = '%1 = number of documents';
        OneDayLbl: Label '%1 day', Comment = '%1 = number of days (1)';
        DaysLbl: Label '%1 days', Comment = '%1 = number of days';
        OneInvoiceLbl: Label '%1 invoice', Comment = '%1 = number of invoices (1)';
        InvoicesLbl: Label '%1 invoices', Comment = '%1 = number of invoices';
        OneCustomerLbl: Label '%1 customer', Comment = '%1 = number of customers (1)';
        CustomersLbl: Label '%1 customers', Comment = '%1 = number of customers';
        DetailLbl: Label '%1 overdue on %2; the oldest is %3 overdue.', Comment = '%1 = amount, %2 = number of documents, for example 2 documents, %3 = days, for example 45 days';
        OneDocumentDetailLbl: Label '%1 overdue on one document, by %2.', Comment = '%1 = amount, %2 = days, for example 45 days';
        BrokenPromiseLbl: Label 'The payment promised for %1 has not arrived.', Comment = '%1 = date';
        PendingPromiseLbl: Label 'Payment is promised for %1.', Comment = '%1 = date';
        DisputedLbl: Label '%1 is disputed or on hold.', Comment = '%1 = amount';
        UnappliedLbl: Label '%1 in payments or credit memos is not yet applied.', Comment = '%1 = amount';
        CreditUsedLbl: Label 'Credit limit %1 used, including sales orders, shipments and invoices not yet posted.', Comment = '%1 = percentage';
        EmailLineLbl: Label '- %1 %2, due %3, %4 overdue: %5', Comment = '%1 = document type, %2 = document number, %3 = due date, %4 = days, for example 45 days, %5 = amount outstanding';
        EmailCreditLineLbl: Label '- %1 %2, not yet applied: %3', Comment = '%1 = document type, for example Payment, %2 = document number, %3 = amount, negative';
        EmailTotalLbl: Label 'Total overdue: %1', Comment = '%1 = amount';
        EmailNetTotalLbl: Label 'Total overdue, less payments and credits not yet applied: %1', Comment = '%1 = amount';
        KeptCustomersMsg: Label 'Review saved with %1. Open a customer card to see its latest review in the Collections review panel.', Comment = '%1 = number of customers, for example 3 customers';
        OneDraftSavedMsg: Label 'One reminder email is saved as a draft in your email outbox.';
        DraftsSavedMsg: Label '%1 reminder emails are saved as drafts in your email outbox.', Comment = '%1 = number of emails';
        OneDraftKeptMsg: Label 'No email account is set up, so one reminder email is kept on the review. Open it there with Open Email.';
        DraftsKeptMsg: Label 'No email account is set up, so %1 reminder emails are kept on the review. Open them there with Open Email.', Comment = '%1 = number of emails';

    procedure CopilotCapability(): Enum "Copilot Capability"
    begin
        exit(Enum::"Copilot Capability"::"EXR Collections");
    end;

    procedure PromptResourceName(): Text
    begin
        exit(PromptTok);
    end;

    procedure UsesTolerance(): Boolean
    begin
        exit(false);
    end;

    procedure ReviewsSelection(): Boolean
    begin
        exit(true);
    end;

    procedure DraftsEmailPerFinding(): Boolean
    begin
        exit(true);
    end;

    // Per finding type, so the model cannot chase a disputed debt or ignore a broken promise.
    procedure IsActionAllowed(FindingType: Code[30]; FindingAction: Enum "EXR Action"): Boolean
    begin
        case FindingType of
            DisputeTok:
                exit(FindingAction in [Enum::"EXR Action"::"Resolve dispute first", Enum::"EXR Action"::"Phone call"]);
            PromisePendingTok:
                exit(FindingAction in [Enum::"EXR Action"::"Wait - promise pending", Enum::"EXR Action"::"Phone call"]);
            PromiseBrokenTok:
                exit(FindingAction in [Enum::"EXR Action"::"Phone call", Enum::"EXR Action"::"Email reminder", Enum::"EXR Action"::"Credit review - hold new orders"]);
            CreditRiskTok, OverdueTok:
                exit(FindingAction in [Enum::"EXR Action"::"Email reminder", Enum::"EXR Action"::"Phone call", Enum::"EXR Action"::"Credit review - hold new orders"]);
        end;
        exit(false);
    end;

    // One finding per customer, in rank order, for the top Max. Customers. Customers with nothing overdue are never listed.
    procedure BuildFacts(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        TempCollectionCustomer: Record "EXR Collection Customer" temporary;
        AsOfDate: Date;
        Found: Integer;
        Shown: Integer;
        PlanOverdue: Decimal;
    begin
        AsOfDate := WorkDate();
        CollectCustomers(ExrRun, AsOfDate, TempCollectionCustomer, RunContext);
        Found := TempCollectionCustomer.Count();
        RunContext.AddDate('', AsOfFactTok, AsOfDate);
        if ExrRun."Salesperson Code" <> '' then
            RunContext.AddContext('salespersonFilter', ExrRun."Salesperson Code");
        if ExrRun."Customer Posting Group" <> '' then
            RunContext.AddContext('customerPostingGroupFilter', ExrRun."Customer Posting Group");
        TempCollectionCustomer.SetCurrentKey(Score, "Total Overdue");
        TempCollectionCustomer.Ascending(false);
        if TempCollectionCustomer.FindSet() then
            repeat
                Shown += 1;
                PlanOverdue += TempCollectionCustomer."Total Overdue";
                AddCustomerFinding(TempCollectionCustomer, Shown, AsOfDate, TempFinding, RunContext);
            until (TempCollectionCustomer.Next() = 0) or (Shown >= MaxCustomers(ExrRun));
        RunContext.AddPhrase('', CustomersFoundFactTok, RunContext.CountPhrase(Found, OneCustomerLbl, CustomersLbl));
        RunContext.AddPhrase('', CustomersShownFactTok, RunContext.CountPhrase(Shown, OneCustomerLbl, CustomersLbl));
        RunContext.AddAmount('', PlanOverdueFactTok, PlanOverdue);
    end;

    // The customer's overdue entries as of the work date, read from the ledger by AL, each in the currency it was posted in.
    procedure BuildEmailTable(var TempFinding: Record "EXR Finding" temporary) EmailTable: Text
    begin
        if TempFinding.FindSet() then
            repeat
                if TempFinding."Action" = Enum::"EXR Action"::"Email reminder" then begin
                    if EmailTable <> '' then
                        EmailTable += NewLine() + NewLine();
                    EmailTable += CustomerEmailTable(TempFinding."Source System Id");
                end;
            until TempFinding.Next() = 0;
    end;

    // The only writes are on the findings themselves: the recipient from the customer card and the draft flag.
    // A finding whose action is not Email reminder keeps no email.
    procedure ApplyKeep(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary): Text
    var
        Customer: Record Customer;
        EmailDraft: Codeunit "EXR Email Draft";
        RunContext: Codeunit "EXR Run Context";
        Customers: Integer;
        Emails: Integer;
        DraftsSaved: Boolean;
    begin
        if TempFinding.FindSet() then
            repeat
                Customers += 1;
                if (TempFinding."Action" <> Enum::"EXR Action"::"Email reminder") or (TempFinding."Email Subject" = '') then begin
                    TempFinding."Email Subject" := '';
                    TempFinding.SetEmailBody('');
                end else begin
                    Emails += 1;
                    Customer.SetLoadFields("E-Mail");
                    if Customer.GetBySystemId(TempFinding."Source System Id") then
                        TempFinding."Email To" := Customer."E-Mail";
                    TempFinding."Email Draft Saved" := EmailDraft.SaveFindingDraft(TempFinding);
                    DraftsSaved := TempFinding."Email Draft Saved";
                end;
                TempFinding.Modify();
            until TempFinding.Next() = 0;
        exit(KeptMessage(RunContext.CountPhrase(Customers, OneCustomerLbl, CustomersLbl), Emails, DraftsSaved));
    end;

    // Every customer with an open debt due before the as-of date that matches the dialog's filters, with its signals and score.
    // With a filter, only the filtered customers' entries are read; without one, a single pass over the overdue entries.
    local procedure CollectCustomers(ExrRun: Record "EXR Run"; AsOfDate: Date; var TempCollectionCustomer: Record "EXR Collection Customer" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        Customer: Record Customer;
        Excluded: List of [Code[20]];
    begin
        if (ExrRun."Salesperson Code" = '') and (ExrRun."Customer Posting Group" = '') then
            ReadOverdueEntries(ExrRun, '', AsOfDate, TempCollectionCustomer, Excluded, RunContext)
        else begin
            Customer.ReadIsolation := IsolationLevel::ReadCommitted;
            SetCustomerFilters(ExrRun, Customer);
            Customer.SetLoadFields("No.");
            if Customer.FindSet() then
                repeat
                    ReadOverdueEntries(ExrRun, Customer."No.", AsOfDate, TempCollectionCustomer, Excluded, RunContext);
                until Customer.Next() = 0;
        end;

        TempCollectionCustomer.Reset();
        if TempCollectionCustomer.FindSet() then
            repeat
                AddUnappliedCredits(AsOfDate, TempCollectionCustomer);
                // payments or credit memos not yet applied already cover what is overdue: nothing to chase
                if TempCollectionCustomer."Unapplied Credits" >= TempCollectionCustomer."Total Overdue" then
                    TempCollectionCustomer.Delete()
                else begin
                    AddPaymentHistory(AsOfDate, TempCollectionCustomer);
                    TempCollectionCustomer.Score := PriorityScore(TempCollectionCustomer, AsOfDate);
                    TempCollectionCustomer.Modify();
                end;
            until TempCollectionCustomer.Next() = 0;
    end;

    // Open debts due before the as-of date, of one customer (CustomerNo set) or of all customers.
    local procedure ReadOverdueEntries(ExrRun: Record "EXR Run"; CustomerNo: Code[20]; AsOfDate: Date; var TempCollectionCustomer: Record "EXR Collection Customer" temporary; var Excluded: List of [Code[20]]; var RunContext: Codeunit "EXR Run Context")
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        // a worklist that feeds no write: read committed, no lock
        CustLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        if CustomerNo <> '' then begin
            CustLedgerEntry.SetCurrentKey("Customer No.", Open, Positive, "Due Date", "Currency Code");
            CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        end else
            CustLedgerEntry.SetCurrentKey(Open, "Due Date");
        CustLedgerEntry.SetRange(Open, true);
        CustLedgerEntry.SetFilter("Due Date", '<%1', AsOfDate);
        CustLedgerEntry.SetRange(Positive, true);
        CustLedgerEntry.SetFilter("Posting Date", '..%1', AsOfDate);
        CustLedgerEntry.SetLoadFields("Customer No.", "Due Date", "Currency Code", "Promised Pay Date", "Dispute Status", "On Hold");
        CustLedgerEntry.SetAutoCalcFields("Remaining Amt. (LCY)");
        if CustLedgerEntry.FindSet() then
            repeat
                if IsCandidate(ExrRun, CustLedgerEntry."Customer No.", TempCollectionCustomer, Excluded) then begin
                    AddOverdueEntry(CustLedgerEntry, AsOfDate, TempCollectionCustomer);
                    // an amount the model writes in the customer's own currency is flagged too
                    RunContext.AddCurrency(CustLedgerEntry."Currency Code");
                end;
            until CustLedgerEntry.Next() = 0;
    end;

    local procedure SetCustomerFilters(ExrRun: Record "EXR Run"; var Customer: Record Customer)
    begin
        if ExrRun."Salesperson Code" <> '' then
            Customer.SetRange("Salesperson Code", ExrRun."Salesperson Code");
        if ExrRun."Customer Posting Group" <> '' then
            Customer.SetRange("Customer Posting Group", ExrRun."Customer Posting Group");
    end;

    // The first entry of a customer reads the customer once, through the dialog's filters.
    local procedure IsCandidate(ExrRun: Record "EXR Run"; CustomerNo: Code[20]; var TempCollectionCustomer: Record "EXR Collection Customer" temporary; var Excluded: List of [Code[20]]): Boolean
    var
        Customer: Record Customer;
        SalesLine: Record "Sales Line";
        CreditExposure: Decimal;
    begin
        if TempCollectionCustomer.Get(CustomerNo) then
            exit(true);
        if Excluded.Contains(CustomerNo) then
            exit(false);
        Customer.ReadIsolation := IsolationLevel::ReadCommitted;
        Customer.SetRange("No.", CustomerNo);
        SetCustomerFilters(ExrRun, Customer);
        Customer.SetLoadFields("No.", Name, "Credit Limit (LCY)");
        Customer.SetAutoCalcFields("Balance (LCY)", "Outstanding Orders (LCY)", "Shipped Not Invoiced (LCY)", "Outstanding Invoices (LCY)");
        if not Customer.FindFirst() then begin
            Excluded.Add(CustomerNo);
            exit(false);
        end;
        TempCollectionCustomer.Init();
        TempCollectionCustomer."Customer No." := Customer."No.";
        TempCollectionCustomer."Customer Name" := Customer.Name;
        TempCollectionCustomer."Customer System Id" := Customer.SystemId;
        TempCollectionCustomer."Customer Record ID" := Customer.RecordId();
        TempCollectionCustomer."Credit Limit" := Customer."Credit Limit (LCY)";
        TempCollectionCustomer."Open Orders" := Customer."Outstanding Orders (LCY)";
        if Customer."Credit Limit (LCY)" > 0 then begin
            // as the sales credit check (Customer.GetTotalAmountLCY) counts it, without prepayments, returns and service documents,
            // which would need permissions on more tables; an invoice made from a shipment is counted once
            CreditExposure := Customer."Balance (LCY)" + Customer."Outstanding Orders (LCY)" + Customer."Shipped Not Invoiced (LCY)" +
                Customer."Outstanding Invoices (LCY)" - SalesLine.OutstandingInvoiceAmountFromShipment(Customer."No.");
            TempCollectionCustomer."Credit Used %" := Round(CreditExposure / Customer."Credit Limit (LCY)" * 100, 0.01);
        end;
        TempCollectionCustomer.Insert();
        exit(true);
    end;

    // Age buckets by days past the due date, the oldest due date, promises, disputes and holds.
    // A disputed or held entry, or one with a promise still to come, is not chased yet and weighs half.
    local procedure AddOverdueEntry(CustLedgerEntry: Record "Cust. Ledger Entry"; AsOfDate: Date; var TempCollectionCustomer: Record "EXR Collection Customer" temporary)
    var
        DaysOverdue: Integer;
        Amount: Decimal;
        Weight: Decimal;
    begin
        DaysOverdue := AsOfDate - CustLedgerEntry."Due Date";
        Amount := CustLedgerEntry."Remaining Amt. (LCY)";
        case true of
            DaysOverdue <= 30:
                begin
                    TempCollectionCustomer."Overdue 1-30" += Amount;
                    Weight := 1;
                end;
            DaysOverdue <= 60:
                begin
                    TempCollectionCustomer."Overdue 31-60" += Amount;
                    Weight := 2;
                end;
            DaysOverdue <= 90:
                begin
                    TempCollectionCustomer."Overdue 61-90" += Amount;
                    Weight := 3;
                end;
            else begin
                TempCollectionCustomer."Overdue Over 90" += Amount;
                Weight := 4;
            end;
        end;
        TempCollectionCustomer."Total Overdue" += Amount;
        TempCollectionCustomer."Overdue Entries" += 1;
        if (TempCollectionCustomer."Oldest Due Date" = 0D) or (CustLedgerEntry."Due Date" < TempCollectionCustomer."Oldest Due Date") then
            TempCollectionCustomer."Oldest Due Date" := CustLedgerEntry."Due Date";
        case true of
            // On Hold also stops the standard reminders
            IsDisputedOrHeld(CustLedgerEntry):
                begin
                    TempCollectionCustomer."Disputed Amount" += Amount;
                    Weight := Weight / 2;
                end;
            CustLedgerEntry."Promised Pay Date" >= AsOfDate:
                begin
                    TempCollectionCustomer."Pending Promise Amount" += Amount;
                    if (TempCollectionCustomer."Pending Promise Date" = 0D) or (CustLedgerEntry."Promised Pay Date" < TempCollectionCustomer."Pending Promise Date") then
                        TempCollectionCustomer."Pending Promise Date" := CustLedgerEntry."Promised Pay Date";
                    Weight := Weight / 2;
                end;
            CustLedgerEntry."Promised Pay Date" <> 0D:
                begin
                    // the latest promise that was broken is the one to mention
                    TempCollectionCustomer."Broken Promise Amount" += Amount;
                    if CustLedgerEntry."Promised Pay Date" > TempCollectionCustomer."Broken Promise Date" then
                        TempCollectionCustomer."Broken Promise Date" := CustLedgerEntry."Promised Pay Date";
                end;
        end;
        TempCollectionCustomer."Weighted Overdue" += Amount * Weight;
        TempCollectionCustomer.Modify();
    end;

    local procedure IsDisputedOrHeld(CustLedgerEntry: Record "Cust. Ledger Entry"): Boolean
    begin
        exit((CustLedgerEntry."Dispute Status" <> '') or (CustLedgerEntry."On Hold" <> ''));
    end;

    // The customer's own norm: average days late on invoices paid in the last 12 months; early payments count as 0.
    // Only invoices closed by a payment count, not those closed by a credit memo.
    local procedure AddPaymentHistory(AsOfDate: Date; var TempCollectionCustomer: Record "EXR Collection Customer" temporary)
    var
        PaidInvoices: Query "EXR Paid Invoices";
        TotalDaysLate: Integer;
    begin
        PaidInvoices.SetRange(CustomerNo, TempCollectionCustomer."Customer No.");
        PaidInvoices.SetRange(ClosedAtDate, CalcDate('<-12M>', AsOfDate), AsOfDate);
        PaidInvoices.Open();
        while PaidInvoices.Read() do begin
            TempCollectionCustomer."Paid Invoices" += 1;
            if PaidInvoices.ClosedAtDate > PaidInvoices.DueDate then
                TotalDaysLate += PaidInvoices.ClosedAtDate - PaidInvoices.DueDate;
        end;
        PaidInvoices.Close();
        if TempCollectionCustomer."Paid Invoices" > 0 then
            TempCollectionCustomer."Average Days Late" := Round(TotalDaysLate / TempCollectionCustomer."Paid Invoices", 1);
    end;

    // Open payments and credit memos lower what the customer really owes: they reduce the score and are listed in the reminder.
    local procedure AddUnappliedCredits(AsOfDate: Date; var TempCollectionCustomer: Record "EXR Collection Customer" temporary)
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        CustLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        CustLedgerEntry.SetCurrentKey("Customer No.", Open, Positive, "Due Date", "Currency Code");
        CustLedgerEntry.SetRange("Customer No.", TempCollectionCustomer."Customer No.");
        CustLedgerEntry.SetRange(Open, true);
        CustLedgerEntry.SetRange(Positive, false);
        CustLedgerEntry.SetFilter("Posting Date", '..%1', AsOfDate);
        CustLedgerEntry.SetLoadFields("Entry No.");
        CustLedgerEntry.SetAutoCalcFields("Remaining Amt. (LCY)");
        if CustLedgerEntry.FindSet() then
            repeat
                TempCollectionCustomer."Unapplied Credits" -= CustLedgerEntry."Remaining Amt. (LCY)";
            until CustLedgerEntry.Next() = 0;
    end;

    // Older debt weighs more (x1 to x4 by bucket; disputed, held and promised entries half). A broken promise, a nearly used
    // credit limit and paying far later than usual raise the score; unapplied payments and credit memos lower it.
    // Limit: fixed weights; move them to the setup if credit controllers ask to tune them
    local procedure PriorityScore(TempCollectionCustomer: Record "EXR Collection Customer" temporary; AsOfDate: Date): Decimal
    var
        Weighted: Decimal;
        Factor: Integer;
    begin
        Weighted := TempCollectionCustomer."Weighted Overdue";
        // Unapplied Credits is below Total Overdue here, otherwise the customer was skipped
        if TempCollectionCustomer."Unapplied Credits" > 0 then
            Weighted := Weighted * (TempCollectionCustomer."Total Overdue" - TempCollectionCustomer."Unapplied Credits") / TempCollectionCustomer."Total Overdue";
        Factor := 100;
        if TempCollectionCustomer."Broken Promise Date" <> 0D then
            Factor += 50;
        if IsCreditRisk(TempCollectionCustomer) then
            Factor += 25;
        if PaysLaterThanUsual(TempCollectionCustomer, AsOfDate) then
            Factor += 25;
        // decimals kept, so small debts still rank by their signals
        exit(Round(Weighted * Factor / 10000, 0.01));
    end;

    local procedure IsCreditRisk(TempCollectionCustomer: Record "EXR Collection Customer" temporary): Boolean
    begin
        exit((TempCollectionCustomer."Credit Limit" > 0) and (TempCollectionCustomer."Credit Used %" >= 90));
    end;

    // More than 30 days later than the customer's own average on the invoices it paid in the last 12 months.
    local procedure PaysLaterThanUsual(TempCollectionCustomer: Record "EXR Collection Customer" temporary; AsOfDate: Date): Boolean
    begin
        if TempCollectionCustomer."Paid Invoices" = 0 then
            exit(false);
        exit(AsOfDate - TempCollectionCustomer."Oldest Due Date" > TempCollectionCustomer."Average Days Late" + 30);
    end;

    // A dispute or a pending promise sets the type only when, with unapplied credits, it covers everything overdue;
    // otherwise the rest is chased: a broken promise first, then the credit limit.
    local procedure FindingTypeOf(TempCollectionCustomer: Record "EXR Collection Customer" temporary): Text
    var
        NothingToChase: Boolean;
    begin
        NothingToChase := TempCollectionCustomer."Disputed Amount" + TempCollectionCustomer."Pending Promise Amount" + TempCollectionCustomer."Unapplied Credits" >=
            TempCollectionCustomer."Total Overdue";
        case true of
            NothingToChase and (TempCollectionCustomer."Disputed Amount" <> 0):
                exit(DisputeTok);
            NothingToChase:
                exit(PromisePendingTok);
            TempCollectionCustomer."Broken Promise Date" <> 0D:
                exit(PromiseBrokenTok);
            IsCreditRisk(TempCollectionCustomer):
                exit(CreditRiskTok);
        end;
        exit(OverdueTok);
    end;

    local procedure DefaultAction(FindingType: Text): Enum "EXR Action"
    begin
        case FindingType of
            DisputeTok:
                exit(Enum::"EXR Action"::"Resolve dispute first");
            PromiseBrokenTok:
                exit(Enum::"EXR Action"::"Phone call");
            PromisePendingTok:
                exit(Enum::"EXR Action"::"Wait - promise pending");
            CreditRiskTok:
                exit(Enum::"EXR Action"::"Credit review - hold new orders");
        end;
        exit(Enum::"EXR Action"::"Email reminder");
    end;

    // Age sets the severity; a broken promise or a nearly used credit limit makes it High.
    local procedure SeverityOf(TempCollectionCustomer: Record "EXR Collection Customer" temporary): Enum "EXR Severity"
    begin
        if (TempCollectionCustomer."Overdue Over 90" <> 0) or (TempCollectionCustomer."Broken Promise Date" <> 0D) or IsCreditRisk(TempCollectionCustomer) then
            exit(Enum::"EXR Severity"::High);
        if (TempCollectionCustomer."Overdue 31-60" <> 0) or (TempCollectionCustomer."Overdue 61-90" <> 0) then
            exit(Enum::"EXR Severity"::Medium);
        exit(Enum::"EXR Severity"::Low);
    end;

    local procedure AddCustomerFinding(TempCollectionCustomer: Record "EXR Collection Customer" temporary; Rank: Integer; AsOfDate: Date; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        FindingType: Text;
        FindingKey: Text;
        Detail: Text;
        OldestDays: Integer;
    begin
        FindingType := FindingTypeOf(TempCollectionCustomer);
        FindingKey := StrSubstNo(FindingKeyTok, FindingType, Format(Rank, 0, 9));
        OldestDays := AsOfDate - TempCollectionCustomer."Oldest Due Date";
        RunContext.AddCount(FindingKey, RankFactTok, Rank);
        RunContext.AddPhrase(FindingKey, ScoreFactTok, Format(TempCollectionCustomer.Score, 0, 9));
        AddAmountIfAny(RunContext, FindingKey, Bucket1FactTok, TempCollectionCustomer."Overdue 1-30");
        AddAmountIfAny(RunContext, FindingKey, Bucket2FactTok, TempCollectionCustomer."Overdue 31-60");
        AddAmountIfAny(RunContext, FindingKey, Bucket3FactTok, TempCollectionCustomer."Overdue 61-90");
        AddAmountIfAny(RunContext, FindingKey, Bucket4FactTok, TempCollectionCustomer."Overdue Over 90");
        RunContext.AddAmount(FindingKey, TotalOverdueFactTok, TempCollectionCustomer."Total Overdue");
        RunContext.AddPhrase(FindingKey, OverdueCountFactTok, RunContext.CountPhrase(TempCollectionCustomer."Overdue Entries", OneDocumentLbl, DocumentsLbl));
        RunContext.AddDate(FindingKey, OldestDueFactTok, TempCollectionCustomer."Oldest Due Date");
        RunContext.AddPhrase(FindingKey, OldestDaysFactTok, RunContext.CountPhrase(OldestDays, OneDayLbl, DaysLbl));
        if TempCollectionCustomer."Paid Invoices" > 0 then begin
            RunContext.AddPhrase(FindingKey, AverageLateFactTok, RunContext.CountPhrase(TempCollectionCustomer."Average Days Late", OneDayLbl, DaysLbl));
            RunContext.AddPhrase(FindingKey, PaidCountFactTok, RunContext.CountPhrase(TempCollectionCustomer."Paid Invoices", OneInvoiceLbl, InvoicesLbl));
        end;
        if TempCollectionCustomer."Overdue Entries" = 1 then
            Detail := StrSubstNo(OneDocumentDetailLbl, RunContext.FormatAmount(TempCollectionCustomer."Total Overdue"), RunContext.CountPhrase(OldestDays, OneDayLbl, DaysLbl))
        else
            Detail := StrSubstNo(DetailLbl, RunContext.FormatAmount(TempCollectionCustomer."Total Overdue"),
                RunContext.CountPhrase(TempCollectionCustomer."Overdue Entries", OneDocumentLbl, DocumentsLbl), RunContext.CountPhrase(OldestDays, OneDayLbl, DaysLbl));
        if TempCollectionCustomer."Broken Promise Date" <> 0D then begin
            RunContext.AddDate(FindingKey, BrokenDateFactTok, TempCollectionCustomer."Broken Promise Date");
            RunContext.AddAmount(FindingKey, BrokenAmountFactTok, TempCollectionCustomer."Broken Promise Amount");
            Detail := StrSubstNo(SentenceTok, Detail, StrSubstNo(BrokenPromiseLbl, RunContext.FormatDate(TempCollectionCustomer."Broken Promise Date")));
        end;
        if TempCollectionCustomer."Pending Promise Date" <> 0D then begin
            RunContext.AddDate(FindingKey, PendingDateFactTok, TempCollectionCustomer."Pending Promise Date");
            RunContext.AddAmount(FindingKey, PendingAmountFactTok, TempCollectionCustomer."Pending Promise Amount");
            Detail := StrSubstNo(SentenceTok, Detail, StrSubstNo(PendingPromiseLbl, RunContext.FormatDate(TempCollectionCustomer."Pending Promise Date")));
        end;
        if TempCollectionCustomer."Disputed Amount" <> 0 then begin
            RunContext.AddAmount(FindingKey, DisputedFactTok, TempCollectionCustomer."Disputed Amount");
            Detail := StrSubstNo(SentenceTok, Detail, StrSubstNo(DisputedLbl, RunContext.FormatAmount(TempCollectionCustomer."Disputed Amount")));
        end;
        if TempCollectionCustomer."Credit Limit" > 0 then begin
            RunContext.AddAmount(FindingKey, CreditLimitFactTok, TempCollectionCustomer."Credit Limit");
            RunContext.AddPercent(FindingKey, CreditUsedFactTok, TempCollectionCustomer."Credit Used %");
            if IsCreditRisk(TempCollectionCustomer) then
                Detail := StrSubstNo(SentenceTok, Detail, StrSubstNo(CreditUsedLbl, RunContext.FormatPercent(TempCollectionCustomer."Credit Used %")));
        end;
        AddAmountIfAny(RunContext, FindingKey, OpenOrdersFactTok, TempCollectionCustomer."Open Orders");
        if TempCollectionCustomer."Unapplied Credits" <> 0 then begin
            RunContext.AddAmount(FindingKey, UnappliedFactTok, TempCollectionCustomer."Unapplied Credits");
            Detail := StrSubstNo(SentenceTok, Detail, StrSubstNo(UnappliedLbl, RunContext.FormatAmount(TempCollectionCustomer."Unapplied Credits")));
        end;
        AddFinding(TempFinding, TempCollectionCustomer, Rank, FindingKey, FindingType, Detail);
    end;

    local procedure AddFinding(var TempFinding: Record "EXR Finding" temporary; TempCollectionCustomer: Record "EXR Collection Customer" temporary; Rank: Integer; FindingKey: Text; FindingType: Text; Detail: Text)
    begin
        TempFinding.Reset();
        TempFinding.Init();
        TempFinding."Line No." := Rank * 10000;
        TempFinding.Rank := Rank;
        TempFinding."Finding Key" := CopyStr(FindingKey, 1, MaxStrLen(TempFinding."Finding Key"));
        TempFinding."Finding Type" := CopyStr(FindingType, 1, MaxStrLen(TempFinding."Finding Type"));
        TempFinding.Severity := SeverityOf(TempCollectionCustomer);
        TempFinding.Subject := CopyStr(StrSubstNo(SubjectTok, TempCollectionCustomer."Customer No.", TempCollectionCustomer."Customer Name"), 1, MaxStrLen(TempFinding.Subject));
        TempFinding.Detail := CopyStr(Detail, 1, MaxStrLen(TempFinding.Detail));
        TempFinding.Description := TempFinding.Detail;
        TempFinding."Action" := DefaultAction(FindingType);
        TempFinding."Amount (LCY)" := TempCollectionCustomer."Total Overdue";
        TempFinding."Source Record ID" := TempCollectionCustomer."Customer Record ID";
        TempFinding."Source System Id" := TempCollectionCustomer."Customer System Id";
        TempFinding.Accepted := true;
        TempFinding.Insert();
    end;

    local procedure AddAmountIfAny(var RunContext: Codeunit "EXR Run Context"; Owner: Text; FactCaption: Text; Amount: Decimal)
    begin
        if Amount <> 0 then
            RunContext.AddAmount(Owner, FactCaption, Amount);
    end;

    // The overdue entries the reminder chases, the payments and credit memos not yet applied, and a net total per currency,
    // so a customer billed in EUR sees EUR. Disputed, held and promised entries are left out.
    local procedure CustomerEmailTable(CustomerSystemId: Guid) EmailTable: Text
    var
        Customer: Record Customer;
        CustLedgerEntry: Record "Cust. Ledger Entry";
        RunContext: Codeunit "EXR Run Context";
        Totals: Dictionary of [Code[10], Decimal];
        CurrencyCode: Code[10];
        AsOfDate: Date;
        HasCredits: Boolean;
    begin
        Customer.SetLoadFields("No.");
        if not Customer.GetBySystemId(CustomerSystemId) then
            exit('');
        AsOfDate := WorkDate();
        CustLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        CustLedgerEntry.SetCurrentKey("Customer No.", Open, Positive, "Due Date", "Currency Code");
        CustLedgerEntry.SetRange("Customer No.", Customer."No.");
        CustLedgerEntry.SetRange(Open, true);
        CustLedgerEntry.SetRange(Positive, true);
        CustLedgerEntry.SetFilter("Due Date", '<%1', AsOfDate);
        CustLedgerEntry.SetFilter("Posting Date", '..%1', AsOfDate);
        CustLedgerEntry.SetRange("Dispute Status", '');
        CustLedgerEntry.SetRange("On Hold", '');
        CustLedgerEntry.SetLoadFields("Document Type", "Document No.", "Due Date", "Currency Code", "Promised Pay Date");
        CustLedgerEntry.SetAutoCalcFields("Remaining Amount");
        if CustLedgerEntry.FindSet() then
            repeat
                // a payment promised for a date still to come is not chased
                if CustLedgerEntry."Promised Pay Date" < AsOfDate then begin
                    AddEmailLine(EmailTable, StrSubstNo(EmailLineLbl, CustLedgerEntry."Document Type", CustLedgerEntry."Document No.", RunContext.FormatDate(CustLedgerEntry."Due Date"),
                        RunContext.CountPhrase(AsOfDate - CustLedgerEntry."Due Date", OneDayLbl, DaysLbl),
                        RunContext.FormatCurrencyAmount(CustLedgerEntry."Remaining Amount", CustLedgerEntry."Currency Code")));
                    AddToTotal(Totals, CustLedgerEntry."Currency Code", CustLedgerEntry."Remaining Amount");
                end;
            until CustLedgerEntry.Next() = 0;
        if EmailTable = '' then
            exit('');

        CustLedgerEntry.SetRange(Positive, false);
        CustLedgerEntry.SetRange("Due Date");
        CustLedgerEntry.SetRange("Dispute Status");
        CustLedgerEntry.SetRange("On Hold");
        if CustLedgerEntry.FindSet() then
            repeat
                HasCredits := true;
                AddEmailLine(EmailTable, StrSubstNo(EmailCreditLineLbl, CustLedgerEntry."Document Type", CustLedgerEntry."Document No.",
                    RunContext.FormatCurrencyAmount(CustLedgerEntry."Remaining Amount", CustLedgerEntry."Currency Code")));
                AddToTotal(Totals, CustLedgerEntry."Currency Code", CustLedgerEntry."Remaining Amount");
            until CustLedgerEntry.Next() = 0;
        foreach CurrencyCode in Totals.Keys() do
            if HasCredits then
                AddEmailLine(EmailTable, StrSubstNo(EmailNetTotalLbl, RunContext.FormatCurrencyAmount(Totals.Get(CurrencyCode), CurrencyCode)))
            else
                AddEmailLine(EmailTable, StrSubstNo(EmailTotalLbl, RunContext.FormatCurrencyAmount(Totals.Get(CurrencyCode), CurrencyCode)));
    end;

    local procedure AddEmailLine(var EmailTable: Text; EmailLine: Text)
    begin
        if EmailTable <> '' then
            EmailTable += NewLine();
        EmailTable += EmailLine;
    end;

    local procedure AddToTotal(var Totals: Dictionary of [Code[10], Decimal]; CurrencyCode: Code[10]; Amount: Decimal)
    var
        Total: Decimal;
    begin
        if not Totals.Get(CurrencyCode, Total) then
            Total := 0;
        Totals.Set(CurrencyCode, Total + Amount);
    end;

    local procedure KeptMessage(CustomersPhrase: Text; Emails: Integer; DraftsSaved: Boolean) Confirmation: Text
    begin
        Confirmation := StrSubstNo(KeptCustomersMsg, CustomersPhrase);
        case true of
            Emails = 0:
                exit(Confirmation);
            DraftsSaved and (Emails = 1):
                exit(StrSubstNo(SentenceTok, Confirmation, OneDraftSavedMsg));
            DraftsSaved:
                exit(StrSubstNo(SentenceTok, Confirmation, StrSubstNo(DraftsSavedMsg, Emails)));
            Emails = 1:
                exit(StrSubstNo(SentenceTok, Confirmation, OneDraftKeptMsg));
        end;
        exit(StrSubstNo(SentenceTok, Confirmation, StrSubstNo(DraftsKeptMsg, Emails)));
    end;

    // MaxValue is checked only through Validate, so the bounds are applied here too.
    local procedure MaxCustomers(ExrRun: Record "EXR Run"): Integer
    begin
        if ExrRun."Max. Customers" > 25 then
            exit(25);
        if ExrRun."Max. Customers" > 0 then
            exit(ExrRun."Max. Customers");
        exit(10);
    end;

    local procedure NewLine(): Text
    var
        LineFeed: Char;
    begin
        LineFeed := 10;
        exit(Format(LineFeed));
    end;
}
