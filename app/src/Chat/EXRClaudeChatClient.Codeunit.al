namespace PrabinBhusal.ExplainResolve;

// Claude Messages API: one non-streaming POST, JSON in and out.
codeunit 58218 "EXR Claude Chat Client" implements "EXR Chat Client"
{
    Access = Internal;

    var
        // same name as in table EXR Setup
        ApiKeyStorageTok: Label 'EXR-API-Key', Locked = true;
        NoApiKeyErr: Label 'Enter the API key on the Explain and Resolve Setup page first.';
        InvalidSchemaErr: Label 'The JSON schema for the reply is not valid JSON.';
        SendFailedErr: Label 'The request to the Claude API could not be sent: %1 In a sandbox, turn on Allow HttpClient Requests for this extension in Extension Management > Configure.', Comment = '%1 = error from the HTTP client';
        BlockedErr: Label 'Business Central blocked the request to the Claude API. Turn on Allow HttpClient Requests for this extension in Extension Management > Configure.';
        InvalidApiKeyErr: Label 'The Claude API did not accept the API key. Enter a valid key on the Explain and Resolve Setup page.';
        RateLimitErr: Label 'The Claude API rate limit was reached. Wait a minute and try again.';
        OverloadedErr: Label 'The Claude API is overloaded at the moment. Try again in a few minutes.';
        NoCreditsErr: Label 'Your Claude API credits are used up. Add credits in the Claude Console and try again.';
        ApiErr: Label 'The Claude API returned status %1: %2', Comment = '%1 = HTTP status code, %2 = error message from the API';
        UnexpectedResponseErr: Label 'The Claude API returned a response that could not be read.';
        RefusalErr: Label 'The model declined to answer this request.';
        MaxTokensErr: Label 'The reply was cut off because it reached the Max Output Tokens limit. Raise Max Output Tokens on the Explain and Resolve Setup page and try again.';

    procedure Complete(SystemPrompt: Text; UserMessage: Text; JsonSchema: Text; var ChatResult: Codeunit "EXR Chat Result")
    var
        Setup: Record "EXR Setup";
        ResponseText: Text;
        StatusCode: Integer;
        StartedAt: DateTime;
    begin
        Setup.GetSetup();
        if not Setup.HasApiKey() then
            Error(NoApiKeyErr);
        StartedAt := CurrentDateTime();
        if not SendRequest(Setup, BuildRequestBody(Setup, SystemPrompt, UserMessage, JsonSchema), StatusCode, ResponseText) then
            RaiseApiError(StatusCode, ResponseText);
        ChatResult.SetCallDuration(CurrentDateTime() - StartedAt);
        ParseResponse(ResponseText, ChatResult);
    end;

    // No temperature, top_p or top_k: API version 2026-10-21 rejects them.
    internal procedure BuildRequestBody(Setup: Record "EXR Setup"; SystemPrompt: Text; UserMessage: Text; JsonSchema: Text) Body: Text
    var
        Request: JsonObject;
        UserTurn: JsonObject;
        Messages: JsonArray;
        OutputConfig: JsonObject;
        OutputFormat: JsonObject;
        Schema: JsonObject;
    begin
        Request.Add('model', Setup.Model);
        Request.Add('max_tokens', Setup."Max Output Tokens");
        Request.Add('system', SystemPrompt);
        UserTurn.Add('role', 'user');
        UserTurn.Add('content', UserMessage);
        Messages.Add(UserTurn);
        Request.Add('messages', Messages);
        OutputConfig.Add('effort', EffortValue(Setup.Effort));
        if JsonSchema <> '' then begin
            if not Schema.ReadFrom(JsonSchema) then
                Error(InvalidSchemaErr);
            OutputFormat.Add('type', 'json_schema');
            OutputFormat.Add('schema', Schema);
            OutputConfig.Add('format', OutputFormat);
        end;
        Request.Add('output_config', OutputConfig);
        Request.WriteTo(Body);
    end;

    // Joins the text blocks and skips thinking blocks. A refusal or a cut-off reply raises an error.
    internal procedure ParseResponse(ResponseText: Text; var ChatResult: Codeunit "EXR Chat Result")
    var
        Response: JsonObject;
        Usage: JsonObject;
        Token: JsonToken;
        Block: JsonToken;
        Reply: TextBuilder;
        StopReason: Text;
    begin
        if not Response.ReadFrom(ResponseText) then
            Error(UnexpectedResponseErr);
        if not Response.Get('content', Token) then
            Error(UnexpectedResponseErr);
        if not Token.IsArray() then
            Error(UnexpectedResponseErr);
        foreach Block in Token.AsArray() do
            if Block.IsObject() then
                if ReadText(Block.AsObject(), 'type') = 'text' then
                    Reply.Append(ReadText(Block.AsObject(), 'text'));
        if Response.Get('usage', Token) then
            if Token.IsObject() then
                Usage := Token.AsObject();
        StopReason := ReadText(Response, 'stop_reason');
        ChatResult.SetReply(Reply.ToText(), StopReason, ReadInteger(Usage, 'input_tokens'), ReadInteger(Usage, 'output_tokens'));
        case StopReason of
            'refusal':
                Error(RefusalErr);
            'max_tokens':
                Error(MaxTokensErr);
        end;
    end;

    // Error body: {"type":"error","error":{"type":"...","message":"..."}}. The key never appears in the message.
    internal procedure RaiseApiError(StatusCode: Integer; ResponseText: Text)
    var
        Response: JsonObject;
        Token: JsonToken;
        ApiErrorType: Text;
        ApiMessage: Text;
    begin
        if Response.ReadFrom(ResponseText) then
            if Response.Get('error', Token) then
                if Token.IsObject() then begin
                    ApiErrorType := ReadText(Token.AsObject(), 'type');
                    ApiMessage := ReadText(Token.AsObject(), 'message');
                end;
        // an empty balance comes back as 400 invalid_request_error or as 402 billing_error
        if (StatusCode = 402) or (ApiErrorType = 'billing_error') or LowerCase(ApiMessage).Contains('credit balance') then
            Error(NoCreditsErr);
        case StatusCode of
            401:
                Error(InvalidApiKeyErr);
            429:
                Error(RateLimitErr);
            529:
                Error(OverloadedErr);
        end;
        if ApiMessage = '' then
            ApiMessage := UnexpectedResponseErr;
        Error(ApiErr, StatusCode, ApiMessage);
    end;

    // Returns false on an HTTP error status; StatusCode and ResponseText then hold the API's answer.
    [NonDebuggable]
    local procedure SendRequest(Setup: Record "EXR Setup"; Body: Text; var StatusCode: Integer; var ResponseText: Text): Boolean
    var
        Client: HttpClient;
        Request: HttpRequestMessage;
        Response: HttpResponseMessage;
        Content: HttpContent;
        RequestHeaders: HttpHeaders;
        ContentHeaders: HttpHeaders;
    begin
        // the key goes only over https, to the endpoint it was entered for
        Setup.CheckEndpoint();
        Request.Method('POST');
        Request.SetRequestUri(Setup.Endpoint);
        Request.GetHeaders(RequestHeaders);
        RequestHeaders.Add('x-api-key', StoredApiKey());
        RequestHeaders.Add('anthropic-version', Setup."API Version");
        Content.WriteFrom(Body);
        Content.GetHeaders(ContentHeaders);
        if ContentHeaders.Contains('Content-Type') then
            ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');
        Request.Content(Content);
        // reasoning models can take a while; the platform default is 100 s
        Client.Timeout(120000);

        if not Client.Send(Request, Response) then
            Error(SendFailedErr, GetLastErrorText());
        if Response.IsBlockedByEnvironment() then
            Error(BlockedErr);
        StatusCode := Response.HttpStatusCode();
        Response.Content().ReadAs(ResponseText);
        exit(Response.IsSuccessStatusCode());
    end;

    // Local on purpose: no other object, and no app named in internalsVisibleTo, can read the key.
    [NonDebuggable]
    local procedure StoredApiKey() ApiKey: SecretText
    begin
        if IsolatedStorage.Get(ApiKeyStorageTok, DataScope::Module, ApiKey) then;
    end;

    local procedure EffortValue(Effort: Enum "EXR Effort"): Text
    begin
        case Effort of
            Effort::Low:
                exit('low');
            Effort::Medium:
                exit('medium');
            Effort::High:
                exit('high');
        end;
    end;

    // null and missing values read as empty
    local procedure ReadText(JObject: JsonObject; KeyName: Text): Text
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

    local procedure ReadInteger(JObject: JsonObject; KeyName: Text): Integer
    var
        Token: JsonToken;
    begin
        if not JObject.Get(KeyName, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        if Token.AsValue().IsNull() then
            exit(0);
        exit(Token.AsValue().AsInteger());
    end;
}
