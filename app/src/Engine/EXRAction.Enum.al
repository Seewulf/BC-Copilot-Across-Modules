namespace PrabinBhusal.ExplainResolve;

// Closed allow-list of every action the model may choose. Each capability accepts only its own values.
enum 58202 "EXR Action"
{
    Extensible = false;

    value(0; "Accept within tolerance")
    {
        Caption = 'Accept within tolerance';
    }
    value(1; "Hold until received")
    {
        Caption = 'Hold until received';
    }
    value(2; "Request credit memo")
    {
        Caption = 'Request credit memo';
    }
    value(3; "Ask vendor to confirm price")
    {
        Caption = 'Ask vendor to confirm price';
    }
    value(4; "Assign as item charge")
    {
        Caption = 'Assign as item charge';
    }
    value(5; "Query possible duplicate")
    {
        Caption = 'Query possible duplicate';
    }
    value(6; "Email reminder")
    {
        Caption = 'Email reminder';
    }
    value(7; "Phone call")
    {
        Caption = 'Phone call';
    }
    value(8; "Wait - promise pending")
    {
        Caption = 'Wait - promise pending';
    }
    value(9; "Resolve dispute first")
    {
        Caption = 'Resolve dispute first';
    }
    value(10; "Credit review - hold new orders")
    {
        Caption = 'Credit review - hold new orders';
    }
    // Check payment run
    value(11; Pay)
    {
        Caption = 'Pay';
    }
    value(12; Hold)
    {
        Caption = 'Hold';
    }
    value(13; "Verify bank details by phone")
    {
        Caption = 'Verify bank details by phone';
    }
    value(14; "Ask vendor to confirm duplicate")
    {
        Caption = 'Ask vendor to confirm duplicate';
    }
}
