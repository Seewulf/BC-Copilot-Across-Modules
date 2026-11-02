namespace PrabinBhusal.ExplainResolve;

// How sure the model is about its explanation. Blank when no explanation came back.
enum 58206 "EXR Confidence"
{
    Extensible = false;

    value(0; " ")
    {
        Caption = ' ', Locked = true;
    }
    value(1; High)
    {
        Caption = 'High';
    }
    value(2; Medium)
    {
        Caption = 'Medium';
    }
    value(3; Low)
    {
        Caption = 'Low';
    }
}
