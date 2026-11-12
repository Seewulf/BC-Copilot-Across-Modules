namespace PrabinBhusal.ExplainResolve;

using System.AI;
using System.Upgrade;

// Registers the Copilot capabilities on install. The upgrade codeunit calls the same procedure.
// A fresh install sets the upgrade tags, so upgrade code never overwrites what users set later.
codeunit 58200 "EXR Install"
{
    Subtype = Install;
    Access = Internal;

    var
        LearnMoreUrlTxt: Label 'https://github.com/Seewulf/BC-Copilot-Across-Modules', Locked = true;
        ReviewDefaultsTagTok: Label 'EXR-ReviewSetupDefaults-20261031', Locked = true;
        // 1.1: Check payment run registered, and its setup defaults
        PaymentRunCapabilityTagTok: Label 'EXR-PaymentRunCapability-20261103', Locked = true;
        PaymentRunDefaultsTagTok: Label 'EXR-PaymentRunSetupDefaults-20261103', Locked = true;
        // 1.1.0.2: the old Max Output Tokens default of 8000 raised to 16000
        MaxOutputTokensTagTok: Label 'EXR-MaxOutputTokens-20261112', Locked = true;

    trigger OnInstallAppPerDatabase()
    var
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        RegisterCapabilities();
        if not UpgradeTag.HasDatabaseUpgradeTag(PaymentRunCapabilityTag()) then
            UpgradeTag.SetDatabaseUpgradeTag(PaymentRunCapabilityTag());
    end;

    trigger OnInstallAppPerCompany()
    var
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if not UpgradeTag.HasUpgradeTag(ReviewDefaultsTag()) then
            UpgradeTag.SetUpgradeTag(ReviewDefaultsTag());
        if not UpgradeTag.HasUpgradeTag(PaymentRunDefaultsTag()) then
            UpgradeTag.SetUpgradeTag(PaymentRunDefaultsTag());
        if not UpgradeTag.HasUpgradeTag(MaxOutputTokensTag()) then
            UpgradeTag.SetUpgradeTag(MaxOutputTokensTag());
    end;

    internal procedure RegisterCapabilities()
    begin
        RegisterCapability(Enum::"Copilot Capability"::"EXR Purchase Variance");
        RegisterCapability(Enum::"Copilot Capability"::"EXR Collections");
        RegisterCapability(Enum::"Copilot Capability"::"EXR Payment Run");
    end;

    internal procedure ReviewDefaultsTag(): Code[250]
    begin
        exit(ReviewDefaultsTagTok);
    end;

    internal procedure PaymentRunCapabilityTag(): Code[250]
    begin
        exit(PaymentRunCapabilityTagTok);
    end;

    internal procedure PaymentRunDefaultsTag(): Code[250]
    begin
        exit(PaymentRunDefaultsTagTok);
    end;

    internal procedure MaxOutputTokensTag(): Code[250]
    begin
        exit(MaxOutputTokensTagTok);
    end;

    local procedure RegisterCapability(Capability: Enum "Copilot Capability")
    var
        CopilotCapability: Codeunit "Copilot Capability";
    begin
        if CopilotCapability.IsCapabilityRegistered(Capability) then
            exit;
        CopilotCapability.RegisterCapability(Capability, Enum::"Copilot Availability"::Preview, Enum::"Copilot Billing Type"::"Not Billed", LearnMoreUrlTxt);
    end;

    // New companies get the tags too, so the upgrade leaves their setup alone.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Upgrade Tag", OnGetPerCompanyUpgradeTags, '', false, false)]
    local procedure RegisterPerCompanyTags(var PerCompanyUpgradeTags: List of [Code[250]])
    begin
        PerCompanyUpgradeTags.Add(ReviewDefaultsTag());
        PerCompanyUpgradeTags.Add(PaymentRunDefaultsTag());
        PerCompanyUpgradeTags.Add(MaxOutputTokensTag());
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Upgrade Tag", OnGetPerDatabaseUpgradeTags, '', false, false)]
    local procedure RegisterPerDatabaseTags(var PerDatabaseUpgradeTags: List of [Code[250]])
    begin
        PerDatabaseUpgradeTags.Add(PaymentRunCapabilityTag());
    end;
}
