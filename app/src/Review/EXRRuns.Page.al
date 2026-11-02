namespace PrabinBhusal.ExplainResolve;

// Every run, newest first: the usage log and the audit trail of what was kept.
page 58203 "EXR Runs"
{
    Caption = 'Explain and Resolve Runs';
    PageType = List;
    SourceTable = "EXR Run";
    SourceTableView = sorting("Entry No.") order(descending);
    CardPageId = "EXR Run";
    ApplicationArea = All;
    UsageCategory = History;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Runs)
            {
                field("Entry No."; Rec."Entry No.") { }
                field("Created At"; Rec."Created At") { }
                field(Capability; Rec.Capability) { }
                field("Source No."; Rec."Source No.") { }
                field(Status; Rec.Status) { }
                field("User ID"; Rec."User ID") { }
                field(Summary; Rec.Summary) { }
                field("No. of Findings"; Rec."No. of Findings") { }
                field("Unverified Figures"; Rec."Unverified Figures") { }
                field(Model; Rec.Model) { }
                field("Input Tokens"; Rec."Input Tokens") { }
                field("Output Tokens"; Rec."Output Tokens") { }
                field(Duration; Rec.Duration) { }
                field("Prompt Version"; Rec."Prompt Version") { Visible = false; }
                field("Error Message"; Rec."Error Message") { Visible = false; }
            }
        }
    }
}
