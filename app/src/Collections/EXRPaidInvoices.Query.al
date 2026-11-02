namespace PrabinBhusal.ExplainResolve;

using Microsoft.Sales.Receivables;

// Invoices closed by a payment, for a customer's usual delay. One statement per customer instead of a lookup per invoice.
// Read only and it feeds no write, so the default isolation is enough and no lock is taken.
query 58200 "EXR Paid Invoices"
{
    Caption = 'Explain and Resolve Paid Invoices';
    QueryType = Normal;
    Access = Internal;

    elements
    {
        dataitem(Invoice; "Cust. Ledger Entry")
        {
            DataItemTableFilter = "Document Type" = const(Invoice), Open = const(false), Reversed = const(false);

            filter(CustomerNo; "Customer No.") { }
            column(DueDate; "Due Date") { }
            column(ClosedAtDate; "Closed at Date") { }
            // a corrective credit memo or a return closes an invoice too; only a payment counts as paying it
            dataitem(ClosingEntry; "Cust. Ledger Entry")
            {
                DataItemLink = "Entry No." = Invoice."Closed by Entry No.";
                DataItemTableFilter = "Document Type" = const(Payment);
                SqlJoinType = InnerJoin;

                column(ClosingEntryNo; "Entry No.") { }
            }
        }
    }
}
