namespace PrabinBhusal.ExplainResolve;

// In-memory working set of Plan collections: one row per customer with overdue invoices, scored and ranked by AL.
table 58203 "EXR Collection Customer"
{
    Caption = 'Explain and Resolve Collection Customer';
    TableType = Temporary;
    DataClassification = CustomerContent;
    Access = Internal;

    fields
    {
        field(1; "Customer No."; Code[20])
        {
            Caption = 'Customer No.';
        }
        field(2; "Customer Name"; Text[100])
        {
            Caption = 'Customer Name';
        }
        field(3; "Customer System Id"; Guid)
        {
            Caption = 'Customer System Id';
        }
        field(4; "Customer Record ID"; RecordId)
        {
            Caption = 'Customer Record ID';
        }
        field(10; "Overdue 1-30"; Decimal)
        {
            Caption = 'Overdue 1-30 Days (LCY)';
        }
        field(11; "Overdue 31-60"; Decimal)
        {
            Caption = 'Overdue 31-60 Days (LCY)';
        }
        field(12; "Overdue 61-90"; Decimal)
        {
            Caption = 'Overdue 61-90 Days (LCY)';
        }
        field(13; "Overdue Over 90"; Decimal)
        {
            Caption = 'Overdue Over 90 Days (LCY)';
        }
        field(14; "Total Overdue"; Decimal)
        {
            Caption = 'Total Overdue (LCY)';
        }
        field(15; "Overdue Entries"; Integer)
        {
            Caption = 'Overdue Entries';
        }
        field(16; "Oldest Due Date"; Date)
        {
            Caption = 'Oldest Due Date';
        }
        field(20; "Paid Invoices"; Integer)
        {
            Caption = 'Invoices Paid in the Last 12 Months';
        }
        field(21; "Average Days Late"; Integer)
        {
            Caption = 'Average Days Late';
        }
        field(30; "Broken Promise Date"; Date)
        {
            Caption = 'Broken Promise Date';
        }
        field(31; "Broken Promise Amount"; Decimal)
        {
            Caption = 'Broken Promise Amount (LCY)';
        }
        field(32; "Pending Promise Date"; Date)
        {
            Caption = 'Pending Promise Date';
        }
        field(33; "Pending Promise Amount"; Decimal)
        {
            Caption = 'Pending Promise Amount (LCY)';
        }
        field(34; "Disputed Amount"; Decimal)
        {
            Caption = 'Disputed Amount (LCY)';
        }
        field(40; "Credit Limit"; Decimal)
        {
            Caption = 'Credit Limit (LCY)';
        }
        field(41; "Credit Used %"; Decimal)
        {
            Caption = 'Credit Used %';
        }
        field(42; "Open Orders"; Decimal)
        {
            Caption = 'Open Sales Orders (LCY)';
        }
        field(43; "Unapplied Credits"; Decimal)
        {
            Caption = 'Unapplied Payments and Credits (LCY)';
        }
        field(50; Score; Decimal)
        {
            Caption = 'Priority Score';
        }
        // each overdue amount times its age weight; disputed, held and promised entries count half
        field(51; "Weighted Overdue"; Decimal)
        {
            Caption = 'Weighted Overdue (LCY)';
        }
    }

    keys
    {
        key(PK; "Customer No.") { Clustered = true; }
        key(ByScore; Score, "Total Overdue") { }
    }
}
