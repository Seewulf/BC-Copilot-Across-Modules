namespace PrabinBhusal.ExplainResolve;

// Extensible so another provider, or a test mock, can be plugged in.
enum 58200 "EXR Chat Provider" implements "EXR Chat Client"
{
    Extensible = true;

    value(0; Claude)
    {
        Caption = 'Claude API';
        Implementation = "EXR Chat Client" = "EXR Claude Chat Client";
    }
}
