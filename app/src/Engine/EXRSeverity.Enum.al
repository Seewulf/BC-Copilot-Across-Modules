namespace PrabinBhusal.ExplainResolve;

// How serious a finding is. Drives the sort order and the styling.
enum 58203 "EXR Severity"
{
    Extensible = false;

    value(0; Info)
    {
        Caption = 'Info';
    }
    value(1; Low)
    {
        Caption = 'Low';
    }
    value(2; Medium)
    {
        Caption = 'Medium';
    }
    value(3; High)
    {
        Caption = 'High';
    }
}
