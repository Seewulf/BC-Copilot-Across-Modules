namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;

// Lets the tests swap the Claude API for the mock client through the setup.
enumextension 58270 "EXR Mock Chat Provider" extends "EXR Chat Provider"
{
    value(58270; Mock)
    {
        Caption = 'Mock (tests only)';
        Implementation = "EXR Chat Client" = "EXR Mock Chat Client";
    }
}
