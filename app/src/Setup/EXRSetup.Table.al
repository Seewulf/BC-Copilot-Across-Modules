namespace PrabinBhusal.ExplainResolve;

// Singleton setup. The API key lives in isolated storage, never in a table field.
table 58200 "EXR Setup"
{
    Caption = 'Explain and Resolve Setup';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
        }
        field(10; Provider; Enum "EXR Chat Provider")
        {
            Caption = 'Provider';
            ToolTip = 'Specifies the AI service that explains the findings.';
        }
        field(11; Model; Text[100])
        {
            Caption = 'Model';
            InitValue = 'claude-haiku-5-5';
            ToolTip = 'Specifies the model ID that the provider runs, for example claude-haiku-5-5.';
        }
        field(12; Endpoint; Text[250])
        {
            Caption = 'Endpoint';
            InitValue = 'https://api.anthropic.com/v1/messages';
            ToolTip = 'Specifies the URL that the requests are sent to. Only https:// addresses are allowed.';

            trigger OnValidate()
            begin
                CheckHttps();
            end;
        }
        field(13; "API Version"; Text[30])
        {
            Caption = 'API Version';
            InitValue = '2026-10-21';
            ToolTip = 'Specifies the API version that is sent with every request, so the request and reply formats do not change unexpectedly.';
        }
        field(14; Effort; Enum "EXR Effort")
        {
            Caption = 'Effort';
            ToolTip = 'Specifies how much the model thinks before it answers. Higher effort can give better explanations but takes longer and uses more tokens.';
        }
        field(20; "Max Output Tokens"; Integer)
        {
            Caption = 'Max Output Tokens';
            // room for thinking at higher effort and for one reminder per customer
            InitValue = 8000;
            MinValue = 256;
            MaxValue = 128000;
            ToolTip = 'Specifies the most tokens the model may write in one reply, thinking included. A reply that reaches this limit is cut off and cannot be used.';
        }
        field(21; "Daily Calls per User"; Integer)
        {
            Caption = 'Daily Calls per User';
            InitValue = 50;
            MinValue = 1;
            ToolTip = 'Specifies the most runs that one user can start per day. Runs are counted from the Explain and Resolve Runs created today; a blocked attempt is logged as Blocked by Limit and does not count.';
        }
        field(22; "Daily Calls per Company"; Integer)
        {
            Caption = 'Daily Calls per Company';
            InitValue = 500;
            MinValue = 1;
            ToolTip = 'Specifies the most runs that all users in this company together can start per day. Runs are counted from the Explain and Resolve Runs created today; a blocked attempt is logged as Blocked by Limit and does not count.';
        }
        field(30; "Variance Tolerance %"; Decimal)
        {
            Caption = 'Variance Tolerance %';
            InitValue = 2;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            MaxValue = 100;
            ToolTip = 'Specifies the default price difference, in percent, that Explain variance accepts without a finding. Users can change it in the dialog.';
        }
        // On Hold is a free Code[3] on the purchase header with no table behind it
        field(31; "Hold Code"; Code[3])
        {
            Caption = 'Hold Code';
            InitValue = 'QRY';
            ToolTip = 'Specifies the On Hold code that Keep it puts on a purchase invoice when a kept finding needs an answer from the vendor. Business Central copies it to the vendor ledger entry, so Suggest Vendor Payments skips the invoice. Leave it blank to never put invoices on hold.';
        }
        field(32; "Default Email Tone"; Enum "EXR Email Tone")
        {
            Caption = 'Default Email Tone';
            InitValue = Neutral;
            ToolTip = 'Specifies the tone of drafted emails. Users can change it in the dialog.';
        }
    }

    keys
    {
        key(PK; "Primary Key") { Clustered = true; }
    }

    var
        // the Claude client reads the key itself under the same name
        ApiKeyStorageTok: Label 'EXR-API-Key', Locked = true;
        KeyEndpointStorageTok: Label 'EXR-API-Endpoint', Locked = true;
        HttpsOnlyErr: Label 'The endpoint must start with https://.';
        SetupMissingErr: Label 'Open the Explain and Resolve Setup page in this company first.';
        EndpointChangedErr: Label 'The endpoint changed after the API key was entered. Enter the API key again.';
        NoKeyPermissionErr: Label 'You need permission to change the Explain and Resolve Setup to change the API key.';

    // Leaves Rec on the setup record, with the defaults filled in when it is new.
    procedure InsertIfMissing()
    begin
        Rec.Reset();
        if not Rec.Get() then begin
            Rec.Init();
            Rec.Insert();
        end;
    end;

    // Read-only, so a model call never writes before its HTTP request.
    internal procedure GetSetup()
    begin
        if not Rec.Get() then
            Error(SetupMissingErr);
    end;

    // One key for all companies (DataScope Module), tied to the endpoint it was entered for. An empty key removes it.
    internal procedure SetApiKey(ApiKey: SecretText)
    begin
        CheckKeyPermission();
        if ApiKey.IsEmpty() then begin
            RemoveApiKey();
            exit;
        end;
        if EncryptionEnabled() then
            IsolatedStorage.SetEncrypted(ApiKeyStorageTok, ApiKey, DataScope::Module)
        else
            IsolatedStorage.Set(ApiKeyStorageTok, ApiKey, DataScope::Module);
        IsolatedStorage.Set(KeyEndpointStorageTok, Rec.Endpoint, DataScope::Module);
    end;

    procedure HasApiKey(): Boolean
    begin
        exit(IsolatedStorage.Contains(ApiKeyStorageTok, DataScope::Module));
    end;

    internal procedure RemoveApiKey()
    begin
        CheckKeyPermission();
        if IsolatedStorage.Contains(ApiKeyStorageTok, DataScope::Module) then
            IsolatedStorage.Delete(ApiKeyStorageTok, DataScope::Module);
        if IsolatedStorage.Contains(KeyEndpointStorageTok, DataScope::Module) then
            IsolatedStorage.Delete(KeyEndpointStorageTok, DataScope::Module);
    end;

    // Runs before the key is sent: https only, and only to the endpoint the key was entered for.
    internal procedure CheckEndpoint()
    var
        KeyEndpoint: Text;
    begin
        CheckHttps();
        if not IsolatedStorage.Get(KeyEndpointStorageTok, DataScope::Module, KeyEndpoint) then
            Error(EndpointChangedErr);
        if KeyEndpoint <> Rec.Endpoint then
            Error(EndpointChangedErr);
    end;

    local procedure CheckHttps()
    begin
        if not LowerCase(Rec.Endpoint).StartsWith('https://') then
            Error(HttpsOnlyErr);
    end;

    // Isolated storage ignores table permissions, so key changes check them here.
    local procedure CheckKeyPermission()
    begin
        if not Rec.WritePermission() then
            Error(NoKeyPermissionErr);
    end;
}
