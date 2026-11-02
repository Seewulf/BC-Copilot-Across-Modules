namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// The Plan collections detectors on their own, without the AI service. Each test gives its customers a new salesperson
// and filters the run on it, so CRONUS customers never take part. Days are relative to the work date (W).
codeunit 58284 "EXR Collections Detector Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        CollectionsLibrary: Codeunit "EXR Collections Library";
        RunContext: Codeunit "EXR Run Context";

    [Test]
    procedure OverdueAmountsFallIntoAgeBuckets()
    var
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        CustomerNo: Code[20];
    begin
        // [GIVEN] one customer with entries 1, 30, 31, 60, 61, 90 and 91 days overdue and one due today
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        CustomerNo := CollectionsLibrary.CreateCustomer('Adatum Interiors Ltd.', SalespersonCode);
        CollectionsLibrary.PostInvoice(CustomerNo, -120, -1, 1);
        CollectionsLibrary.PostInvoice(CustomerNo, -120, -30, 2);
        CollectionsLibrary.PostInvoice(CustomerNo, -120, -31, 4);
        CollectionsLibrary.PostInvoice(CustomerNo, -120, -60, 8);
        CollectionsLibrary.PostInvoice(CustomerNo, -120, -61, 16);
        CollectionsLibrary.PostInvoice(CustomerNo, -120, -90, 32);
        CollectionsLibrary.PostInvoice(CustomerNo, -120, -91, 64);
        CollectionsLibrary.PostInvoice(CustomerNo, -120, 0, 128);

        // [WHEN] the detectors run
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        CollectionsLibrary.FindCollections(ExrRun, TempFinding);

        // [THEN] each amount lands in its bucket by days past due, and the entry due today is not overdue
        Assert.IsTrue(CollectionsLibrary.GetFinding(TempFinding, CustomerNo), 'finding');
        Assert.AreEqual('OVERDUE-1', TempFinding."Finding Key", 'finding key');
        Assert.AreEqual(RunContext.FormatAmount(3), ScenarioLibrary.FactValue('OVERDUE-1', 'overdue 1-30 days'), '1 and 30 days');
        Assert.AreEqual(RunContext.FormatAmount(12), ScenarioLibrary.FactValue('OVERDUE-1', 'overdue 31-60 days'), '31 and 60 days');
        Assert.AreEqual(RunContext.FormatAmount(48), ScenarioLibrary.FactValue('OVERDUE-1', 'overdue 61-90 days'), '61 and 90 days');
        Assert.AreEqual(RunContext.FormatAmount(64), ScenarioLibrary.FactValue('OVERDUE-1', 'overdue more than 90 days'), '91 days');
        Assert.AreEqual(127, TempFinding."Amount (LCY)", 'total overdue without the entry due today');
        Assert.AreEqual('7 documents', ScenarioLibrary.FactValue('OVERDUE-1', 'overdue documents, as a phrase'), 'documents');
        Assert.AreEqual('91 days', ScenarioLibrary.FactValue('OVERDUE-1', 'days the oldest document is overdue, as a phrase'), 'oldest');
        Assert.AreEqual(RunContext.FormatDate(WorkDate() - 91), ScenarioLibrary.FactValue('OVERDUE-1', 'oldest due date'), 'oldest due date');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::High, 'more than 90 days is High');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Email reminder", 'default action');
    end;

    [Test]
    procedure AverageDaysLateComesFromInvoicesPaidInTheLast12Months()
    var
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        CustomerNo: Code[20];
    begin
        // [GIVEN] invoices paid 20 days late, 10 days late and 10 days early in the last 12 months, one paid late
        // more than 12 months ago, one cancelled by a credit memo 30 days after its due date, and one invoice 40 days overdue
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        CustomerNo := CollectionsLibrary.CreateCustomer('Litware Workspace Co.', SalespersonCode);
        CollectionsLibrary.PayInvoice(CustomerNo, CollectionsLibrary.PostInvoice(CustomerNo, -200, -170, 100), -150);
        CollectionsLibrary.PayInvoice(CustomerNo, CollectionsLibrary.PostInvoice(CustomerNo, -130, -100, 100), -90);
        CollectionsLibrary.PayInvoice(CustomerNo, CollectionsLibrary.PostInvoice(CustomerNo, -80, -60, 100), -70);
        CollectionsLibrary.PayInvoice(CustomerNo, CollectionsLibrary.PostInvoice(CustomerNo, -400, -390, 100), -370);
        CollectionsLibrary.PostCreditMemo(CustomerNo, -50, 100, CollectionsLibrary.PostInvoice(CustomerNo, -100, -80, 100));
        CollectionsLibrary.PostInvoice(CustomerNo, -70, -40, 500);

        // [WHEN] the detectors run
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        CollectionsLibrary.FindCollections(ExrRun, TempFinding);

        // [THEN] the usual delay is (20 + 10 + 0) / 3 = 10 days over 3 invoices; the old one, the cancelled one and early payment days do not count
        Assert.AreEqual('10 days', ScenarioLibrary.FactValue('OVERDUE-1', 'usual delay: average days late on invoices paid in the last 12 months, as a phrase'), 'average days late');
        Assert.AreEqual('3 invoices', ScenarioLibrary.FactValue('OVERDUE-1', 'invoices paid in the last 12 months, as a phrase'), 'invoices paid');
        Assert.AreEqual(RunContext.FormatAmount(500), ScenarioLibrary.FactValue('OVERDUE-1', 'total overdue'), 'only the open invoice is overdue');
    end;

    [Test]
    procedure BrokenAndPendingPromisesAreFound()
    var
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        BrokenNo: Code[20];
        PendingNo: Code[20];
    begin
        // [GIVEN] one customer whose payment promised for W-5 did not arrive, and one who promised to pay on W+5
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        BrokenNo := CollectionsLibrary.CreateCustomer('Adatum Interiors Ltd.', SalespersonCode);
        CollectionsLibrary.SetPromisedPayDate(CollectionsLibrary.PostInvoice(BrokenNo, -75, -45, 1000), -5);
        PendingNo := CollectionsLibrary.CreateCustomer('Wingtip Studios', SalespersonCode);
        CollectionsLibrary.SetPromisedPayDate(CollectionsLibrary.PostInvoice(PendingNo, -75, -45, 2000), 5);

        // [WHEN] the detectors run
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        CollectionsLibrary.FindCollections(ExrRun, TempFinding);

        // [THEN] the broken promise ranks first with a phone call, despite the smaller debt
        Assert.IsTrue(CollectionsLibrary.GetFinding(TempFinding, BrokenNo), 'broken promise finding');
        Assert.AreEqual('PROMISE_BROKEN-1', TempFinding."Finding Key", 'broken promise ranks first');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Phone call", 'phone call');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::High, 'High');
        Assert.AreEqual(RunContext.FormatDate(WorkDate() - 5), ScenarioLibrary.FactValue('PROMISE_BROKEN-1', 'promised payment date that has passed'), 'promised date');
        Assert.AreEqual(RunContext.FormatAmount(1000), ScenarioLibrary.FactValue('PROMISE_BROKEN-1', 'amount that was promised and not paid'), 'promised amount');
        // [THEN] the promise still to come waits
        Assert.IsTrue(CollectionsLibrary.GetFinding(TempFinding, PendingNo), 'pending promise finding');
        Assert.AreEqual('PROMISE_PENDING-2', TempFinding."Finding Key", 'pending promise ranks second');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Wait - promise pending", 'wait');
        Assert.AreEqual(RunContext.FormatDate(WorkDate() + 5), ScenarioLibrary.FactValue('PROMISE_PENDING-2', 'promised payment date still to come'), 'date to come');
    end;

    [Test]
    procedure DisputedAndHeldEntriesAreNotChased()
    var
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        MixedNo: Code[20];
        HeldNo: Code[20];
    begin
        // [GIVEN] a customer with a disputed invoice of 3,200 due W-50, one of 400 on hold due W-40 and an undisputed
        // one of 900 due W-20; and a customer whose only overdue invoice, 1,000 due W-45, is on hold
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        MixedNo := CollectionsLibrary.CreateCustomer('Fabrikam Office Supplies', SalespersonCode);
        CollectionsLibrary.SetDisputed(CollectionsLibrary.PostInvoice(MixedNo, -80, -50, 3200));
        CollectionsLibrary.SetOnHold(CollectionsLibrary.PostInvoice(MixedNo, -70, -40, 400));
        CollectionsLibrary.PostInvoice(MixedNo, -50, -20, 900);
        HeldNo := CollectionsLibrary.CreateCustomer('Wingtip Studios', SalespersonCode);
        CollectionsLibrary.SetOnHold(CollectionsLibrary.PostInvoice(HeldNo, -75, -45, 1000));

        // [WHEN] the detectors run
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        CollectionsLibrary.FindCollections(ExrRun, TempFinding);

        // [THEN] the undisputed 900 is still chased, and the disputed and held amounts weigh half: (3,200 + 400) x 2 / 2 + 900
        Assert.IsTrue(CollectionsLibrary.GetFinding(TempFinding, MixedNo), 'mixed finding');
        Assert.AreEqual('OVERDUE-1', TempFinding."Finding Key", 'the rest is chased');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Email reminder", 'reminder for the rest');
        Assert.AreEqual(RunContext.FormatAmount(3600), ScenarioLibrary.FactValue('OVERDUE-1', 'amount disputed or on hold'), 'disputed or held amount');
        Assert.AreEqual(4500, TempFinding."Amount (LCY)", 'total overdue');
        Assert.AreEqual('45', ScenarioLibrary.FactValue('OVERDUE-1', 'priority score'), 'score: 4,500 / 100');
        Assert.IsTrue(TempFinding.Detail.Contains('is disputed or on hold.'), 'detail');
        // [THEN] an entry on hold counts like a dispute: with nothing else overdue, it is resolved first
        Assert.IsTrue(CollectionsLibrary.GetFinding(TempFinding, HeldNo), 'held finding');
        Assert.AreEqual('DISPUTE-2', TempFinding."Finding Key", 'held only');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Resolve dispute first", 'resolve first');
    end;

    [Test]
    procedure UnappliedPaymentsLowerTheScoreOrSkipTheCustomer()
    var
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        CoveredNo: Code[20];
        PartlyCoveredNo: Code[20];
    begin
        // [GIVEN] two customers each owing 1,000 due W-45: one paid 1,000 and one paid 400, neither payment applied yet
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        CoveredNo := CollectionsLibrary.CreateCustomer('Adatum Interiors Ltd.', SalespersonCode);
        CollectionsLibrary.PostInvoice(CoveredNo, -75, -45, 1000);
        CollectionsLibrary.PostPayment(CoveredNo, -10, 1000, '');
        PartlyCoveredNo := CollectionsLibrary.CreateCustomer('Litware Workspace Co.', SalespersonCode);
        CollectionsLibrary.PostInvoice(PartlyCoveredNo, -75, -45, 1000);
        CollectionsLibrary.PostPayment(PartlyCoveredNo, -10, 400, '');

        // [WHEN] the detectors run
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        CollectionsLibrary.FindCollections(ExrRun, TempFinding);

        // [THEN] the customer whose payment covers the debt is not chased
        Assert.IsFalse(CollectionsLibrary.GetFinding(TempFinding, CoveredNo), 'covered by an unapplied payment');
        // [THEN] the other is scored on what it still owes, 2,000 x 600 / 1,000 / 100, and the payment is a fact
        Assert.IsTrue(CollectionsLibrary.GetFinding(TempFinding, PartlyCoveredNo), 'partly covered');
        Assert.AreEqual('12', ScenarioLibrary.FactValue('OVERDUE-1', 'priority score'), 'netted score');
        Assert.AreEqual(RunContext.FormatAmount(400), ScenarioLibrary.FactValue('OVERDUE-1', 'payments and credit memos not yet applied'), 'unapplied');
        Assert.IsTrue(TempFinding.Detail.Contains('is not yet applied.'), 'detail');
    end;

    [Test]
    procedure CreditLimitUseIsComputed()
    var
        Customer: Record Customer;
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        CustomerNo: Code[20];
    begin
        // [GIVEN] a customer with a credit limit of 1,000, 800 overdue and a sales invoice of 100 not yet posted
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        CustomerNo := CollectionsLibrary.CreateCustomer('Tailspin Fit-Out Ltd.', SalespersonCode);
        CollectionsLibrary.PostInvoice(CustomerNo, -40, -10, 800);
        CollectionsLibrary.CreateSalesDocument(Enum::"Sales Document Type"::Invoice, CustomerNo, 100);
        CollectionsLibrary.SetCreditLimit(CustomerNo, 1000);
        Customer.Get(CustomerNo);
        Customer.CalcFields("Outstanding Invoices (LCY)");

        // [WHEN] the detectors run
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        CollectionsLibrary.FindCollections(ExrRun, TempFinding);

        // [THEN] the unposted invoice counts as in the sales credit check, so at least 90% of the limit is used: a credit review
        Assert.AreNotEqual(0, Customer."Outstanding Invoices (LCY)", 'invoice not yet posted');
        Assert.IsTrue(CollectionsLibrary.GetFinding(TempFinding, CustomerNo), 'finding');
        Assert.AreEqual('CREDIT_RISK-1', TempFinding."Finding Key", 'finding key');
        Assert.AreEqual(RunContext.FormatPercent((800 + Customer."Outstanding Invoices (LCY)") / 1000 * 100),
            ScenarioLibrary.FactValue('CREDIT_RISK-1', 'credit limit used, including sales orders, shipments and invoices not yet posted'), 'credit used');
        Assert.AreEqual(RunContext.FormatAmount(1000), ScenarioLibrary.FactValue('CREDIT_RISK-1', 'credit limit'), 'credit limit');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Credit review - hold new orders", 'credit review');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::High, 'High');
    end;

    [Test]
    procedure OpenSalesOrdersAreShown()
    var
        Customer: Record Customer;
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        CustomerNo: Code[20];
    begin
        // [GIVEN] a customer without a credit limit, with 500 overdue and an open sales order
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        CustomerNo := CollectionsLibrary.CreateCustomer('Litware Workspace Co.', SalespersonCode);
        CollectionsLibrary.PostInvoice(CustomerNo, -40, -10, 500);
        CollectionsLibrary.CreateSalesOrder(CustomerNo, 100);
        Customer.Get(CustomerNo);
        Customer.CalcFields("Outstanding Orders (LCY)");

        // [WHEN] the detectors run
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        CollectionsLibrary.FindCollections(ExrRun, TempFinding);

        // [THEN] the order amount is a fact, and no limit means no credit facts and no credit risk
        Assert.AreNotEqual(0, Customer."Outstanding Orders (LCY)", 'order is outstanding');
        Assert.AreEqual(RunContext.FormatAmount(Customer."Outstanding Orders (LCY)"), ScenarioLibrary.FactValue('OVERDUE-1', 'open sales orders'), 'open orders');
        Assert.AreEqual('', ScenarioLibrary.FactValue('OVERDUE-1', 'credit limit used, including sales orders, shipments and invoices not yet posted'), 'no credit fact without a limit');
    end;

    [Test]
    procedure CustomersWithNothingOverdueAreSkipped()
    var
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SalespersonCode: Code[20];
        NotDueNo: Code[20];
        PaidNo: Code[20];
        OverdueNo: Code[20];
    begin
        // [GIVEN] a customer whose invoice is not due yet, one who paid, and one 5 days overdue
        ScenarioLibrary.InitialiseForTest();
        SalespersonCode := CollectionsLibrary.CreateSalesperson();
        NotDueNo := CollectionsLibrary.CreateCustomer('Wingtip Studios', SalespersonCode);
        CollectionsLibrary.PostInvoice(NotDueNo, -45, 10, 700);
        PaidNo := CollectionsLibrary.CreateCustomer('Fabrikam Office Supplies', SalespersonCode);
        CollectionsLibrary.PayInvoice(PaidNo, CollectionsLibrary.PostInvoice(PaidNo, -60, -30, 800), -5);
        OverdueNo := CollectionsLibrary.CreateCustomer('Litware Workspace Co.', SalespersonCode);
        CollectionsLibrary.PostInvoice(OverdueNo, -35, -5, 300);

        // [WHEN] the detectors run
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
        CollectionsLibrary.FindCollections(ExrRun, TempFinding);

        // [THEN] only the overdue customer is listed, and the run counts one customer in the singular
        TempFinding.Reset();
        Assert.AreEqual(1, TempFinding.Count(), 'one customer');
        Assert.IsTrue(CollectionsLibrary.GetFinding(TempFinding, OverdueNo), 'the overdue customer');
        Assert.IsFalse(CollectionsLibrary.GetFinding(TempFinding, NotDueNo), 'not due yet');
        Assert.IsFalse(CollectionsLibrary.GetFinding(TempFinding, PaidNo), 'paid');
        Assert.AreEqual('1 customer', ScenarioLibrary.FactValue('', 'customers with overdue entries, as a phrase'), 'singular');
        Assert.AreEqual('5 days', ScenarioLibrary.FactValue('OVERDUE-1', 'days the oldest document is overdue, as a phrase'), 'days');
        Assert.AreEqual('1 document', ScenarioLibrary.FactValue('OVERDUE-1', 'overdue documents, as a phrase'), 'one document');
        CollectionsLibrary.GetFinding(TempFinding, OverdueNo);
        Assert.AreEqual(RunContext.FormatAmount(300) + ' overdue on one document, by 5 days.', TempFinding.Detail, 'no superlative for one document');
    end;
}
