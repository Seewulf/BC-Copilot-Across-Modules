namespace PrabinBhusal.ExplainResolve.Eval;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Finance.VAT.Setup;
using PrabinBhusal.ExplainResolve;
using System.Security.User;

// Runs one dataset case: builds its scenario, generates once through the recorder and scores the run.
// Every write here happens inside the caller's test transaction, which the test isolation rolls back.
codeunit 58301 "EXR Eval Runner"
{
    Access = Internal;

    var
        Recorder: Codeunit "EXR Eval Recorder";
        Scenarios: Codeunit "EXR Eval Scenarios";
        Scorer: Codeunit "EXR Eval Scorer";
        Engine: Codeunit "EXR Engine";
        MainAppIdTok: Label 'fd0480a3-8f77-4e94-8c93-afbff2a5c456', Locked = true;
        MockModelTok: Label 'mock-model-1', Locked = true;
        NoCaseErr: Label 'This test reads its case from the AI Eval Suite EXR-EVAL. Run the suite from the AI Eval Suite page.';
        ScenarioErr: Label 'Scenario error in %1: %2. The model was scored on the findings that match; fix the dataset or the scenario.', Comment = '%1 = case name, %2 = missing or unexpected findings';

    // Live: the recorder in front of the provider set up on the setup page. Otherwise in front of the test app's mock.
    // Limits, the unusual amount threshold and the posting dates are set so every case runs the same way.
    procedure Prepare(Live: Boolean)
    var
        Setup: Record "EXR Setup";
        GeneralLedgerSetup: Record "General Ledger Setup";
        VATSetup: Record "VAT Setup";
        UserSetup: Record "User Setup";
        InnerProvider: Enum "EXR Chat Provider";
    begin
        Setup.InsertIfMissing();
        InnerProvider := Setup.Provider;
        if InnerProvider = InnerProvider::"Eval Recorder" then
            InnerProvider := InnerProvider::Claude;
        if not Live then begin
            InnerProvider := InnerProvider::Mock;
            Setup.Model := MockModelTok;
            Setup."Max Output Tokens" := 4000;
        end;
        Recorder.Start(InnerProvider);
        Setup.Provider := Setup.Provider::"Eval Recorder";
        Setup."Daily Calls per User" := 100000;
        Setup."Daily Calls per Company" := 100000;
        Setup."Unusual Amount %" := 100;
        Setup.Modify();
        // the mock needs a key to pass the setup check; a real key is never replaced
        if not Live and not Setup.HasApiKey() then
            Setup.SetApiKey('sk-ant-eval-mock-' + Format(CreateGuid()));
        GeneralLedgerSetup.Get();
        GeneralLedgerSetup."Allow Posting From" := 0D;
        GeneralLedgerSetup."Allow Posting To" := 0D;
        GeneralLedgerSetup.Modify();
        if VATSetup.Get() then begin
            VATSetup."Allow VAT Date From" := 0D;
            VATSetup."Allow VAT Date To" := 0D;
            VATSetup.Modify();
        end;
        if UserSetup.Get(UserId()) then begin
            UserSetup."Allow Posting From" := 0D;
            UserSetup."Allow Posting To" := 0D;
            UserSetup."Allow VAT Date From" := 0D;
            UserSetup."Allow VAT Date To" := 0D;
            UserSetup.Modify();
        end;
    end;

    // The case of the current AI Eval Suite iteration.
    procedure CaseFromSuite(InputText: Text) CaseJson: JsonObject
    begin
        if not CaseJson.ReadFrom(InputText) then
            Error(NoCaseErr);
    end;

    // Builds the scenario, commits it so the engine may call the provider, generates and scores. Returns the score.
    procedure RunCase(CaseJson: JsonObject; var ExrRun: Record "EXR Run"; var Output: JsonObject) CaseScore: Decimal
    var
        TempFinding: Record "EXR Finding" temporary;
    begin
        Scenarios.Build(Scorer.JsonObjectOf(CaseJson, 'test_setup'), ExrRun);
        Commit();
        Engine.Generate(ExrRun, TempFinding);
        AddRunInfo(CaseJson, ExrRun, TempFinding, Output);
        CaseScore := Scorer.Score(CaseJson, ExrRun, TempFinding, Recorder.LastReply(), Recorder.LastSystemPrompt(), Recorder.LastUserMessage(), Recorder.LastJsonSchema(), Output);
    end;

    // Builds the scenario, runs the detectors and builds the request: no model call, no cost. Returns the mismatch, empty when none:
    // the findings, the must_cite captions and whether the trap text reaches the model.
    procedure CheckScenario(CaseJson: JsonObject) Mismatch: Text
    var
        ExrRun: Record "EXR Run";
        TempFinding: Record "EXR Finding" temporary;
        RunContext: Codeunit "EXR Run Context";
        Handler: Interface "EXR Capability Handler";
        Expected: JsonObject;
    begin
        Scenarios.Build(Scorer.JsonObjectOf(CaseJson, 'test_setup'), ExrRun);
        RunContext.StartRun();
        Handler := ExrRun.Capability;
        Handler.BuildFacts(ExrRun, TempFinding, RunContext);
        Expected := Scorer.JsonObjectOf(CaseJson, 'expected_data');
        Mismatch := Scorer.CompareFindingSet(Expected, TempFinding);
        Scorer.AddToList(Mismatch, Scorer.MustCiteMismatch(Expected, TempFinding));
        Scorer.AddToList(Mismatch, Scorer.TrapMissingFromRequest(CaseJson, Engine.BuildUserMessage(Handler, ExrRun, TempFinding, RunContext)));
    end;

    // Stops the test when AL did not find the dataset's findings, after the result was recorded.
    procedure StopOnScenarioError(CaseJson: JsonObject; Output: JsonObject)
    var
        Mismatch: Text;
    begin
        Mismatch := Scorer.JsonText(Output, 'scenarioError');
        if Mismatch <> '' then
            Error(ScenarioErr, Scorer.JsonText(CaseJson, 'name'), Mismatch);
    end;

    // The lines of a dataset resource of this app, one case per line.
    procedure ReadDataset(FileName: Text) Cases: List of [JsonObject]
    var
        ResourceStream: InStream;
        CaseJson: JsonObject;
        Line: Text;
    begin
        NavApp.GetResource(FileName, ResourceStream, TextEncoding::UTF8);
        while not ResourceStream.EOS() do begin
            ResourceStream.ReadText(Line);
            if Line.Trim() <> '' then begin
                Clear(CaseJson);
                CaseJson.ReadFrom(Line);
                Cases.Add(CaseJson);
            end;
        end;
    end;

    procedure GetCase(FileName: Text; CaseName: Text): JsonObject
    var
        CaseJson: JsonObject;
    begin
        foreach CaseJson in ReadDataset(FileName) do
            if Scorer.JsonText(CaseJson, 'name') = CaseName then
                exit(CaseJson);
    end;

    // What a reader of the results needs besides the checks: versions, usage and what the user would see.
    local procedure AddRunInfo(CaseJson: JsonObject; ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; var Output: JsonObject)
    var
        Setup: Record "EXR Setup";
        MainApp: ModuleInfo;
        Findings: JsonArray;
        Finding: JsonObject;
        DurationMs: BigInteger;
    begin
        Setup.Get();
        NavApp.GetModuleInfo(MainAppIdTok, MainApp);
        DurationMs := ExrRun.Duration;
        Output.Add('case', Scorer.JsonText(CaseJson, 'name'));
        Output.Add('capability', Format(ExrRun.Capability));
        Output.Add('appVersion', Format(MainApp.AppVersion));
        Output.Add('model', ExrRun.Model);
        Output.Add('effort', Format(Setup.Effort));
        Output.Add('promptVersion', ExrRun."Prompt Version");
        Output.Add('status', Format(ExrRun.Status));
        Output.Add('errorMessage', ExrRun."Error Message");
        Output.Add('modelCalls', Recorder.Calls());
        Output.Add('inputTokens', ExrRun."Input Tokens");
        Output.Add('outputTokens', ExrRun."Output Tokens");
        Output.Add('durationMs', DurationMs);
        Output.Add('summary', ExrRun.Summary);
        Output.Add('emailSubject', ExrRun."Email Subject");
        Output.Add('emailBody', ExrRun.GetEmailBody());
        // what the model itself wrote, so a later reader can score the run again
        Output.Add('rawReply', Recorder.LastReply());
        TempFinding.Reset();
        if TempFinding.FindSet() then
            repeat
                Clear(Finding);
                Finding.Add('key', TempFinding."Finding Key");
                Finding.Add('type', TempFinding."Finding Type");
                Finding.Add('action', Format(TempFinding."Action"));
                Finding.Add('confidence', Format(TempFinding.Confidence));
                Finding.Add('unverifiedFigure', TempFinding."Unverified Figure");
                Finding.Add('explanation', TempFinding.Description);
                Finding.Add('emailSubject', TempFinding."Email Subject");
                Finding.Add('emailBody', TempFinding.GetEmailBody());
                Findings.Add(Finding);
            until TempFinding.Next() = 0;
        TempFinding.Reset();
        Output.Add('findings', Findings);
    end;
}
