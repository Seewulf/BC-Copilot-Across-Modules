namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// The Explain variance detectors on their own, without the AI service: matching, quantities, G/L and charge lines.
// Posting-heavy, so kept small enough for one test runner call; prices and duplicates are in EXR Variance Price Tests.
codeunit 58276 "EXR Purch. Variance Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ScenarioLibrary: Codeunit "EXR Scenario Library";

    [Test]
    procedure HandKeyedLineIsMatchedToTheOrderByVendorAndItem()
    var
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] the demo: 8 of 10 tables received, an invoice keyed by hand for 10 tables at 106
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] 2 tables are not received, worth 212, and the finding points at the order line
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'NOT_RECEIVED-10000'), 'not received finding');
        Assert.AreEqual(212, TempFinding."Amount (LCY)", 'amount not received');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Hold until received", 'default action');
        Assert.IsTrue(TempFinding.Severity = TempFinding.Severity::High, 'severity');
        Assert.AreEqual(Database::"Purchase Line", TempFinding."Source Record ID".TableNo(), 'source is the order line');
        Assert.IsTrue(TempFinding.Accepted, 'accepted by default');
    end;

    [Test]
    procedure ReceiptLinkedLineIsComparedWithTheReceipt()
    var
        OrderHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        PurchRcptLine: Record "Purch. Rcpt. Line";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
        OrderLineNo: Integer;
    begin
        // [GIVEN] an order for 10 at 100 of which 8 are received, and an invoice line for those 8 linked to the
        // receipt line as Get Receipt Lines does, with the cost changed to 106
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Linked item', 100);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Order, VendorNo, '', OrderHeader);
        OrderLineNo := ScenarioLibrary.AddLine(OrderHeader, Enum::"Purchase Line Type"::Item, ItemNo, 10, 100);
        ScenarioLibrary.SetQtyToReceive(OrderHeader, OrderLineNo, 8);
        ScenarioLibrary.PostReceipt(OrderHeader);
        PurchRcptLine.SetRange("Order No.", OrderHeader."No.");
        PurchRcptLine.SetRange("Order Line No.", OrderLineNo);
        PurchRcptLine.FindFirst();
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'LINKED-1', InvoiceHeader);
        ScenarioLibrary.LinkToReceipt(InvoiceHeader, ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 8, 106), PurchRcptLine);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the cost is compared with the order behind the receipt, worth 6 x 8 = 48, and nothing is missing
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_PO-10000'), 'price finding');
        Assert.AreEqual(48, TempFinding."Amount (LCY)", 'difference amount');
        Assert.AreEqual(Database::"Purch. Rcpt. Line", TempFinding."Source Record ID".TableNo(), 'source is the receipt line');
        Assert.IsFalse(ScenarioLibrary.GetFinding(TempFinding, 'NOT_RECEIVED-10000'), 'all 8 received');
    end;

    [Test]
    procedure SplitHandKeyedLinesShareTheReceivedQuantity()
    var
        OrderHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
    begin
        // [GIVEN] 10 ordered and 8 received, and an invoice keyed by hand as two lines of 5
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Split item', 100);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Order, VendorNo, '', OrderHeader);
        ScenarioLibrary.SetQtyToReceive(OrderHeader, ScenarioLibrary.AddLine(OrderHeader, Enum::"Purchase Line Type"::Item, ItemNo, 10, 100), 8);
        ScenarioLibrary.PostReceipt(OrderHeader);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'SPLIT-1', InvoiceHeader);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 5, 100);
        ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 5, 100);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the first line takes 5 of the 8, so the second line is 2 short, worth 200
        Assert.IsFalse(ScenarioLibrary.GetFinding(TempFinding, 'NOT_RECEIVED-10000'), 'first line received');
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'NOT_RECEIVED-20000'), 'second line short');
        Assert.AreEqual(200, TempFinding."Amount (LCY)", 'amount not received');
    end;

    [Test]
    procedure VariantsAreMatchedSeparately()
    var
        OrderHeader: Record "Purchase Header";
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
        VendorNo: Code[20];
        ItemNo: Code[20];
    begin
        // [GIVEN] an order for 10 BLUE at 90, all received, and 10 RED at 100, none received; an invoice for 10 RED at 100
        ScenarioLibrary.InitialiseForTest();
        VendorNo := ScenarioLibrary.CreateVendor();
        ItemNo := ScenarioLibrary.CreateItem('Variant item', 100);
        ScenarioLibrary.CreateItemVariant(ItemNo, 'BLUE');
        ScenarioLibrary.CreateItemVariant(ItemNo, 'RED');
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Order, VendorNo, '', OrderHeader);
        ScenarioLibrary.SetQtyToReceive(OrderHeader, ScenarioLibrary.AddVariantLine(OrderHeader, Enum::"Purchase Line Type"::Item, ItemNo, 'BLUE', 10, 90), 10);
        ScenarioLibrary.SetQtyToReceive(OrderHeader, ScenarioLibrary.AddVariantLine(OrderHeader, Enum::"Purchase Line Type"::Item, ItemNo, 'RED', 10, 100), 0);
        ScenarioLibrary.PostReceipt(OrderHeader);
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, VendorNo, 'RED-1', InvoiceHeader);
        ScenarioLibrary.AddVariantLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, ItemNo, 'RED', 10, 100);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the received BLUE units do not cover RED, and the RED price is compared with the RED order line
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'NOT_RECEIVED-10000'), 'RED not received');
        Assert.AreEqual(1000, TempFinding."Amount (LCY)", 'amount not received');
        Assert.IsFalse(ScenarioLibrary.GetFinding(TempFinding, 'PRICE_VS_PO-10000'), 'no price finding against BLUE');
    end;

    [Test]
    procedure FullyReceivedLineAtOrderCostHasNoFinding()
    var
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] the demo: 5 desks ordered, received and invoiced at the order cost on line 20000
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the desk line has no finding, and the demo gives exactly six findings
        TempFinding.Reset();
        TempFinding.SetFilter("Finding Key", '*-20000');
        Assert.IsTrue(TempFinding.IsEmpty(), 'desk line is fine');
        TempFinding.Reset();
        Assert.AreEqual(6, TempFinding.Count(), 'findings in the demo');
        // [THEN] the summary fact is a grammatical sentence built by AL, with "has" for one line
        Assert.AreEqual('1 of the 4 lines checked has no differences',
            ScenarioLibrary.FactValue('', 'lines checked and how many have no differences, as a full sentence'), 'lines sentence');
    end;

    [Test]
    procedure GLLineWithoutOrderIsFound()
    var
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] the demo: 150 freight on a G/L account line with no order
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the freight line is found with the item charge action
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'NO_PO_LINK-30000'), 'freight finding');
        Assert.AreEqual(150, TempFinding."Amount (LCY)", 'freight amount');
        Assert.IsTrue(TempFinding."Action" = TempFinding."Action"::"Assign as item charge", 'default action');
    end;

    [Test]
    procedure UnassignedItemChargeIsFound()
    var
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] the demo: an item charge line of 75 with no assignment
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreateDemoScenario(InvoiceHeader);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the charge is found with its full amount
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'CHARGE_NOT_ASSIGNED-40000'), 'charge finding');
        Assert.AreEqual(75, TempFinding."Amount (LCY)", 'charge amount');
    end;

    [Test]
    procedure PartlyAssignedItemChargeIsFound()
    var
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
        LineNo: Integer;
    begin
        // [GIVEN] an item charge line of 2 x 75 with 1 assigned
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, ScenarioLibrary.CreateVendor(), 'CHARGE-1', InvoiceHeader);
        LineNo := ScenarioLibrary.AddLine(InvoiceHeader, Enum::"Purchase Line Type"::"Charge (Item)", ScenarioLibrary.CreateItemCharge(), 2, 75);
        ScenarioLibrary.AssignItemCharge(InvoiceHeader, LineNo, 1);

        // [WHEN] the detectors run
        ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] only the unassigned half is found
        Assert.IsTrue(ScenarioLibrary.GetFinding(TempFinding, 'CHARGE_NOT_ASSIGNED-10000'), 'charge finding');
        Assert.AreEqual(75, TempFinding."Amount (LCY)", 'unassigned amount');
    end;

    [Test]
    procedure OnlyOpenInvoicesAreExplained()
    var
        InvoiceHeader: Record "Purchase Header";
        TempFinding: Record "EXR Finding" temporary;
    begin
        // [GIVEN] a released purchase invoice
        ScenarioLibrary.InitialiseForTest();
        ScenarioLibrary.CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, ScenarioLibrary.CreateVendor(), 'REL-1', InvoiceHeader);
        InvoiceHeader.Status := InvoiceHeader.Status::Released;
        InvoiceHeader.Modify();

        // [WHEN] the detectors run
        asserterror ScenarioLibrary.FindDifferences(InvoiceHeader, 2, TempFinding);

        // [THEN] the user is asked to reopen it
        Assert.ExpectedError('works only on an open purchase invoice');
    end;
}
