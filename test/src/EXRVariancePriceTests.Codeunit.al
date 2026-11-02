namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// The Explain variance price, discount and duplicate detectors on their own, without the AI service.
codeunit 58280 "EXR Variance Price Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ScenarioLibrary: Codeunit "EXR Scenario Library";
        PurchVariance: Codeunit "EXR Purch. Variance";

    [Test]
    procedure CostAboveToleranceAgainstTheOrderIsFound()
    var
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] the demo: tables at 106 against 100 on the order
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);

        // [WHEN] the detectors run with a 2% tolerance
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the 6% difference is found, worth 6 x 10 = 60
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_PO-10000'), 'price finding');
        Assert.AreEqual(60, TempFinding."Amount (LCY)", 'difference amount');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Ask vendor to confirm price", 'default action');
    end;

    [Test]
    procedure ToleranceEdgeIsAcceptedAndJustAboveIsFound()
    var
        OrderHeader: Record "Purchase Header";
        AtEdgeHeader: Record "Purchase Header";
        AboveEdgeHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
    begin
        // [GIVEN] an order at 100, fully received, and two invoices at 102 and 102.01
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Edge item', 100);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Order, VendorNo, '', OrderHeader);
        ScenarioLibrary.SetQtyToReceive(OrderHeader, ScenarioLibrary.AddLine(OrderHeader, Enum::"Purchase Line Type"::Item, ItemNo, 2, 100), 2);
        ScenarioLibrary.PostReceipt(OrderHeader);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'EDGE-1', AtEdgeHeader);
        ScenarioLibrary.AddLine(AtEdgeHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 102);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'EDGE-2', AboveEdgeHeader);
        ScenarioLibrary.AddLine(AboveEdgeHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 102.01);

        // [WHEN] the detectors run with a 2% tolerance
        // [THEN] exactly 2% is accepted and 2.01% is a finding
        ScenarioLibrary.FindDifferences(AtEdgeHeader, 2, TempFinding);
        Assert.IsFalse(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_PO-10000'), 'exactly at the tolerance');
        ScenarioLibrary.FindDifferences(AboveEdgeHeader, 2, TempFinding);
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_PO-10000'), 'just above the tolerance');
    end;

    [Test]
    procedure CheaperInvoiceDefaultsToAccept()
    var
        OrderHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
    begin
        // [GIVEN] an order at 100, received, and an invoice at 90
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Cheaper item', 100);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Order, VendorNo, '', OrderHeader);
        ScenarioLibrary.SetQtyToReceive(OrderHeader, ScenarioLibrary.AddLine(OrderHeader, Enum::"Purchase Line Type"::Item, ItemNo, 2, 100), 2);
        ScenarioLibrary.PostReceipt(OrderHeader);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'CHEAP-1', InvoiceHeader);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 2, 90);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the difference in the company's favour is shown, but its action does not hold the invoice
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_PO-10000'), 'price finding');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Accept within tolerance", 'default action');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::Low, 'severity');
    end;

    [Test]
    procedure CostAgainstLatestPostedInvoicesIsFound()
    var
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] the demo: the vendor's last posted invoice has tables at 100, the new invoice at 106
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the price history finding points at the posted invoice line
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_HISTORY-10000'), 'history finding');
        Assert.AreEqual(60, TempFinding."Amount (LCY)", 'difference amount');
        Assert.AreEqual(Database::"Purch. Inv. Line", TempFinding."Source Record ID".TableNo(), 'source is the posted invoice line');
        // [THEN] one posted line reads in the singular, in the detail and in the fact the model cites
        Assert.IsTrue(TempFinding.Detail.Contains('on the latest posted invoice line ('), 'singular detail');
        Assert.IsFalse(TempFinding.Detail.Contains('average'), 'no average of one line');
        Assert.AreEqual('1 posted invoice line', ScenarioLibrary.FactValue('PRICE_VS_HISTORY-10000', 'posted invoice lines compared, as a phrase'), 'singular fact');
        // a wider tolerance accepts it
        ScenarioLibrary.FindDifferences(InvoiceHeader, 10, TempFinding);
        Assert.IsFalse(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_HISTORY-10000'), 'within 10%');
    end;

    [Test]
    procedure OnlyTheLatestThreePostedLinesAreCompared()
    var
        HistoryHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
        Index: Integer;
    begin
        // [GIVEN] an old posted invoice at 1000, then three at 100, and a new invoice at 100
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('History item', 100);
        for Index := 1 to 4 do begin
            ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, CopyStr('HIST-' + Format(Index), 1, 35), HistoryHeader);
            if Index = 1 then
                ScenarioLibrary.AddLine(HistoryHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 1000)
            else
                ScenarioLibrary.AddLine(HistoryHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);
            ScenarioLibrary.PostInvoice(HistoryHeader);
        end;
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'HIST-5', InvoiceHeader);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the old 1000 is outside the latest three, so 100 matches the history
        Assert.IsFalse(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_HISTORY-10000'), 'oldest invoice ignored');
    end;

    [Test]
    procedure ChangedLineDiscountIsFound()
    var
        OrderHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
        OrderLineNo: Integer;
    begin
        // [GIVEN] an order with a 5% line discount, received, and an invoice without the discount
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Discount item', 100);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Order, VendorNo, '', OrderHeader);
        OrderLineNo := ScenarioLibrary.AddLine(OrderHeader, Enum::"Purchase Line Type"::Item, ItemNo, 5, 100);
        ScenarioLibrary.SetLineDiscount(OrderHeader, OrderLineNo, 5);
        ScenarioLibrary.SetQtyToReceive(OrderHeader, OrderLineNo, 5);
        ScenarioLibrary.PostReceipt(OrderHeader);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'DISC-1', InvoiceHeader);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 5, 100);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the lost discount is found, worth 5% of 500
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'DISCOUNT_VS_PO-10000'), 'discount finding');
        Assert.AreEqual(25, TempFinding."Amount (LCY)", 'discount amount');
        TempFinding.Reset();
        Assert.AreEqual(1, TempFinding.Count(), 'only the discount differs');
    end;

    [Test]
    procedure VendorInvoiceNoIsNormalised()
    begin
        // [GIVEN] the same vendor invoice number written in different ways
        // [WHEN] it is normalised
        // [THEN] symbols and spaces go, letters are upper case
        Assert.AreEqual('INV4471', PurchVariance.NormaliseInvoiceNo('INV-4471'), 'hyphen');
        Assert.AreEqual('INV4471', PurchVariance.NormaliseInvoiceNo('INV4471'), 'plain');
        Assert.AreEqual('INV4471', PurchVariance.NormaliseInvoiceNo('inv 4471'), 'lower case and space');
        Assert.AreEqual('4471A', PurchVariance.NormaliseInvoiceNo('4471/a'), 'slash');
        Assert.AreEqual('', PurchVariance.NormaliseInvoiceNo('- /'), 'only symbols');
    end;

    [Test]
    procedure PossibleDuplicateIsFound()
    var
        PostedHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        PurchInvHeader: Record "Purch. Inv. Header";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
    begin
        // [GIVEN] a posted invoice INV4471 and a new invoice 'inv 4471' for the same vendor and amount
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Duplicate item', 100);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'INV4471', PostedHeader);
        ScenarioLibrary.AddLine(PostedHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);
        PurchInvHeader.Get(ScenarioLibrary.PostInvoice(PostedHeader));
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'inv 4471', InvoiceHeader);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the posted invoice is the only finding, with the duplicate action
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'POSSIBLE_DUPLICATE-1'), 'duplicate finding');
        Assert.AreEqual(Format(PurchInvHeader.RecordId()), Format(TempFinding."Source Record ID"), 'source is the posted invoice');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Query possible duplicate", 'default action');
        TempFinding.Reset();
        Assert.AreEqual(1, TempFinding.Count(), 'one finding');
    end;

    [Test]
    procedure DuplicateWithAnotherAmountIsNotFound()
    var
        PostedHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
    begin
        // [GIVEN] a posted invoice INV4471 for 1 item and a new invoice INV-4471 for 2
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Duplicate item', 100);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'INV4471', PostedHeader);
        ScenarioLibrary.AddLine(PostedHeader, Enum::"Purchase Line Type"::Item, ItemNo, 1, 100);
        ScenarioLibrary.PostInvoice(PostedHeader);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'INV-4471', InvoiceHeader);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 2, 100);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the same number with another amount is not a duplicate
        Assert.IsFalse(ScenarioLibrary.GetFinding(TempFinding, 'POSSIBLE_DUPLICATE-1'), 'no duplicate');
    end;
}
