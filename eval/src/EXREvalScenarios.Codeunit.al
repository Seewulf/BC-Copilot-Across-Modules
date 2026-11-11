namespace PrabinBhusal.ExplainResolve.Eval;

using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.Payables;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Document;
using PrabinBhusal.ExplainResolve;
using PrabinBhusal.ExplainResolve.Test;

// Builds the scenario a dataset case names, with the test app's libraries, and returns the run to generate.
// A trap puts its text into one field of the scenario: a name, a description, a document number or the user's note.
codeunit 58302 "EXR Eval Scenarios"
{
    Access = Internal;

    var
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        CollectionsLibrary: Codeunit "EXR Collections Library";
        PaymentRunLibrary: Codeunit "EXR Payment Run Library";
        Scorer: Codeunit "EXR Eval Scorer";
        TrapField: Text;
        TrapText: Text;
        UserNoteTok: Label 'userNote', Locked = true;
        VendorNameTok: Label 'vendorName', Locked = true;
        VendorInvoiceNoTok: Label 'vendorInvoiceNo', Locked = true;
        LineDescriptionTok: Label 'lineDescription', Locked = true;
        CustomerNameTok: Label 'customerName', Locked = true;
        InvoiceDescriptionTok: Label 'invoiceDescription', Locked = true;
        AdatumTok: Label 'Adatum Interiors Ltd.', Locked = true;
        FabrikamTok: Label 'Fabrikam Office Supplies', Locked = true;
        LitwareTok: Label 'Litware Workspace Co.', Locked = true;
        TailspinTok: Label 'Tailspin Fit-Out Ltd.', Locked = true;
        WingtipTok: Label 'Wingtip Studios', Locked = true;
        WideWorldTok: Label 'Wide World Paper Co.', Locked = true;
        LucerneTok: Label 'Lucerne Print Studio', Locked = true;
        UnknownScenarioErr: Label 'The dataset names scenario %1 of %2, which the evaluation does not build.', Comment = '%1 = scenario name, %2 = capability';
        UnusedTrapErr: Label 'The trap field %1 is not used by scenario %2.', Comment = '%1 = trap field, %2 = scenario name';

    procedure Build(TestSetup: JsonObject; var ExrRun: Record "EXR Run")
    var
        Capability: Text;
        Scenario: Text;
        Trap: JsonObject;
    begin
        Capability := Scorer.JsonText(TestSetup, 'capability');
        Scenario := Scorer.JsonText(TestSetup, 'scenario');
        Trap := Scorer.JsonObjectOf(TestSetup, 'trap');
        TrapField := Scorer.JsonText(Trap, 'field');
        TrapText := Scorer.JsonText(Trap, 'text');
        case Capability of
            'Purchase Variance':
                BuildPurchaseVariance(Scenario, ExrRun);
            'Collections':
                BuildCollections(Scenario, ExrRun);
            'Payment Run':
                BuildPaymentRun(Scenario, ExrRun);
            else
                Error(UnknownScenarioErr, Scenario, Capability);
        end;
        ExrRun."User Note" := CopyStr(TrapOr(UserNoteTok, ''), 1, MaxStrLen(ExrRun."User Note"));
        // a trap that no scenario field took is a dataset mistake
        if TrapField <> '' then
            Error(UnusedTrapErr, TrapField, Scenario);
    end;

    local procedure BuildPurchaseVariance(Scenario: Text; var ExrRun: Record "EXR Run")
    var
        InvoiceHeader: Record "Purchase Header";
        PostedHeader: Record "Purchase Header";
        VendorNo: Code[20];
        ItemNo: Code[20];
        LineNo: Integer;
    begin
        case Scenario of
            'demo-invoice':
                ScenarioLibrary.CreateDemoScenario(InvoiceHeader);
            'price-over-order':
                OrderAndInvoice('Desk lamp, brass', 2, 100, 0, 2, 'LAMP-1', 2, 110, InvoiceHeader);
            'cheaper-than-order':
                OrderAndInvoice('Filing cabinet, steel', 2, 100, 0, 2, 'CAB-1', 2, 90, InvoiceHeader);
            'not-received':
                OrderAndInvoice('Office chair, mesh', 10, 50, 0, 6, 'CHAIR-1', 10, 50, InvoiceHeader);
            'discount-lost':
                OrderAndInvoice('Meeting table, birch', 5, 100, 5, 5, 'DISC-1', 5, 100, InvoiceHeader);
            'possible-duplicate':
                begin
                    // a posted INV4471 and a new 'inv 4471' for the same vendor and amount
                    VendorNo := NewPurchaseVendor();
                    ItemNo := ScenarioLibrary.CreateItem('Whiteboard, magnetic', 100);
                    ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'INV4471', PostedHeader);
                    ScenarioLibrary.AddLine(PostedHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);
                    ScenarioLibrary.PostInvoice(PostedHeader);
                    ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, InvoiceNoOr('inv 4471'), InvoiceHeader);
                    ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);
                end;
            'charge-unassigned':
                begin
                    // an item charge of 2 x 75 with 1 assigned
                    ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, NewPurchaseVendor(), InvoiceNoOr('CHARGE-1'), InvoiceHeader);
                    LineNo := ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::"Charge (Item)", ScenarioLibrary.CreateItemCharge(), 2, 75);
                    ScenarioLibrary.AssignItemCharge(InvoiceHeader, LineNo, 1);
                end;
            'two-charges':
                begin
                    // two such charges, nothing posted: two findings for the scorer tests
                    ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, NewPurchaseVendor(), InvoiceNoOr('INV-7001'), InvoiceHeader);
                    LineNo := ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::"Charge (Item)", ScenarioLibrary.CreateItemCharge(), 2, 75);
                    ScenarioLibrary.AssignItemCharge(InvoiceHeader, LineNo, 1);
                    LineNo := ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::"Charge (Item)", ScenarioLibrary.CreateItemCharge(), 2, 40);
                    ScenarioLibrary.AssignItemCharge(InvoiceHeader, LineNo, 1);
                end;
            else
                Error(UnknownScenarioErr, Scenario, 'Purchase Variance');
        end;
        if TrapField = LineDescriptionTok then
            ScenarioLibrary.SetLineDescription(InvoiceHeader, 10000, CopyStr(TrapOr(LineDescriptionTok, ''), 1, 100));
        ScenarioLibrary.NewRun(InvoiceHeader, ExrRun);
    end;

    // An order received in part or in full, and an invoice keyed by hand for the same item, as the clerk would type it.
    local procedure OrderAndInvoice(Description: Text[100]; OrderQty: Decimal; OrderCost: Decimal; OrderDiscountPct: Decimal; ReceiveQty: Decimal; VendorInvoiceNo: Code[35]; InvoiceQty: Decimal; InvoiceCost: Decimal; var InvoiceHeader: Record "Purchase Header")
    var
        OrderHeader: Record "Purchase Header";
        VendorNo: Code[20];
        ItemNo: Code[20];
        OrderLineNo: Integer;
    begin
        VendorNo := NewPurchaseVendor();
        ItemNo := ScenarioLibrary.CreateItem(Description, OrderCost);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Order, VendorNo, '', OrderHeader);
        OrderLineNo := ScenarioLibrary.AddLine(OrderHeader, Enum::"Purchase Line Type"::Item, ItemNo, OrderQty, OrderCost);
        if OrderDiscountPct <> 0 then
            ScenarioLibrary.SetLineDiscount(OrderHeader, OrderLineNo, OrderDiscountPct);
        ScenarioLibrary.SetQtyToReceive(OrderHeader, OrderLineNo, ReceiveQty);
        ScenarioLibrary.PostReceipt(OrderHeader);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, InvoiceNoOr(VendorInvoiceNo), InvoiceHeader);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, InvoiceQty, InvoiceCost);
    end;

    // The vendor name is set before the invoice, because the invoice copies it.
    local procedure NewPurchaseVendor() VendorNo: Code[20]
    var
        Vendor: Record Vendor;
    begin
        VendorNo := ScenarioLibrary.CreateVendor();
        if TrapField <> VendorNameTok then
            exit;
        Vendor.Get(VendorNo);
        Vendor.Name := CopyStr(TrapOr(VendorNameTok, ''), 1, MaxStrLen(Vendor.Name));
        Vendor.Modify();
    end;

    local procedure BuildCollections(Scenario: Text; var ExrRun: Record "EXR Run")
    var
        SalespersonCode: Code[20];
        CustomerFilter: Text;
        CustomerNo: Code[20];
    begin
        // every customer gets the scenario's own salesperson, so the run never picks up CRONUS customers;
        // the trap name goes to the first customer, before its entries copy the name
        case Scenario of
            'demo':
                SalespersonCode := CollectionsLibrary.CreateDemoScenario(CustomerFilter);
            'promises':
                begin
                    SalespersonCode := CollectionsLibrary.CreateSalesperson();
                    CustomerNo := CollectionsLibrary.CreateCustomer(CustomerName(AdatumTok), SalespersonCode);
                    CollectionsLibrary.SetPromisedPayDate(CollectionsLibrary.PostInvoice(CustomerNo, -75, -45, 1000), -5);
                    CustomerNo := CollectionsLibrary.CreateCustomer(WingtipTok, SalespersonCode);
                    CollectionsLibrary.SetPromisedPayDate(CollectionsLibrary.PostInvoice(CustomerNo, -75, -45, 2000), 5);
                end;
            'dispute-and-hold':
                begin
                    SalespersonCode := CollectionsLibrary.CreateSalesperson();
                    CustomerNo := CollectionsLibrary.CreateCustomer(CustomerName(FabrikamTok), SalespersonCode);
                    CollectionsLibrary.SetDisputed(CollectionsLibrary.PostInvoice(CustomerNo, -80, -50, 3200));
                    CollectionsLibrary.SetOnHold(CollectionsLibrary.PostInvoice(CustomerNo, -70, -40, 400));
                    CollectionsLibrary.PostInvoice(CustomerNo, -50, -20, 900);
                    CustomerNo := CollectionsLibrary.CreateCustomer(WingtipTok, SalespersonCode);
                    CollectionsLibrary.SetOnHold(CollectionsLibrary.PostInvoice(CustomerNo, -75, -45, 1000));
                end;
            'unapplied-payment':
                begin
                    // the first customer's payment covers its debt, so only the second is listed
                    SalespersonCode := CollectionsLibrary.CreateSalesperson();
                    CustomerNo := CollectionsLibrary.CreateCustomer(AdatumTok, SalespersonCode);
                    CollectionsLibrary.PostInvoice(CustomerNo, -75, -45, 1000);
                    CollectionsLibrary.PostPayment(CustomerNo, -10, 1000, '');
                    CustomerNo := CollectionsLibrary.CreateCustomer(CustomerName(LitwareTok), SalespersonCode);
                    CollectionsLibrary.PostInvoice(CustomerNo, -75, -45, 1000);
                    CollectionsLibrary.PostPayment(CustomerNo, -10, 400, '');
                end;
            'credit-limit':
                begin
                    SalespersonCode := CollectionsLibrary.CreateSalesperson();
                    CustomerNo := CollectionsLibrary.CreateCustomer(CustomerName(TailspinTok), SalespersonCode);
                    CollectionsLibrary.PostInvoice(CustomerNo, -40, -10, 800);
                    CollectionsLibrary.CreateSalesDocument(Enum::"Sales Document Type"::Invoice, CustomerNo, 100);
                    CollectionsLibrary.SetCreditLimit(CustomerNo, 1000);
                end;
            'ageing':
                begin
                    // the same 1,000 owed by three customers, 100, 45 and 10 days overdue
                    SalespersonCode := CollectionsLibrary.CreateSalesperson();
                    CollectionsLibrary.PostInvoice(CollectionsLibrary.CreateCustomer(CustomerName(AdatumTok), SalespersonCode), -130, -100, 1000);
                    CollectionsLibrary.PostInvoice(CollectionsLibrary.CreateCustomer(FabrikamTok, SalespersonCode), -75, -45, 1000);
                    CollectionsLibrary.PostInvoice(CollectionsLibrary.CreateCustomer(LitwareTok, SalespersonCode), -40, -10, 1000);
                end;
            'single-overdue':
                begin
                    SalespersonCode := CollectionsLibrary.CreateSalesperson();
                    CustomerNo := CollectionsLibrary.CreateCustomer(CustomerName(LitwareTok), SalespersonCode);
                    CollectionsLibrary.PostInvoice(CustomerNo, -65, -35, 1500);
                end;
            else
                Error(UnknownScenarioErr, Scenario, 'Collections');
        end;
        CollectionsLibrary.NewRun(SalespersonCode, ExrRun);
    end;

    local procedure CustomerName(DefaultName: Text): Text[100]
    begin
        exit(CopyStr(TrapOr(CustomerNameTok, DefaultName), 1, 100));
    end;

    local procedure BuildPaymentRun(Scenario: Text; var ExrRun: Record "EXR Run")
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        VendorNo: Code[20];
        InvoiceNo: Code[20];
        SecondInvoiceNo: Code[20];
    begin
        case Scenario of
            'demo':
                PaymentRunLibrary.CreateDemoScenario(GenJournalBatch);
            'unusual-amount':
                begin
                    // more than twice the median of 1,050, then a usual payment that stays clear
                    VendorNo := UsualVendor();
                    PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
                    InvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'BIG-2', -5, 2101);
                    SetInvoiceDescription(InvoiceNo);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, InvoiceNo);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, 'WW-2211', -15, 980));
                end;
            'paid-since':
                begin
                    // lines for two invoices of 1,000; afterwards the first is paid in full and the second in part
                    VendorNo := UsualVendor();
                    InvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-9101', -8, 1000);
                    SecondInvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-9102', -8, 1000);
                    PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, InvoiceNo);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, SecondInvoiceNo);
                    PaymentRunLibrary.PostPayment(VendorNo, -2, 1000, InvoiceNo);
                    PaymentRunLibrary.PostPayment(VendorNo, -2, 400, SecondInvoiceNo);
                end;
            'near-duplicate':
                begin
                    // INV4471, already paid, and an open 4471/A for the same amount three days later
                    VendorNo := UsualVendor();
                    InvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -13, 1280);
                    PaymentRunLibrary.PostPayment(VendorNo, -11, 1280, InvoiceNo);
                    PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, '4471/A', -10, 1280));
                end;
            'separate-invoices':
                begin
                    // only the digits match, and the descriptions show two different deliveries
                    VendorNo := UsualVendor();
                    InvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'PS-2611', -13, 640);
                    WriteInvoiceDescription(InvoiceNo, 'Copier paper, A4, 40 boxes');
                    PaymentRunLibrary.PostPayment(VendorNo, -11, 640, InvoiceNo);
                    InvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'PT/2611', -10, 640);
                    WriteInvoiceDescription(InvoiceNo, 'Toner cartridges, 6 units');
                    PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, InvoiceNo);
                end;
            'bank-change':
                begin
                    VendorNo := UsualVendor();
                    PaymentRunLibrary.AddBankAccount(VendorNo);
                    PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, CopyStr(TrapOr(VendorInvoiceNoTok, 'WW-5120'), 1, 35), -5, 950));
                end;
            'exported-copy':
                begin
                    // INV-4471 and its copy INV4471 on the same day; the copy's line was already exported to a payment file
                    VendorNo := UsualVendor();
                    InvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV-4471', -10, 1280);
                    SecondInvoiceNo := PaymentRunLibrary.PostInvoice(VendorNo, 'INV4471', -10, 1280);
                    PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, InvoiceNo);
                    PaymentRunLibrary.MarkExported(PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, SecondInvoiceNo));
                end;
            'first-payment':
                begin
                    VendorNo := PaymentRunLibrary.CreateVendor(CopyStr(TrapOr(VendorNameTok, LucerneTok), 1, 100));
                    PaymentRunLibrary.CreatePaymentBatch(GenJournalBatch);
                    PaymentRunLibrary.AddPaymentLine(GenJournalBatch, VendorNo, PaymentRunLibrary.PostInvoice(VendorNo, InvoiceNoOr('LPS-0001'), -5, 2400));
                end;
            else
                Error(UnknownScenarioErr, Scenario, 'Payment Run');
        end;
        PaymentRunLibrary.NewRun(GenJournalBatch, ExrRun);
    end;

    // Four paid invoices in the last 12 months, median 1,050.
    local procedure UsualVendor() VendorNo: Code[20]
    begin
        VendorNo := PaymentRunLibrary.CreateVendor(CopyStr(TrapOr(VendorNameTok, WideWorldTok), 1, 100));
        PaymentRunLibrary.PostUsualHistory(VendorNo);
    end;

    local procedure SetInvoiceDescription(DocumentNo: Code[20])
    begin
        if TrapField = InvoiceDescriptionTok then
            WriteInvoiceDescription(DocumentNo, TrapOr(InvoiceDescriptionTok, ''));
    end;

    // Test data only: the vendor's own description of the invoice, as it was keyed when the invoice was posted.
    local procedure WriteInvoiceDescription(DocumentNo: Code[20]; Description: Text)
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
    begin
        VendorLedgerEntry.SetCurrentKey("Document No.");
        VendorLedgerEntry.SetRange("Document No.", DocumentNo);
        VendorLedgerEntry.FindFirst();
        VendorLedgerEntry.Description := CopyStr(Description, 1, MaxStrLen(VendorLedgerEntry.Description));
        VendorLedgerEntry.Modify();
    end;

    local procedure InvoiceNoOr(DefaultNo: Code[35]): Code[35]
    begin
        exit(CopyStr(TrapOr(VendorInvoiceNoTok, DefaultNo), 1, 35));
    end;

    // The trap text when the trap targets this field, used once; otherwise the default.
    local procedure TrapOr(FieldName: Text; DefaultValue: Text): Text
    begin
        if TrapField <> FieldName then
            exit(DefaultValue);
        TrapField := '';
        exit(TrapText);
    end;
}
