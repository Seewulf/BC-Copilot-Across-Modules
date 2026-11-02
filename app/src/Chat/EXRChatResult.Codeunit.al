namespace PrabinBhusal.ExplainResolve;

// What one model call returned: the reply text, token counts, stop reason and duration.
codeunit 58219 "EXR Chat Result"
{
    var
        ReplyValue: Text;
        StopReasonValue: Text;
        InputTokenCount: Integer;
        OutputTokenCount: Integer;
        CallDurationValue: Duration;

    procedure SetReply(NewReply: Text; NewStopReason: Text; NewInputTokens: Integer; NewOutputTokens: Integer)
    begin
        ReplyValue := NewReply;
        StopReasonValue := NewStopReason;
        InputTokenCount := NewInputTokens;
        OutputTokenCount := NewOutputTokens;
    end;

    procedure SetCallDuration(NewCallDuration: Duration)
    begin
        CallDurationValue := NewCallDuration;
    end;

    procedure Reply(): Text
    begin
        exit(ReplyValue);
    end;

    procedure StopReason(): Text
    begin
        exit(StopReasonValue);
    end;

    procedure InputTokens(): Integer
    begin
        exit(InputTokenCount);
    end;

    procedure OutputTokens(): Integer
    begin
        exit(OutputTokenCount);
    end;

    procedure CallDuration(): Duration
    begin
        exit(CallDurationValue);
    end;
}
