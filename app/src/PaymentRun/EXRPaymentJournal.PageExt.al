namespace PrabinBhusal.ExplainResolve;

using Microsoft.Finance.GeneralLedger.Journal;
using System.AI;

// Check payment run on the Payment Journal, plus the latest kept check of this batch in a FactBox.
pageextension 58203 "EXR Payment Journal" extends "Payment Journal"
{
    layout
    {
        addfirst(factboxes)
        {
            part(EXRRunFactBox; "EXR Run FactBox")
            {
                ApplicationArea = All;
                Caption = 'Payment run review';
                Visible = EXRShowReview;
                SubPageLink = Capability = const("Payment Run"), "Journal Template Name" = field("Journal Template Name"), "Journal Batch Name" = field("Journal Batch Name");
            }
        }
    }

    actions
    {
        addfirst(Prompting)
        {
            action(EXRCheckPaymentRun)
            {
                ApplicationArea = All;
                Caption = 'Check payment run';
                Image = Sparkle;
                Visible = EXRCapabilityActive;
                ToolTip = 'Check the vendor payments in this batch for possible duplicate invoices, changed bank accounts, unusual amounts, first payments and invoices on hold. Business Central computes every signal, the AI service explains them for the approver, and nothing changes until you keep it.';
                RunObject = page "EXR Prompt";
                // 81 = Gen. Journal Line
                RunPageLink = Capability = const("Payment Run"), "Source Table No." = const(81), "Journal Template Name" = field("Journal Template Name"), "Journal Batch Name" = field("Journal Batch Name");
            }
        }
    }

    trigger OnOpenPage()
    var
        ExrRun: Record "EXR Run";
        CopilotCapability: Codeunit "Copilot Capability";
    begin
        // journal users without Explain and Resolve permissions never see the action or load the FactBox
        EXRShowReview := ExrRun.ReadPermission();
        EXRCapabilityActive := CopilotCapability.IsCapabilityActive(Enum::"Copilot Capability"::"EXR Payment Run") and EXRShowReview;
    end;

    var
        EXRCapabilityActive: Boolean;
        EXRShowReview: Boolean;
}
