namespace PrabinBhusal.ExplainResolve;

// The latest kept finding about the record on the host page, such as a customer in a Plan collections worklist.
// A collections run covers many customers, so the panel links through the finding's source, not the run's.
// Only accepted findings are saved, and only on Keep it, so every row here belongs to a kept review.
// Only ranked findings, from a review of a selection, link to a record. The others have no source, and a new record's
// empty id would match all of them, so they are left out.
page 58207 "EXR Finding FactBox"
{
    Caption = 'Latest review';
    PageType = CardPart;
    SourceTable = "EXR Finding";
    SourceTableView = sorting("Source System Id", "Run Entry No.") order(descending) where(Rank = filter(<> 0));
    ApplicationArea = All;
    Editable = false;

    layout
    {
        area(Content)
        {
            field("Run Created At"; Rec."Run Created At")
            {
                trigger OnDrillDown()
                var
                    ExrRun: Record "EXR Run";
                begin
                    if ExrRun.Get(Rec."Run Entry No.") then
                        Page.Run(Page::"EXR Run", ExrRun);
                end;
            }
            field(Rank; Rec.Rank) { }
            field(Description; Rec.Description)
            {
                MultiLine = true;
            }
            field(FindingAction; Rec."Action") { }
            field("Amount (LCY)"; Rec."Amount (LCY)") { }
            field("Email Subject"; Rec."Email Subject") { }
            field("Email Draft Saved"; Rec."Email Draft Saved") { }
        }
    }
}
