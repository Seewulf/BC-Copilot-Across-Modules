namespace PrabinBhusal.ExplainResolve;

using System.AI;
using System.Security.Encryption;
using System.Telemetry;
using System.Utilities;

// Shared pipeline for every capability: guards, deterministic facts, one model call, validation and rendering.
// Nothing is written before the model call; Keep and Discard write the outcome.
codeunit 58202 "EXR Engine"
{
    Access = Internal;

    var
        SharedPromptTok: Label 'shared-rules.md', Locked = true;
        PromptVersionTok: Label '%1#%2', Locked = true;
        TableTok: Label '{TABLE}', Locked = true;
        FactTokenPatternTok: Label '\{F\d+\}', Locked = true;
        // a whole finding key in any letter case, so LINE-1 never matches inside LINE-10
        KeyPatternTok: Label '(?i)(?<![A-Z0-9_])%1(?![A-Z0-9_])', Locked = true;
        SentenceStartKeyTok: Label '(?i)(?<=^\s*|[.!?]\s+|\n\s*)%1(?![A-Z0-9_])', Locked = true;
        // stands in for a token or key in the flag checks: no pattern matches it, and an address glued to it still reads as one
        PlaceholderTok: Label '_', Locked = true;
        // a currency symbol, two decimals, a thousands separator or a percentage: a figure the model wrote itself
        FigurePatternTok: Label '[£$€¥]\s?\d|\d[.,]\d{2}(?!\d)|\d{1,3}(,\d{3})+|\d\s?%', Locked = true;
        // in any text: an email address, an IBAN or a phone number (9 or more characters) the model wrote itself, the shape of a payment redirection
        ContactPatternTok: Label '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]+|(?<![A-Za-z0-9])[A-Z]{2}\d{2}(\s?[A-Z0-9]{4}){2,}|\+?\d[\d\s().-]{7,}\d', Locked = true;
        // in an email also a run of six or more digits, such as an account number
        AccountNoPatternTok: Label '\d{6,}', Locked = true;
        ReplySchemaTok: Label '{"type":"object","additionalProperties":false,"required":["summary","findings","emailSubject","emailBody"],"properties":{"summary":{"type":"string"},"findings":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["key","explanation","action","confidence"],"properties":{"key":{"type":"string","enum":%1},"explanation":{"type":"string"},"action":{"type":"string","enum":%2},"confidence":{"type":"string","enum":["High","Medium","Low"]}}}},"emailSubject":{"type":"string"},"emailBody":{"type":"string"}}}', Locked = true;
        // one email per finding, for example a reminder per customer; empty strings when the action needs no email
        ReplySchemaPerFindingTok: Label '{"type":"object","additionalProperties":false,"required":["summary","findings"],"properties":{"summary":{"type":"string"},"findings":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["key","explanation","action","confidence","emailSubject","emailBody"],"properties":{"key":{"type":"string","enum":%1},"explanation":{"type":"string"},"action":{"type":"string","enum":%2},"confidence":{"type":"string","enum":["High","Medium","Low"]},"emailSubject":{"type":"string"},"emailBody":{"type":"string"}}}}}}', Locked = true;
        // no email at all, for example a payment run: the summary is the note for the approver
        ReplySchemaNoEmailTok: Label '{"type":"object","additionalProperties":false,"required":["summary","findings"],"properties":{"summary":{"type":"string"},"findings":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["key","explanation","action","confidence"],"properties":{"key":{"type":"string","enum":%1},"explanation":{"type":"string"},"action":{"type":"string","enum":%2},"confidence":{"type":"string","enum":["High","Medium","Low"]}}}}}}', Locked = true;
        FeatureNameTok: Label 'Explain and Resolve', Locked = true;
        GeneratedEventIdTok: Label 'EXR0001', Locked = true;
        FailedEventIdTok: Label 'EXR0002', Locked = true;
        BlockedEventIdTok: Label 'EXR0003', Locked = true;
        KeptEventIdTok: Label 'EXR0004', Locked = true;
        DiscardedEventIdTok: Label 'EXR0005', Locked = true;
        GeneratedEventTok: Label 'Run generated', Locked = true;
        FailedEventTok: Label 'Run failed', Locked = true;
        BlockedEventTok: Label 'Run blocked by limit', Locked = true;
        KeptEventTok: Label 'Run kept', Locked = true;
        DiscardedEventTok: Label 'Run discarded', Locked = true;
        TelemetryErrorTok: Label 'The AI service failed or answered in the wrong format.', Locked = true;
        NoApiKeyErr: Label 'Enter the API key on the Explain and Resolve Setup page first.';
        CapabilityOffErr: Label '%1 is switched off. An administrator can turn it on in Copilot & agent capabilities.', Comment = '%1 = name of the capability';
        SourceMissingErr: Label 'The record to review no longer exists.';
        UserLimitErr: Label 'You have reached your daily limit of %1. The limit is set on the Explain and Resolve Setup page.', Comment = '%1 = daily limit per user, for example 50 runs';
        CompanyLimitErr: Label 'This company has reached its daily limit of %1. The limit is set on the Explain and Resolve Setup page.', Comment = '%1 = daily limit per company, for example 500 runs';
        OneRunLbl: Label '%1 run', Comment = '%1 = number of runs (1)';
        RunsLbl: Label '%1 runs', Comment = '%1 = number of runs';
        InvalidReplyErr: Label 'The AI service answered twice in a format that could not be read.';
        BlockedErr: Label '%1', Locked = true;
        RegenerateFailedErr: Label 'A new result could not be created, so the previous one is kept. %1', Comment = '%1 = error from the AI service';
        OutputBudgetErr: Label 'This review has %1 findings, each with its own email, and a reply that long may be cut off at the Max Output Tokens limit of %2. Review %3 or fewer at a time, or ask an administrator to raise Max Output Tokens on the Explain and Resolve Setup page.', Comment = '%1 = number of findings, %2 = Max Output Tokens, %3 = number of findings that fit';
        NoFindingsMsg: Label 'Business Central found nothing that needs attention, so the AI service was not called.';
        // shown in place of {TABLE} while the user reviews the email; Keep it puts the real table there
        TablePreviewLbl: Label '[Business Central lists the lines here when you keep it]';
        AiUnavailableMsg: Label 'AI unavailable: the findings below were computed by Business Central and are shown without an explanation. %1', Comment = '%1 = error from the AI service';

    // The run arrives with the capability, the source and the options. It leaves inserted as Generated, Failed or Blocked by Limit.
    procedure Generate(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary)
    var
        Setup: Record "EXR Setup";
        RunContext: Codeunit "EXR Run Context";
        Handler: Interface "EXR Capability Handler";
        Reply: JsonObject;
        SystemPrompt: Text;
        ErrorText: Text;
    begin
        TempFinding.Reset();
        TempFinding.DeleteAll();
        Handler := ExrRun.Capability;
        CheckSetup(Setup);
        CheckCapabilityActive(Handler.CopilotCapability());
        ResolveSource(Handler, ExrRun);
        ExrRun."Entry No." := 0;
        ExrRun."User ID" := CopyStr(UserId(), 1, MaxStrLen(ExrRun."User ID"));
        ExrRun."Created At" := CurrentDateTime();
        ExrRun.Model := Setup.Model;
        if LimitReached(Setup, ExrRun, ErrorText) then begin
            ExrRun.Status := ExrRun.Status::"Blocked by Limit";
            ExrRun."Error Message" := CopyStr(ErrorText, 1, MaxStrLen(ExrRun."Error Message"));
            ExrRun.Insert(true);
            LogRun(ExrRun, BlockedEventIdTok, BlockedEventTok);
            exit;
        end;

        RunContext.StartRun();
        Handler.BuildFacts(ExrRun, TempFinding, RunContext);
        SystemPrompt := LoadSystemPrompt(Handler, ExrRun);
        if TempFinding.IsEmpty() then
            ExrRun.Summary := NoFindingsMsg
        else begin
            CheckOutputBudget(Setup, Handler, TempFinding);
            if CallModel(Setup, SystemPrompt, BuildUserMessage(Handler, ExrRun, TempFinding, RunContext), BuildReplySchema(Handler, TempFinding), ExrRun, Reply, ErrorText) then
                ApplyReply(Handler, Reply, ExrRun, TempFinding, RunContext)
            else
                FailClosed(ExrRun, ErrorText);
        end;
        ExrRun.Insert(true);
        if ExrRun.Status = ExrRun.Status::Failed then
            LogRun(ExrRun, FailedEventIdTok, FailedEventTok)
        else
            LogRun(ExrRun, GeneratedEventIdTok, GeneratedEventTok);
    end;

    // For the dialog: generates a new run and only when that succeeds replaces the current run and its findings,
    // discarding the old run. A blocked or failed attempt leaves the current run as it was, so it can still be kept.
    procedure Regenerate(var CurrentRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; NewRun: Record "EXR Run")
    var
        TempNewFinding: Record "EXR Finding" temporary;
    begin
        Generate(NewRun, TempNewFinding);
        if NewRun.Status = NewRun.Status::"Blocked by Limit" then begin
            // keep the Blocked by Limit row before the error rolls back the action
            Commit();
            Error(BlockedErr, NewRun."Error Message");
        end;
        // a failed call replaces nothing once there is a result; the Failed row stays as the usage record
        // (the first Generate still shows a failed run, with its findings and no explanation)
        if (NewRun.Status = NewRun.Status::Failed) and (CurrentRun."Entry No." <> 0) then begin
            Commit();
            Error(RegenerateFailedErr, NewRun."Error Message");
        end;
        Discard(CurrentRun);
        CurrentRun := NewRun;
        TempFinding.Reset();
        TempFinding.DeleteAll();
        TempNewFinding.Reset();
        if TempNewFinding.FindSet() then
            repeat
                TempFinding := TempNewFinding;
                // the email body is a Blob: copied explicitly, not through the record assignment
                TempFinding.SetEmailBody(TempNewFinding.GetEmailBody());
                TempFinding.Insert();
            until TempNewFinding.Next() = 0;
    end;

    // Saves the run, the accepted findings, the emails and the capability's own writes. A second Keep it changes nothing.
    // Returns the confirmation for the user; empty when nothing was kept.
    procedure Keep(var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; EmailSubject: Text; EmailBody: Text) KeptMessage: Text
    var
        Finding: Record "EXR Finding";
        Handler: Interface "EXR Capability Handler";
    begin
        ExrRun.ReadIsolation := IsolationLevel::UpdLock;
        ExrRun.Get(ExrRun."Entry No.");
        if ExrRun.Status in [ExrRun.Status::Kept, ExrRun.Status::Discarded, ExrRun.Status::"Blocked by Limit"] then
            exit('');
        Handler := ExrRun.Capability;
        TempFinding.Reset();
        TempFinding.SetRange(Accepted, true);
        // the emails list the accepted findings only
        if Handler.DraftsEmailPerFinding() then
            InsertFindingEmailTables(Handler, TempFinding)
        else
            if Handler.DraftsEmail() then begin
                // saved first because the draft reads the body from the table
                ExrRun."Email Subject" := CopyStr(EmailSubject, 1, MaxStrLen(ExrRun."Email Subject"));
                ExrRun.SetEmailBody(InsertEmailTable(EmailBody, Handler.BuildEmailTable(TempFinding)));
                ExrRun.Modify();
            end;
        // the handler gets the accepted findings only and may fill in their recipients and draft flags
        KeptMessage := Handler.ApplyKeep(ExrRun, TempFinding);
        TempFinding.SetRange(Accepted, true);
        if TempFinding.FindSet() then
            repeat
                Finding := TempFinding;
                Finding."Run Entry No." := ExrRun."Entry No.";
                Finding.SetEmailBody(TempFinding.GetEmailBody());
                Finding.Insert();
            until TempFinding.Next() = 0;
        ExrRun.Status := ExrRun.Status::Kept;
        ExrRun.Modify();
        TempFinding.Reset();
        LogRun(ExrRun, KeptEventIdTok, KeptEventTok);
    end;

    // Writes only the run row. Failed and blocked runs keep their status.
    procedure Discard(var ExrRun: Record "EXR Run")
    begin
        if ExrRun."Entry No." = 0 then
            exit;
        ExrRun.ReadIsolation := IsolationLevel::UpdLock;
        if not ExrRun.Get(ExrRun."Entry No.") then
            exit;
        if ExrRun.Status <> ExrRun.Status::Generated then
            exit;
        ExrRun.Status := ExrRun.Status::Discarded;
        ExrRun.Modify();
        LogRun(ExrRun, DiscardedEventIdTok, DiscardedEventTok);
    end;

    procedure CheckCapabilityActive(CopilotCapabilityValue: Enum "Copilot Capability")
    var
        CopilotCapability: Codeunit "Copilot Capability";
    begin
        // false when the capability is not registered for this app or an admin switched it off
        if not CopilotCapability.IsCapabilityActive(CopilotCapabilityValue) then
            Error(CapabilityOffErr, Format(CopilotCapabilityValue));
    end;

    // The fact pack: every string from data or from the user goes in wrapped as untrusted.
    procedure BuildUserMessage(Handler: Interface "EXR Capability Handler"; ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context") UserMessage: Text
    var
        Pack: JsonObject;
        Findings: JsonArray;
    begin
        Pack.Add('task', Format(ExrRun.Capability));
        Pack.Add('context', RunContext.ContextJson());
        Pack.Add('documentFacts', RunContext.FactsJson(''));
        TempFinding.Reset();
        if TempFinding.FindSet() then
            repeat
                Findings.Add(FindingJson(Handler, TempFinding, RunContext));
            until TempFinding.Next() = 0;
        Pack.Add('findings', Findings);
        if Handler.DraftsEmail() then
            Pack.Add('emailTone', Format(ExrRun."Email Tone"));
        if ExrRun."User Note" <> '' then
            Pack.Add('userNote', RunContext.WrapUntrusted(ExrRun."User Note"));
        Pack.WriteTo(UserMessage);
    end;

    // Strict schema: only the known finding keys and the actions some finding of this run allows can come back.
    // The per-type check happens again in ApplyFindingReply.
    procedure BuildReplySchema(Handler: Interface "EXR Capability Handler"; var TempFinding: Record "EXR Finding" temporary): Text
    var
        FindingKeys: JsonArray;
        ActionNames: JsonArray;
        FindingAction: Enum "EXR Action";
        Ordinal: Integer;
        KeysText: Text;
        ActionsText: Text;
    begin
        TempFinding.Reset();
        if TempFinding.FindSet() then
            repeat
                FindingKeys.Add(TempFinding."Finding Key");
            until TempFinding.Next() = 0;
        FindingKeys.WriteTo(KeysText);
        foreach Ordinal in Enum::"EXR Action".Ordinals() do begin
            FindingAction := Enum::"EXR Action".FromInteger(Ordinal);
            if AnyFindingAllows(Handler, TempFinding, FindingAction) then
                ActionNames.Add(ActionName(FindingAction));
        end;
        ActionNames.WriteTo(ActionsText);
        if not Handler.DraftsEmail() then
            exit(StrSubstNo(ReplySchemaNoEmailTok, KeysText, ActionsText));
        if Handler.DraftsEmailPerFinding() then
            exit(StrSubstNo(ReplySchemaPerFindingTok, KeysText, ActionsText));
        exit(StrSubstNo(ReplySchemaTok, KeysText, ActionsText));
    end;

    procedure ReadReply(ReplyText: Text; var Reply: JsonObject): Boolean
    var
        Token: JsonToken;
    begin
        Clear(Reply);
        if not Reply.ReadFrom(ReplyText) then
            exit(false);
        if not Reply.Get('summary', Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        if not Reply.Get('findings', Token) then
            exit(false);
        exit(Token.IsArray());
    end;

    // Validates the reply against the findings and fills in the figures. Anything unknown is dropped.
    procedure ApplyReply(Handler: Interface "EXR Capability Handler"; Reply: JsonObject; var ExrRun: Record "EXR Run"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    var
        EmailDraft: Codeunit "EXR Email Draft";
        Findings: JsonToken;
        Item: JsonToken;
        Body: Text;
        Flagged: Boolean;
    begin
        AddFindingReferences(TempFinding, RunContext);
        ExrRun.Summary := CopyStr(Render(TextValue(Reply, 'summary'), RunContext, Flagged), 1, MaxStrLen(ExrRun.Summary));
        ExrRun."Unverified Figures" := Flagged;
        if Reply.Get('findings', Findings) then
            if Findings.IsArray() then
                foreach Item in Findings.AsArray() do
                    if Item.IsObject() then
                        if ApplyFindingReply(Handler, Item.AsObject(), TempFinding, RunContext) then
                            ExrRun."Unverified Figures" := true;
        if Handler.DraftsEmail() and not Handler.DraftsEmailPerFinding() then begin
            // one email for the whole run goes to the one party all its findings are about, so every subject may appear
            ExrRun."Email Subject" := CopyStr(EmailDraft.SubjectWithReference(RenderEmail(TextValue(Reply, 'emailSubject'), '', RunContext, Flagged), RunContext.EmailReference(), MaxStrLen(ExrRun."Email Subject")), 1, MaxStrLen(ExrRun."Email Subject"));
            ExrRun."Unverified Figures" := ExrRun."Unverified Figures" or Flagged;
            // {TABLE} stays in the body: Keep it fills it from the findings the user accepted
            Body := RenderEmail(TextValue(Reply, 'emailBody'), '', RunContext, Flagged);
            ExrRun."Unverified Figures" := ExrRun."Unverified Figures" or Flagged;
            ExrRun.SetEmailBody(Body);
        end;
        TempFinding.Reset();
        ExrRun.Status := ExrRun.Status::Generated;
    end;

    // The body as the user sees it while reviewing: {TABLE} reads as a plain-language placeholder.
    procedure PreviewEmailBody(Body: Text): Text
    begin
        exit(Body.Replace(TableTok, TablePreviewLbl));
    end;

    // Turns the placeholder back into {TABLE}, so Keep it can put the table there.
    procedure EmailBodyFromPreview(PreviewBody: Text): Text
    begin
        exit(PreviewBody.Replace(TablePreviewLbl, TableTok));
    end;

    // Replaces known {Fn} tokens with their values and finding keys with their references, and drops unknown tokens.
    // Flags figures, addresses, IBANs and phone numbers written outside tokens and keys.
    procedure Render(Input: Text; var RunContext: Codeunit "EXR Run Context"; var Flagged: Boolean): Text
    begin
        exit(RenderText(Input, false, '', RunContext, Flagged));
    end;

    // Email text goes to an outside party. A finding's own email (Owner set) may cite only that finding's dates: any other
    // token is dropped and flagged. Every email is also flagged for an account number in the text.
    procedure RenderEmail(Input: Text; Owner: Text; var RunContext: Codeunit "EXR Run Context"; var Flagged: Boolean): Text
    begin
        exit(RenderText(Input, true, Owner, RunContext, Flagged));
    end;

    local procedure RenderText(Input: Text; IsEmail: Boolean; Owner: Text; var RunContext: Codeunit "EXR Run Context"; var Flagged: Boolean) Output: Text
    var
        TempMatches: Record Matches temporary;
        Regex: Codeunit Regex;
        Token: Text;
        Value: Text;
        WithoutTokens: Text;
        FindingKey: Text;
        KeyPattern: Text;
        CurrencyPattern: Text;
        OwnDatesOnly: Boolean;
        Found: Boolean;
        Dropped: Boolean;
    begin
        Output := Input;
        OwnDatesOnly := IsEmail and (Owner <> '');
        WithoutTokens := Input.Replace(TableTok, '');
        Regex.Match(Input, FactTokenPatternTok, TempMatches);
        if TempMatches.FindSet() then
            repeat
                Token := TempMatches.ReadValue();
                WithoutTokens := WithoutTokens.Replace(Token, PlaceholderTok);
                if OwnDatesOnly then
                    Found := RunContext.TryGetDateFactOf(Token, Owner, Value)
                else
                    Found := RunContext.TryGetFact(Token, Value);
                if not Found then begin
                    Value := '';
                    Dropped := Dropped or OwnDatesOnly;
                end;
                // a sentence fact brings its own full stop, so one the model adds after it is dropped
                if Value.EndsWith('.') then
                    Output := Output.Replace(Token + '.', Value);
                Output := Output.Replace(Token, Value);
            until TempMatches.Next() = 0;
        // a finding key works like a token: the user sees the finding's reference, whose numbers are never flagged.
        // A finding's own email may name only that finding, so another finding's key there is dropped and flagged.
        foreach FindingKey in RunContext.FindingKeys() do begin
            KeyPattern := StrSubstNo(KeyPatternTok, Regex.Escape(FindingKey));
            if Regex.IsMatch(Output, KeyPattern) then begin
                WithoutTokens := Regex.Replace(WithoutTokens, KeyPattern, PlaceholderTok);
                Value := '';
                if OwnDatesOnly and (FindingKey <> Owner) then
                    Dropped := true
                else begin
                    // $ is special in a regex replacement
                    Value := RunContext.FindingReference(FindingKey).Replace('$', '$$');
                    // a reference that starts a sentence gets a capital: payment EXR-1 reads as Payment EXR-1
                    Output := Regex.Replace(Output, StrSubstNo(SentenceStartKeyTok, Regex.Escape(FindingKey)), UpperCase(CopyStr(Value, 1, 1)) + CopyStr(Value, 2));
                end;
                Output := Regex.Replace(Output, KeyPattern, Value);
            end;
        end;
        Flagged := Dropped or Regex.IsMatch(WithoutTokens, FigurePatternTok);
        if not Flagged then
            Flagged := Regex.IsMatch(WithoutTokens, ContactPatternTok);
        if not Flagged and IsEmail then
            Flagged := Regex.IsMatch(WithoutTokens, AccountNoPatternTok);
        // an amount written with the run's currency code, such as GBP 150
        CurrencyPattern := RunContext.CurrencyFigurePattern();
        if not Flagged and (CurrencyPattern <> '') then
            Flagged := Regex.IsMatch(WithoutTokens, CurrencyPattern);
    end;

    local procedure CheckSetup(var Setup: Record "EXR Setup")
    begin
        Setup.GetSetup();
        if not Setup.HasApiKey() then
            Error(NoApiKeyErr);
    end;

    // A run over a selection, such as Plan collections, has no single source record.
    local procedure ResolveSource(Handler: Interface "EXR Capability Handler"; var ExrRun: Record "EXR Run")
    var
        SourceRecordRef: RecordRef;
    begin
        if Handler.ReviewsSelection() then
            exit;
        SourceRecordRef.Open(ExrRun."Source Table No.");
        if not SourceRecordRef.GetBySystemId(ExrRun."Source System Id") then
            Error(SourceMissingErr);
        ExrRun."Source Record ID" := SourceRecordRef.RecordId();
        SourceRecordRef.Close();
    end;

    // Every run today counts except blocked attempts. Read committed is enough for a cost cap.
    local procedure LimitReached(Setup: Record "EXR Setup"; ExrRun: Record "EXR Run"; var ErrorText: Text): Boolean
    var
        TodaysRun: Record "EXR Run";
    begin
        TodaysRun.ReadIsolation := IsolationLevel::ReadCommitted;
        TodaysRun.SetCurrentKey("Created At");
        TodaysRun.SetRange("Created At", CreateDateTime(Today(), 0T), CreateDateTime(Today() + 1, 0T) - 1);
        TodaysRun.SetFilter(Status, '<>%1', TodaysRun.Status::"Blocked by Limit");
        if TodaysRun.Count() >= Setup."Daily Calls per Company" then begin
            ErrorText := StrSubstNo(CompanyLimitErr, RunCount(Setup."Daily Calls per Company"));
            exit(true);
        end;
        TodaysRun.SetCurrentKey("User ID", "Created At");
        TodaysRun.SetRange("User ID", ExrRun."User ID");
        if TodaysRun.Count() >= Setup."Daily Calls per User" then begin
            ErrorText := StrSubstNo(UserLimitErr, RunCount(Setup."Daily Calls per User"));
            exit(true);
        end;
        exit(false);
    end;

    // Shared rules plus the capability prompt. The version is the file name and a hash of the text.
    local procedure LoadSystemPrompt(Handler: Interface "EXR Capability Handler"; var ExrRun: Record "EXR Run") SystemPrompt: Text
    var
        CryptographyManagement: Codeunit "Cryptography Management";
        HashAlgorithmType: Option MD5,SHA1,SHA256,SHA384,SHA512;
    begin
        SystemPrompt := NavApp.GetResourceAsText(SharedPromptTok, TextEncoding::UTF8) + NewLine() + NewLine() + NavApp.GetResourceAsText(Handler.PromptResourceName(), TextEncoding::UTF8);
        ExrRun."Prompt Version" := CopyStr(StrSubstNo(PromptVersionTok, Handler.PromptResourceName(), CopyStr(CryptographyManagement.GenerateHash(SystemPrompt, HashAlgorithmType::SHA256), 1, 12)), 1, MaxStrLen(ExrRun."Prompt Version"));
    end;

    // An invalid reply is retried once; a provider error is not retried.
    local procedure CallModel(Setup: Record "EXR Setup"; SystemPrompt: Text; UserMessage: Text; JsonSchema: Text; var ExrRun: Record "EXR Run"; var Reply: JsonObject; var ErrorText: Text): Boolean
    var
        Attempt: Integer;
        ReplyText: Text;
    begin
        for Attempt := 1 to 2 do begin
            if not RunProvider(Setup.Provider, SystemPrompt, UserMessage, JsonSchema, ExrRun, ReplyText, ErrorText) then
                exit(false);
            if ReadReply(ReplyText, Reply) then
                exit(true);
        end;
        ErrorText := InvalidReplyErr;
        exit(false);
    end;

    local procedure RunProvider(Provider: Enum "EXR Chat Provider"; SystemPrompt: Text; UserMessage: Text; JsonSchema: Text; var ExrRun: Record "EXR Run"; var ReplyText: Text; var ErrorText: Text): Boolean
    var
        ChatRunner: Codeunit "EXR Chat Runner";
        ChatResult: Codeunit "EXR Chat Result";
        Succeeded: Boolean;
    begin
        ChatRunner.SetRequest(Provider, SystemPrompt, UserMessage, JsonSchema);
        ClearLastError();
        Succeeded := ChatRunner.Run();
        ChatRunner.GetResult(ChatResult);
        ExrRun."Input Tokens" += ChatResult.InputTokens();
        ExrRun."Output Tokens" += ChatResult.OutputTokens();
        ExrRun.Duration += ChatResult.CallDuration();
        if not Succeeded then begin
            ErrorText := GetLastErrorText();
            exit(false);
        end;
        ReplyText := ChatResult.Reply();
        exit(true);
    end;

    // A reply with an email per finding grows with the findings: stop before a call that Max Output Tokens would cut off.
    // Limit: rough budget of 1,000 tokens for the summary and thinking plus 300 per finding; measure if replies still get cut
    local procedure CheckOutputBudget(Setup: Record "EXR Setup"; Handler: Interface "EXR Capability Handler"; var TempFinding: Record "EXR Finding" temporary)
    var
        FindingCount: Integer;
        FindingsThatFit: Integer;
    begin
        if not Handler.DraftsEmailPerFinding() then
            exit;
        TempFinding.Reset();
        FindingCount := TempFinding.Count();
        if 1000 + FindingCount * 300 <= Setup."Max Output Tokens" then
            exit;
        FindingsThatFit := (Setup."Max Output Tokens" - 1000) div 300;
        if FindingsThatFit < 0 then
            FindingsThatFit := 0;
        Error(OutputBudgetErr, FindingCount, Setup."Max Output Tokens", FindingsThatFit);
    end;

    // The deterministic findings stay, without an explanation.
    local procedure FailClosed(var ExrRun: Record "EXR Run"; ErrorText: Text)
    begin
        ExrRun.Status := ExrRun.Status::Failed;
        ExrRun."Error Message" := CopyStr(ErrorText, 1, MaxStrLen(ExrRun."Error Message"));
        ExrRun.Summary := CopyStr(StrSubstNo(AiUnavailableMsg, ErrorText), 1, MaxStrLen(ExrRun.Summary));
    end;

    // Returns whether the finding's own email has a figure the model wrote itself.
    local procedure ApplyFindingReply(Handler: Interface "EXR Capability Handler"; Item: JsonObject; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context") EmailFlagged: Boolean
    var
        FindingAction: Enum "EXR Action";
        FindingKey: Text;
        Explanation: Text;
        Flagged: Boolean;
        BodyFlagged: Boolean;
    begin
        FindingKey := UpperCase(TextValue(Item, 'key'));
        if (FindingKey = '') or (StrLen(FindingKey) > MaxStrLen(TempFinding."Finding Key")) then
            exit(false);
        TempFinding.Reset();
        TempFinding.SetRange("Finding Key", FindingKey);
        if not TempFinding.FindFirst() then
            exit(false);
        Explanation := Render(TextValue(Item, 'explanation'), RunContext, Flagged);
        if Explanation <> '' then begin
            TempFinding.Description := CopyStr(Explanation, 1, MaxStrLen(TempFinding.Description));
            TempFinding."Unverified Figure" := Flagged;
        end;
        // an action outside this finding type's allow-list is dropped and the detector's own action stays
        if TryParseAction(TextValue(Item, 'action'), FindingAction) then
            if Handler.IsActionAllowed(TempFinding."Finding Type", FindingAction) then
                TempFinding."Action" := FindingAction;
        TempFinding.Confidence := ParseConfidence(TextValue(Item, 'confidence'));
        if Handler.DraftsEmailPerFinding() then
            // only a reminder carries its own email; one drafted for any other action is dropped, so it cannot be opened or edited
            if TempFinding."Action" = Enum::"EXR Action"::"Email reminder" then begin
                TempFinding."Email Subject" := CopyStr(RenderEmail(TextValue(Item, 'emailSubject'), TempFinding."Finding Key", RunContext, Flagged), 1, MaxStrLen(TempFinding."Email Subject"));
                // {TABLE} stays in the body: Keep it fills in this finding's table
                TempFinding.SetEmailBody(RenderEmail(TextValue(Item, 'emailBody'), TempFinding."Finding Key", RunContext, BodyFlagged));
                EmailFlagged := Flagged or BodyFlagged;
                TempFinding."Unverified Figure" := TempFinding."Unverified Figure" or EmailFlagged;
            end else begin
                TempFinding."Email Subject" := '';
                TempFinding.SetEmailBody('');
            end;
        TempFinding.Modify();
        TempFinding.Reset();
    end;

    // The user never sees finding keys, so Render shows a key the model writes as the finding's subject,
    // unless the capability already gave a shorter reference.
    local procedure AddFindingReferences(var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context")
    begin
        TempFinding.Reset();
        if TempFinding.FindSet() then
            repeat
                RunContext.AddFindingReference(TempFinding."Finding Key", TempFinding.Subject);
            until TempFinding.Next() = 0;
    end;

    local procedure FindingJson(Handler: Interface "EXR Capability Handler"; var TempFinding: Record "EXR Finding" temporary; var RunContext: Codeunit "EXR Run Context") Finding: JsonObject
    var
        Context: JsonObject;
    begin
        Finding.Add('key', TempFinding."Finding Key");
        Finding.Add('type', TempFinding."Finding Type");
        Finding.Add('severity', Format(TempFinding.Severity));
        Finding.Add('subject', RunContext.WrapUntrusted(TempFinding.Subject));
        // only findings that have their own text, so the requests of the other capabilities stay as they were
        Context := RunContext.FindingContextJson(TempFinding."Finding Key");
        if Context.Keys().Count() > 0 then
            Finding.Add('context', Context);
        Finding.Add('suggestedAction', ActionName(TempFinding."Action"));
        Finding.Add('allowedActions', AllowedActions(Handler, TempFinding."Finding Type"));
        Finding.Add('facts', RunContext.FactsJson(TempFinding."Finding Key"));
    end;

    local procedure AllowedActions(Handler: Interface "EXR Capability Handler"; FindingType: Code[30]) ActionNames: JsonArray
    var
        FindingAction: Enum "EXR Action";
        Ordinal: Integer;
    begin
        foreach Ordinal in Enum::"EXR Action".Ordinals() do begin
            FindingAction := Enum::"EXR Action".FromInteger(Ordinal);
            if Handler.IsActionAllowed(FindingType, FindingAction) then
                ActionNames.Add(ActionName(FindingAction));
        end;
    end;

    local procedure AnyFindingAllows(Handler: Interface "EXR Capability Handler"; var TempFinding: Record "EXR Finding" temporary; FindingAction: Enum "EXR Action"): Boolean
    begin
        if TempFinding.FindSet() then
            repeat
                if Handler.IsActionAllowed(TempFinding."Finding Type", FindingAction) then
                    exit(true);
            until TempFinding.Next() = 0;
        exit(false);
    end;

    // The model sees the enum value names, so captions can be translated without breaking the contract.
    local procedure ActionName(FindingAction: Enum "EXR Action"): Text
    begin
        exit(Enum::"EXR Action".Names().Get(Enum::"EXR Action".Ordinals().IndexOf(FindingAction.AsInteger())));
    end;

    local procedure TryParseAction(Name: Text; var FindingAction: Enum "EXR Action"): Boolean
    var
        Index: Integer;
    begin
        Index := Enum::"EXR Action".Names().IndexOf(Name);
        if Index = 0 then
            exit(false);
        FindingAction := Enum::"EXR Action".FromInteger(Enum::"EXR Action".Ordinals().Get(Index));
        exit(true);
    end;

    local procedure ParseConfidence(Value: Text): Enum "EXR Confidence"
    begin
        case UpperCase(Value) of
            'HIGH':
                exit(Enum::"EXR Confidence"::High);
            'MEDIUM':
                exit(Enum::"EXR Confidence"::Medium);
            'LOW':
                exit(Enum::"EXR Confidence"::Low);
        end;
        exit(Enum::"EXR Confidence"::" ");
    end;

    // Each accepted finding with an email gets its own table, for example the customer's open invoices.
    local procedure InsertFindingEmailTables(Handler: Interface "EXR Capability Handler"; var TempFinding: Record "EXR Finding" temporary)
    var
        TempOneFinding: Record "EXR Finding" temporary;
    begin
        if TempFinding.FindSet() then
            repeat
                if TempFinding."Email Subject" <> '' then begin
                    TempOneFinding.Reset();
                    TempOneFinding.DeleteAll();
                    TempOneFinding := TempFinding;
                    TempOneFinding.Insert();
                    TempFinding.SetEmailBody(InsertEmailTable(TempFinding.GetEmailBody(), Handler.BuildEmailTable(TempOneFinding)));
                    TempFinding.Modify();
                end;
            until TempFinding.Next() = 0;
    end;

    local procedure RunCount(Number: Integer): Text
    var
        RunContext: Codeunit "EXR Run Context";
    begin
        exit(RunContext.CountPhrase(Number, OneRunLbl, RunsLbl));
    end;

    local procedure InsertEmailTable(Body: Text; EmailTable: Text): Text
    begin
        if Body.Contains(TableTok) then
            exit(Body.Replace(TableTok, EmailTable));
        if EmailTable = '' then
            exit(Body);
        exit(Body + NewLine() + NewLine() + EmailTable);
    end;

    local procedure TextValue(JObject: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not JObject.Get(KeyName, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure NewLine(): Text
    var
        LineFeed: Char;
    begin
        LineFeed := 10;
        exit(Format(LineFeed));
    end;

    // Usage figures only, never business data.
    local procedure LogRun(ExrRun: Record "EXR Run"; EventId: Text; EventName: Text)
    var
        FeatureTelemetry: Codeunit "Feature Telemetry";
        CustomDimensions: Dictionary of [Text, Text];
        DurationMs: BigInteger;
    begin
        DurationMs := ExrRun.Duration;
        CustomDimensions.Add('Capability', ExrRun.Capability.Names().Get(ExrRun.Capability.Ordinals().IndexOf(ExrRun.Capability.AsInteger())));
        CustomDimensions.Add('InputTokens', Format(ExrRun."Input Tokens", 0, 9));
        CustomDimensions.Add('OutputTokens', Format(ExrRun."Output Tokens", 0, 9));
        CustomDimensions.Add('DurationMs', Format(DurationMs, 0, 9));
        if ExrRun.Status = ExrRun.Status::Failed then
            FeatureTelemetry.LogError(EventId, FeatureNameTok, EventName, TelemetryErrorTok, '', CustomDimensions)
        else
            FeatureTelemetry.LogUsage(EventId, FeatureNameTok, EventName, CustomDimensions);
    end;
}
