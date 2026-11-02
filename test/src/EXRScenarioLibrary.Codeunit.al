namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Finance.GeneralLedger.Account;
using Microsoft.Finance.GeneralLedger.Ledger;
using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Finance.VAT.Setup;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Setup;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using Microsoft.Purchases.Payables;
using Microsoft.Purchases.Posting;
using Microsoft.Purchases.Vendor;
using PrabinBhusal.ExplainResolve;
using System.Security.User;

// Purchase scenarios built with standard posting only, so they run on an online sandbox without Microsoft test libraries.
// Vendors and items are created fresh with readable fictional names and numbers (EXR-V0001, EXR-I0001) that never clash with CRONUS;
// their posting groups are copied from an existing vendor and item (CRONUS 10000 and 1920-S when they exist).
// Documents use a blank location, or one without warehouse handling when locations are mandatory.
codeunit 58275 "EXR Scenario Library"
{
    var
        CopyFromVendor: Record Vendor;
        CopyFromItem: Record Item;
        TemplatesLoaded: Boolean;
        LocationCode: Code[10];
        DemoVendorNo: Code[20];
        DemoTableItemNo: Code[20];
        DemoDeskItemNo: Code[20];
        CronusVendorTok: Label '10000', Locked = true;
        CronusItemTok: Label '1920-S', Locked = true;
#pragma warning disable AA0240
        // a reserved example.com address for the demo vendor, never a real one
        VendorEmailTok: Label 'accounts@example.com', Locked = true;
#pragma warning restore AA0240
        VendorNameTok: Label 'Northwind Office Furniture Ltd.', Locked = true;
        TableDescriptionTok: Label 'Conference table, oak', Locked = true;
        DeskDescriptionTok: Label 'Office desk, walnut', Locked = true;
        ItemChargeDescriptionTok: Label 'Inbound freight', Locked = true;
        VendorPrefixTok: Label 'EXR-V', Locked = true;
        ItemPrefixTok: Label 'EXR-I', Locked = true;
        ItemChargePrefixTok: Label 'EXR-IC', Locked = true;
        FirstCounterTok: Label '0001', Locked = true;
        StartsWithTok: Label '%1*', Locked = true;
        HistoryInvoiceNoTok: Label 'INV4471', Locked = true;
        DemoInvoiceNoTok: Label 'INV-4472', Locked = true;
        DuplicateInvoiceNoTok: Label 'INV4472', Locked = true;
        FreightFilterTok: Label '@*freight*', Locked = true;
        FingerprintTok: Label '%1|%2|%3|%4|%5|%6|%7;', Locked = true;
        LedgerFingerprintTok: Label 'G/L %1, vendor %2, item %3, value %4', Locked = true;
        EmailBodyTok: Label 'Hello,%1%1Please check the lines below.%1{TABLE}%1%1Kind regards', Locked = true;
        EmailSubjectTok: Label 'Query on your invoice', Locked = true;
        NoTemplateItemErr: Label 'No inventory item with complete posting setup was found to copy posting groups from.', Locked = true;
        NoLocationErr: Label 'Locations are mandatory, but no location without warehouse receive, put-away or bins was found.', Locked = true;

    // Test setup only: mock provider, a dummy key, high limits and posting on the work date. Test isolation rolls it back.
    procedure InitialiseForTest()
    var
        Setup: Record "EXR Setup";
        GeneralLedgerSetup: Record "General Ledger Setup";
        VATSetup: Record "VAT Setup";
        UserSetup: Record "User Setup";
        MockChatClient: Codeunit "EXR Mock Chat Client";
    begin
        MockChatClient.Reset();
        Setup.InsertIfMissing();
        Setup.Provider := Setup.Provider::Mock;
        Setup.Model := 'mock-model-1';
        Setup."Daily Calls per User" := 1000;
        Setup."Daily Calls per Company" := 10000;
        // a fixed value, so the output budget check of Plan collections does not depend on the sandbox setup
        Setup."Max Output Tokens" := 4000;
        Setup."Variance Tolerance %" := 2;
        Setup."Hold Code" := 'QRY';
        Setup."Default Email Tone" := Setup."Default Email Tone"::Neutral;
        Setup.Modify();
        Setup.SetApiKey('sk-ant-test-' + Format(CreateGuid()));
        GeneralLedgerSetup.Get();
        GeneralLedgerSetup."Allow Posting From" := 0D;
        GeneralLedgerSetup."Allow Posting To" := 0D;
        GeneralLedgerSetup.Modify();
        // the company-wide VAT date range applies when the user has none
        if VATSetup.Get() then begin
            VATSetup."Allow VAT Date From" := 0D;
            VATSetup."Allow VAT Date To" := 0D;
            VATSetup.Modify();
        end;
        if UserSetup.Get(UserId()) then begin
            UserSetup."Allow Posting From" := 0D;
            UserSetup."Allow Posting To" := 0D;
            UserSetup."Allow VAT Date From" := 0D;
            UserSetup."Allow VAT Date To" := 0D;
            UserSetup.Modify();
        end;
    end;

    // The demo: 10 tables and 5 desks ordered, 8 tables and 5 desks received, and an invoice keyed by hand
    // for 10 tables at +6%, 5 desks at the order cost, 150 freight with no order and an unassigned item charge.
    // A posted invoice INV4472 for the same total makes INV-4472 a possible duplicate.
    procedure CreateDemoScenario(var InvoiceHeader: Record "Purchase Header")
    var
        HistoryHeader: Record "Purchase Header";
        OrderHeader: Record "Purchase Header";
        DuplicateHeader: Record "Purchase Header";
    begin
        DemoVendorNo := CreateVendor();
        DemoTableItemNo := CreateItem(TableDescriptionTok, 100);
        DemoDeskItemNo := CreateItem(DeskDescriptionTok, 50);
        // price history: an earlier invoice at the order prices
        CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, DemoVendorNo, HistoryInvoiceNoTok, HistoryHeader);
        AddLine(HistoryHeader, Enum::"Purchase Line Type"::Item, DemoTableItemNo, 1, 100);
        AddLine(HistoryHeader, Enum::"Purchase Line Type"::Item, DemoDeskItemNo, 1, 50);
        PostInvoice(HistoryHeader);

        CreatePurchaseHeader(Enum::"Purchase Document Type"::Order, DemoVendorNo, '', OrderHeader);
        SetQtyToReceive(OrderHeader, AddLine(OrderHeader, Enum::"Purchase Line Type"::Item, DemoTableItemNo, 10, 100), 8);
        SetQtyToReceive(OrderHeader, AddLine(OrderHeader, Enum::"Purchase Line Type"::Item, DemoDeskItemNo, 5, 50), 5);
        PostReceipt(OrderHeader);

        CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, DemoVendorNo, DemoInvoiceNoTok, InvoiceHeader);
        AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, DemoTableItemNo, 10, 106);
        AddLine(InvoiceHeader, Enum::"Purchase Line Type"::Item, DemoDeskItemNo, 5, 50);
        AddLine(InvoiceHeader, Enum::"Purchase Line Type"::"G/L Account", FreightAccountNo(), 1, 150);
        AddLine(InvoiceHeader, Enum::"Purchase Line Type"::"Charge (Item)", CreateItemCharge(), 1, 75);

        // one G/L line with the same VAT group, so the item price history is unchanged and the totals match
        InvoiceHeader.CalcFields(Amount);
        CreatePurchaseHeader(Enum::"Purchase Document Type"::Invoice, DemoVendorNo, DuplicateInvoiceNoTok, DuplicateHeader);
        AddLine(DuplicateHeader, Enum::"Purchase Line Type"::"G/L Account", FreightAccountNo(), 1, InvoiceHeader.Amount);
        PostInvoice(DuplicateHeader);
    end;

    procedure DemoTableItem(): Code[20]
    begin
        exit(DemoTableItemNo);
    end;

    procedure DemoVendorEmail(): Text
    begin
        exit(VendorEmailTok);
    end;

    // The groups the vendor and item templates are known to post with, for customers and G/L lines of other scenarios.
    procedure GetPostingGroups(var GenBusPostingGroup: Code[20]; var VATBusPostingGroup: Code[20]; var GenProdPostingGroup: Code[20]; var VATProdPostingGroup: Code[20])
    begin
        LoadTemplates();
        GenBusPostingGroup := CopyFromVendor."Gen. Bus. Posting Group";
        VATBusPostingGroup := CopyFromVendor."VAT Bus. Posting Group";
        GenProdPostingGroup := CopyFromItem."Gen. Prod. Posting Group";
        VATProdPostingGroup := CopyFromItem."VAT Prod. Posting Group";
    end;

    // A readable number that is unique per run: the prefix and a counter, such as EXR-C0003. Field 1 is No. in every table it is used for.
    procedure NextNo(TableNo: Integer; Prefix: Text): Code[20]
    var
        RecordRef: RecordRef;
        NoFieldRef: FieldRef;
    begin
        RecordRef.Open(TableNo);
        NoFieldRef := RecordRef.Field(1);
        NoFieldRef.SetFilter(StrSubstNo(StartsWithTok, Prefix));
        if RecordRef.FindLast() then
            exit(CopyStr(IncStr(Format(NoFieldRef.Value())), 1, 20));
        exit(CopyStr(Prefix + FirstCounterTok, 1, 20));
    end;

    procedure CreateVendor(): Code[20]
    var
        Vendor: Record Vendor;
    begin
        LoadTemplates();
        Vendor.Init();
        Vendor."No." := NextNo(Database::Vendor, VendorPrefixTok);
        Vendor.Name := VendorNameTok;
        Vendor.Insert(true);
        Vendor."Gen. Bus. Posting Group" := CopyFromVendor."Gen. Bus. Posting Group";
        Vendor."VAT Bus. Posting Group" := CopyFromVendor."VAT Bus. Posting Group";
        Vendor."Vendor Posting Group" := CopyFromVendor."Vendor Posting Group";
        Vendor."E-Mail" := VendorEmailTok;
        Vendor.Modify(true);
        exit(Vendor."No.");
    end;

    procedure CreateItem(Description: Text[100]; UnitCost: Decimal): Code[20]
    var
        Item: Record Item;
    begin
        LoadTemplates();
        Item.Init();
        Item."No." := NextNo(Database::Item, ItemPrefixTok);
        Item.Insert(true);
        Item.Description := Description;
        Item.Validate("Base Unit of Measure", CopyFromItem."Base Unit of Measure");
        Item."Gen. Prod. Posting Group" := CopyFromItem."Gen. Prod. Posting Group";
        Item."VAT Prod. Posting Group" := CopyFromItem."VAT Prod. Posting Group";
        Item."Inventory Posting Group" := CopyFromItem."Inventory Posting Group";
        Item."Last Direct Cost" := UnitCost;
        Item."Unit Cost" := UnitCost;
        Item.Modify(true);
        exit(Item."No.");
    end;

    procedure CreateItemVariant(ItemNo: Code[20]; VariantCode: Code[10])
    var
        ItemVariant: Record "Item Variant";
    begin
        ItemVariant.Init();
        ItemVariant."Item No." := ItemNo;
        ItemVariant.Code := VariantCode;
        ItemVariant.Description := VariantCode;
        ItemVariant.Insert(true);
    end;

    procedure CreateItemCharge(): Code[20]
    var
        ItemCharge: Record "Item Charge";
    begin
        LoadTemplates();
        ItemCharge.Init();
        ItemCharge."No." := NextNo(Database::"Item Charge", ItemChargePrefixTok);
        ItemCharge.Description := ItemChargeDescriptionTok;
        ItemCharge."Gen. Prod. Posting Group" := CopyFromItem."Gen. Prod. Posting Group";
        ItemCharge."VAT Prod. Posting Group" := CopyFromItem."VAT Prod. Posting Group";
        ItemCharge.Insert(true);
        exit(ItemCharge."No.");
    end;

    // A direct-posting income statement account, preferably one named freight.
    procedure FreightAccountNo(): Code[20]
    var
        GLAccount: Record "G/L Account";
    begin
        GLAccount.SetRange("Account Type", GLAccount."Account Type"::Posting);
        GLAccount.SetRange("Direct Posting", true);
        GLAccount.SetRange(Blocked, false);
        GLAccount.SetRange("Income/Balance", GLAccount."Income/Balance"::"Income Statement");
        GLAccount.SetFilter("Gen. Posting Type", '<>%1', GLAccount."Gen. Posting Type"::Sale);
        GLAccount.SetFilter(Name, FreightFilterTok);
        if GLAccount.FindFirst() then
            exit(GLAccount."No.");
        GLAccount.SetRange(Name);
        GLAccount.FindFirst();
        exit(GLAccount."No.");
    end;

    procedure CreatePurchaseHeader(DocumentType: Enum "Purchase Document Type"; VendorNo: Code[20]; VendorInvoiceNo: Code[35]; var PurchaseHeader: Record "Purchase Header")
    begin
        LoadTemplates();
        Clear(PurchaseHeader);
        PurchaseHeader.Init();
        PurchaseHeader."Document Type" := DocumentType;
        PurchaseHeader.Insert(true);
        PurchaseHeader.SetHideValidationDialog(true);
        PurchaseHeader.Validate("Buy-from Vendor No.", VendorNo);
        // overrides a default location from the company, user or responsibility center
        PurchaseHeader.Validate("Location Code", LocationCode);
        PurchaseHeader."Vendor Invoice No." := VendorInvoiceNo;
        PurchaseHeader.Modify(true);
    end;

    // Returns the line number. G/L lines get the item posting groups, so the posting setup is known to exist.
    procedure AddLine(PurchaseHeader: Record "Purchase Header"; LineType: Enum "Purchase Line Type"; No: Code[20]; Quantity: Decimal; DirectUnitCost: Decimal): Integer
    begin
        exit(AddVariantLine(PurchaseHeader, LineType, No, '', Quantity, DirectUnitCost));
    end;

    // The variant is set before the quantity and cost, because validating it looks the cost up again.
    procedure AddVariantLine(PurchaseHeader: Record "Purchase Header"; LineType: Enum "Purchase Line Type"; No: Code[20]; VariantCode: Code[10]; Quantity: Decimal; DirectUnitCost: Decimal): Integer
    var
        PurchaseLine: Record "Purchase Line";
        LineNo: Integer;
    begin
        LoadTemplates();
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        LineNo := 10000;
        if PurchaseLine.FindLast() then
            LineNo := PurchaseLine."Line No." + 10000;
        PurchaseLine.Init();
        PurchaseLine."Document Type" := PurchaseHeader."Document Type";
        PurchaseLine."Document No." := PurchaseHeader."No.";
        PurchaseLine."Line No." := LineNo;
        PurchaseLine.Insert(true);
        PurchaseLine.Validate(Type, LineType);
        PurchaseLine.Validate("No.", No);
        if VariantCode <> '' then
            PurchaseLine.Validate("Variant Code", VariantCode);
        if LineType = LineType::"G/L Account" then begin
            PurchaseLine.Validate("Gen. Prod. Posting Group", CopyFromItem."Gen. Prod. Posting Group");
            PurchaseLine.Validate("VAT Prod. Posting Group", CopyFromItem."VAT Prod. Posting Group");
        end;
        PurchaseLine.Validate(Quantity, Quantity);
        PurchaseLine.Validate("Direct Unit Cost", DirectUnitCost);
        PurchaseLine.Modify(true);
        exit(LineNo);
    end;

    procedure SetQtyToReceive(PurchaseHeader: Record "Purchase Header"; LineNo: Integer; Quantity: Decimal)
    var
        PurchaseLine: Record "Purchase Line";
    begin
        PurchaseLine.Get(PurchaseHeader."Document Type", PurchaseHeader."No.", LineNo);
        PurchaseLine.Validate("Qty. to Receive", Quantity);
        PurchaseLine.Modify(true);
    end;

    procedure SetLineDiscount(PurchaseHeader: Record "Purchase Header"; LineNo: Integer; LineDiscountPct: Decimal)
    var
        PurchaseLine: Record "Purchase Line";
    begin
        PurchaseLine.Get(PurchaseHeader."Document Type", PurchaseHeader."No.", LineNo);
        PurchaseLine.Validate("Line Discount %", LineDiscountPct);
        PurchaseLine.Modify(true);
    end;

    procedure SetLineDescription(PurchaseHeader: Record "Purchase Header"; LineNo: Integer; Description: Text[100])
    var
        PurchaseLine: Record "Purchase Line";
    begin
        PurchaseLine.Get(PurchaseHeader."Document Type", PurchaseHeader."No.", LineNo);
        PurchaseLine.Description := Description;
        PurchaseLine.Modify(true);
    end;

    // Assigns part of an item charge line; the assignment is all the detector reads.
    procedure AssignItemCharge(PurchaseHeader: Record "Purchase Header"; LineNo: Integer; QtyToAssign: Decimal)
    var
        PurchaseLine: Record "Purchase Line";
        ItemChargeAssignment: Record "Item Charge Assignment (Purch)";
    begin
        PurchaseLine.SetLoadFields("No.");
        PurchaseLine.Get(PurchaseHeader."Document Type", PurchaseHeader."No.", LineNo);
        ItemChargeAssignment.Init();
        ItemChargeAssignment."Document Type" := PurchaseHeader."Document Type";
        ItemChargeAssignment."Document No." := PurchaseHeader."No.";
        ItemChargeAssignment."Document Line No." := LineNo;
        ItemChargeAssignment."Line No." := 10000;
        ItemChargeAssignment."Item Charge No." := PurchaseLine."No.";
        ItemChargeAssignment."Qty. to Assign" := QtyToAssign;
        ItemChargeAssignment.Insert();
    end;

    // What Get Receipt Lines leaves on the invoice line: the link to the receipt line.
    procedure LinkToReceipt(PurchaseHeader: Record "Purchase Header"; LineNo: Integer; PurchRcptLine: Record "Purch. Rcpt. Line")
    var
        PurchaseLine: Record "Purchase Line";
    begin
        PurchaseLine.Get(PurchaseHeader."Document Type", PurchaseHeader."No.", LineNo);
        PurchaseLine."Receipt No." := PurchRcptLine."Document No.";
        PurchaseLine."Receipt Line No." := PurchRcptLine."Line No.";
        PurchaseLine.Modify(true);
    end;

    procedure PostReceipt(var PurchaseHeader: Record "Purchase Header")
    begin
        PurchaseHeader.Get(PurchaseHeader."Document Type", PurchaseHeader."No.");
        PurchaseHeader.Receive := true;
        PurchaseHeader.Invoice := false;
        PurchaseHeader.Modify();
        Codeunit.Run(Codeunit::"Purch.-Post", PurchaseHeader);
    end;

    procedure PostInvoice(var PurchaseHeader: Record "Purchase Header"): Code[20]
    var
        PurchInvHeader: Record "Purch. Inv. Header";
        InvoiceNo: Code[20];
    begin
        InvoiceNo := PurchaseHeader."No.";
        PurchaseHeader.Get(PurchaseHeader."Document Type", PurchaseHeader."No.");
        PurchaseHeader.Receive := true;
        PurchaseHeader.Invoice := true;
        PurchaseHeader.Modify();
        Codeunit.Run(Codeunit::"Purch.-Post", PurchaseHeader);
        PurchInvHeader.SetRange("Pre-Assigned No.", InvoiceNo);
        PurchInvHeader.FindFirst();
        exit(PurchInvHeader."No.");
    end;

    // Runs the detectors only, without the AI service.
    procedure FindDifferences(PurchaseHeader: Record "Purchase Header"; TolerancePct: Decimal; var TempFinding: Record "EXR Finding" temporary)
    var
        ExrRun: Record "EXR Run";
        RunContext: Codeunit "EXR Run Context";
        Handler: Interface "EXR Capability Handler";
    begin
        NewRun(PurchaseHeader, ExrRun);
        ExrRun."Tolerance %" := TolerancePct;
        TempFinding.Reset();
        TempFinding.DeleteAll();
        RunContext.StartRun();
        Handler := ExrRun.Capability;
        Handler.BuildFacts(ExrRun, TempFinding, RunContext);
    end;

    procedure NewRun(PurchaseHeader: Record "Purchase Header"; var ExrRun: Record "EXR Run")
    begin
        Clear(ExrRun);
        ExrRun.Capability := ExrRun.Capability::"Purchase Variance";
        ExrRun."Source Table No." := Database::"Purchase Header";
        ExrRun."Source System Id" := PurchaseHeader.SystemId;
        ExrRun."Tolerance %" := 2;
        ExrRun."Email Tone" := ExrRun."Email Tone"::Neutral;
    end;

    procedure GetFinding(var TempFinding: Record "EXR Finding" temporary; FindingKey: Text): Boolean
    begin
        TempFinding.Reset();
        TempFinding.SetRange("Finding Key", FindingKey);
        exit(TempFinding.FindFirst());
    end;

    // A reply in the shape the JSON schema asks for, with one finding.
    procedure Reply(Summary: Text; FindingKey: Text; Explanation: Text; ActionName: Text; Confidence: Text): Text
    begin
        exit(ReplyWithSubject(Summary, FindingKey, Explanation, ActionName, Confidence, EmailSubjectTok));
    end;

    procedure ReplyWithSubject(Summary: Text; FindingKey: Text; Explanation: Text; ActionName: Text; Confidence: Text; EmailSubject: Text) ReplyText: Text
    var
        ReplyJson: JsonObject;
        FindingJson: JsonObject;
        Findings: JsonArray;
        LineFeed: Char;
    begin
        LineFeed := 10;
        FindingJson.Add('key', FindingKey);
        FindingJson.Add('explanation', Explanation);
        FindingJson.Add('action', ActionName);
        FindingJson.Add('confidence', Confidence);
        Findings.Add(FindingJson);
        ReplyJson.Add('summary', Summary);
        ReplyJson.Add('findings', Findings);
        ReplyJson.Add('emailSubject', EmailSubject);
        ReplyJson.Add('emailBody', StrSubstNo(EmailBodyTok, Format(LineFeed)));
        ReplyJson.WriteTo(ReplyText);
    end;

    // The value of the fact with this caption, as the model sees it; empty when the fact was not registered.
    procedure FactValue(Owner: Text; FactCaption: Text): Text
    var
        RunContext: Codeunit "EXR Run Context";
        Facts: JsonObject;
        FactToken: JsonToken;
        ValueToken: JsonToken;
        TokenKey: Text;
    begin
        Facts := RunContext.FactsJson(Owner);
        foreach TokenKey in Facts.Keys() do begin
            Facts.Get(TokenKey, FactToken);
            FactToken.AsObject().Get('caption', ValueToken);
            if ValueToken.AsValue().AsText() = FactCaption then begin
                FactToken.AsObject().Get('value', ValueToken);
                exit(ValueToken.AsValue().AsText());
            end;
        end;
        exit('');
    end;

    // Equal before and after a run proves that nothing was posted.
    procedure LedgerFingerprint(): Text
    var
        GLEntry: Record "G/L Entry";
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        ValueEntry: Record "Value Entry";
    begin
        exit(StrSubstNo(LedgerFingerprintTok, GLEntry.Count(), VendorLedgerEntry.Count(), ItemLedgerEntry.Count(), ValueEntry.Count()));
    end;

    procedure LinesFingerprint(PurchaseHeader: Record "Purchase Header") Fingerprint: Text
    var
        PurchaseLine: Record "Purchase Line";
    begin
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.SetLoadFields(Type, "No.", Quantity, "Direct Unit Cost", "Line Discount %", "Line Amount");
        if PurchaseLine.FindSet() then
            repeat
                Fingerprint += StrSubstNo(FingerprintTok, PurchaseLine."Line No.", PurchaseLine.Type, PurchaseLine."No.", PurchaseLine.Quantity,
                    PurchaseLine."Direct Unit Cost", PurchaseLine."Line Discount %", PurchaseLine."Line Amount");
            until PurchaseLine.Next() = 0;
    end;

    local procedure LoadTemplates()
    begin
        if TemplatesLoaded then
            exit;
        LocationCode := FindLocation();
        if not CopyFromVendor.Get(CronusVendorTok) then
            Clear(CopyFromVendor);
        if not HasVendorGroups(CopyFromVendor) then begin
            CopyFromVendor.Reset();
            CopyFromVendor.SetFilter("Gen. Bus. Posting Group", '<>%1', '');
            CopyFromVendor.SetFilter("VAT Bus. Posting Group", '<>%1', '');
            CopyFromVendor.SetFilter("Vendor Posting Group", '<>%1', '');
            CopyFromVendor.SetRange("Currency Code", '');
            CopyFromVendor.SetRange(Blocked, CopyFromVendor.Blocked::" ");
            CopyFromVendor.FindFirst();
        end;
        if CopyFromItem.Get(CronusItemTok) then
            if IsUsableItem(CopyFromItem) then begin
                TemplatesLoaded := true;
                exit;
            end;
        CopyFromItem.Reset();
        CopyFromItem.SetRange(Type, CopyFromItem.Type::Inventory);
        CopyFromItem.SetRange(Blocked, false);
        CopyFromItem.SetFilter("Gen. Prod. Posting Group", '<>%1', '');
        CopyFromItem.SetFilter("VAT Prod. Posting Group", '<>%1', '');
        CopyFromItem.SetFilter("Inventory Posting Group", '<>%1', '');
        CopyFromItem.SetFilter("Base Unit of Measure", '<>%1', '');
        if CopyFromItem.FindSet() then
            repeat
                if IsUsableItem(CopyFromItem) then begin
                    TemplatesLoaded := true;
                    exit;
                end;
            until CopyFromItem.Next() = 0;
        Error(NoTemplateItemErr);
    end;

    local procedure HasVendorGroups(Vendor: Record Vendor): Boolean
    begin
        exit((Vendor."Gen. Bus. Posting Group" <> '') and (Vendor."VAT Bus. Posting Group" <> '') and (Vendor."Vendor Posting Group" <> '') and
             (Vendor."Currency Code" = '') and (Vendor.Blocked = Vendor.Blocked::" "));
    end;

    // Blank unless locations are mandatory; then one where Purch.-Post can receive without warehouse documents.
    // Limit: first such location only; choose per item if a company lacks its inventory posting setup
    local procedure FindLocation(): Code[10]
    var
        InventorySetup: Record "Inventory Setup";
        Location: Record Location;
    begin
        InventorySetup.SetLoadFields("Location Mandatory");
        if not InventorySetup.Get() then
            exit('');
        if not InventorySetup."Location Mandatory" then
            exit('');
        Location.SetRange("Use As In-Transit", false);
        Location.SetRange("Require Receive", false);
        Location.SetRange("Require Put-away", false);
        Location.SetRange("Bin Mandatory", false);
        Location.SetRange("Directed Put-away and Pick", false);
        Location.SetLoadFields(Code);
        if not Location.FindFirst() then
            Error(NoLocationErr);
        exit(Location.Code);
    end;

    // An item whose groups have a general, VAT and inventory posting setup with the template vendor and location.
    local procedure IsUsableItem(Item: Record Item): Boolean
    var
        GeneralPostingSetup: Record "General Posting Setup";
        VATPostingSetup: Record "VAT Posting Setup";
        InventoryPostingSetup: Record "Inventory Posting Setup";
    begin
        if Item.Blocked or (Item.Type <> Item.Type::Inventory) or (Item."Base Unit of Measure" = '') then
            exit(false);
        if not GeneralPostingSetup.Get(CopyFromVendor."Gen. Bus. Posting Group", Item."Gen. Prod. Posting Group") then
            exit(false);
        if GeneralPostingSetup."Purch. Account" = '' then
            exit(false);
        if not VATPostingSetup.Get(CopyFromVendor."VAT Bus. Posting Group", Item."VAT Prod. Posting Group") then
            exit(false);
        exit(InventoryPostingSetup.Get(LocationCode, Item."Inventory Posting Group"));
    end;
}
