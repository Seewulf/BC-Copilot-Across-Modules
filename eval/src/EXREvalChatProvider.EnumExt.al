namespace PrabinBhusal.ExplainResolve.Eval;

using PrabinBhusal.ExplainResolve;

// The evaluation sets this provider inside its own rolled-back transaction, so the scorer sees the raw reply.
enumextension 58300 "EXR Eval Chat Provider" extends "EXR Chat Provider"
{
    value(58300; "Eval Recorder")
    {
        Caption = 'Evaluation recorder (evaluation only)';
        Implementation = "EXR Chat Client" = "EXR Eval Recorder";
    }
}
