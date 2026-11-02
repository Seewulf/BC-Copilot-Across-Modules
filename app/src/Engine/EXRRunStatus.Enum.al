namespace PrabinBhusal.ExplainResolve;

// What happened to a run. Every status except Blocked by Limit counts towards the daily limits.
enum 58204 "EXR Run Status"
{
    Extensible = false;

    value(0; Generated)
    {
        Caption = 'Generated';
    }
    value(1; Kept)
    {
        Caption = 'Kept';
    }
    value(2; Discarded)
    {
        Caption = 'Discarded';
    }
    value(3; Failed)
    {
        Caption = 'Failed';
    }
    value(4; "Blocked by Limit")
    {
        Caption = 'Blocked by Limit';
    }
}
