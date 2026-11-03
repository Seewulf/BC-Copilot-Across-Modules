namespace PrabinBhusal.ExplainResolve;

using Microsoft.Utilities;

// Findings of one run, held in a temporary copy: editable Accept in the dialog, read-only on the run card.
// Ranked findings (Plan collections) are listed in rank order; findings with their own email open it with Open Email.
page 58202 "EXR Findings Part"
{
    Caption = 'Findings';
    PageType = ListPart;
    SourceTable = "EXR Finding";
    SourceTableTemporary = true;
    SourceTableView = sorting("Run Entry No.", Severity) order(descending);
    ApplicationArea = All;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field(Accepted; Rec.Accepted)
                {
                    Editable = AcceptEditable;
                }
                field(Severity; Rec.Severity)
                {
                    Editable = false;
                    StyleExpr = SeverityStyle;
                }
                field(Subject; Rec.Subject)
                {
                    Editable = false;

                    trigger OnDrillDown()
                    begin
                        OpenSource();
                    end;
                }
                field(Description; Rec.Description)
                {
                    Editable = false;
                    StyleExpr = DescriptionStyle;
                }
                field(FindingAction; Rec."Action")
                {
                    Editable = false;
                }
                // a part's own actions are not shown in a prompt dialog, so the email opens from this column
                field(Email; Rec."Email Subject")
                {
                    Caption = 'Email';
                    Editable = false;
                    Visible = EmailColumnVisible;
                    ToolTip = 'Specifies the subject of the email drafted for this finding. Choose it to read or change the email.';

                    trigger OnDrillDown()
                    begin
                        if Rec."Email Subject" <> '' then
                            OpenEmailDraft();
                    end;
                }
                field(Confidence; Rec.Confidence)
                {
                    Editable = false;
                }
                field("Amount (LCY)"; Rec."Amount (LCY)")
                {
                    Editable = false;
                }
                field(Detail; Rec.Detail)
                {
                    Editable = false;
                    Visible = false;
                }
                field("Unverified Figure"; Rec."Unverified Figure")
                {
                    Editable = false;
                    Visible = false;
                }
                // filled in on Keep it; a column's visibility cannot follow the host, so these are added with Personalize
                field("Email To"; Rec."Email To")
                {
                    Editable = false;
                    Visible = false;
                }
                field("Email Draft Saved"; Rec."Email Draft Saved")
                {
                    Editable = false;
                    Visible = false;
                }
                // a payment run's vendor and the invoice entry a kept Hold put on hold
                field("Account No."; Rec."Account No.")
                {
                    Editable = false;
                    Visible = false;
                }
                field("Ledger Entry No."; Rec."Ledger Entry No.")
                {
                    Editable = false;
                    Visible = false;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(OpenEmail)
            {
                Caption = 'Open Email';
                Image = Email;
                Enabled = Rec."Email Subject" <> '';
                ToolTip = 'Show the email drafted for this finding. In the dialog you can change it before you keep it; on a kept review it opens in the email editor, and it is sent only if you choose Send.';

                trigger OnAction()
                begin
                    OpenEmailDraft();
                end;
            }
        }
    }

    trigger OnInit()
    begin
        AcceptEditable := true;
        EmailColumnVisible := true;
    end;

    // Called from the host's OnOpenPage, before the columns are shown.
    procedure SetEmailColumnVisible(NewEmailColumnVisible: Boolean)
    begin
        EmailColumnVisible := NewEmailColumnVisible;
    end;

    trigger OnAfterGetRecord()
    begin
        case Rec.Severity of
            Rec.Severity::High:
                SeverityStyle := Format(PageStyle::Unfavorable);
            Rec.Severity::Medium:
                SeverityStyle := Format(PageStyle::Ambiguous);
            else
                SeverityStyle := Format(PageStyle::Standard);
        end;
        DescriptionStyle := Format(PageStyle::Standard);
        if Rec."Unverified Figure" then
            DescriptionStyle := Format(PageStyle::Attention);
    end;

    procedure Load(var TempFinding: Record "EXR Finding" temporary)
    begin
        ClearRows();
        TempFinding.Reset();
        if TempFinding.FindSet() then
            repeat
                Rec := TempFinding;
                Rec.SetEmailBody(TempFinding.GetEmailBody());
                Rec.Insert();
            until TempFinding.Next() = 0;
        SortRows();
        CurrPage.Update(false);
    end;

    // The findings kept with a run; Accept cannot be changed any more.
    procedure LoadRun(RunEntryNo: Integer)
    var
        Finding: Record "EXR Finding";
    begin
        AcceptEditable := false;
        ClearRows();
        Finding.SetRange("Run Entry No.", RunEntryNo);
        if Finding.FindSet() then
            repeat
                Rec := Finding;
                Rec.SetEmailBody(Finding.GetEmailBody());
                Rec.Insert();
            until Finding.Next() = 0;
        SortRows();
        CurrPage.Update(false);
    end;

    // Copies the Accept choices and any edited emails back to the caller's findings.
    procedure GetAccepted(var TempFinding: Record "EXR Finding" temporary)
    var
        TempShownFinding: Record "EXR Finding" temporary;
    begin
        TempShownFinding.Copy(Rec, true);
        TempShownFinding.Reset();
        if TempShownFinding.FindSet() then
            repeat
                if TempFinding.Get(TempShownFinding."Run Entry No.", TempShownFinding."Line No.") then begin
                    TempFinding.Accepted := TempShownFinding.Accepted;
                    TempFinding."Email Subject" := TempShownFinding."Email Subject";
                    TempFinding.SetEmailBody(TempShownFinding.GetEmailBody());
                    TempFinding.Modify();
                end;
            until TempShownFinding.Next() = 0;
    end;

    // Reset also drops the sort, so the highest severity is put back on top.
    local procedure ClearRows()
    begin
        Rec.Reset();
        Rec.DeleteAll();
        Rec.SetCurrentKey("Run Entry No.", Severity);
        Rec.Ascending(false);
    end;

    // A ranked worklist reads top down: rank 1 first.
    local procedure SortRows()
    var
        Ranked: Boolean;
    begin
        Rec.SetFilter(Rank, '<>0');
        Ranked := not Rec.IsEmpty();
        Rec.SetRange(Rank);
        if not Ranked then
            exit;
        Rec.SetCurrentKey("Run Entry No.", Rank);
        Rec.Ascending(true);
    end;

    local procedure OpenSource()
    var
        PageManagement: Codeunit "Page Management";
        SourceRecordRef: RecordRef;
    begin
        if Rec."Source Record ID".TableNo() = 0 then
            exit;
        if not SourceRecordRef.Get(Rec."Source Record ID") then
            exit;
        if not PageManagement.PageRun(SourceRecordRef) then
            PageManagement.PageRunList(SourceRecordRef);
    end;

    // In the dialog the email can still be changed; once kept, it opens in the email editor.
    local procedure OpenEmailDraft()
    var
        EmailDraft: Codeunit "EXR Email Draft";
        EmailPreview: Page "EXR Email Preview";
        NewSubject: Text;
        NewBody: Text;
    begin
        if not AcceptEditable then begin
            // a draft saved on Keep it is already in the outbox; opening it again makes a second copy
            if Rec."Email Draft Saved" then
                if not Confirm(DraftInOutboxQst) then
                    exit;
            EmailDraft.OpenFindingInEditor(Rec);
            exit;
        end;
        EmailPreview.SetEmail(Rec);
        if EmailPreview.RunModal() <> Action::OK then
            exit;
        EmailPreview.GetEmail(NewSubject, NewBody);
        Rec."Email Subject" := CopyStr(NewSubject, 1, MaxStrLen(Rec."Email Subject"));
        Rec.SetEmailBody(NewBody);
        Rec.Modify();
    end;

    var
        SeverityStyle: Text;
        DescriptionStyle: Text;
        AcceptEditable: Boolean;
        EmailColumnVisible: Boolean;
        DraftInOutboxQst: Label 'This email is already saved as a draft in your email outbox. Do you want to open another copy?';
}
