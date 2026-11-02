namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;

// Stands in for the AI service: replies and errors are queued per test, and it remembers what it was sent.
// HttpClientHandler mocking is on-premises only, so the tests swap the provider instead.
codeunit 58270 "EXR Mock Chat Client" implements "EXR Chat Client"
{
    SingleInstance = true;

    var
        QueuedReplies: List of [Text];
        QueuedErrors: List of [Text];
        QueuedInputTokens: List of [Integer];
        QueuedOutputTokens: List of [Integer];
        QueuedDurations: List of [Integer];
        SentSystemPrompt: Text;
        SentUserMessage: Text;
        SentJsonSchema: Text;
        NothingQueuedErr: Label 'The mock chat client has no reply queued.', Locked = true;
        ScriptedErr: Label '%1', Locked = true;

    procedure Reset()
    begin
        Clear(QueuedReplies);
        Clear(QueuedErrors);
        Clear(QueuedInputTokens);
        Clear(QueuedOutputTokens);
        Clear(QueuedDurations);
        SentSystemPrompt := '';
        SentUserMessage := '';
        SentJsonSchema := '';
    end;

    procedure QueueReply(Reply: Text; InputTokens: Integer; OutputTokens: Integer; DurationMs: Integer)
    begin
        Queue(Reply, '', InputTokens, OutputTokens, DurationMs);
    end;

    procedure QueueError(ErrorText: Text)
    begin
        Queue('', ErrorText, 0, 0, 0);
    end;

    procedure LastSystemPrompt(): Text
    begin
        exit(SentSystemPrompt);
    end;

    procedure LastUserMessage(): Text
    begin
        exit(SentUserMessage);
    end;

    procedure LastJsonSchema(): Text
    begin
        exit(SentJsonSchema);
    end;

    procedure Complete(SystemPrompt: Text; UserMessage: Text; JsonSchema: Text; var ChatResult: Codeunit "EXR Chat Result")
    var
        Reply: Text;
        ErrorText: Text;
        InputTokens: Integer;
        OutputTokens: Integer;
        DurationMs: Integer;
    begin
        SentSystemPrompt := SystemPrompt;
        SentUserMessage := UserMessage;
        SentJsonSchema := JsonSchema;
        if QueuedReplies.Count() = 0 then
            Error(NothingQueuedErr);
        Reply := QueuedReplies.Get(1);
        ErrorText := QueuedErrors.Get(1);
        InputTokens := QueuedInputTokens.Get(1);
        OutputTokens := QueuedOutputTokens.Get(1);
        DurationMs := QueuedDurations.Get(1);
        QueuedReplies.RemoveAt(1);
        QueuedErrors.RemoveAt(1);
        QueuedInputTokens.RemoveAt(1);
        QueuedOutputTokens.RemoveAt(1);
        QueuedDurations.RemoveAt(1);
        if ErrorText <> '' then
            Error(ScriptedErr, ErrorText);
        ChatResult.SetReply(Reply, 'end_turn', InputTokens, OutputTokens);
        ChatResult.SetCallDuration(DurationMs);
    end;

    local procedure Queue(Reply: Text; ErrorText: Text; InputTokens: Integer; OutputTokens: Integer; DurationMs: Integer)
    begin
        QueuedReplies.Add(Reply);
        QueuedErrors.Add(ErrorText);
        QueuedInputTokens.Add(InputTokens);
        QueuedOutputTokens.Add(OutputTokens);
        QueuedDurations.Add(DurationMs);
    end;
}
