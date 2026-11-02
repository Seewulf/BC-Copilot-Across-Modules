namespace PrabinBhusal.ExplainResolve;

using Microsoft.Sales.Customer;

// The latest kept collections review of this customer in a FactBox.
pageextension 58202 "EXR Customer Card" extends "Customer Card"
{
    layout
    {
        addfirst(factboxes)
        {
            part(EXRFindingFactBox; "EXR Finding FactBox")
            {
                ApplicationArea = All;
                Caption = 'Collections review';
                Visible = EXRShowReview;
                SubPageLink = "Source System Id" = field(SystemId);
            }
        }
    }

    trigger OnOpenPage()
    var
        ExrRun: Record "EXR Run";
        ExrFinding: Record "EXR Finding";
    begin
        // users without Explain and Resolve permissions never load the FactBox
        EXRShowReview := ExrRun.ReadPermission() and ExrFinding.ReadPermission();
    end;

    var
        EXRShowReview: Boolean;
}
