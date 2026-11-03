namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Purchases.Vendor;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// Check payment run detectors, without the AI service: the amount against the median, bank changes, first payments,
// holds, lines already paid, lines that are not checked, and one finding per line with a signal. Duplicates have their own codeunit.
codeunit 58288 "EXR Payment Run Detector Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        PaymentRunLibrary: Codeunit "EXR Payment Run Library";
        RunContext: Codeunit "EXR Run Context";
        VendorNameTok: Label 'Proseware Office Supplies', Locked = true;
        MedianFactTok: Label 'median payment to this vendor in the last 12 months', Locked = true;
        PaymentCountFactTok: Label 'payments to this vendor in the last 12 months, as a phrase', Locked = true;
        AboveMedianFactTok: Label 'how far the payment is above the median', Locked = true;
        BankDateFactTok: Label 'date a bank account of this vendor was last changed', Locked = true;
        BankAgoFactTok: Label 'how long ago that was, as a phrase', Locked = true;
        BankTargetFactTok: Label 'which bank account this payment goes to, as a full sentence', Locked = true;
        VendorCreatedFactTok: Label 'date the vendor card was created', Locked = true;
        PaidFactTok: Label 'what is still open on the entries this line pays, as a full sentence', Locked = true;
        LineAmountFactTok: Label 'payment amount in the currency of the line', Locked = true;
        OpenAmountFactTok: Label 'amount still open on the entries this line pays, in the currency of the line', Locked = true;
        LinesCheckedFactTok: Label 'vendor payment lines checked, as a phrase', Locked = true;
        LinesClearFactTok: Label 'payment lines with no signal, which stay in the journal to be paid, as a phrase', Locked = true;
        NotCheckedFactTok: Label 'vendor payment lines entered with the vendor as balancing account, which were not checked, as a phrase', Locked = true;

    [Test]
    procedure PaymentFarAboveTheMedianIsFlagged()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        AtLimitLineId: Guid;
        AboveLineId: Guid;
    begin
        // [GIVEN] a vendor paid 900, 1,000, 1,100 and 1,200 in the last 12 months (median 1,050) and a 100% threshold
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        AtLimitLineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'BIG-1', -5, 2100));
        AboveLineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'BIG-2', -5, 2101));

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] twice the median is still in pattern; above it the line is flagged against the median of payments
        Assert.IsFalse(PaymentRunLibrary.GetFindingForLine(TempFinding, AtLimitLineId), 'exactly twice the median');
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, AboveLineId), 'above twice the median');
        Assert.AreEqual('AMOUNT', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::Medium, 'severity');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::Hold, 'default action');
        Assert.AreEqual(RunContext.FormatAmount(1050), ScenarioLibrary.FactValue(TempFinding."Finding Key", MedianFactTok), 'median');
        Assert.AreEqual('4 payments', ScenarioLibrary.FactValue(TempFinding."Finding Key", PaymentCountFactTok), 'payments counted');
        Assert.AreEqual(RunContext.FormatPercent((2101 - 1050) / 1050 * 100), ScenarioLibrary.FactValue(TempFinding."Finding Key", AboveMedianFactTok), 'above the median');
    end;

    [Test]
    procedure AmountIsNotCheckedWithoutAPattern()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        Amounts: List of [Decimal];
        FewPaymentsVendorNo: Code[20];
        UsualVendorNo: Code[20];
    begin
        // [GIVEN] a vendor with only two payments and a vendor with four, each with a payment five times the usual amount
        PaymentRunLibrary.Initialise();
        FewPaymentsVendorNo := PaymentRunLibrary.CreateVendor(VendorNameTok);
        Amounts.Add(1000);
        Amounts.Add(1000);
        PaymentRunLibrary.PostPaymentHistory(FewPaymentsVendorNo, Amounts);
        UsualVendorNo := CreateUsualVendor();
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, FewPaymentsVendorNo, PaymentRunLibrary.PostInvoice(FewPaymentsVendorNo, 'BIG-3', -5, 5000));
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, UsualVendorNo, PaymentRunLibrary.PostInvoice(UsualVendorNo, 'BIG-4', -5, 5000));

        // [WHEN] the check runs with the threshold turned off
        PaymentRunLibrary.SetUnusualAmountPct(0);
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] neither is flagged
        TempFinding.Reset();
        Assert.IsTrue(TempFinding.IsEmpty(), 'threshold off');

        // [WHEN] the threshold is on [THEN] only the vendor with at least 3 payments has a pattern to compare with
        PaymentRunLibrary.SetUnusualAmountPct(100);
        FindSignals(GenJournalBatch, TempFinding);
        Assert.IsFalse(PaymentRunLibrary.GetFinding(TempFinding, FewPaymentsVendorNo), 'two payments are no pattern');
        Assert.IsTrue(PaymentRunLibrary.GetFinding(TempFinding, UsualVendorNo), 'four payments are a pattern');
    end;

    [Test]
    procedure BankAccountChangedInsideTheWindowIsHigh()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        LineId: Guid;
    begin
        // [GIVEN] a vendor whose bank account was added today, and a payment line to that account
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.AddBankAccount(VendorNo);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        LineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'INV-7001', -5, 1000));
        GenJournalLine.GetBySystemId(LineId);
        GenJournalLine."Recipient Bank Account" := PaymentRunLibrary.BankAccountCode();
        GenJournalLine.Modify();
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);

        // [WHEN] the bank-change window is one day, which includes today
        ExrRun."Bank Change Window Days" := 1;
        PaymentRunLibrary.FindSignals(ExrRun, TempFinding);

        // [THEN] the line is High, to verify by phone, with only the date and whether this payment goes to the changed account
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'finding for the line');
        Assert.AreEqual('BANK', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::High, 'severity');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Verify bank details by phone", 'default action');
        Assert.AreEqual(RunContext.FormatDate(Today()), ScenarioLibrary.FactValue(TempFinding."Finding Key", BankDateFactTok), 'changed on');
        Assert.AreEqual('today', ScenarioLibrary.FactValue(TempFinding."Finding Key", BankAgoFactTok), 'how long ago');
        Assert.AreEqual('This payment goes to a bank account that changed', ScenarioLibrary.FactValue(TempFinding."Finding Key", BankTargetFactTok), 'target');

        // [WHEN] the window is 0 [THEN] the check is off
        ExrRun."Bank Change Window Days" := 0;
        PaymentRunLibrary.FindSignals(ExrRun, TempFinding);
        Assert.IsFalse(PaymentRunLibrary.GetFindingForLine(TempFinding, LineId), 'window off');
    end;

    [Test]
    procedure FirstPaymentToAVendorIsFlagged()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        NewVendorNo: Code[20];
        PaidLongAgoVendorNo: Code[20];
    begin
        // [GIVEN] a vendor never paid, and a vendor paid only once, more than 12 months ago
        PaymentRunLibrary.Initialise();
        NewVendorNo := PaymentRunLibrary.CreateVendor(VendorNameTok);
        PaidLongAgoVendorNo := PaymentRunLibrary.CreateVendor(VendorNameTok);
        PaymentRunLibrary.PostPayment(PaidLongAgoVendorNo, -400, 500, '');
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, NewVendorNo, PaymentRunLibrary.PostInvoice(NewVendorNo, 'NEW-1', -5, 2400));
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, PaidLongAgoVendorNo, PaymentRunLibrary.PostInvoice(PaidLongAgoVendorNo, 'OLD-1', -5, 2400));

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] only the first payment ever is flagged, Medium, to verify by phone, with the date the vendor was created
        Assert.IsTrue(PaymentRunLibrary.GetFinding(TempFinding, NewVendorNo), 'first payment');
        Assert.AreEqual('FIRST', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::Medium, 'severity');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Verify bank details by phone", 'default action');
        Assert.AreEqual(RunContext.FormatDate(Today()), ScenarioLibrary.FactValue(TempFinding."Finding Key", VendorCreatedFactTok), 'vendor created');
        Assert.IsFalse(PaymentRunLibrary.GetFinding(TempFinding, PaidLongAgoVendorNo), 'paid before');
    end;

    [Test]
    procedure InvoiceAlreadyOnHoldIsFlagged()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        Context: JsonObject;
        Token: JsonToken;
        VendorNo: Code[20];
        InvoiceNo: Code[20];
    begin
        // [GIVEN] a payment line for an invoice that someone put on hold, to a vendor whose bank account was added today
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.AddBankAccount(VendorNo);
        InvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-8001', -5, 1000);
        PaymentRunLibrary.SetOnHold(InvoiceNo, 'ABC');
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, InvoiceNo);

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] the hold comes first and the line defaults to Hold, not to the phone call the bank change alone would get
        Assert.IsTrue(PaymentRunLibrary.GetFinding(TempFinding, VendorNo), 'finding');
        Assert.AreEqual('ON_HOLD+BANK', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::High, 'severity of the bank change');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::Hold, 'default action');
        // [THEN] the hold code goes to the model as untrusted text
        Context := RunContext.FindingContextJson(TempFinding."Finding Key");
        Context.Get('onHoldCode', Token);
        Assert.AreEqual('<untrusted>ABC</untrusted>', Token.AsValue().AsText(), 'hold code wrapped');
    end;

    [Test]
    procedure LineForAnInvoicePaidSinceIsHeld()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        PaidInvoiceNo: Code[20];
        PartPaidInvoiceNo: Code[20];
        PaidLineId: Guid;
        PartPaidLineId: Guid;
    begin
        // [GIVEN] lines for two invoices of 1,000; afterwards the first is paid in full and the second in part (400)
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaidInvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-9101', -8, 1000);
        PartPaidInvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-9102', -8, 1000);
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        PaidLineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaidInvoiceNo);
        PartPaidLineId := PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PartPaidInvoiceNo);
        PaymentRunLibrary.PostPayment(VendorNo, -2, 1000, PaidInvoiceNo);
        PaymentRunLibrary.PostPayment(VendorNo, -2, 400, PartPaidInvoiceNo);

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] the line for the paid invoice is High and can only be held: nothing it pays is open
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, PaidLineId), 'paid line');
        Assert.AreEqual('PAID', TempFinding."Finding Type", 'type');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::High, 'severity');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::Hold, 'default action');
        Assert.AreEqual('Nothing that this line pays is still open, so it was already paid or settled', ScenarioLibrary.FactValue(TempFinding."Finding Key", PaidFactTok), 'nothing open');
        // [THEN] the line for the part-paid invoice would pay 1,000 where 600 is open
        Assert.IsTrue(PaymentRunLibrary.GetFindingForLine(TempFinding, PartPaidLineId), 'part-paid line');
        Assert.AreEqual('PAID', TempFinding."Finding Type", 'type of the part-paid line');
        Assert.AreEqual('The line pays more than is still open on the entries it pays', ScenarioLibrary.FactValue(TempFinding."Finding Key", PaidFactTok), 'pays more');
        Assert.AreEqual(RunContext.FormatCurrencyAmount(1000, ''), ScenarioLibrary.FactValue(TempFinding."Finding Key", LineAmountFactTok), 'line amount');
        Assert.AreEqual(RunContext.FormatCurrencyAmount(600, ''), ScenarioLibrary.FactValue(TempFinding."Finding Key", OpenAmountFactTok), 'still open');
    end;

    [Test]
    procedure VendorAsBalancingAccountIsCountedNotChecked()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
    begin
        // [GIVEN] a usual vendor payment, and a payment to a vendor never paid before, keyed with the vendor as balancing account
        PaymentRunLibrary.Initialise();
        VendorNo := CreateUsualVendor();
        PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
        PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'WW-3001', -5, 980));
        PaymentRunLibrary.AddBalancingVendorLine(GenJournalBatch, PaymentRunLibrary.CreateVendor(VendorNameTok), 2400);

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] that line is not checked, and the summary is told so
        TempFinding.Reset();
        Assert.IsTrue(TempFinding.IsEmpty(), 'no finding');
        Assert.AreEqual('1 payment line', ScenarioLibrary.FactValue('', LinesCheckedFactTok), 'lines checked');
        Assert.AreEqual('1 payment line', ScenarioLibrary.FactValue('', NotCheckedFactTok), 'lines not checked');
    end;

    [Test]
    procedure DemoGivesOneFindingPerRiskyLine()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        TempFinding: Record "EXR Finding" temporary;
        Vendor: Record Vendor;
    begin
        // [GIVEN] the demo: two Proseware lines for INV-4471 and INV4471 with a bank account added today, a usual Wide World
        // payment and a first payment to Lucerne
        PaymentRunLibrary.Initialise();
        PaymentRunLibrary.CreateDemoScenario(GenJournalBatch);

        // [WHEN] the payment run is checked
        FindSignals(GenJournalBatch, TempFinding);

        // [THEN] each Proseware line is one High finding with both signals: INV4471, entered later, is the copy and defaults to Hold;
        // INV-4471 to a phone call about the bank details. Lucerne is a first payment and Wide World is clear
        TempFinding.Reset();
        Assert.AreEqual(3, TempFinding.Count(), 'three lines with a signal');
        TempFinding.SetRange(Severity, TempFinding.Severity::High);
        TempFinding.SetRange("Finding Type", 'DUP_COPY+BANK');
        Assert.IsTrue(TempFinding.FindFirst(), 'the copy');
        Assert.IsTrue(TempFinding.Subject.EndsWith('INV4471'), 'the copy entered later');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::Hold, 'the copy is held');
        TempFinding.SetRange("Finding Type", 'DUPLICATE+BANK');
        Assert.IsTrue(TempFinding.FindFirst(), 'the first invoice');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Verify bank details by phone", 'the first invoice is checked by phone');
        TempFinding.SetRange(Severity);
        TempFinding.SetRange("Finding Type", 'FIRST');
        Assert.IsTrue(TempFinding.FindFirst(), 'Lucerne');
        Vendor.Get(TempFinding."Account No.");
        Assert.AreEqual('Lucerne Print Studio', Vendor.Name, 'first-time vendor');
        Assert.AreEqual('4 payment lines', ScenarioLibrary.FactValue('', LinesCheckedFactTok), 'lines checked');
        Assert.AreEqual('1 payment line', ScenarioLibrary.FactValue('', LinesClearFactTok), 'lines with no signal');
        Assert.AreEqual('', ScenarioLibrary.FactValue('', NotCheckedFactTok), 'every vendor line checked');
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
