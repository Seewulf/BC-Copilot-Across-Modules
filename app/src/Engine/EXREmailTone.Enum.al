namespace PrabinBhusal.ExplainResolve;

// Tone of the drafted email. Neutral is first so that it is also the default on existing setups.
enum 58207 "EXR Email Tone"
{
    Extensible = false;

    value(0; Neutral)
    {
        Caption = 'Neutral';
    }
    value(1; Friendly)
    {
        Caption = 'Friendly';
    }
    value(2; Firm)
    {
        Caption = 'Firm';
    }
    value(3; "Final notice")
    {
        Caption = 'Final notice';
    }
}
