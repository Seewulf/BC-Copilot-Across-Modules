namespace PrabinBhusal.ExplainResolve.Eval;

using System.TestTools.AITestToolkit;

// Imports the datasets and the AI eval suite EXR-EVAL from the app's resources. Runs nothing and calls no model.
codeunit 58305 "EXR Eval Install"
{
    Subtype = Install;
    Access = Internal;

    var
        PurchaseVarianceFileTok: Label 'EXR-EVAL-PV.jsonl', Locked = true;
        CollectionsFileTok: Label 'EXR-EVAL-COL.jsonl', Locked = true;
        PaymentRunFileTok: Label 'EXR-EVAL-PR.jsonl', Locked = true;
        SuiteFileTok: Label 'EXR-EVAL.xml', Locked = true;
        SuiteCodeTok: Label 'EXR-EVAL', Locked = true;

    trigger OnInstallAppPerCompany()
    begin
        ImportSuite();
    end;

    // The toolkit replaces a dataset this app imported before and skips a suite whose XML did not change.
    internal procedure ImportSuite()
    var
        AITALTestSuiteMgt: Codeunit "AIT AL Test Suite Mgt";
        ResourceStream: InStream;
    begin
        ImportDataset(PurchaseVarianceFileTok);
        ImportDataset(CollectionsFileTok);
        ImportDataset(PaymentRunFileTok);
        NavApp.GetResource(SuiteFileTok, ResourceStream, TextEncoding::UTF8);
        AITALTestSuiteMgt.ImportAITestSuite(ResourceStream);
        RemoveReplacedLines();
    end;

    // A changed suite XML replaces the suite record but leaves its old lines, numbered below the new ones:
    // keep only the newest line per dataset, so no dataset runs twice.
    local procedure RemoveReplacedLines()
    var
        AITTestMethodLine: Record "AIT Test Method Line";
        NewerLine: Record "AIT Test Method Line";
    begin
        AITTestMethodLine.SetRange("Test Suite Code", SuiteCodeTok);
        if AITTestMethodLine.FindSet() then
            repeat
                NewerLine.SetRange("Test Suite Code", SuiteCodeTok);
                NewerLine.SetRange("Input Dataset", AITTestMethodLine."Input Dataset");
                NewerLine.SetFilter("Line No.", '>%1', AITTestMethodLine."Line No.");
                if not NewerLine.IsEmpty() then
                    AITTestMethodLine.Delete(true);
            until AITTestMethodLine.Next() = 0;
    end;

    local procedure ImportDataset(FileName: Text)
    var
        AITALTestSuiteMgt: Codeunit "AIT AL Test Suite Mgt";
        ResourceStream: InStream;
    begin
        NavApp.GetResource(FileName, ResourceStream, TextEncoding::UTF8);
        AITALTestSuiteMgt.ImportTestInputs(FileName, ResourceStream);
    end;
}
