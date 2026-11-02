namespace PrabinBhusal.ExplainResolve;

using System.AI;

// One implementation per capability. The engine calls these and never branches on the capability.
interface "EXR Capability Handler"
{
    // The Copilot capability that admins switch on or off.
    procedure CopilotCapability(): Enum "Copilot Capability";

    // File name of the capability prompt in the prompts resource folder.
    procedure PromptResourceName(): Text;

    // Whether the dialog shows the tolerance option.
    procedure UsesTolerance(): Boolean;

    // Whether the run reviews a selection chosen with the dialog's filters instead of one source record.
    procedure ReviewsSelection(): Boolean;

    // Whether each finding gets its own email (one per customer) instead of one email for the run.
    procedure DraftsEmailPerFinding(): Boolean;

    // Deterministic detectors: fill the findings and register every figure in the run context.
    // The run carries the source and the options; the handler fills Source No.
    procedure BuildFacts(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context");

    // Whether the model may choose this action for a finding of this type. Otherwise the detector's action stays.
    procedure IsActionAllowed(FindingType: Code[30]; FindingAction: Enum "EXR Action"): Boolean;

    // The table for the email, rendered by AL on Keep it: from the accepted findings of the run,
    // or from the one finding it is given when each finding has its own email.
    procedure BuildEmailTable(var TempFinding: Record "EXR Finding" temporary): Text;

    // The only writes this capability makes, for the accepted findings it is given. Returns the confirmation for the user.
    procedure ApplyKeep(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary): Text;
}
