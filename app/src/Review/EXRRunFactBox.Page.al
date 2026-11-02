namespace PrabinBhusal.ExplainResolve;

// The latest kept review of the record on the host page. No Provider property, so Summarize can read it.
page 58205 "EXR Run FactBox"
{
    Caption = 'Latest review';
    PageType = CardPart;
    SourceTable = "EXR Run";
    SourceTableView = sorting("Entry No.") order(descending) where(Status = const(Kept));
    ApplicationArea = All;
    Editable = false;

    layout
    {
        area(Content)
        {
            field("Created At"; Rec."Created At")
            {
                trigger OnDrillDown()
                begin
                    Page.Run(Page::"EXR Run", Rec);
                end;
            }
            field("User ID"; Rec."User ID") { }
            field(Summary; Rec.Summary)
            {
                MultiLine = true;
            }
            field("No. of Findings"; Rec."No. of Findings") { }
            field("Email Draft Saved"; Rec."Email Draft Saved") { }
        }
    }
}
