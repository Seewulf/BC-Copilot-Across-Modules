namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// The request body sent to the Claude Messages API. No HTTP call is made.
codeunit 58272 "EXR Claude Request Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ClaudeChatClient: Codeunit "EXR Claude Chat Client";
        SystemPromptTxt: Label 'You explain invoice variances.', Locked = true;
        UserMessageTxt: Label 'Why is line 10000 different?', Locked = true;
        SchemaTxt: Label '{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"],"additionalProperties":false}', Locked = true;

    [Test]
    procedure BodyHasModelMaxTokensSystemAndUserMessage()
    var
        Setup: Record "EXR Setup";
        Body: JsonObject;
        Messages: JsonToken;
    begin
        // [GIVEN] a setup with a model and an output token limit
        Setup.Init();
        Setup.Model := 'claude-haiku-5-5';
        Setup."Max Output Tokens" := 1234;

        // [WHEN] the request body is built
        Body := BuildBody(Setup, '');

        // [THEN] it carries the model, the limit, the system prompt and one user message
        Assert.AreEqual('claude-haiku-5-5', ValueAt(Body, 'model').AsText(), 'model');
        Assert.AreEqual(1234, ValueAt(Body, 'max_tokens').AsInteger(), 'max_tokens');
        Assert.AreEqual(SystemPromptTxt, ValueAt(Body, 'system').AsText(), 'system');
        Body.Get('messages', Messages);
        Assert.AreEqual(1, Messages.AsArray().Count(), 'one message');
        Assert.AreEqual('user', ValueAt(Body, 'messages[0].role').AsText(), 'role');
        Assert.AreEqual(UserMessageTxt, ValueAt(Body, 'messages[0].content').AsText(), 'content');
    end;

    [Test]
    procedure EffortAndSchemaGoInOutputConfig()
    var
        Setup: Record "EXR Setup";
        Body: JsonObject;
    begin
        // [GIVEN] high effort and a JSON schema
        Setup.Init();
        Setup.Effort := Setup.Effort::High;

        // [WHEN] the request body is built
        Body := BuildBody(Setup, SchemaTxt);

        // [THEN] output_config holds the effort and a json_schema format with the schema
        Assert.AreEqual('high', ValueAt(Body, 'output_config.effort').AsText(), 'effort');
        Assert.AreEqual('json_schema', ValueAt(Body, 'output_config.format.type').AsText(), 'format type');
        Assert.AreEqual('boolean', ValueAt(Body, 'output_config.format.schema.properties.ok.type').AsText(), 'schema property');
        Assert.AreEqual('ok', ValueAt(Body, 'output_config.format.schema.required[0]').AsText(), 'schema required');
    end;

    [Test]
    procedure FormatIsOmittedWithoutSchema()
    var
        Setup: Record "EXR Setup";
        Body: JsonObject;
        OutputConfig: JsonToken;
    begin
        // [GIVEN] medium effort and no schema
        Setup.Init();
        Setup.Effort := Setup.Effort::Medium;

        // [WHEN] the request body is built
        Body := BuildBody(Setup, '');

        // [THEN] output_config holds only the effort
        Assert.AreEqual('medium', ValueAt(Body, 'output_config.effort').AsText(), 'effort');
        Body.Get('output_config', OutputConfig);
        Assert.IsFalse(OutputConfig.AsObject().Contains('format'), 'format omitted');
    end;

    [Test]
    procedure NoSamplingParametersAreSent()
    var
        Setup: Record "EXR Setup";
        Body: JsonObject;
    begin
        // [GIVEN] the default setup (low effort)
        Setup.Init();

        // [WHEN] the request body is built
        Body := BuildBody(Setup, SchemaTxt);

        // [THEN] it has exactly the five expected keys and no temperature, top_p or top_k
        Assert.IsFalse(Body.Contains('temperature'), 'temperature');
        Assert.IsFalse(Body.Contains('top_p'), 'top_p');
        Assert.IsFalse(Body.Contains('top_k'), 'top_k');
        Assert.AreEqual(5, Body.Keys().Count(), 'only model, max_tokens, system, messages and output_config');
        Assert.AreEqual('low', ValueAt(Body, 'output_config.effort').AsText(), 'default effort');
    end;

    [Test]
    procedure InvalidSchemaIsRefused()
    var
        Setup: Record "EXR Setup";
    begin
        // [GIVEN] a schema that is not JSON
        Setup.Init();

        // [WHEN] the request body is built
        asserterror ClaudeChatClient.BuildRequestBody(Setup, SystemPromptTxt, UserMessageTxt, '{"type": object');

        // [THEN] it fails with a clear message instead of sending a broken request
        Assert.ExpectedError('not valid JSON');
    end;

    local procedure BuildBody(Setup: Record "EXR Setup"; JsonSchema: Text) Body: JsonObject
    begin
        Assert.IsTrue(Body.ReadFrom(ClaudeChatClient.BuildRequestBody(Setup, SystemPromptTxt, UserMessageTxt, JsonSchema)), 'body is JSON');
    end;

    local procedure ValueAt(Body: JsonObject; Path: Text): JsonValue
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Body.SelectToken(Path, Token), Path);
        exit(Token.AsValue());
    end;
}
