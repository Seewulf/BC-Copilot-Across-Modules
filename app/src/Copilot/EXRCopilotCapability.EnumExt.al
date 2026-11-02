namespace PrabinBhusal.ExplainResolve;

using System.AI;

// One value per capability, so admins can switch each one on or off in Copilot & agent capabilities.
enumextension 58200 "EXR Copilot Capability" extends "Copilot Capability"
{
    value(58200; "EXR Purchase Variance")
    {
        Caption = 'Explain invoice variance';
    }
    value(58201; "EXR Collections")
    {
        Caption = 'Plan collections';
    }
}
