namespace PrabinBhusal.ExplainResolve;

// Test Connection: one tiny call with a JSON schema through the configured provider.
codeunit 58220 "EXR Connection Test"
{
    Access = Internal;

    var
        SystemPromptTxt: Label 'You check that a connection works. Set ok to true and write a greeting of a few words in reply.', Locked = true;
        UserMessageTxt: Label 'This is a connection test from Business Central.', Locked = true;
        SchemaTxt: Label '{"type":"object","properties":{"ok":{"type":"boolean"},"reply":{"type":"string"}},"required":["ok","reply"],"additionalProperties":false}', Locked = true;
        ConnectedMsg: Label 'Connected to %1 in %2 s (%3 input and %4 output tokens).', Comment = '%1 = model, %2 = seconds, %3 = input tokens, %4 = output tokens';
        NotJsonReplyErr: Label 'The model answered, but the reply did not follow the JSON schema. Check that the model supports structured outputs.';

    // Returns the success message; a failed call raises the provider's error.
    procedure TestConnection(): Text
    var
        Setup: Record "EXR Setup";
        ChatResult: Codeunit "EXR Chat Result";
        ChatClient: Interface "EXR Chat Client";
        Reply: JsonObject;
        Seconds: Decimal;
    begin
        Setup.GetSetup();
        ChatClient := Setup.Provider;
        ChatClient.Complete(SystemPromptTxt, UserMessageTxt, SchemaTxt, ChatResult);
        if not Reply.ReadFrom(ChatResult.Reply()) then
            Error(NotJsonReplyErr);
        if not Reply.Contains('ok') then
            Error(NotJsonReplyErr);
        Seconds := ChatResult.CallDuration() / 1000;
        exit(StrSubstNo(ConnectedMsg, Setup.Model, Format(Round(Seconds, 0.1), 0, '<Precision,1:1><Standard Format,0>'), ChatResult.InputTokens(), ChatResult.OutputTokens()));
    end;
}
