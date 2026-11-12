namespace PrabinBhusal.ExplainResolve;

using System.Upgrade;

// Registers capabilities added in a new version, once per upgrade tag. Registration also skips values that already exist.
// A setup that existed before a version's new fields gets their defaults once; values users set later are never touched.
codeunit 58201 "EXR Upgrade"
{
    Subtype = Upgrade;
    Access = Internal;

    // 1.1 adds Check payment run.
    trigger OnUpgradePerDatabase()
    var
        Install: Codeunit "EXR Install";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if UpgradeTag.HasDatabaseUpgradeTag(Install.PaymentRunCapabilityTag()) then
            exit;
        Install.RegisterCapabilities();
        UpgradeTag.SetDatabaseUpgradeTag(Install.PaymentRunCapabilityTag());
    end;

    trigger OnUpgradePerCompany()
    begin
        UpgradeReviewDefaults();
        UpgradePaymentRunDefaults();
        UpgradeMaxOutputTokens();
    end;

    // Once per company: without it an existing setup would have every payment run check turned off (0 days, 0%).
    internal procedure UpgradePaymentRunDefaults()
    var
        Install: Codeunit "EXR Install";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if UpgradeTag.HasUpgradeTag(Install.PaymentRunDefaultsTag()) then
            exit;
        FillPaymentRunDefaults();
        UpgradeTag.SetUpgradeTag(Install.PaymentRunDefaultsTag());
    end;

    // Only the 1.1 fields; every other setup value stays as the company set it.
    internal procedure FillPaymentRunDefaults()
    var
        Setup: Record "EXR Setup";
        DefaultSetup: Record "EXR Setup";
    begin
        if not Setup.Get() then
            exit;
        DefaultSetup.Init();
        Setup."Duplicate Window Days" := DefaultSetup."Duplicate Window Days";
        Setup."Bank Change Window Days" := DefaultSetup."Bank Change Window Days";
        Setup."Unusual Amount %" := DefaultSetup."Unusual Amount %";
        Setup.Modify();
    end;

    // Once per company: Effort High was cut off at the old default of 8000.
    internal procedure UpgradeMaxOutputTokens()
    var
        Install: Codeunit "EXR Install";
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if UpgradeTag.HasUpgradeTag(Install.MaxOutputTokensTag()) then
            exit;
        RaiseOldMaxOutputTokens();
        UpgradeTag.SetUpgradeTag(Install.MaxOutputTokensTag());
    end;

    // Only the untouched old default moves to the new one; any value the company chose stays.
    internal procedure RaiseOldMaxOutputTokens()
    var
        Setup: Record "EXR Setup";
        DefaultSetup: Record "EXR Setup";
    begin
        if not Setup.Get() then
            exit;
        if Setup."Max Output Tokens" <> 8000 then
            exit;
        DefaultSetup.Init();
        Setup."Max Output Tokens" := DefaultSetup."Max Output Tokens";
        Setup.Modify();
    end;

    // InitValue fills new rows only, so an existing setup would get a 0% tolerance and no hold code.
    local procedure UpgradeReviewDefaults()
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
