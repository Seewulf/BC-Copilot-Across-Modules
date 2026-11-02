namespace PrabinBhusal.ExplainResolve;

// The only way the app talks to an AI model. A failed call raises an error.
interface "EXR Chat Client"
{
    // JsonSchema is optional: an empty text means a free-text reply.
    procedure Complete(SystemPrompt: Text; UserMessage: Text; JsonSchema: Text; var ChatResult: Codeunit "EXR Chat Result");
}
