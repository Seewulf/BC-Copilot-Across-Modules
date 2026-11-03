namespace PrabinBhusal.ExplainResolve;

// The review dialog for every capability. Opened through RunPageLink with the capability and, for a single record, its source;
// for a payment run, the journal template and batch. Options show per capability: tolerance for Explain variance, filters and
// the customer count for Plan collections, the duplicate and bank-change windows for Check payment run.
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
                Visible = EmailToneVisible;
                ToolTip = 'Specifies the tone of the drafted emails.';
            }
        }
        area(Prompt)
        {
            field(UserNote; Rec."User Note")
            {
                ShowCaption = false;
                MultiLine = true;
                InstructionalText = 'Optional: add what you already know, for example that freight was agreed, that a customer is on a payment plan or that a vendor sends one large invoice a year.';
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
            field(DuplicateWindowDays; Rec."Duplicate Window Days")
            {
                Caption = 'Duplicate window (days)';
                Visible = PaymentWindowsVisible;
            }
            field(BankChangeWindowDays; Rec."Bank Change Window Days")
            {
                Caption = 'Bank-change window (days)';
                Visible = PaymentWindowsVisible;
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
                ToolTip = 'Save the review with the accepted findings and save the emails as drafts. Explain variance also puts the invoice on hold when a finding needs the vendor''s answer; Check payment run holds the payments whose action is Hold. Nothing is posted or sent.';
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
            action(AnnualInvoice)
            {
                Caption = 'A vendor sends one large invoice a year';
                ToolTip = 'Tell the AI service that a large payment to a vendor can be expected.';
                Visible = PaymentWindowsVisible;

                trigger OnAction()
                begin
                    Rec."User Note" := AnnualInvoiceTxt;
                end;
            }
            action(NewSupplier)
            {
                Caption = 'We started buying from a new supplier';
                ToolTip = 'Tell the AI service that a first payment to a new vendor is expected.';
                Visible = PaymentWindowsVisible;

                trigger OnAction()
                begin
                    Rec."User Note" := NewSupplierTxt;
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
        // a payment run reviews the lines of the batch the journal shows
        if Rec.GetFilter("Journal Template Name") <> '' then
            JournalTemplateName := Rec.GetRangeMin("Journal Template Name");
        if Rec.GetFilter("Journal Batch Name") <> '' then
            JournalBatchName := Rec.GetRangeMin("Journal Batch Name");
        if Handler.UsesPaymentWindows() and ((JournalTemplateName = '') or (JournalBatchName = '')) then
            Error(NoSourceErr);
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
        Rec."Journal Template Name" := JournalTemplateName;
        Rec."Journal Batch Name" := JournalBatchName;
        Rec."Tolerance %" := Setup."Variance Tolerance %";
        Rec."Email Tone" := Setup."Default Email Tone";
        Rec."Duplicate Window Days" := Setup."Duplicate Window Days";
        Rec."Bank Change Window Days" := Setup."Bank Change Window Days";
        Rec.Insert();
        ToleranceVisible := Handler.UsesTolerance();
        PaymentWindowsVisible := Handler.UsesPaymentWindows();
        // the customer filters belong to the selection of Plan collections only
        SelectionVisible := Handler.ReviewsSelection() and not PaymentWindowsVisible;
        EmailToneVisible := Handler.DraftsEmail();
        RunEmailVisible := Handler.DraftsEmail() and not Handler.DraftsEmailPerFinding();
        CurrPage.Findings.Page.SetEmailColumnVisible(Handler.DraftsEmailPerFinding());
        // the web client drops a message raised while a prompt dialog closes, so the outcome is told up front
        case true of
            PaymentWindowsVisible:
                KeepNote := PaymentRunKeepNoteTxt;
            SelectionVisible:
                KeepNote := SelectionKeepNoteTxt;
            else
                KeepNote := RecordKeepNoteTxt;
        end;
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
        if PaymentWindowsVisible then begin
            NewRun."Journal Template Name" := Rec."Journal Template Name";
            NewRun."Journal Batch Name" := Rec."Journal Batch Name";
            NewRun."Duplicate Window Days" := Rec."Duplicate Window Days";
            NewRun."Bank Change Window Days" := Rec."Bank Change Window Days";
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
        JournalTemplateName: Code[10];
        JournalBatchName: Code[10];
        ToleranceVisible: Boolean;
        SelectionVisible: Boolean;
        PaymentWindowsVisible: Boolean;
        EmailToneVisible: Boolean;
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
        PaymentRunKeepNoteTxt: Label 'Keep it saves this check as payment run evidence. For each ticked line whose action is Hold, it checks the line again and deletes it from this payment journal. For a bank change, an unusual amount or a first payment it puts every invoice the line pays on hold with the Hold Code from the setup, otherwise only the possible duplicate, so the next Suggest Vendor Payments skips them. Credit memos are never put on hold, and a line that pays nothing still open is only removed. A line already exported to a payment file or with a printed check stops Keep it. All other lines stay in the journal unchanged. Nothing is posted, no payment file is exported and no bank details are changed. The journal''s Payment run review panel shows the latest check.';
        AnnualInvoiceTxt: Label 'One of these vendors sends us a single large invoice once a year.';
        NewSupplierTxt: Label 'We started buying from a new supplier this month.';
}
