namespace PrabinBhusal.ExplainResolve;

// One difference found by Business Central. Temporary in the dialog; only accepted findings are saved on Keep it.
table 58202 "EXR Finding"
{
    Caption = 'Explain and Resolve Finding';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Run Entry No."; Integer)
        {
            Caption = 'Run Entry No.';
            TableRelation = "EXR Run";
            ToolTip = 'Specifies the run that the finding belongs to.';
        }
        field(2; "Line No."; Integer)
        {
            Caption = 'Line No.';
            ToolTip = 'Specifies the number of the finding within the run.';
        }
        field(3; "Finding Key"; Code[30])
        {
            Caption = 'Finding Key';
            ToolTip = 'Specifies the key that the model uses to refer to the finding.';
        }
        field(4; "Finding Type"; Code[30])
        {
            Caption = 'Finding Type';
            ToolTip = 'Specifies the detector that raised the finding.';
        }
        field(5; Severity; Enum "EXR Severity")
        {
            Caption = 'Severity';
            ToolTip = 'Specifies how serious the finding is.';
        }
        field(6; Subject; Text[250])
        {
            Caption = 'Subject';
            ToolTip = 'Specifies the line or document that the finding is about. Choose it to open the source record.';
        }
        field(7; Detail; Text[250])
        {
            Caption = 'Detail';
            ToolTip = 'Specifies the figures that Business Central computed for the finding.';
        }
        field(8; Description; Text[2048])
        {
            Caption = 'Explanation';
            ToolTip = 'Specifies the explanation of the finding. Every figure in it comes from Business Central.';
        }
        field(9; "Action"; Enum "EXR Action")
        {
            Caption = 'Action';
            ToolTip = 'Specifies the suggested resolution.';
        }
        field(10; Confidence; Enum "EXR Confidence")
        {
            Caption = 'Confidence';
            ToolTip = 'Specifies how sure the model is about its explanation. It is blank when no explanation came back.';
        }
        field(11; "Amount (LCY)"; Decimal)
        {
            Caption = 'Amount (LCY)';
            AutoFormatType = 1;
            AutoFormatExpression = '';
            ToolTip = 'Specifies the amount of the difference in local currency.';
        }
        field(12; "Source Record ID"; RecordId)
        {
            Caption = 'Source Record ID';
            ToolTip = 'Specifies the record that shows the difference, for example the receipt line.';
        }
        field(13; Accepted; Boolean)
        {
            Caption = 'Accept';
            ToolTip = 'Specifies whether the finding is kept when you choose Keep it. Only accepted findings can put the invoice on hold.';
        }
        field(14; "Unverified Figure"; Boolean)
        {
            Caption = 'Unverified Figure';
            ToolTip = 'Specifies whether the explanation contains a figure that the model wrote itself instead of a figure from Business Central.';
        }
        // ranked capabilities such as Plan collections: 1 is contacted first
        field(15; Rank; Integer)
        {
            Caption = 'Rank';
            BlankZero = true;
            ToolTip = 'Specifies the position of the finding in the worklist. Business Central ranks the customers by a priority score.';
        }
        // links a finding to its customer, so the customer card shows the latest review that includes it
        field(16; "Source System Id"; Guid)
        {
            Caption = 'Source System Id';
            ToolTip = 'Specifies the system ID of the record that the finding is about, for example the customer.';
        }
        // one email per finding, for example a reminder per customer
        field(17; "Email To"; Text[250])
        {
            Caption = 'Email To';
            DataClassification = EndUserIdentifiableInformation;
            ToolTip = 'Specifies the email address that the draft is addressed to. Business Central takes it from the customer card when you keep the review; it is never sent to the AI service.';
        }
        field(18; "Email Subject"; Text[250])
        {
            Caption = 'Email Subject';
            ToolTip = 'Specifies the subject of the email drafted for this finding.';
        }
        field(19; "Email Body"; Blob)
        {
            Caption = 'Email Body';
        }
        field(20; "Email Draft Saved"; Boolean)
        {
            Caption = 'Email Draft Saved';
            ToolTip = 'Specifies whether the email was saved as a draft in the email outbox. Without an email account only the text on this finding is kept.';
        }
        field(21; "Run Created At"; DateTime)
        {
            Caption = 'Reviewed At';
            FieldClass = FlowField;
            CalcFormula = lookup("EXR Run"."Created At" where("Entry No." = field("Run Entry No.")));
            Editable = false;
            ToolTip = 'Specifies when the review that kept this finding was started. Choose it to open the review.';
        }
        // a payment line's vendor, its flagged invoice and the entries it pays: Keep it checks them again before it holds the payment
        field(22; "Account No."; Code[20])
        {
            Caption = 'Account No.';
            ToolTip = 'Specifies the vendor that the payment line pays.';
        }
        field(23; "Ledger Entry No."; Integer)
        {
            Caption = 'Ledger Entry No.';
            BlankZero = true;
            ToolTip = 'Specifies the vendor ledger entry of the invoice that the finding is about: the possible duplicate, or the first invoice the payment line pays.';
        }
        field(24; "Applied Entries"; Integer)
        {
            Caption = 'Applied Entries';
            BlankZero = true;
            ToolTip = 'Specifies how many open vendor ledger entries the payment line paid when it was checked.';
        }
        // the sum of those entry numbers: with the count, it shows that the line still pays the same entries
        field(25; "Applied Entry Checksum"; BigInteger)
        {
            Caption = 'Applied Entry Checksum';
            ToolTip = 'Specifies the sum of the entry numbers of the vendor ledger entries the payment line paid when it was checked.';
        }
    }

    keys
    {
        key(PK; "Run Entry No.", "Line No.") { Clustered = true; }
        key(BySeverity; "Run Entry No.", Severity) { }
        key(ByRank; "Run Entry No.", Rank) { }
        key(BySource; "Source System Id", "Run Entry No.") { }
    }

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
