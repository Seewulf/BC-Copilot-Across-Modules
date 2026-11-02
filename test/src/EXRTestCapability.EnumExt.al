namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;

// Lets the tests run Generate for a capability that is switched off.
enumextension 58272 "EXR Test Capability" extends "EXR Capability"
{
    value(58270; "EXR Test Unregistered")
    {
        Caption = 'Unregistered test capability';
        Implementation = "EXR Capability Handler" = "EXR Test Capability Handler";
    }
}
