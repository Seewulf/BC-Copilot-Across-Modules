namespace PrabinBhusal.ExplainResolve.Eval;

using PrabinBhusal.ExplainResolve;
using System.TestTools.AITestToolkit;
using System.TestTools.TestRunner;

// Tools for a test runner that reports only error text, such as al_run_tests: each method stops on purpose with its result.
// The Smoke methods run one case against the real provider (one or two billed calls each); ExportPage1-16 read the latest AI Eval Suite run in pages;
// SuiteStatus shows the suite lines and dataset sizes, free, before a billed run.
codeunit 58309 "EXR Eval Console"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;
    TestHttpRequestPolicy = AllowAllOutboundRequests;

    var
        Runner: Codeunit "EXR Eval Runner";
        SuiteCodeTok: Label 'EXR-EVAL', Locked = true;
        ResultTok: Label 'EXR-EVAL-RESULT %1', Locked = true;
        VersionTok: Label '%1 v%2 ', Locked = true, Comment = '%1 = dataset, %2 = log version';

    [Test]
    procedure SmokePurchaseVariance()
    begin
        Smoke('EXR-EVAL-PV.jsonl', 'PV-01');
    end;

    [Test]
    procedure SmokeCollections()
    begin
        Smoke('EXR-EVAL-COL.jsonl', 'COL-T2');
    end;

    [Test]
    procedure SmokePaymentRun()
    begin
        Smoke('EXR-EVAL-PR.jsonl', 'PR-T4');
    end;

    [Test]
    procedure SuiteStatus()
    var
        AITTestMethodLine: Record "AIT Test Method Line";
        TestInput: Record "Test Input";
        Result: JsonObject;
        Lines: JsonArray;
        Line: JsonObject;
        OutputText: Text;
    begin
        AITTestMethodLine.SetRange("Test Suite Code", SuiteCodeTok);
        if AITTestMethodLine.FindSet() then
            repeat
                Clear(Line);
                TestInput.SetRange("Test Input Group Code", AITTestMethodLine."Input Dataset");
                Line.Add('lineNo', AITTestMethodLine."Line No.");
                Line.Add('codeunitId', AITTestMethodLine."Codeunit ID");
                Line.Add('dataset', AITTestMethodLine."Input Dataset");
                Line.Add('description', AITTestMethodLine.Description);
                Line.Add('cases', TestInput.Count());
                Lines.Add(Line);
            until AITTestMethodLine.Next() = 0;
        Result.Add('suite', SuiteCodeTok);
        Result.Add('lines', Lines);
        Result.WriteTo(OutputText);
        Error(ResultTok, OutputText);
    end;

    [Test]
    procedure ExportPage1()
    begin
        Export(1);
    end;

    [Test]
    procedure ExportPage2()
    begin
        Export(2);
    end;

    [Test]
    procedure ExportPage3()
    begin
        Export(3);
    end;

    [Test]
    procedure ExportPage4()
    begin
        Export(4);
    end;

    [Test]
    procedure ExportPage5()
    begin
        Export(5);
    end;

    [Test]
    procedure ExportPage6()
    begin
        Export(6);
    end;

    [Test]
    procedure ExportPage7()
    begin
        Export(7);
    end;

    [Test]
    procedure ExportPage8()
    begin
        Export(8);
    end;

    [Test]
    procedure ExportPage9()
    begin
        Export(9);
    end;

    [Test]
    procedure ExportPage10()
    begin
        Export(10);
    end;

    [Test]
    procedure ExportPage11()
    begin
        Export(11);
    end;

    [Test]
    procedure ExportPage12()
    begin
        Export(12);
    end;

    [Test]
    procedure ExportPage13()
    begin
        Export(13);
    end;

    [Test]
    procedure ExportPage14()
    begin
        Export(14);
    end;

    [Test]
    procedure ExportPage15()
    begin
        Export(15);
    end;

    [Test]
    procedure ExportPage16()
    begin
        Export(16);
    end;

    // The same path as the AI Eval Suite, but nothing is logged: the scored result is the error text.
    local procedure Smoke(FileName: Text; CaseName: Text)
    var
        ExrRun: Record "EXR Run";
        Output: JsonObject;
        Result: JsonObject;
        Cases: JsonArray;
        OutputText: Text;
    begin
        Runner.Prepare(true);
        Runner.RunCase(Runner.GetCase(FileName, CaseName), ExrRun, Output);
        Cases.Add(Output);
        Result.Add('suite', SuiteCodeTok);
        Result.Add('runId', 'smoke');
        Result.Add('cases', Cases);
        Result.WriteTo(OutputText);
        Error(ResultTok, OutputText);
    end;

    // One page of the latest logged run of each dataset (the version of its newest log entry), as {"suite", "page", "pages", "cases": [...]}.
    // Business Central cuts error text over about 25,000 characters in the middle, so cases are split into pages of at most PageBudget.
    // Filtered by version: the toolkit leaves Run ID empty on these log entries.
    local procedure Export(PageNo: Integer)
    var
        AITLogEntry: Record "AIT Log Entry";
        Result: JsonObject;
        Cases: JsonArray;
        CaseOutput: JsonObject;
        Datasets: List of [Code[100]];
        Dataset: Code[100];
        CaseText: Text;
        OutputText: Text;
        Versions: Text;
        LogVersion: Integer;
        CurrentPage: Integer;
        PageLength: Integer;
    begin
        Datasets.Add('EXR-EVAL-PV');
        Datasets.Add('EXR-EVAL-COL');
        Datasets.Add('EXR-EVAL-PR');
        CurrentPage := 1;
        PageLength := 0;
        foreach Dataset in Datasets do begin
            AITLogEntry.Reset();
            AITLogEntry.SetRange("Test Suite Code", SuiteCodeTok);
            AITLogEntry.SetRange("Test Input Group Code", Dataset);
            if AITLogEntry.FindLast() then begin
                LogVersion := AITLogEntry.Version;
                Versions += StrSubstNo(VersionTok, Dataset, LogVersion);
                AITLogEntry.SetRange(Version, LogVersion);
                AITLogEntry.FindSet();
                repeat
                    CaseOutput := LogEntryOutput(AITLogEntry);
                    CaseOutput.WriteTo(CaseText);
                    if (PageLength > 0) and (PageLength + StrLen(CaseText) > PageBudget()) then begin
                        CurrentPage += 1;
                        PageLength := 0;
                    end;
                    PageLength += StrLen(CaseText);
                    if CurrentPage = PageNo then
                        Cases.Add(CaseOutput);
                until AITLogEntry.Next() = 0;
            end;
        end;
        Result.Add('suite', SuiteCodeTok);
        Result.Add('page', PageNo);
        Result.Add('pages', CurrentPage);
        Result.Add('runId', Versions.TrimEnd(' '));
        Result.Add('cases', Cases);
        Result.WriteTo(OutputText);
        Error(ResultTok, OutputText);
    end;

    // The case output the test logged (its "answer"), with the log entry's own fields.
    local procedure LogEntryOutput(AITLogEntry: Record "AIT Log Entry") CaseOutput: JsonObject
    var
        Logged: JsonObject;
        Answer: JsonToken;
    begin
        if Logged.ReadFrom(AITLogEntry.GetOutputBlob()) and Logged.Get('answer', Answer) and Answer.IsObject() then
            CaseOutput := Answer.AsObject()
        else
            CaseOutput.Add('rawOutput', AITLogEntry.GetOutputBlob());
        CaseOutput.Add('logEntryNo', AITLogEntry."Entry No.");
        CaseOutput.Add('logVersion', AITLogEntry.Version);
        CaseOutput.Add('logStatus', Format(AITLogEntry.Status));
        CaseOutput.Add('logMessage', AITLogEntry.GetMessage());
        CaseOutput.Add('logDurationMs', AITLogEntry."Duration (ms)");
        CaseOutput.Add('logStartTime', AITLogEntry."Start Time");
    end;

    local procedure PageBudget(): Integer
    begin
        exit(20000);
    end;
}
