namespace PrabinBhusal.ExplainResolve;

using System.AI;

page 58200 "EXR Setup"
{
    Caption = 'Explain and Resolve Setup';
    PageType = Card;
    SourceTable = "EXR Setup";
    ApplicationArea = All;
    UsageCategory = Administration;
    InsertAllowed = false;
    DeleteAllowed = false;
    AboutTitle = 'Set up Explain and Resolve';
    AboutText = 'Connect Business Central to your own AI service. Business Central computes every figure from its ledgers, the model only explains them, and nothing is saved until a person keeps it. Turn each feature on or off in Copilot & agent capabilities.';

    layout
    {
        area(Content)
        {
            group(Connection)
            {
                Caption = 'Connection';
                AboutTitle = 'Your own API key';
                AboutText = 'Calls go to your own Claude API account with your own key, so they use your API credits and no Copilot Credits.';

                field(Provider; Rec.Provider) { }
                field(Model; Rec.Model) { }
                field(Endpoint; Rec.Endpoint) { }
                field("API Version"; Rec."API Version") { }
                field(ApiKey; ApiKeyText)
                {
                    Caption = 'API Key';
                    ExtendedDatatype = Masked;
                    Editable = CanEditKey;
                    ToolTip = 'Specifies the API key for the AI service. It is kept in isolated storage and is never shown again. To replace it, enter a new key.';

                    trigger OnValidate()
                    begin
                        // an emptied field keeps the stored key; Remove API Key deletes it
                        if ApiKeyText <> '' then
                            Rec.SetApiKey(ApiKeyText);
                        ShowApiKeyPlaceholder();
                    end;
                }
            }
            group(Reply)
            {
                Caption = 'Reply';

                field(Effort; Rec.Effort) { }
                field("Max Output Tokens"; Rec."Max Output Tokens") { }
            }
            group(Limits)
            {
                Caption = 'Limits';
                AboutTitle = 'Keep costs under control';
                AboutText = 'Daily limits cap how many calls a user and the whole company can make, so a busy day cannot run up an unexpected bill.';

                field("Daily Calls per User"; Rec."Daily Calls per User") { }
                field("Daily Calls per Company"; Rec."Daily Calls per Company") { }
            }
            group(Review)
            {
                Caption = 'Review defaults';
                AboutTitle = 'What Keep it may change';
                AboutText = 'Explain variance flags price differences beyond the tolerance. When a kept finding needs an answer from the vendor, Keep it puts the invoice on hold with the hold code and saves the vendor email as a draft. Nothing is posted or sent.';

                field("Variance Tolerance %"; Rec."Variance Tolerance %") { }
                field("Hold Code"; Rec."Hold Code") { }
                field("Default Email Tone"; Rec."Default Email Tone") { }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(TestConnection)
            {
                Caption = 'Test Connection';
                Image = TestDatabase;
                ToolTip = 'Send a short test request with the stored key to check that the model answers and that the extension may make HTTP requests.';

                trigger OnAction()
                var
                    ConnectionTest: Codeunit "EXR Connection Test";
                begin
                    CurrPage.SaveRecord();
                    // keep the edits and release the setup row before the HTTP call
                    Commit();
                    Message(ConnectionTest.TestConnection());
                end;
            }
            action(RemoveApiKey)
            {
                Caption = 'Remove API Key';
                Image = Delete;
                Enabled = CanEditKey;
                ToolTip = 'Delete the stored API key. No calls can be made until a new key is entered.';

                trigger OnAction()
                begin
                    if not Confirm(RemoveApiKeyQst, false) then
                        exit;
                    Rec.RemoveApiKey();
                    ShowApiKeyPlaceholder();
                end;
            }
        }
        area(Navigation)
        {
            action(CopilotCapabilities)
            {
                Caption = 'Copilot & agent capabilities';
                Image = Setup;
                RunObject = page "Copilot AI Capabilities";
                ToolTip = 'Turn the Explain and Resolve features on or off, together with the other Copilot capabilities.';
            }
            action(Runs)
            {
                Caption = 'Runs';
                Image = Log;
                RunObject = page "EXR Runs";
                ToolTip = 'View every run with its status, tokens and duration, and the reviews that were kept.';
            }
        }
        area(Promoted)
        {
            actionref(TestConnection_Promoted; TestConnection) { }
        }
    }

    trigger OnOpenPage()
    begin
        Rec.InsertIfMissing();
        CanEditKey := Rec.WritePermission();
        ShowApiKeyPlaceholder();
    end;

    // The masked field shows dots when a key is stored; the key itself never comes back to the page.
    local procedure ShowApiKeyPlaceholder()
    begin
        Clear(ApiKeyText);
        if Rec.HasApiKey() then
            ApiKeyText := ApiKeyPlaceholderTok;
    end;

    var
        [NonDebuggable]
        ApiKeyText: Text;
        CanEditKey: Boolean;
        ApiKeyPlaceholderTok: Label '********', Locked = true;
        RemoveApiKeyQst: Label 'Do you want to remove the stored API key? It is removed for all companies.';
}
