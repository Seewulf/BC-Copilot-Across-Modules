namespace PrabinBhusal.ExplainResolve.Test;

using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Customer;
using PrabinBhusal.ExplainResolve;

// Live demo only: builds the demo documents for real and opens them. Posting must be allowed on the dates used
// (the work date for the invoice demo, up to 200 days before it for the collections demo, up to 270 days for the payment run).
pageextension 58270 "EXR Setup Demo" extends "EXR Setup"
{
    actions
    {
        addlast(Processing)
        {
            action(EXRCreateDemoScenario)
            {
                ApplicationArea = All;
                Caption = 'Create demo invoice scenario';
                Image = CreateDocument;
                ToolTip = 'Create a vendor, two items, a received purchase order and a purchase invoice with differences, then open the invoice. Three documents are posted to build the price history and a possible duplicate.';

                trigger OnAction()
                var
                    InvoiceHeader: Record "Purchase Header";
                    ScenarioLibrary: Codeunit "EXR Scenario Library";
                begin
                    ScenarioLibrary.CreateDemoScenario(InvoiceHeader);
                    Commit();
                    Page.Run(Page::"Purchase Invoice", InvoiceHeader);
                end;
            }
            action(EXRCreateCollectionsScenario)
            {
                ApplicationArea = All;
                Caption = 'Create demo collections scenario';
                Image = CreateDocument;
                ToolTip = 'Create five customers with invoices posted 20 to 200 days before the work date, a part payment, a broken payment promise, a disputed invoice and a nearly used credit limit, then open the Customer List filtered to them. In Plan collections, choose their salesperson to review only these customers. The invoices and payments are posted as customer journal lines, so their entries have no posted sales invoice to show or navigate to.';

                trigger OnAction()
                var
                    Customer: Record Customer;
                    CollectionsLibrary: Codeunit "EXR Collections Library";
                    CustomerFilter: Text;
                    SalespersonCode: Code[20];
                begin
                    SalespersonCode := CollectionsLibrary.CreateDemoScenario(CustomerFilter);
                    Commit();
                    Message(DemoCreatedMsg, SalespersonCode);
                    Customer.SetFilter("No.", CustomerFilter);
                    Page.Run(Page::"Customer List", Customer);
                end;
            }
            action(EXRCreatePaymentRunScenario)
            {
                ApplicationArea = All;
                Caption = 'Create demo payment run scenario';
                Image = CreateDocument;
                ToolTip = 'Create three vendors: one with two open invoices INV-4471 and INV4471 for the same amount and date and a bank account added today, one with a usual payment pattern, and one that has never been paid. Then create a payment journal batch with one payment line per open invoice and open it. The invoices and the payment history are posted as vendor journal lines, up to 270 days before the work date; the payment lines are not posted.';

                trigger OnAction()
                var
                    GenJournalBatch: Record "Gen. Journal Batch";
                    PaymentRunLibrary: Codeunit "EXR Payment Run Library";
                    GenJnlManagement: Codeunit GenJnlManagement;
                begin
                    PaymentRunLibrary.CreateDemoScenario(GenJournalBatch);
                    Commit();
                    GenJnlManagement.TemplateSelectionFromBatch(GenJournalBatch);
                end;
            }
        }
    }

    var
        DemoCreatedMsg: Label 'The demo customers are created. In Plan collections, set Salesperson to %1 to review only them.', Comment = '%1 = salesperson code';
}
