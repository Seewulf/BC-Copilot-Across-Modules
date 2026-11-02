namespace PrabinBhusal.ExplainResolve;

// One finding's email in the review dialog, such as a customer reminder. The text uses the full width and can be changed before Keep it.
page 58206 "EXR Email Preview"
{
    Caption = 'Email draft';
    // the finding's subject (the customer), not the record key
    DataCaptionExpression = Rec.Subject;
    PageType = StandardDialog;
    ApplicationArea = All;
    SourceTable = "EXR Finding";
    SourceTableTemporary = true;
    Extensible = false;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'Email';

                field(Subject; Rec.Subject)
                {
                    Caption = 'For';
                    Editable = false;
                }
                field(EmailSubject; Rec."Email Subject")
                {
                    Caption = 'Subject';
                }
            }
            // alone in its own group without a caption, so the text uses the full width
            group(EmailText)
            {
                Caption = 'Email text';

                field(BodyText; BodyText)
                {
                    Caption = 'Email text';
                    ShowCaption = false;
                    MultiLine = true;
                    ToolTip = 'Specifies the email text. When you keep the review, Business Central replaces the line in square brackets with the open items and the total, and adds the recipient from the customer card. It is saved as a draft and never sent automatically.';
                }
            }
        }
    }

    // var, so the body is read from the caller's temporary finding
    procedure SetEmail(var TempFinding: Record "EXR Finding" temporary)
    var
        Engine: Codeunit "EXR Engine";
    begin
        Rec := TempFinding;
        Rec.Insert();
        BodyText := Engine.PreviewEmailBody(TempFinding.GetEmailBody());
    end;

    procedure GetEmail(var NewSubject: Text; var NewBody: Text)
    var
        Engine: Codeunit "EXR Engine";
    begin
        NewSubject := Rec."Email Subject";
        NewBody := Engine.EmailBodyFromPreview(BodyText);
    end;

    var
        BodyText: Text;
}
