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

    trigger OnInstallAppPerDatabase()
    begin
        RegisterCapabilities();
    end;

    trigger OnInstallAppPerCompany()
    var
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if not UpgradeTag.HasUpgradeTag(ReviewDefaultsTag()) then
            UpgradeTag.SetUpgradeTag(ReviewDefaultsTag());
    end;

    internal procedure RegisterCapabilities()
    begin
        RegisterCapability(Enum::"Copilot Capability"::"EXR Purchase Variance");
        RegisterCapability(Enum::"Copilot Capability"::"EXR Collections");
    end;

    internal procedure ReviewDefaultsTag(): Code[250]
    begin
        exit(ReviewDefaultsTagTok);
    end;

    local procedure RegisterCapability(Capability: Enum "Copilot Capability")
    var
        CopilotCapability: Codeunit "Copilot Capability";
    begin
        if CopilotCapability.IsCapabilityRegistered(Capability) then
            exit;
        CopilotCapability.RegisterCapability(Capability, Enum::"Copilot Availability"::Preview, Enum::"Copilot Billing Type"::"Not Billed", LearnMoreUrlTxt);
    end;

    // New companies get the tag too, so the upgrade leaves their setup alone.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Upgrade Tag", OnGetPerCompanyUpgradeTags, '', false, false)]
    local procedure RegisterPerCompanyTags(var PerCompanyUpgradeTags: List of [Code[250]])
    begin
        PerCompanyUpgradeTags.Add(ReviewDefaultsTag());
    end;
}
