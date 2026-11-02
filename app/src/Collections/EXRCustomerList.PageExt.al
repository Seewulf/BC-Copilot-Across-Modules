namespace PrabinBhusal.ExplainResolve;

using Microsoft.Sales.Customer;
using System.AI;

// Plan collections on the Customer List. RunObject cannot pass the list's filters, so the dialog has its own filter fields.
pageextension 58201 "EXR Customer List" extends "Customer List"
{
    actions
    {
        addfirst(Prompting)
        {
            action(EXRPlanCollections)
            {
                ApplicationArea = All;
                Caption = 'Plan collections';
                Image = Sparkle;
                Visible = EXRCapabilityActive;
                ToolTip = 'Rank the customers with overdue invoices and draft a reminder for each one that needs it. Business Central computes every figure from the customer ledger, the AI service explains the ranking and drafts the emails, and nothing is saved or sent until you keep it.';
                RunObject = page "EXR Prompt";
                // 18 = Customer
                RunPageLink = Capability = const(Collections), "Source Table No." = const(18);
            }
        }
    }

    trigger OnOpenPage()
    var
        ExrRun: Record "EXR Run";
        CopilotCapability: Codeunit "Copilot Capability";
    begin
        // sales users without Explain and Resolve permissions never see the action (WritePermission would need Delete, which EXR USER has not)
        EXRCapabilityActive := CopilotCapability.IsCapabilityActive(Enum::"Copilot Capability"::"EXR Collections") and ExrRun.ReadPermission();
    end;

    var
        EXRCapabilityActive: Boolean;
}
