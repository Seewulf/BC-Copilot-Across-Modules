namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Sales.Customer;
using Microsoft.Sales.Receivables;
using PrabinBhusal.ExplainResolve;
using System.Email;
using System.TestLibraries.Utilities;

// Human in the loop for Plan collections: Keep it writes only the run, the accepted findings and the reminder drafts;
// Discard writes only the run. Customer ledger entries, promises, disputes, credit limits and reminders never change.
codeunit 58286 "EXR Collections Keep Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Engine: Codeunit "EXR Engine";
        MockChatClient: Codeunit "EXR Mock Chat Client";
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        CollectionsLibrary: Codeunit "EXR Collections Library";
        RunContext: Codeunit "EXR Run Context";
        ReminderSubjectTok: Label 'Overdue invoices on your account', Locked = true;
        InvoiceLineTok: Label '- Invoice %1, due %2', Locked = true;
        LatestExplanationTok: Label 'Still the oldest debt.', Locked = true;

    [Test]
    procedure KeepWritesTheWorklistAndDraftsOnly()
    var
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        EmailAccount: Codeunit "Email Account";
        CustomerNos: List of [Text];
        Fingerprints: List of [Text];
        CustomerNo: Text;
        ReceivablesBefore: Text;
        CustomerFilter: Text;
        SalespersonCode: Code[20];
        Body: Text;
        Index: Integer;
    begin
        // [GIVEN] the demo: Adatum broke a promise, Tailspin nearly used its credit limit, Litware is plainly overdue,
        // Fabrikam disputes an invoice and Wingtip owes nothing yet; the reply drafts reminders for Litware and, wrongly, Fabrikam
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateDemoScenario(CustomerFilter);
        CustomerNos := CustomerFilter.Split('|');
        Commit();
        MockChatClient.QueueReply(DemoReply(), 2000, 600, 3000);
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Generated, 'generated');
        // [THEN] in the dialog the disputed customer already has no email to open, because its action is not Email reminder
        TempFinding.SetRange("Finding Key", 'DISPUTE-4');
        Assert.IsTrue(TempFinding.FindFirst(), 'Fabrikam in the dialog');
        Assert.AreEqual('', TempFinding."Email Subject", 'no email to open for a dispute');
        TempFinding.Reset();
        ReceivablesBefore := CollectionsLibrary.ReceivablesFingerprint();
        foreach CustomerNo in CustomerNos do
            Fingerprints.Add(CollectionsLibrary.CustomerFingerprint(CopyStr(CustomerNo, 1, 20)));

        // [WHEN] the user keeps it
        Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] the run is kept with the four ranked customers
        ExrRun.Get(ExrRun."Entry No.");
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Kept, 'kept');
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.AreEqual(4, Finding.Count(), 'four customers kept');
        // [THEN] Litware's reminder has the recipient from the customer card and the table of its overdue invoices from the ledger
        Finding.SetRange("Finding Key", 'OVERDUE-3');
        Assert.IsTrue(Finding.FindFirst(), 'Litware finding');
        Assert.AreEqual(ReminderSubjectTok, Finding."Email Subject", 'subject');
        Assert.AreEqual(CollectionsLibrary.CustomerEmail(), Finding."Email To", 'recipient filled in by AL');
        Body := Finding.GetEmailBody();
        Assert.IsFalse(Body.Contains('{TABLE}'), 'table placeholder replaced');
        Assert.IsTrue(Body.Contains(OpenInvoiceLine(CopyStr(CustomerNos.Get(3), 1, 20), 1200)), 'first overdue invoice listed');
        Assert.IsTrue(Body.Contains(OpenInvoiceLine(CopyStr(CustomerNos.Get(3), 1, 20), 2000)), 'second overdue invoice listed');
        Assert.IsTrue(Body.Contains('Total overdue: ' + RunContext.FormatAmount(3200)), 'total');
        Assert.AreEqual(EmailAccount.IsAnyAccountRegistered(), Finding."Email Draft Saved", 'draft only when an email account exists');
        // [THEN] the reminder drafted for the disputed customer is not kept, because its action is not Email reminder
        Finding.SetRange("Finding Key", 'DISPUTE-4');
        Assert.IsTrue(Finding.FindFirst(), 'Fabrikam finding');
        Assert.IsTrue(Finding."Action" = Finding."Action"::"Resolve dispute first", 'dispute action kept');
        Assert.AreEqual('', Finding."Email Subject", 'no email for a dispute');
        Assert.AreEqual('', Finding.GetEmailBody(), 'no email text for a dispute');
        // [THEN] no ledger entry, promise, dispute, hold, credit limit or reminder changed, and nothing was posted
        Assert.AreEqual(ReceivablesBefore, CollectionsLibrary.ReceivablesFingerprint(), 'receivables unchanged');
        for Index := 1 to CustomerNos.Count() do
            Assert.AreEqual(Fingerprints.Get(Index), CollectionsLibrary.CustomerFingerprint(CopyStr(CustomerNos.Get(Index), 1, 20)), 'customer unchanged');
    end;

    [Test]
    procedure UntickedCustomerIsNotKept()
    var
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        EmailAccount: Codeunit "Email Account";
        SalespersonCode: Code[20];
        KeptMessage: Text;
    begin
        // [GIVEN] two overdue customers; the user unticks the second
        GenerateTwoCustomerRun(SalespersonCode, ExrRun, TempFinding);
        TempFinding.Reset();
        TempFinding.SetRange(Rank, 2);
        TempFinding.ModifyAll(Accepted, false);
        TempFinding.Reset();

        // [WHEN] the user keeps it
        KeptMessage := Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] only the accepted customer is saved, and the confirmation counts it in the singular
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.AreEqual(1, Finding.Count(), 'accepted customer only');
        Assert.IsTrue(KeptMessage.StartsWith('Review saved with 1 customer.'), 'singular customer');
        // the wording depends on whether the company has an email account
        if EmailAccount.IsAnyAccountRegistered() then
            Assert.IsTrue(KeptMessage.Contains('One reminder email is saved'), 'singular email saved')
        else
            Assert.IsTrue(KeptMessage.Contains('so one reminder email is kept'), 'singular email kept');
    end;

    [Test]
    procedure DiscardWritesOnlyTheRunRow()
    var
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        ReceivablesBefore: Text;
    begin
        // [GIVEN] a generated collections run
        GenerateTwoCustomerRun(SalespersonCode, ExrRun, TempFinding);
        ReceivablesBefore := CollectionsLibrary.ReceivablesFingerprint();

        // [WHEN] the user discards it
        Engine.Discard(ExrRun);

        // [THEN] only the run row changes, to Discarded
        ExrRun.Get(ExrRun."Entry No.");
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Discarded, 'discarded');
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.IsTrue(Finding.IsEmpty(), 'no findings saved');
        Assert.AreEqual(ReceivablesBefore, CollectionsLibrary.ReceivablesFingerprint(), 'receivables unchanged');
    end;

    [Test]
    procedure CustomerPanelShowsTheLatestKeptReview()
    var
        Customer: Record Customer;
        FirstRun: Record "EXR Run";
        SecondRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        FindingFactBox: TestPage "EXR Finding FactBox";
        SalespersonCode: Code[20];
    begin
        // [GIVEN] two kept collections reviews that both include the same customer, with different explanations
        GenerateTwoCustomerRun(SalespersonCode, FirstRun, TempFinding);
        Engine.Keep(FirstRun, TempFinding, '', '');
        Commit();
        MockChatClient.QueueReply(TwoCustomerReply(LatestExplanationTok), 100, 10, 100);
        CollectionsLibrary.NewRun(SalespersonCode, SecondRun);
        Engine.Generate(SecondRun, TempFinding);
        Engine.Keep(SecondRun, TempFinding, '', '');
        TempFinding.SetRange(Rank, 1);
        TempFinding.FindFirst();
        Assert.IsTrue(Customer.GetBySystemId(TempFinding."Source System Id"), 'finding linked to its customer');
        Finding.SetRange("Source System Id", Customer.SystemId);
        Assert.AreEqual(2, Finding.Count(), 'one finding per kept review');

        // [WHEN] the panel opens with the Customer Card's link
        // the panel page itself, because closing a Customer Card TestPage crashes in the platform
        FindingFactBox.OpenView();
        FindingFactBox.Filter.SetFilter("Source System Id", Format(Customer.SystemId));

        // [THEN] it shows the finding of the second review
        Assert.AreEqual(LatestExplanationTok, FindingFactBox.Description.Value(), 'latest review in the panel');
        FindingFactBox.Close();
    end;

    [Test]
    procedure ReminderListsOnlyTheEntriesItChases()
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        ExrRun: Record "EXR Run";
        Finding: Record "EXR Finding";
        TempFinding: Record "EXR Finding" temporary;
        Findings: JsonArray;
        SalespersonCode: Code[20];
        CustomerNo: Code[20];
        ChasedNo: Code[20];
        DisputedNo: Code[20];
        HeldNo: Code[20];
        PromisedNo: Code[20];
        Body: Text;
    begin
        // [GIVEN] a customer with 1,000 overdue to chase, 300 disputed, 200 on hold, 250 promised for W+5 and a payment of 100 not yet applied
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        CustomerNo := CollectionsLibrary.CreateCustomer('Adatum Interiors Ltd.', SalespersonCode);
        ChasedNo := CollectionsLibrary.PostInvoice(CustomerNo, -75, -45, 1000);
        DisputedNo := CollectionsLibrary.PostInvoice(CustomerNo, -70, -40, 300);
        CollectionsLibrary.SetDisputed(DisputedNo);
        HeldNo := CollectionsLibrary.PostInvoice(CustomerNo, -65, -35, 200);
        CollectionsLibrary.SetOnHold(HeldNo);
        PromisedNo := CollectionsLibrary.PostInvoice(CustomerNo, -60, -30, 250);
        CollectionsLibrary.SetPromisedPayDate(PromisedNo, 5);
        CollectionsLibrary.PostPayment(CustomerNo, -5, 100, '');
        Commit();
        Findings.Add(CollectionsLibrary.FindingReply('OVERDUE-1', 'Part of the debt can be chased.', 'Email reminder', ReminderSubjectTok, ReminderBody()));
        MockChatClient.QueueReply(CollectionsLibrary.Reply('Chase the undisputed invoice.', Findings), 100, 10, 100);
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        Engine.Generate(ExrRun, TempFinding);

        // [WHEN] the user keeps the reminder
        Engine.Keep(ExrRun, TempFinding, '', '');

        // [THEN] it lists the invoice to chase and the unapplied payment, with the net total
        Finding.SetRange("Run Entry No.", ExrRun."Entry No.");
        Assert.IsTrue(Finding.FindFirst(), 'kept finding');
        Body := Finding.GetEmailBody();
        Assert.IsTrue(Body.Contains(StrSubstNo(InvoiceLineTok, ChasedNo, RunContext.FormatDate(WorkDate() - 45))), 'invoice to chase listed');
        CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        CustLedgerEntry.SetRange("Document Type", CustLedgerEntry."Document Type"::Payment);
        CustLedgerEntry.FindFirst();
        Assert.IsTrue(Body.Contains(CustLedgerEntry."Document No." + ', not yet applied: ' + RunContext.FormatAmount(-100)), 'unapplied payment listed');
        Assert.IsTrue(Body.Contains('Total overdue, less payments and credits not yet applied: ' + RunContext.FormatAmount(900)), 'net total');
        // [THEN] the disputed, held and promised invoices are left out
        Assert.IsFalse(Body.Contains(DisputedNo), 'disputed invoice left out');
        Assert.IsFalse(Body.Contains(HeldNo), 'held invoice left out');
        Assert.IsFalse(Body.Contains(PromisedNo), 'promised invoice left out');
    end;

    local procedure GenerateTwoCustomerRun(var SalespersonCode: Code[20]; var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary)
    begin
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        CollectionsLibrary.PostInvoice(CollectionsLibrary.CreateCustomer('Adatum Interiors Ltd.', SalespersonCode), -130, -100, 1000);
        CollectionsLibrary.PostInvoice(CollectionsLibrary.CreateCustomer('Litware Workspace Co.', SalespersonCode), -60, -30, 1000);
        Commit();
        MockChatClient.QueueReply(TwoCustomerReply('The oldest debt.'), 1000, 300, 1500);
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        Engine.Generate(ExrRun, TempFinding);
        Assert.IsTrue(ExrRun.Status = ExrRun.Status::Generated, 'generated');
    end;

    local procedure TwoCustomerReply(FirstExplanation: Text): Text
    var
        Findings: JsonArray;
    begin
        Findings.Add(CollectionsLibrary.FindingReply('OVERDUE-1', FirstExplanation, 'Email reminder', ReminderSubjectTok, ReminderBody()));
        Findings.Add(CollectionsLibrary.FindingReply('OVERDUE-2', 'A newer debt.', 'Phone call', '', ''));
        exit(CollectionsLibrary.Reply('Contact the oldest debt first.', Findings));
    end;

    // The demo ranks Adatum (broken promise), Tailspin (credit limit), Litware (overdue) and Fabrikam (dispute).
    local procedure DemoReply(): Text
    var
        Findings: JsonArray;
    begin
        Findings.Add(CollectionsLibrary.FindingReply('PROMISE_BROKEN-1', 'The promised payment did not arrive.', 'Phone call', '', ''));
        Findings.Add(CollectionsLibrary.FindingReply('CREDIT_RISK-2', 'New orders would pass the credit limit.', 'Credit review - hold new orders', '', ''));
        Findings.Add(CollectionsLibrary.FindingReply('OVERDUE-3', 'Two invoices are overdue.', 'Email reminder', ReminderSubjectTok, ReminderBody()));
        Findings.Add(CollectionsLibrary.FindingReply('DISPUTE-4', 'Chase it anyway.', 'Email reminder', 'Pay now', ReminderBody()));
        exit(CollectionsLibrary.Reply('Call Adatum first.', Findings));
    end;

    local procedure ReminderBody(): Text
    var
        LineFeed: Char;
    begin
        LineFeed := 10;
        exit('Hello,' + Format(LineFeed) + 'These invoices are overdue:' + Format(LineFeed) + '{TABLE}' + Format(LineFeed) + 'Kind regards');
    end;

    // The line Business Central writes for the customer's open invoice of this amount.
    local procedure OpenInvoiceLine(CustomerNo: Code[20]; Amount: Decimal): Text
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        CustLedgerEntry.SetRange(Open, true);
        CustLedgerEntry.SetRange("Amount (LCY)", Amount);
        CustLedgerEntry.FindFirst();
        exit(StrSubstNo(InvoiceLineTok, CustLedgerEntry."Document No.", RunContext.FormatDate(CustLedgerEntry."Due Date")));
    end;
}
