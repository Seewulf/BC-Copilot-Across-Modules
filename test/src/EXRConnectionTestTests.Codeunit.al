namespace PrabinBhusal.ExplainResolve.Test;

using PrabinBhusal.ExplainResolve;
using System.TestLibraries.Utilities;

// Test Connection through the mock provider, and the Claude client's checks that stop a call before anything is sent.
// RequiredTestIsolation = Codeunit rolls back the setup changes and the test keys in isolated storage.
codeunit 58274 "EXR Connection Test Tests"
{
    Subtype = Test;
    RequiredTestIsolation = Codeunit;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        MockChatClient: Codeunit "EXR Mock Chat Client";
        ConnectionTest: Codeunit "EXR Connection Test";
        ScriptedErrorTxt: Label 'The Claude API rate limit was reached. Wait a minute and try again.', Locked = true;

    [Test]
    procedure SuccessMessageShowsModelDurationAndTokens()
    var
        Schema: JsonObject;
        Token: JsonToken;
        Result: Text;
    begin
        // [GIVEN] the mock provider answers in 1.4 s with 35 input and 12 output tokens
        UseMockProvider();
        MockChatClient.QueueReply('{"ok":true,"reply":"Hello"}', 35, 12, 1400);

        // [WHEN] the connection is tested
        Result := ConnectionTest.TestConnection();

        // [THEN] the message names the stored model, the duration and the tokens
        Assert.AreEqual('Connected to mock-model-1 in ' + Format(1.4, 0, '<Precision,1:1><Standard Format,0>') + ' s (35 input and 12 output tokens).', Result, 'message');
        // [THEN] the provider got a system prompt, a user message and a schema asking for ok and reply
        Assert.AreNotEqual('', MockChatClient.LastSystemPrompt(), 'system prompt');
        Assert.AreNotEqual('', MockChatClient.LastUserMessage(), 'user message');
        Assert.IsTrue(Schema.ReadFrom(MockChatClient.LastJsonSchema()), 'schema is JSON');
        Assert.IsTrue(Schema.SelectToken('properties.ok', Token), 'schema has ok');
        Assert.IsTrue(Schema.SelectToken('properties.reply', Token), 'schema has reply');
    end;

    [Test]
    procedure ProviderErrorIsPassedThrough()
    begin
        // [GIVEN] the mock provider fails
        UseMockProvider();
        MockChatClient.QueueError(ScriptedErrorTxt);

        // [WHEN] the connection is tested
        asserterror ConnectionTest.TestConnection();

        // [THEN] the provider's own error reaches the user
        Assert.ExpectedError(ScriptedErrorTxt);
    end;

    [Test]
    procedure ReplyOutsideSchemaIsRefused()
    begin
        // [GIVEN] the mock provider answers with plain text instead of the requested JSON
        UseMockProvider();
        MockChatClient.QueueReply('Hello there', 30, 5, 900);

        // [WHEN] the connection is tested
        asserterror ConnectionTest.TestConnection();

        // [THEN] the user is told the reply did not follow the schema
        Assert.ExpectedError('did not follow the JSON schema');
    end;

    [Test]
    procedure ReplyWithoutOkIsRefused()
    begin
        // [GIVEN] the mock provider answers with JSON that lacks the ok property
        UseMockProvider();
        MockChatClient.QueueReply('{"reply":"Hello"}', 30, 5, 900);

        // [WHEN] the connection is tested
        asserterror ConnectionTest.TestConnection();

        // [THEN] the user is told the reply did not follow the schema
        Assert.ExpectedError('did not follow the JSON schema');
    end;

    [Test]
    procedure MissingApiKeyStopsTheCall()
    var
        Setup: Record "EXR Setup";
    begin
        // [GIVEN] the Claude provider and no stored key
        UseClaudeProvider(Setup);
        Setup.RemoveApiKey();

        // [WHEN] the connection is tested
        asserterror ConnectionTest.TestConnection();

        // [THEN] the user is asked for the key before any request is built
        Assert.ExpectedError('Enter the API key on the Explain and Resolve Setup page first.');
    end;

    [Test]
    procedure ChangedEndpointStopsTheCall()
    var
        Setup: Record "EXR Setup";
    begin
        // [GIVEN] a key entered for one endpoint, then a different endpoint without entering the key again
        UseClaudeProvider(Setup);
        Setup.SetApiKey('sk-ant-test-' + Format(CreateGuid()));
        Setup.Validate(Endpoint, 'https://example.invalid/v1/messages');
        Setup.Modify();

        // [WHEN] the connection is tested
        asserterror ConnectionTest.TestConnection();

        // [THEN] the call stops before the key is sent to the new endpoint
        Assert.ExpectedError('The endpoint changed after the API key was entered.');
    end;

    [Test]
    procedure PlainHttpEndpointStopsTheCall()
    var
        Setup: Record "EXR Setup";
    begin
        // [GIVEN] an http endpoint written without validation, and a key entered for it
        UseClaudeProvider(Setup);
        Setup.Endpoint := 'http://example.invalid/v1/messages';
        Setup.Modify();
        Setup.SetApiKey('sk-ant-test-' + Format(CreateGuid()));

        // [WHEN] the connection is tested
        asserterror ConnectionTest.TestConnection();

        // [THEN] the call stops before the key is sent in clear text
        Assert.ExpectedError('The endpoint must start with https://.');
    end;

    local procedure UseMockProvider()
    var
        Setup: Record "EXR Setup";
    begin
        MockChatClient.Reset();
        Setup.InsertIfMissing();
        Setup.Provider := Setup.Provider::Mock;
        Setup.Model := 'mock-model-1';
        Setup.Modify();
    end;

    local procedure UseClaudeProvider(var Setup: Record "EXR Setup")
    begin
        Setup.InsertIfMissing();
        Setup.Provider := Setup.Provider::Claude;
        Setup.Modify();
    end;
}
