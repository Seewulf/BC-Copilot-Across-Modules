namespace PrabinBhusal.ExplainResolve;

using Microsoft.CRM.Team;
using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Sales.Customer;

// One row per Generate call: what was asked, what came back and what the user did with it.
table 58201 "EXR Run"
{
    Caption = 'Explain and Resolve Run';
    DataClassification = CustomerContent;
    DrillDownPageId = "EXR Runs";
    LookupPageId = "EXR Runs";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
            ToolTip = 'Specifies the number of the run.';
        }
        field(2; Capability; Enum "EXR Capability")
        {
            Caption = 'Capability';
            ToolTip = 'Specifies the feature that created the run.';
        }
        field(3; "Source Table No."; Integer)
        {
            Caption = 'Source Table No.';
            ToolTip = 'Specifies the table of the record that was reviewed.';
        }
        field(4; "Source System Id"; Guid)
        {
            Caption = 'Source System Id';
            ToolTip = 'Specifies the system ID of the record that was reviewed.';
        }
        field(5; "Source Record ID"; RecordId)
        {
            Caption = 'Source Record ID';
            ToolTip = 'Specifies the record that was reviewed.';
        }
        field(6; "Source No."; Code[20])
        {
            Caption = 'Source No.';
            ToolTip = 'Specifies the number of the document or record that was reviewed.';
        }
        field(7; "User ID"; Code[50])
        {
            Caption = 'User ID';
            DataClassification = EndUserIdentifiableInformation;
            ToolTip = 'Specifies the user who started the run.';
        }
        field(8; "Created At"; DateTime)
        {
            Caption = 'Created At';
            ToolTip = 'Specifies when the run was started.';
        }
        field(9; Status; Enum "EXR Run Status")
        {
            Caption = 'Status';
            ToolTip = 'Specifies whether the result was kept, discarded, failed or blocked by a daily limit.';
        }
        field(10; Summary; Text[2048])
        {
            Caption = 'Summary';
            ToolTip = 'Specifies the summary, with every figure filled in by Business Central.';
        }
        field(11; "Email To"; Text[250])
        {
            Caption = 'Email To';
            DataClassification = EndUserIdentifiableInformation;
            ToolTip = 'Specifies the email address that the draft is addressed to. It is never sent to the AI service.';
        }
        field(12; "Email Subject"; Text[250])
        {
            Caption = 'Email Subject';
            ToolTip = 'Specifies the subject of the drafted email.';
        }
        field(13; "Email Body"; Blob)
        {
            Caption = 'Email Body';
        }
        field(14; "Email Draft Saved"; Boolean)
        {
            Caption = 'Email Draft Saved';
            ToolTip = 'Specifies whether the email was saved as a draft in the email outbox. Without an email account only the text on this run is kept.';
        }
        field(15; Model; Text[100])
        {
            Caption = 'Model';
            ToolTip = 'Specifies the model that wrote the explanation.';
        }
        field(16; "Input Tokens"; Integer)
        {
            Caption = 'Input Tokens';
            ToolTip = 'Specifies how many input tokens the run used, retries included.';
        }
        field(17; "Output Tokens"; Integer)
        {
            Caption = 'Output Tokens';
            ToolTip = 'Specifies how many output tokens the run used, retries included.';
        }
        field(18; Duration; Duration)
        {
            Caption = 'Duration';
            ToolTip = 'Specifies how long the AI service took to answer.';
        }
        field(19; "Prompt Version"; Text[100])
        {
            Caption = 'Prompt Version';
            ToolTip = 'Specifies the prompt file and a hash of the prompt text that the run used.';
        }
        field(20; "Tolerance %"; Decimal)
        {
            Caption = 'Tolerance %';
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            MaxValue = 100;
            ToolTip = 'Specifies the price difference, in percent, that is accepted without a finding.';
        }
        field(21; "Email Tone"; Enum "EXR Email Tone")
        {
            Caption = 'Email Tone';
            ToolTip = 'Specifies the tone of the drafted email.';
        }
        field(22; "User Note"; Text[2048])
        {
            Caption = 'User Note';
            ToolTip = 'Specifies the note that the user added for the AI service.';
        }
        field(23; "Unverified Figures"; Boolean)
        {
            Caption = 'Unverified Figures';
            ToolTip = 'Specifies whether the summary or the email contains a figure that the model wrote itself instead of a figure from Business Central. Check it before you rely on it.';
        }
        field(24; "Error Message"; Text[2048])
        {
            Caption = 'Error Message';
            ToolTip = 'Specifies why the AI service could not explain the findings, or why the run was blocked.';
        }
        // options of Plan collections, which reviews a selection of customers instead of one record
        field(25; "Salesperson Code"; Code[20])
        {
            Caption = 'Salesperson Code';
            TableRelation = "Salesperson/Purchaser";
            ToolTip = 'Specifies the salesperson whose customers are reviewed. Leave it blank to review all customers.';
        }
        field(26; "Customer Posting Group"; Code[20])
        {
            Caption = 'Customer Posting Group';
            TableRelation = "Customer Posting Group";
            ToolTip = 'Specifies the customer posting group whose customers are reviewed. Leave it blank to review all customers.';
        }
        field(27; "Max. Customers"; Integer)
        {
            Caption = 'Max. Customers';
            InitValue = 10;
            MinValue = 1;
            MaxValue = 25;
            ToolTip = 'Specifies how many of the highest-ranked customers are reviewed.';
        }
        // options of Check payment run, which reviews the lines of one payment journal batch
        field(40; "Journal Template Name"; Code[10])
        {
            Caption = 'Journal Template Name';
            TableRelation = "Gen. Journal Template";
            ToolTip = 'Specifies the journal template of the payment journal that was checked.';
        }
        field(41; "Journal Batch Name"; Code[10])
        {
            Caption = 'Journal Batch Name';
            TableRelation = "Gen. Journal Batch".Name where("Journal Template Name" = field("Journal Template Name"));
            ToolTip = 'Specifies the payment journal batch that was checked.';
        }
        field(42; "Duplicate Window Days"; Integer)
        {
            Caption = 'Duplicate Window (Days)';
            MinValue = 0;
            MaxValue = 3650;
            ToolTip = 'Specifies how many days apart two invoices with the same amount and a matching vendor invoice number may be posted and still be flagged as a possible duplicate. 0 turns the check off.';
        }
        field(43; "Bank Change Window Days"; Integer)
        {
            Caption = 'Bank-Change Window (Days)';
            MinValue = 0;
            MaxValue = 3650;
            ToolTip = 'Specifies how many days back, counted from today, a change to one of the vendor''s bank accounts flags a payment. 0 turns the check off.';
        }
        field(30; "No. of Findings"; Integer)
        {
            Caption = 'No. of Findings';
            FieldClass = FlowField;
            CalcFormula = count("EXR Finding" where("Run Entry No." = field("Entry No.")));
            Editable = false;
            ToolTip = 'Specifies how many findings were kept with the run.';
        }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(UserDay; "User ID", "Created At") { }
        key(Day; "Created At") { }
        key(Source; "Source System Id", Status) { }
        // the Payment Journal's FactBox: the latest kept check of one batch
        key(Journal; "Journal Template Name", "Journal Batch Name", Capability, Status) { }
    }

    trigger OnInsert()
    begin
        if Rec."User ID" = '' then
            Rec."User ID" := CopyStr(UserId(), 1, MaxStrLen(Rec."User ID"));
        if Rec."Created At" = 0DT then
            Rec."Created At" := CurrentDateTime();
    end;

    trigger OnDelete()
    var
        Finding: Record "EXR Finding";
    begin
        Finding.SetRange("Run Entry No.", Rec."Entry No.");
        Finding.DeleteAll();
    end;

    procedure SetEmailBody(NewBody: Text)
    var
        BodyOutStream: OutStream;
    begin
        Clear(Rec."Email Body");
        if NewBody = '' then
            exit;
        Rec."Email Body".CreateOutStream(BodyOutStream, TextEncoding::UTF8);
        BodyOutStream.WriteText(NewBody);
    end;

    procedure GetEmailBody() Body: Text
    var
        BodyInStream: InStream;
    begin
        Rec.CalcFields("Email Body");
        if not Rec."Email Body".HasValue() then
            exit('');
        Rec."Email Body".CreateInStream(BodyInStream, TextEncoding::UTF8);
        BodyInStream.Read(Body);
    end;
}
