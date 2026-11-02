namespace PrabinBhusal.ExplainResolve;

// How much the model thinks before it answers. Closed: the API accepts only these values.
enum 58205 "EXR Effort"
{
    Extensible = false;

    value(0; Low)
    {
        Caption = 'Low';
    }
    value(1; Medium)
    {
        Caption = 'Medium';
    }
    value(2; High)
    {
        Caption = 'High';
    }
}
