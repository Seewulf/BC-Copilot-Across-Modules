namespace PrabinBhusal.ExplainResolve.Eval;

using PrabinBhusal.ExplainResolve;

// Sits between the engine and the real provider (or the mock) and keeps what was sent and the raw reply, for the scorer.
// The engine renders tokens and keys away, so the raw reply is the only place to see what the model itself wrote.
codeunit 58304 "EXR Eval Recorder" implements "EXR Chat Client"
{
    // public, like the mock: the main app's chat runner creates it through the provider enum
    SingleInstance = true;

    var
        InnerProvider: Enum "EXR Chat Provider";
        CallCount: Integer;
        SentSystemPrompt: Text;
        SentUserMessage: Text;
        SentJsonSchema: Text;
        ReceivedReply: Text;

    procedure Start(NewInnerProvider: Enum "EXR Chat Provider")
    begin
        InnerProvider := NewInnerProvider;
        CallCount := 0;
        SentSystemPrompt := '';
        SentUserMessage := '';
        SentJsonSchema := '';
        ReceivedReply := '';
    end;

    procedure Complete(SystemPrompt: Text; UserMessage: Text; JsonSchema: Text; var ChatResult: Codeunit "EXR Chat Result")
    var
        ChatClient: Interface "EXR Chat Client";
    begin
        CallCount += 1;
        SentSystemPrompt := SystemPrompt;
        SentUserMessage := UserMessage;
        SentJsonSchema := JsonSchema;
        ReceivedReply := '';
        ChatClient := InnerProvider;
        ChatClient.Complete(SystemPrompt, UserMessage, JsonSchema, ChatResult);
        ReceivedReply := ChatResult.Reply();
    end;

    procedure Calls(): Integer
    begin
        exit(CallCount);
    end;

    procedure LastSystemPrompt(): Text
    begin
        exit(SentSystemPrompt);
    end;

    procedure LastUserMessage(): Text
    begin
        exit(SentUserMessage);
    end;

    // The strict reply schema of the last call: it limits the actions the model can choose.
    procedure LastJsonSchema(): Text
    begin
        exit(SentJsonSchema);
    end;

    // The reply of the last call, empty when it failed. After a retry this is the reply the engine used.
    procedure LastReply(): Text
    begin
        exit(ReceivedReply);
    end;
}
