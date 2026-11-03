namespace PrabinBhusal.ExplainResolve;

using Microsoft.CRM.Team;
using Microsoft.Finance.GeneralLedger.Journal;
using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using Microsoft.Purchases.Payables;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Sales.Receivables;
using System.Diagnostics;
using System.Email;

// Use the features: read the setup and the source tables, write runs and findings, and only what Keep it writes.
// The setup page and Test Connection are admin-only.
permissionset 58200 "EXR USER"
{
    Caption = 'Explain and Resolve - User';
    Assignable = true;
    // Keep it saves the vendor email and the customer reminders as drafts
    IncludedPermissionSets = "Email - Edit";

    Permissions =
        tabledata "EXR Setup" = R,
        table "EXR Setup" = X,
        tabledata "EXR Run" = RIM,
        table "EXR Run" = X,
        tabledata "EXR Finding" = RIM,
        table "EXR Finding" = X,
        table "EXR Collection Customer" = X,
        codeunit "EXR Chat Result" = X,
        codeunit "EXR Claude Chat Client" = X,
        codeunit "EXR Chat Runner" = X,
        codeunit "EXR Engine" = X,
        codeunit "EXR Run Context" = X,
        codeunit "EXR Email Draft" = X,
        codeunit "EXR Purch. Variance" = X,
        codeunit "EXR Collections" = X,
        codeunit "EXR Payment Run" = X,
        query "EXR Paid Invoices" = X,
        page "EXR Prompt" = X,
        page "EXR Findings Part" = X,
        page "EXR Runs" = X,
        page "EXR Run" = X,
        page "EXR Run FactBox" = X,
        page "EXR Email Preview" = X,
        page "EXR Finding FactBox" = X,
        // Explain variance reads these; Keep it sets On Hold through EXR Purch. Variance only (indirect modify)
        tabledata "Purchase Header" = Rm,
        tabledata "Purchase Line" = R,
        tabledata "Item Charge Assignment (Purch)" = R,
        tabledata "Purch. Rcpt. Line" = R,
        tabledata "Purch. Inv. Header" = R,
        tabledata "Purch. Inv. Line" = R,
        tabledata Vendor = R,
        // Plan collections only reads: the ledger and its details (remaining amounts), open orders and the dialog's filter lookups
        tabledata Customer = R,
        tabledata "Cust. Ledger Entry" = R,
        tabledata "Detailed Cust. Ledg. Entry" = R,
        tabledata "Sales Line" = R,
        tabledata "Salesperson/Purchaser" = R,
        tabledata "Customer Posting Group" = R,
        tabledata "General Ledger Setup" = R,
        // Check payment run reads the batch's lines, the vendor ledger and only the change time of vendor bank accounts.
        // Keep it deletes a held line through EXR Payment Run only (indirect delete). On Hold and the cleared application are
        // written through Vend. Entry-Edit and Vend. Entry-SetAppl.ID only (indirect modify), and the change log records them
        tabledata "Gen. Journal Line" = Rd,
        tabledata "Vendor Ledger Entry" = Rm,
        tabledata "Detailed Vendor Ledg. Entry" = Rm,
        tabledata "Change Log Entry" = i,
        tabledata "Vendor Bank Account" = R;
}
