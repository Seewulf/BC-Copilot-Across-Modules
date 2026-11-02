namespace PrabinBhusal.ExplainResolve;

using System.Upgrade;

// Registers capabilities added in a new version. Registration skips values that already exist.
// A setup that existed before the review defaults came gets those defaults once.
codeunit 58201 "EXR Upgrade"
{
    Subtype = Upgrade;
    Access = Internal;

    trigger OnUpgradePerDatabase()
    var
        Install: Codeunit "EXR Install";
    begin
        Install.RegisterCapabilities();
    end;

    // InitValue fills new rows only, so an existing setup would get a 0% tolerance and no hold code.
    trigger OnUpgradePerCompany()
    var
        Setup: Record "EXR Setup";
        DefaultSetup: Record "EXR Setup";
        Install: Codeunit "EXR Install";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if UpgradeTag.HasUpgradeTag(Install.ReviewDefaultsTag()) then
            exit;
        if Setup.Get() then begin
            DefaultSetup.Init();
            Setup."Variance Tolerance %" := DefaultSetup."Variance Tolerance %";
            Setup."Hold Code" := DefaultSetup."Hold Code";
            Setup.Modify();
        end;
        UpgradeTag.SetUpgradeTag(Install.ReviewDefaultsTag());
    end;
}
