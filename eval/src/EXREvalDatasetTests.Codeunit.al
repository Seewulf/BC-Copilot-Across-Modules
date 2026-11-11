namespace PrabinBhusal.ExplainResolve.Eval;

using System.TestLibraries.Utilities;

// Every dataset case builds its scenario and Business Central finds exactly the findings the case expects.
// Detectors only: no model call, so the datasets can be checked for free before a billed run.
codeunit 58308 "EXR Eval Dataset Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Runner: Codeunit "EXR Eval Runner";
        Scorer: Codeunit "EXR Eval Scorer";
        CaseErrorTok: Label '%1: %2', Locked = true;
        EmptyDatasetErr: Label 'Dataset %1 has no cases.', Comment = '%1 = file name';

    [Test]
    procedure PurchaseVarianceCasesGiveTheirFindings()
    begin
        // [GIVEN] the Explain invoice variance dataset [WHEN] each scenario is built [THEN] its findings match
        Assert.AreEqual('', Mismatches('EXR-EVAL-PV.jsonl'), 'scenario errors');
    end;

    [Test]
    procedure CollectionsCasesGiveTheirFindings()
    begin
        // [GIVEN] the Plan collections dataset [WHEN] each scenario is built [THEN] its findings match
        Assert.AreEqual('', Mismatches('EXR-EVAL-COL.jsonl'), 'scenario errors');
    end;

    [Test]
    procedure PaymentRunCasesGiveTheirFindings()
    begin
        // [GIVEN] the Check payment run dataset [WHEN] each scenario is built [THEN] its findings match
        Assert.AreEqual('', Mismatches('EXR-EVAL-PR.jsonl'), 'scenario errors');
    end;

    local procedure Mismatches(FileName: Text) Result: Text
    var
        Cases: List of [JsonObject];
        CaseJson: JsonObject;
        Mismatch: Text;
    begin
        Runner.Prepare(false);
        Cases := Runner.ReadDataset(FileName);
        if Cases.Count() = 0 then
            Error(EmptyDatasetErr, FileName);
        foreach CaseJson in Cases do begin
            Mismatch := Runner.CheckScenario(CaseJson);
            if Mismatch <> '' then
                Result += StrSubstNo(CaseErrorTok, Scorer.JsonText(CaseJson, 'name'), Mismatch) + ' | ';
        end;
    end;
}
