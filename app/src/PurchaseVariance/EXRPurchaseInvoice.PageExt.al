namespace PrabinBhusal.ExplainResolve;

using Microsoft.Purchases.Document;
using System.AI;

// Explain variance on the purchase invoice, plus the latest kept review in a FactBox.
pageextension 58200 "EXR Purchase Invoice" extends "Purchase Invoice"
{
    layout
    {
        addfirst(factboxes)
        {
            // 38 = Purchase Header
            part(EXRRunFactBox; "EXR Run FactBox")
            {
                ApplicationArea = All;
                Caption = 'Variance review';
                Visible = EXRShowReview;
                SubPageLink = "Source Table No." = const(38), "Source System Id" = field(SystemId);
            }
        }
    }

    actions
    {
        addfirst(Prompting)
        {
            action(EXRExplainVariance)
            {
                ApplicationArea = All;
                Caption = 'Explain variance';
                Image = Sparkle;
                Visible = EXRCapabilityActive;
                Enabled = Rec.Status = Rec.Status::Open;
                ToolTip = 'Compare this invoice with its receipts, the purchase order, recent prices and posted invoices. Business Central computes every figure, the AI service explains them and drafts a vendor email, and nothing is saved until you keep it.';
                RunObject = page "EXR Prompt";
                RunPageLink = Capability = const("Purchase Variance"), "Source Table No." = const(38), "Source System Id" = field(SystemId);
            }
        }
    }

    trigger OnOpenPage()
    var
        ExrRun: Record "EXR Run";
        ExrFinding: Record "EXR Finding";
        CopilotCapability: Codeunit "Copilot Capability";
    begin
        EXRCapabilityActive := CopilotCapability.IsCapabilityActive(Enum::"Copilot Capability"::"EXR Purchase Variance");
        // purchasing users without Explain and Resolve permissions never load the FactBox
        EXRShowReview := ExrRun.ReadPermission() and ExrFinding.ReadPermission();
    end;

    var
        EXRCapabilityActive: Boolean;
        EXRShowReview: Boolean;
}
