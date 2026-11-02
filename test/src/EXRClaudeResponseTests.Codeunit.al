namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// Reads replies and error bodies in the shape the Claude Messages API returns them. No HTTP call is made.
codeunit 58273 "EXR Claude Response Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ClaudeChatClient: Codeunit "EXR Claude Chat Client";
        ReplyWithThinkingTxt: Label '{"id":"msg_01XFDUDYJgAACzvnptvVoYEL","type":"message","role":"assistant","model":"claude-haiku-5-5","content":[{"type":"thinking","thinking":"I should greet the user.","signature":"EqQBCkYIBxgCKkBTDh1Lz"},{"type":"redacted_thinking","data":"EmwKAhgBEgy3va3pzix","text":"MUST NOT APPEAR"},{"type":"text","text":"{\"ok\":true,"},{"type":"text","text":"\"reply\":\"Hello\"}"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":35,"output_tokens":12}}', Locked = true;
        RefusalTxt: Label '{"id":"msg_02","type":"message","role":"assistant","model":"claude-haiku-5-5","content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":null,"explanation":null},"usage":{"input_tokens":40,"output_tokens":0}}', Locked = true;
        CutOffTxt: Label '{"id":"msg_03","type":"message","role":"assistant","model":"claude-haiku-5-5","content":[{"type":"text","text":"{\"ok\":tr"}],"stop_reason":"max_tokens","usage":{"input_tokens":35,"output_tokens":256}}', Locked = true;
        AuthErrorTxt: Label '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"},"request_id":"req_011CSHoEeqs5C35K2UUqR7Fy"}', Locked = true;
        RateLimitErrorTxt: Label '{"type":"error","error":{"type":"rate_limit_error","message":"Number of request tokens has exceeded your per-minute rate limit"}}', Locked = true;
        OverloadedErrorTxt: Label '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}', Locked = true;
        CreditErrorTxt: Label '{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."}}', Locked = true;
        BillingErrorTxt: Label '{"type":"error","error":{"type":"billing_error","message":"This organisation has a billing issue."}}', Locked = true;
        BadRequestErrorTxt: Label '{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: Field required"}}', Locked = true;

    [Test]
    procedure TextBlocksAfterThinkingAreJoined()
    var
        ChatResult: Codeunit "EXR Chat Result";
    begin
        // [GIVEN] a reply with a thinking block, a redacted thinking block that carries a text property, and two text blocks
        // [WHEN] it is parsed
        ClaudeChatClient.ParseResponse(ReplyWithThinkingTxt, ChatResult);

        // [THEN] only the text blocks are joined, and stop reason and tokens are read
        Assert.AreEqual('{"ok":true,"reply":"Hello"}', ChatResult.Reply(), 'reply');
        Assert.AreEqual('end_turn', ChatResult.StopReason(), 'stop reason');
        Assert.AreEqual(35, ChatResult.InputTokens(), 'input tokens');
        Assert.AreEqual(12, ChatResult.OutputTokens(), 'output tokens');
    end;

    [Test]
    procedure RefusalRaisesError()
    var
        ChatResult: Codeunit "EXR Chat Result";
    begin
        // [GIVEN] a reply where the model declined
        // [WHEN] it is parsed
        asserterror ClaudeChatClient.ParseResponse(RefusalTxt, ChatResult);

        // [THEN] the user is told the model declined
        Assert.ExpectedError('The model declined');
    end;

    [Test]
    procedure CutOffReplyRaisesError()
    var
        ChatResult: Codeunit "EXR Chat Result";
    begin
        // [GIVEN] a reply that stopped at the output token limit
        // [WHEN] it is parsed
        asserterror ClaudeChatClient.ParseResponse(CutOffTxt, ChatResult);

        // [THEN] the user is told to raise Max Output Tokens
        Assert.ExpectedError('Max Output Tokens');
    end;

    [Test]
    procedure InvalidApiKeyIsExplained()
    begin
        // [GIVEN] a 401 authentication error
        // [WHEN] it is raised
        asserterror ClaudeChatClient.RaiseApiError(401, AuthErrorTxt);

        // [THEN] the user is told the key was not accepted
        Assert.ExpectedError('did not accept the API key');
    end;

    [Test]
    procedure RateLimitIsExplained()
    begin
        // [GIVEN] a 429 rate limit error
        // [WHEN] it is raised
        asserterror ClaudeChatClient.RaiseApiError(429, RateLimitErrorTxt);

        // [THEN] the user is told to wait
        Assert.ExpectedError('rate limit was reached');
    end;

    [Test]
    procedure OverloadedIsExplained()
    begin
        // [GIVEN] a 529 overloaded error
        // [WHEN] it is raised
        asserterror ClaudeChatClient.RaiseApiError(529, OverloadedErrorTxt);

        // [THEN] the user is told the service is busy
        Assert.ExpectedError('is overloaded at the moment');
    end;

    [Test]
    procedure UsedUpCreditsAreExplained()
    begin
        // [GIVEN] the three ways the API reports an empty balance: a 400 credit message, a 402 status and a billing_error type
        // [WHEN] each is raised
        // [THEN] the user is told the credits are used up
        asserterror ClaudeChatClient.RaiseApiError(400, CreditErrorTxt);
        Assert.ExpectedError('credits are used up');
        asserterror ClaudeChatClient.RaiseApiError(402, '');
        Assert.ExpectedError('credits are used up');
        asserterror ClaudeChatClient.RaiseApiError(400, BillingErrorTxt);
        Assert.ExpectedError('credits are used up');
    end;

    [Test]
    procedure OtherErrorsShowStatusAndMessage()
    begin
        // [GIVEN] any other API error
        // [WHEN] it is raised
        asserterror ClaudeChatClient.RaiseApiError(400, BadRequestErrorTxt);

        // [THEN] the status and the API's own message are shown
        Assert.ExpectedError('The Claude API returned status 400: max_tokens: Field required');
    end;

    [Test]
    procedure UnreadableBodiesAreHandled()
    var
        ChatResult: Codeunit "EXR Chat Result";
    begin
        // [GIVEN] bodies that are not JSON, for example from a proxy, and a JSON reply without content
        // [WHEN] they are read as a reply and as an error
        // [THEN] readable messages come back instead of runtime errors
        asserterror ClaudeChatClient.ParseResponse('<html>Bad Gateway</html>', ChatResult);
        Assert.ExpectedError('could not be read');
        asserterror ClaudeChatClient.ParseResponse('{"stop_reason":"end_turn"}', ChatResult);
        Assert.ExpectedError('could not be read');
        asserterror ClaudeChatClient.RaiseApiError(502, '<html>Bad Gateway</html>');
        Assert.ExpectedError('The Claude API returned status 502');
    end;

    [Test]
    procedure MissingUsageReadsAsZeroTokens()
    var
        ChatResult: Codeunit "EXR Chat Result";
    begin
        // [GIVEN] a reply without usage, as a proxy endpoint may return it
        // [WHEN] it is parsed
        ClaudeChatClient.ParseResponse('{"content":[{"type":"text","text":"Hi"}],"stop_reason":"end_turn"}', ChatResult);

        // [THEN] the text is read and both token counts are zero
        Assert.AreEqual('Hi', ChatResult.Reply(), 'reply');
        Assert.AreEqual(0, ChatResult.InputTokens(), 'input tokens');
        Assert.AreEqual(0, ChatResult.OutputTokens(), 'output tokens');
    end;
}
