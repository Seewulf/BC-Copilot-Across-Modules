namespace PrabinBhusal.ExplainResolve;

// The review dialog for every capability. Opened through RunPageLink with the capability and, for a single record, its source.
// Options show per capability: tolerance for Explain variance, filters and the customer count for Plan collections.
page 58201 "EXR Prompt"
{
    Caption = 'Explain and Resolve';
    PageType = PromptDialog;
    Extensible = false;
    IsPreview = true;
    ApplicationArea = All;
    SourceTable = "EXR Run";
    SourceTableTemporary = true;

    layout
    {
        area(PromptOptions)
        {
            field(EmailTone; Rec."Email Tone")
            {
                Caption = 'Email tone';
                ToolTip = 'Specifies the tone of the drafted emails.';
            }
        }
        area(Prompt)
        {
            field(UserNote; Rec."User Note")
            {
                ShowCaption = false;
                MultiLine = true;
                InstructionalText = 'Optional: add what you already know, for example that freight was agreed or that a customer is on a payment plan.';
                ToolTip = 'Specifies a note for the AI service. It is treated as information, never as an instruction.';
            }
            field(Tolerance; Rec."Tolerance %")
            {
                Caption = 'Tolerance %';
                Visible = ToleranceVisible;
                ToolTip = 'Specifies the price difference, in percent, that is accepted without a finding.';
            }
            field(SalespersonCode; Rec."Salesperson Code")
            {
                Caption = 'Salesperson';
                Visible = SelectionVisible;
            }
            field(CustomerPostingGroup; Rec."Customer Posting Group")
            {
                Caption = 'Customer posting group';
                Visible = SelectionVisible;
            }
            field(MaxCustomers; Rec."Max. Customers")
            {
                Caption = 'Max. customers';
                Visible = SelectionVisible;
            }
        }
        area(Content)
        {
            field(Summary; SummaryText)
            {
                Caption = 'Summary';
                MultiLine = true;
                Editable = false;
                ToolTip = 'Specifies the summary. Every figure in it comes from Business Central.';
            }
            field(UnverifiedFigures; HasUnverifiedFigures)
            {
                Caption = 'Unverified figures';
                Editable = false;
                Style = Attention;
                StyleExpr = HasUnverifiedFigures;
                ToolTip = 'Specifies whether the summary or an email contains a figure that the model wrote itself. Check it before you keep it.';
            }
            part(Findings; "EXR Findings Part")
            {
                Caption = 'Findings';
            }
            group(Email)
            {
                Caption = 'Email draft';
                Visible = RunEmailVisible;

                field(EmailSubject; EmailSubject)
                {
                    Caption = 'Subject';
                    ToolTip = 'Specifies the subject of the email. You can change it before you keep it. Business Central keeps the vendor invoice number in it.';
                }
            }
            // alone in its own group without a caption, so the text uses the full width of the dialog
            group(EmailText)
            {
                Caption = 'Email text';
                Visible = RunEmailVisible;

                field(EmailBody; EmailBody)
                {
                    Caption = 'Email text';
                    ShowCaption = false;
                    MultiLine = true;
                    ToolTip = 'Specifies the email text. You can change it before you keep it. When you keep it, Business Central replaces the line in square brackets with the accepted findings that need the vendor''s answer and adds the recipient. It is saved as a draft and never sent automatically.';
                }
            }
            field(KeepNoteField; KeepNote)
            {
                Caption = 'When you keep it';
                MultiLine = true;
                Editable = false;
                ToolTip = 'Specifies what Keep it saves and changes.';
            }
        }
    }

    actions
    {
        area(SystemActions)
        {
            systemaction(Generate)
            {
                Caption = 'Generate';
                ToolTip = 'Let Business Central find what needs attention and ask the AI service to explain it.';

                trigger OnAction()
                begin
                    RunGeneration();
                end;
            }
            systemaction(Regenerate)
            {
                Caption = 'Regenerate';
                ToolTip = 'Compute the findings again and ask for a new explanation.';

                trigger OnAction()
                begin
                    RunGeneration();
                end;
            }
            systemaction(OK)
            {
                Caption = 'Keep it';
                ToolTip = 'Save the review with the accepted findings and save the emails as drafts. Explain variance also puts the invoice on hold when a finding needs the vendor''s answer. Nothing is posted or sent.';
            }
            systemaction(Cancel)
            {
                Caption = 'Discard';
                ToolTip = 'Close without saving anything except the usage record.';
            }
        }
        area(PromptGuide)
        {
            action(PriceAgreed)
            {
                Caption = 'A price change was agreed';
                ToolTip = 'Tell the AI service that a new price was agreed with the vendor.';
                Visible = ToleranceVisible;

                trigger OnAction()
                begin
                    Rec."User Note" := PriceAgreedTxt;
                end;
            }
            action(FreightAgreed)
            {
                Caption = 'Freight was agreed';
                ToolTip = 'Tell the AI service that the freight charge was agreed.';
                Visible = ToleranceVisible;

                trigger OnAction()
                begin
                    Rec."User Note" := FreightAgreedTxt;
                end;
            }
            action(DeliveryLate)
            {
                Caption = 'The rest of the delivery is on its way';
                ToolTip = 'Tell the AI service that the missing goods are expected.';
                Visible = ToleranceVisible;

                trigger OnAction()
                begin
                    Rec."User Note" := DeliveryLateTxt;
                end;
            }
            action(PaymentPlan)
            {
                Caption = 'A customer agreed a payment plan';
                ToolTip = 'Tell the AI service that one of the customers agreed a payment plan.';
                Visible = SelectionVisible;

                trigger OnAction()
                begin
                    Rec."User Note" := PaymentPlanTxt;
                end;
            }
            action(SalesVisits)
            {
                Caption = 'Our sales team visits customers this week';
                ToolTip = 'Tell the AI service that a phone call or visit can be arranged this week.';
                Visible = SelectionVisible;

                trigger OnAction()
                begin
                    Rec."User Note" := SalesVisitsTxt;
                end;
            }
        }
    }

    trigger OnOpenPage()
    var
        Setup: Record "EXR Setup";
        Handler: Interface "EXR Capability Handler";
        Capability: Enum "EXR Capability";
        SourceSystemId: Guid;
        SourceTableNo: Integer;
    begin
        // the RunPageLink filters name the capability and, for a single record, the source record
        if Rec.GetFilter(Capability) = '' then
            Error(NoSourceErr);
        Capability := Rec.GetRangeMin(Capability);
        Handler := Capability;
        if Rec.GetFilter("Source Table No.") <> '' then
            SourceTableNo := Rec.GetRangeMin("Source Table No.");
        if Rec.GetFilter("Source System Id") <> '' then
            SourceSystemId := Rec.GetRangeMin("Source System Id")
        else
            if not Handler.ReviewsSelection() then
                Error(NoSourceErr);
        Setup.GetSetup();
        Rec.Reset();
        Rec.Init();
        Rec.Capability := Capability;
        Rec."Source Table No." := SourceTableNo;
        Rec."Source System Id" := SourceSystemId;
        Rec."Tolerance %" := Setup."Variance Tolerance %";
        Rec."Email Tone" := Setup."Default Email Tone";
        Rec.Insert();
        ToleranceVisible := Handler.UsesTolerance();
        SelectionVisible := Handler.ReviewsSelection();
        RunEmailVisible := not Handler.DraftsEmailPerFinding();
        CurrPage.Findings.Page.SetEmailColumnVisible(Handler.DraftsEmailPerFinding());
        // the web client drops a message raised while a prompt dialog closes, so the outcome is told up front
        if SelectionVisible then
            KeepNote := SelectionKeepNoteTxt
        else
            KeepNote := RecordKeepNoteTxt;
        CurrPage.Caption := Format(Capability);
    end;

    trigger OnQueryClosePage(CloseAction: Action): Boolean
    var
        Engine: Codeunit "EXR Engine";
    begin
        if Run."Entry No." = 0 then
            exit(true);
        if CloseAction = CloseAction::OK then begin
            CurrPage.Findings.Page.GetAccepted(TempFinding);
            Engine.Keep(Run, TempFinding, EmailSubject, Engine.EmailBodyFromPreview(EmailBody));
        end else
            Engine.Discard(Run);
        exit(true);
    end;

    // Each Generate is a new run. The engine swaps it in only when it succeeds and then discards the old one.
    local procedure RunGeneration()
    var
        NewRun: Record "EXR Run";
        Engine: Codeunit "EXR Engine";
    begin
        NewRun.Capability := Rec.Capability;
        NewRun."Source Table No." := Rec."Source Table No.";
        NewRun."Source System Id" := Rec."Source System Id";
        NewRun."Tolerance %" := Rec."Tolerance %";
        NewRun."Email Tone" := Rec."Email Tone";
        NewRun."User Note" := Rec."User Note";
        // the selection options are kept on the run only for the capability that uses them
        if SelectionVisible then begin
            NewRun."Salesperson Code" := Rec."Salesperson Code";
            NewRun."Customer Posting Group" := Rec."Customer Posting Group";
            NewRun."Max. Customers" := Rec."Max. Customers";
        end;
        Engine.Regenerate(Run, TempFinding, NewRun);
        SummaryText := Run.Summary;
        // StyleExpr needs a page variable, not a field of another record
        HasUnverifiedFigures := Run."Unverified Figures";
        EmailSubject := Run."Email Subject";
        EmailBody := Engine.PreviewEmailBody(Run.GetEmailBody());
        CurrPage.Findings.Page.Load(TempFinding);
    end;

    var
        Run: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        SummaryText: Text;
        EmailSubject: Text;
        EmailBody: Text;
        KeepNote: Text;
        ToleranceVisible: Boolean;
        SelectionVisible: Boolean;
        RunEmailVisible: Boolean;
        HasUnverifiedFigures: Boolean;
        NoSourceErr: Label 'Open this dialog from the record that you want to review.';
        PriceAgreedTxt: Label 'The vendor told us that the new price was agreed with our buyer.';
        FreightAgreedTxt: Label 'The freight charge was agreed with the vendor when the order was placed.';
        DeliveryLateTxt: Label 'The vendor says the rest of the delivery arrives next week.';
        PaymentPlanTxt: Label 'One of these customers agreed a payment plan with our credit controller last week.';
        SalesVisitsTxt: Label 'Our salespeople visit several of these customers this week, so a phone call or visit can be arranged.';
        RecordKeepNoteTxt: Label 'Keep it saves this review, puts the invoice on hold when a finding needs the vendor''s answer and saves the email as a draft (or keeps it on the review when no email account is set up). Nothing is posted or sent. Reopen the invoice to see the review in its panel.';
        SelectionKeepNoteTxt: Label 'Keep it saves the ticked customers as a worklist and saves their reminders as drafts (or keeps them on the review when no email account is set up). Nothing is posted or sent. Each customer card shows its latest review.';
}
