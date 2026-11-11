namespace PrabinBhusal.ExplainResolve.Eval;

// Brings the suite and datasets in on every upgrade too, so a republish picks up new resources.
codeunit 58306 "EXR Eval Upgrade"
{
    Subtype = Upgrade;
    Access = Internal;

    trigger OnUpgradePerCompany()
    var
        EvalInstall: Codeunit "EXR Eval Install";
    begin
        EvalInstall.ImportSuite();
    end;
}
