namespace PrabinBhusal.ExplainResolve;

// One provider call, run through Codeunit.Run: a failure is caught, and Codeunit.Run refuses to start inside a write transaction.
codeunit 58204 "EXR Chat Runner"
{
    Access = Internal;

    trigger OnRun()
    var
        ChatClient: Interface "EXR Chat Client";
    begin
        ChatClient := Provider;
        ChatClient.Complete(SystemPrompt, UserMessage, JsonSchema, ChatResult);
    end;

    var
        ChatResult: Codeunit "EXR Chat Result";
        Provider: Enum "EXR Chat Provider";
        SystemPrompt: Text;
        UserMessage: Text;
        JsonSchema: Text;

    procedure SetRequest(NewProvider: Enum "EXR Chat Provider"; NewSystemPrompt: Text; NewUserMessage: Text; NewJsonSchema: Text)
    begin
        Provider := NewProvider;
        SystemPrompt := NewSystemPrompt;
        UserMessage := NewUserMessage;
        JsonSchema := NewJsonSchema;
    end;

    // Also after a failed call: tokens of a refused or cut-off reply still count.
    procedure GetResult(var Result: Codeunit "EXR Chat Result")
    begin
        Result.SetReply(ChatResult.Reply(), ChatResult.StopReason(), ChatResult.InputTokens(), ChatResult.OutputTokens());
        Result.SetCallDuration(ChatResult.CallDuration());
    end;
}
