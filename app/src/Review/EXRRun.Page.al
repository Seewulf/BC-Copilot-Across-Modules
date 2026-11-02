namespace PrabinBhusal.ExplainResolve;

using Microsoft.Utilities;

// One run with its kept findings and email text. Read-only: it is the audit trail.
// Findings with their own email, such as customer reminders, open it with Open Email on the findings.
page 58204 "EXR Run"
{
    Caption = 'Explain and Resolve Run';
    PageType = Card;
    SourceTable = "EXR Run";
    ApplicationArea = All;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';

                field("Entry No."; Rec."Entry No.") { }
                field(Capability; Rec.Capability) { }
                field("Source No."; Rec."Source No.") { }
                field(Status; Rec.Status) { }
                field("Created At"; Rec."Created At") { }
                field("User ID"; Rec."User ID") { }
                field(Summary; Rec.Summary)
                {
                    MultiLine = true;
                }
                field("Unverified Figures"; Rec."Unverified Figures") { }
                field("Error Message"; Rec."Error Message")
                {
                    MultiLine = true;
                }
            }
            part(Findings; "EXR Findings Part")
            {
                Caption = 'Kept findings';
            }
            // a review with one email per finding, such as Plan collections, opens them on the findings instead
            group(Email)
            {
                Caption = 'Email draft';
                Visible = RunEmailVisible;

                field("Email To"; Rec."Email To") { }
                field("Email Subject"; Rec."Email Subject") { }
                field(EmailBody; EmailBody)
                {
                    Caption = 'Email Body';
                    MultiLine = true;
                    ToolTip = 'Specifies the email text that was kept with the run.';
                }
                field("Email Draft Saved"; Rec."Email Draft Saved") { }
            }
            group(Usage)
            {
                Caption = 'Usage';

                field(Model; Rec.Model) { }
                field("Input Tokens"; Rec."Input Tokens") { }
                field("Output Tokens"; Rec."Output Tokens") { }
                field(Duration; Rec.Duration) { }
                field("Prompt Version"; Rec."Prompt Version") { }
                // only the options that the run's capability uses
                group(ToleranceOption)
                {
                    ShowCaption = false;
                    Visible = ToleranceVisible;

                    field("Tolerance %"; Rec."Tolerance %") { }
                }
                group(SelectionOptions)
                {
                    ShowCaption = false;
                    Visible = SelectionVisible;

                    field("Salesperson Code"; Rec."Salesperson Code") { }
                    field("Customer Posting Group"; Rec."Customer Posting Group") { }
                    field("Max. Customers"; Rec."Max. Customers") { }
                }
                field("Email Tone"; Rec."Email Tone") { }
                field("User Note"; Rec."User Note")
                {
                    MultiLine = true;
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
                ToolTip = 'Open the email text in the email editor, addressed and related to the document. It is sent only if you choose Send.';

                trigger OnAction()
                var
                    EmailDraft: Codeunit "EXR Email Draft";
                begin
                    EmailDraft.OpenInEditor(Rec);
                end;
            }
            action(OpenSource)
            {
                Caption = 'Open Document';
                Image = Document;
                // a run over a selection, such as Plan collections, has no single document
                Enabled = HasSource;
                ToolTip = 'Open the document or record that was reviewed.';

                trigger OnAction()
                var
                    PageManagement: Codeunit "Page Management";
                    SourceRecordRef: RecordRef;
                begin
                    if SourceRecordRef.Get(Rec."Source Record ID") then
                        PageManagement.PageRun(SourceRecordRef);
                end;
            }
        }
        area(Promoted)
        {
            actionref(OpenEmail_Promoted; OpenEmail) { }
            actionref(OpenSource_Promoted; OpenSource) { }
        }
    }

    trigger OnAfterGetCurrRecord()
    var
        Handler: Interface "EXR Capability Handler";
    begin
        Handler := Rec.Capability;
        ToleranceVisible := Handler.UsesTolerance();
        SelectionVisible := Handler.ReviewsSelection();
        RunEmailVisible := not Handler.DraftsEmailPerFinding();
        EmailBody := Rec.GetEmailBody();
        HasSource := not IsNullGuid(Rec."Source System Id");
        CurrPage.Findings.Page.LoadRun(Rec."Entry No.");
    end;

    var
        EmailBody: Text;
        HasSource: Boolean;
        ToleranceVisible: Boolean;
        SelectionVisible: Boolean;
        RunEmailVisible: Boolean;
}
