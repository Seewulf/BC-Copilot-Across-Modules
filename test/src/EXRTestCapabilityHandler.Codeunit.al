namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;
using System.AI;

// A capability whose Copilot capability is never registered, so Generate must stop at the capability guard.
codeunit 58279 "EXR Test Capability Handler" implements "EXR Capability Handler"
{
    procedure CopilotCapability(): Enum "Copilot Capability"
    begin
        exit(Enum::"Copilot Capability"::"EXR Test Unregistered");
    end;

    procedure PromptResourceName(): Text
    begin
        exit('');
    end;

    procedure UsesTolerance(): Boolean
    begin
        exit(false);
    end;

    procedure ReviewsSelection(): Boolean
    begin
        exit(false);
    end;

    procedure DraftsEmailPerFinding(): Boolean
    begin
        exit(false);
    end;

    procedure BuildFacts(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    begin
    end;

    procedure IsActionAllowed(FindingType: Code[30]; FindingAction: Enum "EXR Action"): Boolean
    begin
        exit(false);
    end;

    procedure BuildEmailTable(var TempFinding: Record "EXR Finding" temporary): Text
    begin
        exit('');
    end;

    procedure ApplyKeep(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary): Text
    begin
        exit('');
    end;
}
