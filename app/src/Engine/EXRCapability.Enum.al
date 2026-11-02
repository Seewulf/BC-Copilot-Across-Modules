namespace PrabinBhusal.ExplainResolve;

// One value per capability. Each value names the codeunit that does its detectors, allowed actions and writes.
enum 58201 "EXR Capability" implements "EXR Capability Handler"
{
    Extensible = true;

    value(0; "Purchase Variance")
    {
        Caption = 'Explain invoice variance';
        Implementation = "EXR Capability Handler" = "EXR Purch. Variance";
    }
    value(1; Collections)
    {
        Caption = 'Plan collections';
        Implementation = "EXR Capability Handler" = "EXR Collections";
    }
}
