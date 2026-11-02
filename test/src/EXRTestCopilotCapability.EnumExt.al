namespace PrabinBhusal.ExplainResolve.Test;

using System.AI;

// A capability that is never registered, so the engine's capability guard can be tested.
enumextension 58271 "EXR Test Copilot Capability" extends "Copilot Capability"
{
    value(58270; "EXR Test Unregistered")
    {
        Caption = 'Unregistered test capability';
    }
}
