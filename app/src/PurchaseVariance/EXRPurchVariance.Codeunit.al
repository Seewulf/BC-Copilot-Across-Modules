namespace PrabinBhusal.ExplainResolve;

using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using Microsoft.Purchases.Vendor;
using System.AI;

// Explain invoice variance: AL compares an open purchase invoice with its receipts, the order, the price history
// and posted invoices, in LCY. Keep it may only set On Hold and save the vendor email draft.
codeunit 58206 "EXR Purch. Variance" implements "EXR Capability Handler"
{
    Access = Internal;
    // users get indirect modify only, for On Hold in ApplyKeep
    Permissions = tabledata "Purchase Header" = m;

    var
        // base quantity that earlier hand-keyed lines already took from the pooled order lines, per item and variant
        ClaimedQtyBase: Dictionary of [Text, Decimal];
        CurrencyCode: Code[10];
        CurrencyFactor: Decimal;
        TolerancePct: Decimal;
        PromptTok: Label 'purchase-variance.md', Locked = true;
        FindingKeyTok: Label '%1-%2', Locked = true;
        ItemVariantKeyTok: Label '%1|%2', Locked = true;
        AllowedCharactersTok: Label 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', Locked = true;
        NotReceivedTok: Label 'NOT_RECEIVED', Locked = true;
        PriceVsOrderTok: Label 'PRICE_VS_PO', Locked = true;
        PriceVsHistoryTok: Label 'PRICE_VS_HISTORY', Locked = true;
        DiscountVsOrderTok: Label 'DISCOUNT_VS_PO', Locked = true;
        NoOrderLinkTok: Label 'NO_PO_LINK', Locked = true;
        ChargeNotAssignedTok: Label 'CHARGE_NOT_ASSIGNED', Locked = true;
        DuplicateTok: Label 'POSSIBLE_DUPLICATE', Locked = true;
        // fact captions are read by the model only
        ToleranceFactTok: Label 'price tolerance', Locked = true;
        LinesCheckedFactTok: Label 'lines checked and how many have no differences, as a full sentence', Locked = true;
        InvoicedQtyFactTok: Label 'invoiced quantity', Locked = true;
        ReceivedQtyFactTok: Label 'received and not yet invoiced quantity', Locked = true;
        MissingQtyFactTok: Label 'quantity not received', Locked = true;
        MissingAmountFactTok: Label 'amount not received', Locked = true;
        InvoiceCostFactTok: Label 'invoice unit cost', Locked = true;
        OrderCostFactTok: Label 'order unit cost', Locked = true;
        HistoryCostFactTok: Label 'average unit cost on the latest posted invoice lines', Locked = true;
        HistoryOneCostFactTok: Label 'unit cost on the latest posted invoice line', Locked = true;
        HistoryCountFactTok: Label 'posted invoice lines compared, as a phrase', Locked = true;
        DifferencePctFactTok: Label 'difference in percent', Locked = true;
        DifferenceAmountFactTok: Label 'difference amount', Locked = true;
        InvoiceDiscountFactTok: Label 'invoice line discount', Locked = true;
        OrderDiscountFactTok: Label 'order line discount', Locked = true;
        LineAmountFactTok: Label 'line amount', Locked = true;
        UnassignedQtyFactTok: Label 'quantity not assigned', Locked = true;
        UnassignedAmountFactTok: Label 'amount not assigned', Locked = true;
        PostedAmountFactTok: Label 'amount of the posted invoice', Locked = true;
        LineSubjectLbl: Label 'Line %1: %2 %3', Comment = '%1 = line number, %2 = item or account number, %3 = description';
        DuplicateSubjectLbl: Label 'Posted invoice %1 (vendor invoice %2)', Comment = '%1 = posted invoice number, %2 = vendor invoice number';
        NotReceivedLbl: Label 'Invoiced %1, received and not yet invoiced %2: %3 not received.', Comment = '%1 = invoiced quantity, %2 = received quantity, %3 = missing quantity';
        PriceVsOrderLbl: Label 'Unit cost %1 against %2 on the order (%3).', Comment = '%1 = invoice unit cost, %2 = order unit cost, %3 = difference in percent';
        PriceVsHistoryLbl: Label 'Unit cost %1 against an average of %2 on the last %3 posted invoice lines (%4).', Comment = '%1 = invoice unit cost, %2 = average unit cost, %3 = number of posted invoice lines, %4 = difference in percent';
        PriceVsOneInvoiceLbl: Label 'Unit cost %1 against %2 on the latest posted invoice line (%3).', Comment = '%1 = invoice unit cost, %2 = unit cost on the posted invoice line, %3 = difference in percent';
        OnePostedLineLbl: Label '%1 posted invoice line', Comment = '%1 = number of posted invoice lines (1)';
        PostedLinesLbl: Label '%1 posted invoice lines', Comment = '%1 = number of posted invoice lines';
        NoLinesCheckedLbl: Label 'The invoice has no lines to check.';
        OnlyLineOkLbl: Label 'The only line checked has no differences.';
        OnlyLineDiffersLbl: Label 'The only line checked has differences.';
        AllLinesOkLbl: Label 'All %1 lines checked have no differences.', Comment = '%1 = number of lines checked';
        AllLinesDifferLbl: Label 'All %1 lines checked have differences.', Comment = '%1 = number of lines checked';
        OneLineOkLbl: Label '1 of the %1 lines checked has no differences.', Comment = '%1 = number of lines checked';
        SomeLinesOkLbl: Label '%1 of the %2 lines checked have no differences.', Comment = '%1 = number of lines without differences, %2 = number of lines checked';
        KeptOnHoldMsg: Label 'Review saved. Invoice %1 is on hold (%2). Reopen the invoice to see the review in the Variance review panel.', Comment = '%1 = invoice number, %2 = On Hold code';
        KeptMsg: Label 'Review saved. Reopen the invoice to see the review in the Variance review panel.';
        DraftSavedMsg: Label 'The vendor email is saved as a draft in your email outbox.';
        DraftKeptMsg: Label 'No email account is set up, so the vendor email is kept on the review. Open it there with Open Email.';
        MessageTok: Label '%1 %2', Locked = true;
        DiscountVsOrderLbl: Label 'Line discount %1 against %2 on the order.', Comment = '%1 = invoice line discount, %2 = order line discount';
        NoOrderLinkLbl: Label 'G/L account line of %1 with no purchase order or receipt.', Comment = '%1 = line amount';
        ChargeNotAssignedLbl: Label 'Item charge with %1 of %2 not assigned to a receipt line.', Comment = '%1 = quantity not assigned, %2 = quantity';
        DuplicateLbl: Label 'Same vendor, the same vendor invoice number once spaces and symbols are removed, and the same amount (%1).', Comment = '%1 = amount';
        EmailTableLineLbl: Label '- %1: %2', Comment = '%1 = line or document, %2 = figures';
        NotOpenErr: Label 'Explain variance works only on an open purchase invoice. Reopen purchase invoice %1 first.', Comment = '%1 = invoice number';

    procedure CopilotCapability(): Enum "Copilot Capability"
    begin
        exit(Enum::"Copilot Capability"::"EXR Purchase Variance");
    end;

    procedure PromptResourceName(): Text
    begin
        exit(PromptTok);
    end;

    procedure UsesTolerance(): Boolean
    begin
        exit(true);
    end;

    procedure ReviewsSelection(): Boolean
    begin
        exit(false);
    end;

    procedure DraftsEmailPerFinding(): Boolean
    begin
        exit(false);
    end;

    procedure DraftsEmail(): Boolean
    begin
        exit(true);
    end;

    procedure UsesPaymentWindows(): Boolean
    begin
        exit(false);
    end;

    // Per finding type, so the model cannot turn a missing delivery or a duplicate into an accept.
    procedure IsActionAllowed(FindingType: Code[30]; FindingAction: Enum "EXR Action"): Boolean
    begin
        case FindingType of
            NotReceivedTok:
                exit(FindingAction in [Enum::"EXR Action"::"Hold until received", Enum::"EXR Action"::"Request credit memo"]);
            DuplicateTok:
                exit(FindingAction = Enum::"EXR Action"::"Query possible duplicate");
            PriceVsOrderTok, PriceVsHistoryTok, DiscountVsOrderTok:
                exit(FindingAction in [Enum::"EXR Action"::"Accept within tolerance", Enum::"EXR Action"::"Ask vendor to confirm price", Enum::"EXR Action"::"Request credit memo"]);
            NoOrderLinkTok, ChargeNotAssignedTok:
                exit(FindingAction in [Enum::"EXR Action"::"Assign as item charge", Enum::"EXR Action"::"Accept within tolerance", Enum::"EXR Action"::"Ask vendor to confirm price"]);
        end;
        exit(false);
    end;

    procedure BuildFacts(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        LinesChecked: Integer;
        LinesWithFindings: Integer;
        FindingsBefore: Integer;
    begin
        PurchaseHeader.SetLoadFields("Document Type", "No.", Status, "Buy-from Vendor No.", "Buy-from Vendor Name", "Vendor Invoice No.", "Currency Code", "Currency Factor");
        PurchaseHeader.GetBySystemId(ExrRun."Source System Id");
        if (PurchaseHeader."Document Type" <> PurchaseHeader."Document Type"::Invoice) or (PurchaseHeader.Status <> PurchaseHeader.Status::Open) then
            Error(NotOpenErr, PurchaseHeader."No.");
        ExrRun."Source No." := PurchaseHeader."No.";
        CurrencyCode := PurchaseHeader."Currency Code";
        CurrencyFactor := PurchaseHeader."Currency Factor";
        TolerancePct := ExrRun."Tolerance %";
        Clear(ClaimedQtyBase);
        RunContext.AddCurrency(CurrencyCode);
        RunContext.AddContext('vendor', PurchaseHeader."Buy-from Vendor Name");
        RunContext.AddContext('invoiceNo', PurchaseHeader."No.");
        RunContext.AddContext('vendorInvoiceNo', PurchaseHeader."Vendor Invoice No.");
        // the vendor needs its own invoice number in the subject
        RunContext.SetEmailReference(PurchaseHeader."Vendor Invoice No.");
        RunContext.AddPercent('', ToleranceFactTok, TolerancePct);
        // every type code of the capability, also one no finding has, so the user never reads it
        RunContext.AddTypeCode(NotReceivedTok);
        RunContext.AddTypeCode(PriceVsOrderTok);
        RunContext.AddTypeCode(PriceVsHistoryTok);
        RunContext.AddTypeCode(DiscountVsOrderTok);
        RunContext.AddTypeCode(NoOrderLinkTok);
        RunContext.AddTypeCode(ChargeNotAssignedTok);
        RunContext.AddTypeCode(DuplicateTok);

        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.SetFilter(Type, '%1|%2|%3', PurchaseLine.Type::Item, PurchaseLine.Type::"G/L Account", PurchaseLine.Type::"Charge (Item)");
        PurchaseLine.SetFilter(Quantity, '<>0');
        PurchaseLine.SetLoadFields(Type, "No.", "Variant Code", Description, Quantity, "Quantity (Base)", "Qty. per Unit of Measure", "Direct Unit Cost", "Line Discount %", "Line Amount",
            "Receipt No.", "Receipt Line No.", "Order No.", "Order Line No.", "Buy-from Vendor No.", "Currency Code");
        PurchaseLine.SetAutoCalcFields("Qty. to Assign", "Qty. Assigned");
        if PurchaseLine.FindSet() then
            repeat
                LinesChecked += 1;
                FindingsBefore := TempFinding.Count();
                case PurchaseLine.Type of
                    PurchaseLine.Type::Item:
                        CheckItemLine(PurchaseLine, TempFinding, RunContext);
                    PurchaseLine.Type::"G/L Account":
                        CheckGLAccountLine(PurchaseLine, TempFinding, RunContext);
                    PurchaseLine.Type::"Charge (Item)":
                        CheckChargeLine(PurchaseLine, TempFinding, RunContext);
                end;
                if TempFinding.Count() > FindingsBefore then
                    LinesWithFindings += 1;
            until PurchaseLine.Next() = 0;
        CheckDuplicate(PurchaseHeader, TempFinding, RunContext);
        RunContext.AddPhrase('', LinesCheckedFactTok, LinesCheckedSentence(LinesChecked, LinesChecked - LinesWithFindings));
    end;

    // Only the findings the vendor has to answer go into the email.
    procedure BuildEmailTable(var TempFinding: Record "EXR Finding" temporary) EmailTable: Text
    begin
        if TempFinding.FindSet() then
            repeat
                if IsVendorQuery(TempFinding."Action") then begin
                    if EmailTable <> '' then
                        EmailTable += NewLine();
                    EmailTable += StrSubstNo(EmailTableLineLbl, TempFinding.Subject, TempFinding.Detail);
                end;
            until TempFinding.Next() = 0;
    end;

    // The only writes: On Hold on the invoice and the email draft. Lines, prices and the order are never changed.
    procedure ApplyKeep(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary): Text
    var
        Setup: Record "EXR Setup";
        PurchaseHeader: Record "Purchase Header";
        Vendor: Record Vendor;
        EmailDraft: Codeunit "EXR Email Draft";
    begin
        if not HasVendorQuery(TempFinding) then
            exit(KeptMsg);
        Setup.GetSetup();
        // read and then modify the same invoice: lock it
        PurchaseHeader.ReadIsolation := IsolationLevel::UpdLock;
        PurchaseHeader.GetBySystemId(ExrRun."Source System Id");
        if (Setup."Hold Code" <> '') and (PurchaseHeader."On Hold" = '') then begin
            PurchaseHeader.Validate("On Hold", Setup."Hold Code");
            PurchaseHeader.Modify(true);
        end;
        Vendor.SetLoadFields("E-Mail");
        if not Vendor.Get(PurchaseHeader."Buy-from Vendor No.") then
            exit(KeptMessage(PurchaseHeader, ExrRun, false));
        ExrRun."Email To" := Vendor."E-Mail";
        if ExrRun."Email Subject" <> '' then begin
            // also when the user removed the vendor invoice number from the subject
            ExrRun."Email Subject" := CopyStr(EmailDraft.SubjectWithReference(ExrRun."Email Subject", PurchaseHeader."Vendor Invoice No.", MaxStrLen(ExrRun."Email Subject")), 1, MaxStrLen(ExrRun."Email Subject"));
            ExrRun."Email Draft Saved" := EmailDraft.SaveDraft(ExrRun, Database::Vendor, Vendor.SystemId);
        end;
        exit(KeptMessage(PurchaseHeader, ExrRun, ExrRun."Email Subject" <> ''));
    end;

    // Upper case, letters and digits only: INV-4471, INV4471 and inv 4471 all give INV4471.
    procedure NormaliseInvoiceNo(VendorInvoiceNo: Text): Text
    begin
        exit(DelChr(UpperCase(VendorInvoiceNo), '=', DelChr(UpperCase(VendorInvoiceNo), '=', AllowedCharactersTok)));
    end;

    local procedure CheckItemLine(PurchaseLine: Record "Purchase Line"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        OrderLine: Record "Purchase Line";
        PurchRcptLine: Record "Purch. Rcpt. Line";
        SourceId: RecordId;
        AvailableQtyBase: Decimal;
        OrderCostBase: Decimal;
        OrderDiscountPct: Decimal;
        HasReceiptOrOrder: Boolean;
        HasOrderTerms: Boolean;
    begin
        if PurchaseLine."Receipt No." <> '' then begin
            PurchRcptLine.SetLoadFields("Qty. Rcd. Not Invoiced", "Qty. per Unit of Measure", "Order No.", "Order Line No.", "Direct Unit Cost", "Line Discount %");
            if PurchRcptLine.Get(PurchaseLine."Receipt No.", PurchaseLine."Receipt Line No.") then begin
                HasReceiptOrOrder := true;
                AvailableQtyBase := PurchRcptLine."Qty. Rcd. Not Invoiced" * QtyPerUnit(PurchRcptLine."Qty. per Unit of Measure");
                SourceId := PurchRcptLine.RecordId();
                // the order line holds the current price; the receipt line the price at receipt
                HasOrderTerms := true;
                OrderCostBase := PurchRcptLine."Direct Unit Cost" / QtyPerUnit(PurchRcptLine."Qty. per Unit of Measure");
                OrderDiscountPct := PurchRcptLine."Line Discount %";
                if GetOrderLine(PurchRcptLine."Order No.", PurchRcptLine."Order Line No.", OrderLine) then
                    HasOrderTerms := ReadOrderTerms(OrderLine, PurchaseLine, OrderCostBase, OrderDiscountPct);
            end;
        end else
            if PurchaseLine."Order No." <> '' then begin
                if GetOrderLine(PurchaseLine."Order No.", PurchaseLine."Order Line No.", OrderLine) then begin
                    HasReceiptOrOrder := true;
                    AvailableQtyBase := OrderLine."Qty. Rcd. Not Invoiced (Base)";
                    SourceId := OrderLine.RecordId();
                    HasOrderTerms := ReadOrderTerms(OrderLine, PurchaseLine, OrderCostBase, OrderDiscountPct);
                end;
            end else
                // keyed by hand: match the open order lines of the same vendor, item and variant
                if FindOpenOrderLines(PurchaseLine, OrderLine, AvailableQtyBase) then begin
                    HasReceiptOrOrder := true;
                    SourceId := OrderLine.RecordId();
                    HasOrderTerms := ReadOrderTerms(OrderLine, PurchaseLine, OrderCostBase, OrderDiscountPct);
                    AvailableQtyBase := ClaimPooledQty(PurchaseLine, AvailableQtyBase);
                end;

        if HasReceiptOrOrder then
            CheckNotReceived(PurchaseLine, AvailableQtyBase, SourceId, TempFinding, RunContext);
        if HasOrderTerms then begin
            CheckPriceVsOrder(PurchaseLine, OrderCostBase, SourceId, TempFinding, RunContext);
            CheckDiscountVsOrder(PurchaseLine, OrderDiscountPct, SourceId, TempFinding, RunContext);
        end;
        CheckPriceVsHistory(PurchaseLine, TempFinding, RunContext);
    end;

    // a) More invoiced than received and not yet invoiced.
    local procedure CheckNotReceived(PurchaseLine: Record "Purchase Line"; AvailableQtyBase: Decimal; SourceId: RecordId; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        FindingKey: Text;
        AvailableQty: Decimal;
        MissingQty: Decimal;
        Amount: Decimal;
    begin
        if PurchaseLine."Quantity (Base)" <= AvailableQtyBase then
            exit;
        AvailableQty := Round(AvailableQtyBase / QtyPerUnit(PurchaseLine."Qty. per Unit of Measure"), 0.00001);
        MissingQty := Round((PurchaseLine."Quantity (Base)" - AvailableQtyBase) / QtyPerUnit(PurchaseLine."Qty. per Unit of Measure"), 0.00001);
        Amount := ToLcy(MissingQty * PurchaseLine."Line Amount" / PurchaseLine.Quantity);
        FindingKey := NewFindingKey(NotReceivedTok, PurchaseLine."Line No.");
        RunContext.AddQuantity(FindingKey, InvoicedQtyFactTok, PurchaseLine.Quantity);
        RunContext.AddQuantity(FindingKey, ReceivedQtyFactTok, AvailableQty);
        RunContext.AddQuantity(FindingKey, MissingQtyFactTok, MissingQty);
        RunContext.AddAmount(FindingKey, MissingAmountFactTok, Amount);
        AddFinding(TempFinding, FindingKey, NotReceivedTok, Enum::"EXR Severity"::High, LineSubject(PurchaseLine),
            StrSubstNo(NotReceivedLbl, RunContext.FormatQuantity(PurchaseLine.Quantity), RunContext.FormatQuantity(AvailableQty), RunContext.FormatQuantity(MissingQty)),
            Enum::"EXR Action"::"Hold until received", Amount, SourceId);
    end;

    // b) Unit cost against the order, per base unit, beyond the tolerance.
    local procedure CheckPriceVsOrder(PurchaseLine: Record "Purchase Line"; OrderCostBase: Decimal; SourceId: RecordId; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        FindingSeverity: Enum "EXR Severity";
        FindingKey: Text;
        InvoiceCostBase: Decimal;
        DifferencePct: Decimal;
        InvoiceCost: Decimal;
        OrderCost: Decimal;
        Amount: Decimal;
    begin
        if OrderCostBase = 0 then
            exit;
        InvoiceCostBase := PurchaseLine."Direct Unit Cost" / QtyPerUnit(PurchaseLine."Qty. per Unit of Measure");
        DifferencePct := (InvoiceCostBase - OrderCostBase) / OrderCostBase * 100;
        if Abs(DifferencePct) <= TolerancePct then
            exit;
        InvoiceCost := ToLcy(PurchaseLine."Direct Unit Cost");
        OrderCost := ToLcy(OrderCostBase * QtyPerUnit(PurchaseLine."Qty. per Unit of Measure"));
        Amount := ToLcy((InvoiceCostBase - OrderCostBase) * PurchaseLine."Quantity (Base)");
        FindingKey := NewFindingKey(PriceVsOrderTok, PurchaseLine."Line No.");
        RunContext.AddAmount(FindingKey, InvoiceCostFactTok, InvoiceCost);
        RunContext.AddAmount(FindingKey, OrderCostFactTok, OrderCost);
        RunContext.AddPercent(FindingKey, DifferencePctFactTok, DifferencePct);
        RunContext.AddAmount(FindingKey, DifferenceAmountFactTok, Amount);
        FindingSeverity := Enum::"EXR Severity"::Medium;
        if DifferencePct < 0 then
            FindingSeverity := Enum::"EXR Severity"::Low;
        AddFinding(TempFinding, FindingKey, PriceVsOrderTok, FindingSeverity, LineSubject(PurchaseLine),
            StrSubstNo(PriceVsOrderLbl, RunContext.FormatAmount(InvoiceCost), RunContext.FormatAmount(OrderCost), RunContext.FormatPercent(DifferencePct)),
            PriceAction(DifferencePct), Amount, SourceId);
    end;

    // c) Unit cost against the average of the vendor's latest three posted invoice lines for the item.
    local procedure CheckPriceVsHistory(PurchaseLine: Record "Purchase Line"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        PurchInvLine: Record "Purch. Inv. Line";
        LatestLineId: RecordId;
        FindingSeverity: Enum "EXR Severity";
        FindingKey: Text;
        Compared: Integer;
        TotalCostBase: Decimal;
        AverageCostBase: Decimal;
        InvoiceCostBase: Decimal;
        DifferencePct: Decimal;
        Amount: Decimal;
    begin
        PurchInvLine.SetCurrentKey(Type, "No.", "Variant Code");
        PurchInvLine.SetRange(Type, PurchInvLine.Type::Item);
        PurchInvLine.SetRange("No.", PurchaseLine."No.");
        PurchInvLine.SetRange("Variant Code", PurchaseLine."Variant Code");
        PurchInvLine.SetRange("Buy-from Vendor No.", PurchaseLine."Buy-from Vendor No.");
        PurchInvLine.SetFilter(Quantity, '<>0');
        PurchInvLine.SetLoadFields("Document No.", "Direct Unit Cost", "Qty. per Unit of Measure");
        // Limit: latest by posted invoice number, not by posting date; use a dated query if number series are mixed
        PurchInvLine.Ascending(false);
        if not PurchInvLine.FindSet() then
            exit;
        LatestLineId := PurchInvLine.RecordId();
        repeat
            Compared += 1;
            TotalCostBase += PostedUnitCostLcy(PurchInvLine) / QtyPerUnit(PurchInvLine."Qty. per Unit of Measure");
        until (PurchInvLine.Next() = 0) or (Compared = 3);
        AverageCostBase := TotalCostBase / Compared;
        if AverageCostBase = 0 then
            exit;
        InvoiceCostBase := ToLcyUnrounded(PurchaseLine."Direct Unit Cost") / QtyPerUnit(PurchaseLine."Qty. per Unit of Measure");
        DifferencePct := (InvoiceCostBase - AverageCostBase) / AverageCostBase * 100;
        if Abs(DifferencePct) <= TolerancePct then
            exit;
        Amount := Round((InvoiceCostBase - AverageCostBase) * PurchaseLine."Quantity (Base)");
        FindingKey := NewFindingKey(PriceVsHistoryTok, PurchaseLine."Line No.");
        RunContext.AddAmount(FindingKey, InvoiceCostFactTok, Round(InvoiceCostBase * QtyPerUnit(PurchaseLine."Qty. per Unit of Measure")));
        // one posted line has no average to speak of
        if Compared = 1 then
            RunContext.AddAmount(FindingKey, HistoryOneCostFactTok, Round(AverageCostBase * QtyPerUnit(PurchaseLine."Qty. per Unit of Measure")))
        else
            RunContext.AddAmount(FindingKey, HistoryCostFactTok, Round(AverageCostBase * QtyPerUnit(PurchaseLine."Qty. per Unit of Measure")));
        RunContext.AddPhrase(FindingKey, HistoryCountFactTok, RunContext.CountPhrase(Compared, OnePostedLineLbl, PostedLinesLbl));
        RunContext.AddPercent(FindingKey, DifferencePctFactTok, DifferencePct);
        RunContext.AddAmount(FindingKey, DifferenceAmountFactTok, Amount);
        FindingSeverity := Enum::"EXR Severity"::Low;
        AddFinding(TempFinding, FindingKey, PriceVsHistoryTok, FindingSeverity, LineSubject(PurchaseLine),
            PriceVsHistoryDetail(RunContext, Round(InvoiceCostBase * QtyPerUnit(PurchaseLine."Qty. per Unit of Measure")),
                Round(AverageCostBase * QtyPerUnit(PurchaseLine."Qty. per Unit of Measure")), Compared, DifferencePct),
            PriceAction(DifferencePct), Amount, LatestLineId);
    end;

    // d) Line discount changed against the order.
    local procedure CheckDiscountVsOrder(PurchaseLine: Record "Purchase Line"; OrderDiscountPct: Decimal; SourceId: RecordId; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        FindingKey: Text;
        Amount: Decimal;
    begin
        if PurchaseLine."Line Discount %" = OrderDiscountPct then
            exit;
        // positive when the invoice gives less discount than the order
        Amount := ToLcy((OrderDiscountPct - PurchaseLine."Line Discount %") / 100 * PurchaseLine."Direct Unit Cost" * PurchaseLine.Quantity);
        FindingKey := NewFindingKey(DiscountVsOrderTok, PurchaseLine."Line No.");
        RunContext.AddPercent(FindingKey, InvoiceDiscountFactTok, PurchaseLine."Line Discount %");
        RunContext.AddPercent(FindingKey, OrderDiscountFactTok, OrderDiscountPct);
        RunContext.AddAmount(FindingKey, DifferenceAmountFactTok, Amount);
        AddFinding(TempFinding, FindingKey, DiscountVsOrderTok, Enum::"EXR Severity"::Medium, LineSubject(PurchaseLine),
            StrSubstNo(DiscountVsOrderLbl, RunContext.FormatPercent(PurchaseLine."Line Discount %"), RunContext.FormatPercent(OrderDiscountPct)),
            PriceAction(Amount), Amount, SourceId);
    end;

    // e) A G/L account line, such as freight, with no order or receipt behind it.
    local procedure CheckGLAccountLine(PurchaseLine: Record "Purchase Line"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        FindingKey: Text;
        Amount: Decimal;
    begin
        if (PurchaseLine."Receipt No." <> '') or (PurchaseLine."Order No." <> '') then
            exit;
        Amount := ToLcy(PurchaseLine."Line Amount");
        FindingKey := NewFindingKey(NoOrderLinkTok, PurchaseLine."Line No.");
        RunContext.AddAmount(FindingKey, LineAmountFactTok, Amount);
        AddFinding(TempFinding, FindingKey, NoOrderLinkTok, Enum::"EXR Severity"::Low, LineSubject(PurchaseLine),
            StrSubstNo(NoOrderLinkLbl, RunContext.FormatAmount(Amount)),
            Enum::"EXR Action"::"Assign as item charge", Amount, PurchaseLine.RecordId());
    end;

    // f) A Charge (Item) line that is not fully assigned.
    local procedure CheckChargeLine(PurchaseLine: Record "Purchase Line"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        FindingKey: Text;
        UnassignedQty: Decimal;
        Amount: Decimal;
    begin
        UnassignedQty := PurchaseLine.Quantity - PurchaseLine."Qty. Assigned" - PurchaseLine."Qty. to Assign";
        if UnassignedQty <= 0 then
            exit;
        Amount := ToLcy(UnassignedQty * PurchaseLine."Line Amount" / PurchaseLine.Quantity);
        FindingKey := NewFindingKey(ChargeNotAssignedTok, PurchaseLine."Line No.");
        RunContext.AddQuantity(FindingKey, UnassignedQtyFactTok, UnassignedQty);
        RunContext.AddAmount(FindingKey, UnassignedAmountFactTok, Amount);
        AddFinding(TempFinding, FindingKey, ChargeNotAssignedTok, Enum::"EXR Severity"::Medium, LineSubject(PurchaseLine),
            StrSubstNo(ChargeNotAssignedLbl, RunContext.FormatQuantity(UnassignedQty), RunContext.FormatQuantity(PurchaseLine.Quantity)),
            Enum::"EXR Action"::"Assign as item charge", Amount, PurchaseLine.RecordId());
    end;

    // g) A posted invoice from the same vendor with the same normalised vendor invoice number and amount.
    local procedure CheckDuplicate(PurchaseHeader: Record "Purchase Header"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        PurchInvHeader: Record "Purch. Inv. Header";
        FindingKey: Text;
        Normalised: Text;
        Matches: Integer;
        Amount: Decimal;
    begin
        Normalised := NormaliseInvoiceNo(PurchaseHeader."Vendor Invoice No.");
        if Normalised = '' then
            exit;
        PurchaseHeader.CalcFields("Amount Including VAT");
        PurchInvHeader.SetCurrentKey("Buy-from Vendor No.");
        PurchInvHeader.SetRange("Buy-from Vendor No.", PurchaseHeader."Buy-from Vendor No.");
        PurchInvHeader.SetFilter("Vendor Invoice No.", LooseFilter(Normalised));
        PurchInvHeader.SetLoadFields("No.", "Vendor Invoice No.", "Currency Code");
        PurchInvHeader.SetAutoCalcFields("Amount Including VAT");
        if PurchInvHeader.FindSet() then
            repeat
                if (NormaliseInvoiceNo(PurchInvHeader."Vendor Invoice No.") = Normalised) and
                   (PurchInvHeader."Currency Code" = PurchaseHeader."Currency Code") and
                   (PurchInvHeader."Amount Including VAT" = PurchaseHeader."Amount Including VAT")
                then begin
                    Matches += 1;
                    Amount := ToLcy(PurchInvHeader."Amount Including VAT");
                    FindingKey := NewFindingKey(DuplicateTok, Matches);
                    RunContext.AddAmount(FindingKey, PostedAmountFactTok, Amount);
                    AddFinding(TempFinding, FindingKey, DuplicateTok, Enum::"EXR Severity"::High,
                        StrSubstNo(DuplicateSubjectLbl, PurchInvHeader."No.", PurchInvHeader."Vendor Invoice No."),
                        StrSubstNo(DuplicateLbl, RunContext.FormatAmount(Amount)),
                        Enum::"EXR Action"::"Query possible duplicate", Amount, PurchInvHeader.RecordId());
                end;
            until PurchInvHeader.Next() = 0;
    end;

    // One line reads "on the latest posted invoice line", several "an average of ... on the last 3 posted invoice lines".
    local procedure PriceVsHistoryDetail(var RunContext: Codeunit "EXR Run Context"; InvoiceCost: Decimal; AverageCost: Decimal; Compared: Integer; DifferencePct: Decimal): Text
    begin
        if Compared = 1 then
            exit(StrSubstNo(PriceVsOneInvoiceLbl, RunContext.FormatAmount(InvoiceCost), RunContext.FormatAmount(AverageCost), RunContext.FormatPercent(DifferencePct)));
        exit(StrSubstNo(PriceVsHistoryLbl, RunContext.FormatAmount(InvoiceCost), RunContext.FormatAmount(AverageCost), Compared, RunContext.FormatPercent(DifferencePct)));
    end;

    // A grammatical sentence for the summary, such as "1 of the 4 lines checked has no differences".
    local procedure LinesCheckedSentence(LinesChecked: Integer; LinesOk: Integer): Text
    begin
        case true of
            LinesChecked = 0:
                exit(NoLinesCheckedLbl);
            (LinesChecked = 1) and (LinesOk = 1):
                exit(OnlyLineOkLbl);
            LinesChecked = 1:
                exit(OnlyLineDiffersLbl);
            LinesOk = LinesChecked:
                exit(StrSubstNo(AllLinesOkLbl, LinesChecked));
            LinesOk = 0:
                exit(StrSubstNo(AllLinesDifferLbl, LinesChecked));
            LinesOk = 1:
                exit(StrSubstNo(OneLineOkLbl, LinesChecked));
        end;
        exit(StrSubstNo(SomeLinesOkLbl, LinesOk, LinesChecked));
    end;

    // Tells the user what was saved; the panel on the open invoice only refreshes when the invoice is reopened.
    local procedure KeptMessage(PurchaseHeader: Record "Purchase Header"; ExrRun: Record "EXR Run"; EmailPrepared: Boolean) Confirmation: Text
    begin
        Confirmation := KeptMsg;
        if PurchaseHeader."On Hold" <> '' then
            Confirmation := StrSubstNo(KeptOnHoldMsg, PurchaseHeader."No.", PurchaseHeader."On Hold");
        if not EmailPrepared then
            exit(Confirmation);
        if ExrRun."Email Draft Saved" then
            exit(StrSubstNo(MessageTok, Confirmation, DraftSavedMsg));
        exit(StrSubstNo(MessageTok, Confirmation, DraftKeptMsg));
    end;

    local procedure GetOrderLine(OrderNo: Code[20]; OrderLineNo: Integer; var OrderLine: Record "Purchase Line"): Boolean
    begin
        if (OrderNo = '') or (OrderLineNo = 0) then
            exit(false);
        OrderLine.SetLoadFields("Direct Unit Cost", "Qty. per Unit of Measure", "Line Discount %", "Currency Code", "Qty. Rcd. Not Invoiced (Base)");
        exit(OrderLine.Get(OrderLine."Document Type"::Order, OrderNo, OrderLineNo));
    end;

    // Sums what is received and not yet invoiced on all order lines; the first open line gives the price.
    local procedure FindOpenOrderLines(PurchaseLine: Record "Purchase Line"; var OrderLine: Record "Purchase Line"; var AvailableQtyBase: Decimal): Boolean
    begin
        OrderLine.SetCurrentKey("Document Type", "Buy-from Vendor No.");
        OrderLine.SetRange("Document Type", OrderLine."Document Type"::Order);
        OrderLine.SetRange("Buy-from Vendor No.", PurchaseLine."Buy-from Vendor No.");
        OrderLine.SetRange(Type, OrderLine.Type::Item);
        OrderLine.SetRange("No.", PurchaseLine."No.");
        OrderLine.SetRange("Variant Code", PurchaseLine."Variant Code");
        if OrderLine.IsEmpty() then
            exit(false);
        OrderLine.CalcSums("Qty. Rcd. Not Invoiced (Base)");
        AvailableQtyBase := OrderLine."Qty. Rcd. Not Invoiced (Base)";
        OrderLine.SetLoadFields("Direct Unit Cost", "Qty. per Unit of Measure", "Line Discount %", "Currency Code");
        OrderLine.SetFilter("Qty. Rcd. Not Invoiced (Base)", '>0');
        if OrderLine.FindFirst() then
            exit(true);
        OrderLine.SetRange("Qty. Rcd. Not Invoiced (Base)");
        exit(OrderLine.FindFirst());
    end;

    // Hand-keyed lines for the same item share one pool: each gets what the earlier lines left, never below zero.
    local procedure ClaimPooledQty(PurchaseLine: Record "Purchase Line"; PooledQtyBase: Decimal) AvailableQtyBase: Decimal
    var
        ItemVariantKey: Text;
        ClaimedBase: Decimal;
    begin
        ItemVariantKey := StrSubstNo(ItemVariantKeyTok, PurchaseLine."No.", PurchaseLine."Variant Code");
        if not ClaimedQtyBase.Get(ItemVariantKey, ClaimedBase) then
            ClaimedBase := 0;
        AvailableQtyBase := PooledQtyBase - ClaimedBase;
        if AvailableQtyBase < 0 then
            AvailableQtyBase := 0;
        ClaimedQtyBase.Set(ItemVariantKey, ClaimedBase + PurchaseLine."Quantity (Base)");
    end;

    // A difference in the company's favour defaults to accept, so on its own it never holds the invoice.
    local procedure PriceAction(DifferenceAgainstUs: Decimal): Enum "EXR Action"
    begin
        if DifferenceAgainstUs < 0 then
            exit(Enum::"EXR Action"::"Accept within tolerance");
        exit(Enum::"EXR Action"::"Ask vendor to confirm price");
    end;

    // False when the order is in another currency, so its price cannot be compared.
    local procedure ReadOrderTerms(OrderLine: Record "Purchase Line"; PurchaseLine: Record "Purchase Line"; var OrderCostBase: Decimal; var OrderDiscountPct: Decimal): Boolean
    begin
        if OrderLine."Currency Code" <> PurchaseLine."Currency Code" then
            exit(false);
        OrderCostBase := OrderLine."Direct Unit Cost" / QtyPerUnit(OrderLine."Qty. per Unit of Measure");
        OrderDiscountPct := OrderLine."Line Discount %";
        exit(true);
    end;

    local procedure PostedUnitCostLcy(PurchInvLine: Record "Purch. Inv. Line"): Decimal
    var
        PurchInvHeader: Record "Purch. Inv. Header";
    begin
        PurchInvHeader.SetLoadFields("Currency Code", "Currency Factor");
        if PurchInvHeader.Get(PurchInvLine."Document No.") then
            if (PurchInvHeader."Currency Code" <> '') and (PurchInvHeader."Currency Factor" <> 0) then
                exit(PurchInvLine."Direct Unit Cost" / PurchInvHeader."Currency Factor");
        exit(PurchInvLine."Direct Unit Cost");
    end;

    local procedure HasVendorQuery(var TempFinding: Record "EXR Finding" temporary): Boolean
    begin
        if TempFinding.FindSet() then
            repeat
                if IsVendorQuery(TempFinding."Action") then
                    exit(true);
            until TempFinding.Next() = 0;
        exit(false);
    end;

    // Actions that need an answer from the vendor; they also put the invoice on hold.
    local procedure IsVendorQuery(FindingAction: Enum "EXR Action"): Boolean
    begin
        exit(FindingAction in [Enum::"EXR Action"::"Hold until received",
                               Enum::"EXR Action"::"Request credit memo",
                               Enum::"EXR Action"::"Ask vendor to confirm price",
                               Enum::"EXR Action"::"Query possible duplicate"]);
    end;

    local procedure AddFinding(var TempFinding: Record "EXR Finding" temporary; FindingKey: Text; FindingType: Text; FindingSeverity: Enum "EXR Severity"; Subject: Text; Detail: Text; FindingAction: Enum "EXR Action"; AmountLcy: Decimal; SourceId: RecordId)
    var
        LineNo: Integer;
    begin
        TempFinding.Reset();
        LineNo := (TempFinding.Count() + 1) * 10000;
        TempFinding.Init();
        TempFinding."Line No." := LineNo;
        TempFinding."Finding Key" := CopyStr(FindingKey, 1, MaxStrLen(TempFinding."Finding Key"));
        TempFinding."Finding Type" := CopyStr(FindingType, 1, MaxStrLen(TempFinding."Finding Type"));
        TempFinding.Severity := FindingSeverity;
        TempFinding.Subject := CopyStr(Subject, 1, MaxStrLen(TempFinding.Subject));
        TempFinding.Detail := CopyStr(Detail, 1, MaxStrLen(TempFinding.Detail));
        TempFinding.Description := TempFinding.Detail;
        TempFinding."Action" := FindingAction;
        TempFinding."Amount (LCY)" := AmountLcy;
        TempFinding."Source Record ID" := SourceId;
        TempFinding.Accepted := true;
        TempFinding.Insert();
    end;

    local procedure NewFindingKey(FindingType: Text; Number: Integer): Text
    begin
        exit(StrSubstNo(FindingKeyTok, FindingType, Format(Number, 0, 9)));
    end;

    local procedure LineSubject(PurchaseLine: Record "Purchase Line"): Text
    begin
        exit(StrSubstNo(LineSubjectLbl, Format(PurchaseLine."Line No.", 0, 9), PurchaseLine."No.", PurchaseLine.Description));
    end;

    // Wildcards between the characters find INV-4471 for INV4471; the exact check runs on the normalised number.
    local procedure LooseFilter(Normalised: Text) Filter: Text
    var
        Index: Integer;
    begin
        Filter := '@*';
        for Index := 1 to StrLen(Normalised) do
            Filter += CopyStr(Normalised, Index, 1) + '*';
    end;

    local procedure QtyPerUnit(QtyPerUnitOfMeasure: Decimal): Decimal
    begin
        if QtyPerUnitOfMeasure = 0 then
            exit(1);
        exit(QtyPerUnitOfMeasure);
    end;

    local procedure ToLcy(Amount: Decimal): Decimal
    begin
        exit(Round(ToLcyUnrounded(Amount)));
    end;

    local procedure ToLcyUnrounded(Amount: Decimal): Decimal
    begin
        if (CurrencyCode = '') or (CurrencyFactor = 0) then
            exit(Amount);
        exit(Amount / CurrencyFactor);
    end;

    local procedure NewLine(): Text
    var
        LineFeed: Char;
    begin
        LineFeed := 10;
        exit(Format(LineFeed));
    end;
}
