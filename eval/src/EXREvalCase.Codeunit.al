namespace PrabinBhusal.ExplainResolve.Eval;

using PrabinBhusal.ExplainResolve;
using System.TestTools.AITestToolkit;

// One dataset case against the real AI provider: one billed model call, two when the engine retries a reply it cannot read.
// Run it from the AI Eval Suite EXR-EVAL, one line per capability: the toolkit logs the output, score and tokens after the
// codeunit isolation rollback, which also removes the scenario, the run row and the setup changes.
codeunit 58300 "EXR Eval Case"
{
    Subtype = Test;
    TestType = AITest;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;
    TestHttpRequestPolicy = AllowAllOutboundRequests;

    var
        AITTestContext: Codeunit "AIT Test Context";
        Runner: Codeunit "EXR Eval Runner";

    [Test]
    procedure ScoreCase()
    var
        ExrRun: Record "EXR Run";
        CaseJson: JsonObject;
        Output: JsonObject;
        OutputText: Text;
        CaseScore: Decimal;
    begin
        // [GIVEN] the case of this iteration, with the recorder in front of the real provider
        CaseJson := Runner.CaseFromSuite(AITTestContext.GetInput().ToText());
        Runner.Prepare(true);

        // [WHEN] its scenario is generated once and scored
        CaseScore := Runner.RunCase(CaseJson, ExrRun, Output);

        // [THEN] the result is logged with the score as accuracy; a scenario that misses its findings fails the test
        Output.WriteTo(OutputText);
        AITTestContext.SetTestOutput(OutputText);
        AITTestContext.SetTokenConsumption(ExrRun."Input Tokens" + ExrRun."Output Tokens");
        AITTestContext.SetAccuracy(CaseScore);
        Runner.StopOnScenarioError(CaseJson, Output);
    end;
}
