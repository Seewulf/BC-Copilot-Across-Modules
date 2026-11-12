# Explain and Resolve for Business Central

Copilot features in Business Central for the finance team of a business that buys and sells stock: the accounts payable clerk who checks purchase invoices, the credit controller who chases overdue customers and the controller who approves the payment run. Business Central computes every figure from its own documents and ledgers, and decides what needs attention. The AI model explains the findings, suggests one action for each from a fixed list and drafts the emails. A person reviews the result and chooses **Keep it** or **Discard**. Until then Business Central saves only a run record: the usage figures, the summary, your note and, for Explain invoice variance, the vendor email text. Findings and customer reminders are saved only when you choose Keep it. Nothing is ever posted, and no email is ever sent: emails are saved as drafts for a person to send.

**Status:** the two v1.0 capabilities are built and covered by automated tests that passed in a sandbox. Version 1.1 adds **Check payment run**, also covered by automated tests that passed in a sandbox. The app is still in development and is not yet on AppSource. All three capabilities are registered as Preview in Copilot & agent capabilities.

## Requirements

**The Copilot features need your own AI provider account and API key. No AI service comes with the app.** Every call goes directly from Business Central to your provider account, not through Microsoft's Copilot service, so your agreement with the provider covers the data that is sent (listed under **What is sent to the AI provider** below). Your provider bills you for the usage. The calls do not use Business Central Copilot Credits.

| AI provider | Status |
|---|---|
| Claude API (Anthropic) | Supported. Create an API key in the Claude Console and enter it on the **Explain and Resolve Setup** page. |
| Azure OpenAI | Planned. It is not built yet, so it cannot be used today. |

- Business Central online, version 29 or later. The app is a per-tenant extension and needs no other apps.
- In a sandbox, turn on **Allow HttpClient Requests** for the extension (Extension Management, choose the extension, **Configure**). Without it Business Central blocks the call to the AI provider.
- Optional: an email account in Business Central. With one, the emails that Keep it saves go to your email outbox as drafts. Without one, the email text is kept with the review in Business Central; for Explain invoice variance you can read it on the run card.

## What it does

All three capabilities work the same way:

1. You choose the Copilot action, set the options and choose **Generate**.
2. Business Central reads the data, runs fixed checks and computes every figure.
3. The model receives those figures and writes a summary, an explanation per finding, one action per finding from a fixed list, a confidence and, for the two capabilities that draft emails, the email text.
4. You review the result in the dialog. You can untick findings in the **Accept** column and change the email subject and text. The action of a finding cannot be changed in the dialog: untick the finding, or add a note and choose **Regenerate**. Regenerate starts a new run: Business Central computes the findings again and calls the provider again, which is billed and counts toward the daily limits. Your ticks and email changes are reset, and a previous generated run is marked Discarded.
5. **Keep it** saves the accepted findings and makes the few changes listed below. **Discard** saves no findings and no drafts. The run record stays on the Runs page.

Every dialog shows a **When you keep it** note that says what Keep it will save and change, because the web client does not show a message while the dialog closes.

If Business Central finds nothing that needs attention, the AI provider is not called. The run is still saved and counts toward the daily limits.

### Explain invoice variance

Where: the **Explain variance** Copilot action on the **Purchase Invoice** page. It works on open invoices only.

Business Central checks the item, G/L account and item charge lines of the invoice that have a quantity. Item lines are compared with their receipts, the purchase order and the vendor's posted invoices. Prices and discounts are compared with the order only when the order is in the invoice's currency. Business Central also looks for a posted invoice that may be a duplicate. Amounts are shown in local currency (LCY), also in the list that Business Central puts in the vendor email. Price differences within the **Tolerance %** (2% by default, changeable in the dialog) are not reported. Line discounts have no tolerance: any difference from the order is reported.

| Check | What Business Central compares | Default action | Actions the model may choose |
|---|---|---|---|
| Not received | Invoiced quantity against the quantity received and not yet invoiced. A line keyed by hand is matched to the vendor's open order lines for the same item and variant. | Hold until received | Hold until received, Request credit memo |
| Price against the order | Unit cost per base unit against the order (or the receipt). | Ask vendor to confirm price (Accept within tolerance when the invoice is cheaper) | Accept within tolerance, Ask vendor to confirm price, Request credit memo |
| Price against history | Unit cost against the average of up to three of the vendor's posted invoice lines for the item and variant, taking those with the highest posted invoice numbers (normally the latest). | Same as above | Same as above |
| Discount against the order | Line discount % against the order. | Ask vendor to confirm price (Accept within tolerance when the invoice gives more discount) | Same as above |
| G/L line without an order | A G/L account line, such as freight, with no order or receipt behind it. | Assign as item charge | Assign as item charge, Accept within tolerance, Ask vendor to confirm price |
| Item charge not assigned | A Charge (Item) line whose quantity is not fully assigned (Qty. to Assign plus Qty. Assigned is less than the quantity). | Assign as item charge | Same as above |
| Possible duplicate | A posted invoice from the same vendor with the same vendor invoice number once spaces and symbols are removed (INV-4472 and INV4472 match), the same currency and the same amount. | Query possible duplicate | Query possible duplicate only |

What the model adds: a short summary that says what matters most and whether the invoice should wait, an explanation of the likely cause of each finding, the action and confidence, and one email to the vendor in the chosen tone (Neutral, Friendly or Firm; the model is told to write Final notice as Firm).

What **Keep it** does:

- Saves the review with the accepted findings.
- When an accepted finding needs an answer from the vendor (Hold until received, Request credit memo, Ask vendor to confirm price or Query possible duplicate), it puts the invoice on hold with the **Hold Code** from the setup (QRY by default). An invoice that is already on hold keeps its code, and a blank Hold Code means invoices are never put on hold. When the invoice is posted, Business Central copies On Hold to the vendor ledger entry, so Suggest Vendor Payments skips it.
- In that case it also saves the vendor email as a draft, if it has a subject, addressed to the email address on the vendor card (or keeps it with the review when no email account is set up). Business Central replaces the placeholder line in the email with the accepted findings that need the vendor's answer, and keeps the vendor invoice number in the subject. When no accepted finding needs the vendor's answer, no draft is saved.
- Never changes the invoice lines, prices or the purchase order, and never posts.

Afterwards: reopen the invoice to see the latest kept review in the **Variance review** FactBox. Choose the date to open the full review. The FactBox is on the open invoice only: after the invoice is posted, find the review on the **Explain and Resolve Runs** page.

### Plan collections

Where: the **Plan collections** Copilot action on the **Customer List** page. In the dialog you can filter on **Salesperson** and **Customer posting group**, and set **Max. customers** (10 by default, at most 25). With the default Max Output Tokens of 16,000 the output-size check allows all 25; with a lower limit a larger plan can stop before the call (see **Output size** below).

Business Central ages the open entries as of the work date and works in local currency. Remaining amounts, balances and credit limit use are today's values. For every customer with open invoices or other debts past their due date, it computes:

- the overdue amount in four age buckets (1-30, 31-60, 61-90 and over 90 days) and the oldest due date;
- the customer's usual delay: the average days late on invoices paid by a payment in the last 12 months (only customers with such invoices have one);
- promised payment dates that have passed, and those still to come;
- amounts that are disputed or on hold;
- credit limit use, counting the balance, open sales orders, shipments not yet invoiced and invoices not yet posted;
- payments and credit memos not yet applied. A customer whose unapplied payments and credits cover everything overdue is left out.

It then gives each customer a priority score. Older debt weighs more: x1 for 1-30 days up to x4 for over 90 days. A disputed or held entry, or one promised for a date still to come, weighs half. The score goes up by 50% for a broken promise, by 25% when 90% or more of the credit limit is used, and by 25% when the oldest debt is more than 30 days later than the customer's usual delay (only for customers with a usual delay). The increases are added, so all three together double the score. Unapplied payments and credits lower it. Business Central ranks the customers by this score; the model explains the ranking and cannot change it.

Each customer gets one situation, checked in the order of this table:

| Situation | When | Default action | Actions the model may choose |
|---|---|---|---|
| Dispute | Everything overdue is disputed, on hold, promised or covered, and part of it is disputed or on hold. | Resolve dispute first | Resolve dispute first, Phone call |
| Promise pending | Everything overdue is promised for a later date or covered by unapplied payments. | Wait - promise pending | Wait - promise pending, Phone call |
| Promise broken | A promised payment date has passed and the debt is still open. | Phone call | Phone call, Email reminder, Credit review - hold new orders |
| Credit risk | 90% or more of the credit limit is used. | Credit review - hold new orders | Email reminder, Phone call, Credit review - hold new orders |
| Overdue | Any other overdue customer. | Email reminder | Same as credit risk |

What the model adds: a summary of who to contact first and why, an explanation of why each customer ranks where it does (compared with its usual delay, when it has one), the action and confidence, and a reminder email for each customer whose action is Email reminder. In the dialog, choose a customer's **Email** column to read or change its reminder.

What **Keep it** does:

- Saves the ticked customers as a worklist with their explanations and actions.
- Saves each reminder as a draft, addressed to the email address on the customer card. Business Central fills in the list of overdue documents the reminder chases (not those that are disputed, on hold or promised for a later date), the payments and credit memos not yet applied, and a total per currency, each amount in the currency it was posted in.
- Never changes ledger entries, promised dates, disputes, holds or credit limits, and does not create Business Central reminder documents.

Afterwards: each customer card shows its latest kept review in the **Collections review** FactBox, with the rank, explanation, action, amount and email subject.

### Check payment run

Where: the **Check payment run** Copilot action on the **Payment Journal** page, for example after **Suggest Vendor Payments**. It checks the journal batch the page shows. In the dialog you can set **Duplicate window (days)** (60 by default) and **Bank-change window (days)** (30 by default); 0 turns that check off. Both defaults come from the setup.

Business Central checks every line of the batch whose account type is Vendor and whose amount is positive, together with the open vendor ledger entries the line pays: the entry in **Applies-to Doc. No.**, or every entry marked with the line's **Applies-to ID** (as Suggest Vendor Payments marks them when it summarizes per vendor). Amounts are in local currency (LCY). A line with one or more signals becomes one finding that lists all its signals. Lines with no signal are not findings: they stay in the journal to be paid, and the summary counts them. A vendor payment keyed the other way round, with a bank or G/L account on the line and the vendor as the balancing account, is not checked; the summary says how many such lines the batch has.

| Signal | What Business Central checks | Severity | Default action | Actions the model may choose |
|---|---|---|---|---|
| Already paid (PAID) | The line is applied to an invoice, but nothing it is applied to is still open, or the line pays more than is still open on it (compared in the line's currency). The invoice was paid or settled after the line was made. | High | Hold | Hold only |
| Possible duplicate, the copy (DUP_COPY) | Another posted invoice of the same vendor, in the same currency and for the same amount, posted at most the duplicate window before or after, whose vendor invoice number is the same once spaces and symbols are removed (INV-4471 and INV4471), and this invoice is the copy: it was entered after the other one, the other one is already closed, or the line pays both. Reversed invoices and invoices cancelled with a credit memo are left out. | High | Hold | Hold only |
| Possible duplicate, entered first (DUPLICATE) | The same, but this invoice was entered first and the other one is still open, so the vendor is asked and the invoice can still be paid once. | High | Ask vendor to confirm duplicate | Hold, Ask vendor to confirm duplicate |
| Matching digits (NEAR_DUP) | The same, but only the digits of the two vendor invoice numbers match, and there are at least 3 of them (INV4471 and 4471/A). Monthly invoices whose numbers share only a year also match, so the model may judge them to be two invoices. | Medium | Ask vendor to confirm duplicate | Pay, Hold, Ask vendor to confirm duplicate |
| Bank account changed (BANK) | A bank account of the vendor added or changed within the bank-change window, counted back from today (1 means today only). Business Central reads the time the bank account record was last changed, so any change to that record counts, not only a new account number. | High | Verify bank details by phone | Hold, Verify bank details by phone |
| Already on hold (ON_HOLD) | An invoice the line pays already has an On Hold code. | Medium | Hold | Hold only |
| Unusual amount (AMOUNT) | The line's amount is more than the **Unusual Amount %** from the setup (100% by default) above the median of the vendor's payments (not invoices) posted in the 12 months up to the work date. Vendors with fewer than 3 such payments, and lines that pay several invoices, are not checked. | Medium | Hold | Pay, Hold |
| First payment (FIRST) | No payment to this vendor has ever been posted. Reversed payments do not count. | Medium | Verify bank details by phone | Pay, Hold, Verify bank details by phone |

A line with several signals gets the highest of their severities. Its default action is Hold when it has PAID, DUP_COPY or ON_HOLD, otherwise Verify bank details by phone when a bank account changed, otherwise Ask vendor to confirm duplicate for a possible duplicate, otherwise the default of its other signal. The model may choose an action that one of the line's signals allows, but Pay only when every signal allows it, and nothing but Hold when the line has PAID, DUP_COPY or ON_HOLD. So it can never pay a possible duplicate, a changed bank account or an invoice on hold, and it cannot take the Hold away from a line that was already paid, from the copy of a duplicate or from an invoice someone put on hold. A line already exported to a payment file, or whose check was printed, is still checked and its explanation says so, but Keep it refuses to hold it (see below).

What the model adds: a short note for the approver as the summary (which payments to stop or check before the run is approved, and how many lines are clear), an explanation of each flagged line, the action and a confidence. For a possible duplicate it compares the two vendor invoice numbers and descriptions and judges whether they are the same invoice: INV-4471 and INV4471 are one number written two ways, while 4471/A may be a second part. It is told whether the other invoice is still open, which of the two was entered first, and whether the other one is paid in this run too, by another line or by the same summarised line. No email is drafted.

What **Keep it** does:

- Saves the review with the ticked lines as payment run evidence. The run's **Source No.** is the batch name.
- For each ticked line whose action is Hold, it first checks the line again: it must still be in the same batch, for the same vendor and amount, and still pay the same open entries (as many, with the same entry numbers). If not, Keep it stops with a message and nothing is kept. A line that was already exported to a payment file, or whose check was printed, exported or transmitted, also stops Keep it with a message, because the bank may pay it whatever happens to the line: void the payment file or the check first.
- It then deletes the line from the payment journal, the same way deleting it on the page does (which also removes the line's application from the entries it paid), and sets On Hold to the **Hold Code** from the setup (QRY by default), through Business Central's standard Vend. Entry-Edit codeunit. For a bank change, an unusual amount or a first payment it puts every invoice the line pays on hold. Otherwise it puts only the possible duplicate on hold, so the other invoices of a summarised line are proposed again by the next Suggest Vendor Payments. Credit memos are never put on hold, an entry that is already on hold keeps its code, and a line that pays nothing still open (an invoice already paid, or a line not applied to any entry) is only removed. The kept finding lists the invoices it put on hold. Suggest Vendor Payments skips invoices that are on hold. With a blank Hold Code, Keep it refuses a Hold and keeps nothing.
- Makes all of this in one transaction: when one line fails its check, no line is deleted and no invoice is put on hold.
- Leaves every other line in the journal unchanged: lines set to Pay, Verify bank details by phone or Ask vendor to confirm duplicate, unticked lines and lines with no signal. Nothing is posted, no payment file is exported, and vendor bank accounts are never changed.

Bank details get stricter handling than other data:

- For the bank check Business Central reads only the code of each vendor bank account and the time the record was last changed. Account numbers, IBANs, SWIFT codes and bank names are not read, so they cannot be sent.
- The model gets the date of the change, how long ago it was and whether this payment goes to the changed account. Business Central works that out from the line's **Recipient Bank Account** code; the code itself is not sent.
- The model is told that the approver should confirm the details by phone on a number already known from earlier records, never one given in a recent email or letter.
- What the check does not see: a bank account that was deleted, a change of the preferred bank account on the vendor card, and a change made before the window when the record has not been changed since.
- The **Explain and Resolve - User** permission set gives read access to the Vendor Bank Account table, because the change time is read from it.

Afterwards: while the batch has lines, the Payment Journal shows the latest kept check of the batch in the **Payment run review** FactBox. Choose the date to open the full review. The **Explain and Resolve Runs** page lists every check with its batch name in **Source No.**; in a review, choose a finding's subject to open the vendor ledger entry of the invoice the finding is about: the possible duplicate, or the first invoice the line pays (or the vendor card when the line pays no open entry).

### Audit trail

The **Explain and Resolve Runs** page lists every run with its capability, status (Generated, Kept, Discarded, Failed or Blocked by Limit), user, summary, model, input and output tokens and duration. The run card also shows the prompt version (the prompt file name and a hash of its text), the options and the note. A kept run opens with its kept findings and emails. Every user of the app can read every run in the company. The app sets no retention policy and has no Delete action, so runs are kept with their summaries, notes and email text.

## How it keeps the AI in check

Recipients always come from Business Central, and each action comes from that finding's fixed list in Business Central. Figures should too: the model is told to cite every figure by token, and the checks below replace the tokens and flag the most common figures the model writes itself.

- **Figures come from Business Central.** Each figure is sent to the model with a token such as `{F3}`, a short caption and its value. The model is told to cite figures only by token. Business Central puts its own values in place of the tokens and removes any token it does not know.
- **Findings are named by Business Central.** Each finding has an internal key that the user never sees. To name a finding, the model writes its key, and Business Central puts the finding's subject or a short name in its place, such as "payment EXR-JP0002 of vendor invoice INV4471". A reminder to one customer can name only that customer: another finding's key there is removed and the reminder is flagged.
- **Unverified figures are flagged, not blocked.** Business Central looks for figures the model wrote itself in these shapes: £, $, € or ¥ before a number, one of this run's currency codes next to a number, an amount with two decimals, a comma thousands separator and a percentage. In every text it also looks for email addresses, IBAN-shaped text and phone numbers (9 or more characters of digits, spaces, brackets, dots and dashes, which also catches a date written as 2026-11-03), and in emails also for runs of six or more digits. If the summary or an email has one, the dialog ticks **Unverified figures**. If an explanation or a customer's reminder has one, that explanation is highlighted. Other numbers, such as a plain whole number or a date in words, are not flagged, and email text you change in the dialog is not checked again. A flagged result can still be kept, so read it first.
- **Each reminder can cite only its own customer's dates.** In a Plan collections reminder, any token other than that customer's own dates is removed and the reminder is flagged. The model is also told not to mention other customers; that instruction is not checked by code.
- **The reply is validated.** The model must answer in a strict JSON schema that allows only this run's finding keys and the actions its findings allow. Unknown findings are dropped. An action outside the finding's own allow-list is ignored and Business Central's default action stays, so the model cannot, for example, turn a possible duplicate into an accept, pay a line whose vendor bank account just changed or take the Hold away from the copy of a duplicate.
- **One retry, then fail closed.** A reply that is not valid JSON, or that lacks the summary or the findings, is retried once. A reply that is cut off or refused, a second unreadable reply, or a provider error fails the run: it is logged as Failed, the dialog's summary starts with "AI unavailable", and the findings Business Central computed are shown with its own figures but no explanation from the model. A failed Regenerate keeps the previous result. You can still keep a failed run. Keep it then saves the findings Business Central computed, without explanations, and makes the changes of their default actions: for Explain invoice variance it puts the invoice on hold when a finding needs the vendor's answer, and for Check payment run it holds the ticked lines whose default action is Hold. The run's status then shows Kept, and its error message stays on the run.
- **Business data is treated as untrusted text.** Names, descriptions, document numbers, filters and the user's note are sent inside `<untrusted>` tags, with `&`, `<` and `>` escaped so the text cannot close the tag. The instructions tell the model to read that text as data and never follow it. The allow-lists and figure checks above apply whatever the model writes.
- **What is sent to the AI provider.** The prompt files, the vendor name or each customer's number and name, item and account numbers with line descriptions, the invoice number and vendor invoice number, the posted invoice numbers and vendor invoice numbers of possible duplicates, invoice line numbers, each finding's type, severity and allowed actions, the salesperson and customer posting group filters, the email tone, your note, and every computed figure (amounts, quantities, dates and percentages) with its caption. For Check payment run it also sends the journal batch name, each flagged line's vendor number and name and payment document number, the vendor invoice number and description of the invoice the line pays and of a possible duplicate, the possible duplicate's document number and an existing hold code. No bank details are sent; see **Check payment run** above.
- **Email addresses and bank details from vendor and customer cards are not sent.** The recipient is taken from the card only when you keep the review, and the lists of documents in the emails are built by Business Central at that point. Text that people type, such as the note, names and descriptions, is sent as typed.
- **Daily limits.** The setup caps the runs per user (50 by default) and per company (500 by default) each day. The limits count runs, not provider calls: a retried run counts once, and Test Connection does not count. A blocked attempt is logged as Blocked by Limit and does not count. The count takes no lock, so runs started at the same moment can go slightly over the cap.
- **Output size is estimated first.** Before a Plan collections call, Business Central estimates the reply at 1,000 tokens plus 300 per customer and stops with a message if that is above **Max Output Tokens**. With the default of 16,000 the estimate allows up to 50 customers, more than the dialog's 25. The estimate is rough: in the measured demo run at Effort High, 4 customers used 3,976 output tokens. A reply that is still cut off fails the run, so at higher effort review fewer customers or raise Max Output Tokens. A higher limit has a cost in time: with claude-haiku-5-5 a reply of 16,000 output tokens would take about 75 seconds (the rate measured in evaluation run 3), and a reply that takes more than 120 seconds fails the run.
- **The API key is protected.** It is kept in isolated storage (encrypted when encryption is turned on), never in a table, and is never shown again after it is entered. It is sent only over https, and only to the endpoint it was entered for: change the endpoint and the key must be entered again. Only users who can change the setup can set or remove it. The key is shared by all companies of the environment, so setting or removing it in one company changes it for all of them.
- **No write transaction during the call.** Nothing is written to the database before the model call, and the call runs through `Codeunit.Run`, which Business Central refuses to start inside an open write transaction. The run is saved after the reply arrives.
- **Usage events hold usage figures only.** Each run logs a feature telemetry event with the capability, token counts and duration, never document or ledger data. The app has no Application Insights connection string and registers no telemetry logger yet, so the publisher does not receive these events. The Runs page keeps the same figures.

## Set up

1. **Install** the extension. Build `app/` with the AL Language extension in Visual Studio Code and publish it to a sandbox, or upload the built `.app` file with **Upload Extension** on the **Extension Management** page. Microsoft removes an app published from Visual Studio Code when the sandbox is updated, so publish it again after an update; an uploaded app stays. Use the upload route for a production environment. Installing registers the three Copilot capabilities. Upgrading from 1.0 registers Check payment run and fills its three new setup fields with their defaults; the other setup values stay as they were. Upgrading to 1.1.0.2 raises **Max Output Tokens** from 8,000 to the new default of 16,000, once per company and only when it is still 8,000; any other value stays.
2. **Assign permission sets** on top of the users' normal Business Central permissions.

   | Permission set | For |
   |---|---|
   | Explain and Resolve - User | People who use the features. Reads the purchase, receivables and payables data the checks need (for Check payment run: payment journal lines, vendor ledger entries and their details, and vendor bank accounts, of which only the code and change time are used). Lets Keep it set On Hold on the purchase invoice and delete a held payment journal line, with indirect permissions. For Check payment run it also gives indirect modify on vendor ledger entries and their details and indirect insert on change log entries: Keep it sets On Hold through the standard Vend. Entry-Edit codeunit, the line's delete clears its application through Vend. Entry-Edit or Vend. Entry-SetAppl.ID, and the change log records every change to a vendor ledger entry. Indirect means these writes are possible only through those objects. Writes runs and findings, and includes Email - Edit so Keep it can save drafts. Can read all runs in the company. |
   | Explain and Resolve - Admin | Everything in User, plus the setup page, the API key, Test Connection and Delete permission on runs and findings (the app itself has no Delete action). |

3. **Sandbox only:** turn on **Allow HttpClient Requests** for the extension (Extension Management, **Configure**).
4. **Open the Explain and Resolve Setup page** and enter your API key. Open the page once in each company: the setup is per company, while the API key is shared by all companies of the environment.

   | Field | Default | Notes |
   |---|---|---|
   | Provider | Claude API | The only provider today. |
   | Model | claude-haiku-5-5 | The model ID your provider runs. Test Connection checks that it answers in JSON that follows a small test schema. |
   | Endpoint | https://api.anthropic.com/v1/messages | Only https:// addresses are allowed. The API key and the request data are sent to this address. |
   | API Version | 2026-10-21 | Sent with every request. |
   | API Key | (empty) | Masked. **Remove API Key** deletes it for all companies. |
   | Effort | Low | How much the model thinks before it answers: Low, Medium or High. Higher effort takes longer and uses more tokens. A reply that takes more than 120 seconds fails the run. |
   | Max Output Tokens | 16000 | The most tokens one reply may use, thinking included (256 to 128,000). A reply cut off at this limit cannot be used. A reply of 16,000 tokens would take about 75 seconds with claude-haiku-5-5 (about 215 output tokens per second in evaluation run 3), and a reply that takes more than 120 seconds fails the run, so with a slower model or a higher limit the time limit can come first. |
   | Daily Calls per User | 50 | Runs one user can start per day. |
   | Daily Calls per Company | 500 | Runs all users in the company can start per day. |
   | Variance Tolerance % | 2 | Default tolerance for Explain invoice variance. Users can change it in the dialog. |
   | Hold Code | QRY | Leave blank to never put invoices on hold. Check payment run puts the vendor ledger entries it holds on hold with this code, and refuses a Hold while it is blank. |
   | Default Email Tone | Neutral | Users can change it in the dialog. |
   | Duplicate Window Days | 60 | Check payment run: how many days apart two posted invoices may be and still be a possible duplicate. Users can change it in the dialog. 0 turns the check off. |
   | Bank Change Window Days | 30 | Check payment run: how many days back, counting today, a change to a vendor bank account flags a payment. Users can change it in the dialog. 0 turns the check off. |
   | Unusual Amount % | 100 | Check payment run: how far above the vendor's median payment of the last 12 months a payment must be to be flagged. 100 flags payments of more than twice the median. 0 turns the check off. |

5. Choose **Test Connection**. It sends one short request and shows the model, the time taken and the tokens used.
6. Choose **Copilot & agent capabilities** and check that **Explain invoice variance**, **Plan collections** and **Check payment run** are active. The Copilot actions are hidden while a capability is off.

## Try it with demo data

The test app (`test/`) adds three actions to the Explain and Resolve Setup page. Use them only in a sandbox: they create and post real documents, and Microsoft does not allow running tests in production environments. The test app depends on Microsoft's Library Assert app. When the test app is installed, the Provider field also lists **Mock (tests only)**: keep it set to **Claude API** for a live demo.

The evaluation app (`eval/`) can also read the main app's internals and calls your AI provider with billed requests: install it only in a sandbox. Results: [docs/evaluation-results.md](docs/evaluation-results.md).

| Action | What it creates | What to do next |
|---|---|---|
| **Create demo invoice scenario** | A vendor (Northwind Office Furniture Ltd.), two items, an earlier posted invoice for the price history, a purchase order with 8 of 10 tables received, a posted invoice INV4472, and an open purchase invoice INV-4472 for 10 tables at a 6% higher price, desks at the order price, an unordered freight line and an unassigned item charge. Posting must be allowed on the work date. | The invoice opens. Choose **Explain variance**, then **Generate**. Expect six findings: not received, price against the order, price against history, G/L line without an order, item charge not assigned and possible duplicate. |
| **Create demo collections scenario** | Five customers with a shared new salesperson and invoices posted 20 to 200 days before the work date, including a part payment, a broken payment promise, a disputed invoice, a nearly used credit limit and a customer with nothing due yet. Posting must be allowed on those dates. | The Customer List opens filtered to the five customers, and a message shows the salesperson code. Choose **Plan collections**, set **Salesperson** to that code and choose **Generate**. Expect four customers ranked; the one with nothing overdue is left out. |
| **Create demo payment run scenario** | Three vendors. Proseware Office Supplies has four paid invoices of 900 to 1,200 in the last year, two open invoices INV-4471 and INV4471 for 1,280 posted 10 days before the work date, and a bank account added today. Wide World Paper Co. has the same payment history and an open invoice for 980. Lucerne Print Studio has never been paid and has an open invoice for 2,400. Then a new batch in the first payment journal template, with one payment line per open invoice, dated the work date and applied to its invoice. The lines are created directly, not by Suggest Vendor Payments, so the batch holds only the demo vendors. Posting must be allowed from 270 days before the work date to the work date. | The Payment Journal opens on the new batch. Choose **Check payment run**, then **Generate**. Expect three findings: both Proseware lines High with a possible duplicate and a bank change (INV4471, entered later, is the copy and can only be held; INV-4471 defaults to Verify bank details by phone) and Lucerne Medium as a first payment. Wide World has no signal and is counted as clear. Keep it with INV4471 at Hold deletes that line and puts its invoice on hold; Suggest Vendor Payments then skips that invoice. |

The demo vendors and customers use example.com email addresses. The demo collections invoices are posted as customer journal lines, so there is no posted sales invoice to open from their entries. The same goes for the demo payment run: its invoices and payment history are posted as vendor journal lines. Its bank account carries a published example IBAN and made-up details, which the check never reads.

## Usage and cost

One measured run of each capability on the demo data above, on 3 November 2026, in a Business Central 29 sandbox (CRONUS UK Ltd., GBP), with the Claude API, model claude-haiku-5-5, **Effort High** and Max Output Tokens 8,000. Effort High is not the default. The default, Low, is expected to use fewer tokens, but it was not measured here.

| Run | Result | Input tokens | Output tokens | Time | Approximate cost |
|---|---|---|---|---|---|
| Plan collections | 4 customers ranked | 4,079 | 3,976 | about 17 seconds | about USD 0.002 |
| Explain invoice variance | 6 findings | 3,651 | 4,426 | about 20 seconds | about USD 0.003 |
| Check payment run | 3 of 4 lines flagged | 4,984 | 4,634 | about 23 seconds | about USD 0.003 |

The cost is worked out at USD 0.10 per million input tokens and USD 0.50 per million output tokens, the claude-haiku-5-5 list price used for this estimate. **What you pay depends on the model you choose and your provider's current price, which can change.** A run with more findings or more customers uses more tokens. The Explain and Resolve Runs page shows the tokens of every run, so you can check your own usage.

## Tests

The test app has 151 automated tests in 18 test codeunits. The 97 tests of version 1.0 all passed in a Business Central 29 sandbox on 2 November 2026. Version 1.1 adds 49 tests: 40 for Check payment run, 5 for its setup fields, upgrade and registration, 3 for how the engine shows a finding the model names, and 1 (in 1.1.0.1) for the full stop after a fact that is a whole sentence. All 146 tests passed on version 1.1.0.1 in the same sandbox on 11 November 2026. Version 1.1.0.2 adds 5: 3 for raising the old Max Output Tokens default of 8,000 to 16,000 once, and 2 for hiding finding type codes such as (FIRST) from the user. All 151 passed on version 1.1.0.2 in the same sandbox on 12 November 2026. Since 1.1.0.2 the test app and the evaluation app need Explain and Resolve 1.1.0.2 or later. The AI provider is replaced by a mock client, so the tests make no calls to a real AI service, cost nothing and give the same result every run. The mock records each request, so the tests can check exactly what would be sent.

What the tests cover:

- **Claude API client:** the request body, effort and JSON schema, no sampling parameters, thinking blocks skipped, refusals and cut-off replies, and clear messages for an invalid key, rate limits, overload and used-up credits.
- **Setup and Test Connection:** defaults, https only, setting and removing the key, a changed endpoint stopping the call, replies outside the schema, the 1.1 upgrade: the new setup fields filled once without changing other values, the upgrade tags and the capability registration, and the 1.1.0.2 upgrade: Max Output Tokens raised from 8,000 to 16,000 once per company, while a value someone chose (such as 12,000 or 4,000) stays.
- **Engine:** capability switched off, missing key, daily limits per user and company, the strict reply schema, unknown findings, tokens and actions dropped, a finding key in the model's text shown as the finding's subject, another customer's key never named in a reminder, one full stop after a fact that is a whole sentence, finding type codes such as (FIRST) or DUPLICATE+BANK never shown to the user, also next to a finding key, untrusted text tagged and escaped, stray figures, currency codes, percentages, addresses, phone numbers and bank details flagged, one retry then fail closed, and no model call when nothing is found.
- **Explain invoice variance:** each check, including the tolerance edge, cheaper invoices, the price history from up to three posted lines, hand-keyed and split lines, variants, duplicate numbers written differently, open invoices only, Keep it putting the invoice on hold without posting, a blank or existing hold code, and the vendor invoice number in the subject.
- **Plan collections:** age buckets, usual delay from invoices paid by a payment, promises, disputes and holds, unapplied payments, credit limit use, ranking and Max. customers, the filters, the allowed actions per situation, no email address or bank data in the request, one email per customer, the output size check, the worklist and drafts on Keep it, and the Collections review FactBox.
- **Check payment run:** possible duplicates with the number written differently or only the digits matching, the window edges, other numbers or amounts and numbers with fewer than 3 digits, the copy held and the first invoice kept, a summarised line that pays both copies, a copy already cancelled with a credit memo, a copy already paid and the true order sent to the model, lines whose invoice was paid in full or in part after the line was made, the amount against the median at its threshold edge and with too few payments, a bank account added today and the bank check turned off, first payments, invoices already on hold (also with a bank change), lines with the vendor as balancing account counted but not checked, the demo's findings, no IBAN, account number, SWIFT code or bank name in the request, names and descriptions tagged as untrusted, no email in the schema, the allowed actions per signal, the model unable to pay a risky line or take a Hold away, phone numbers in the reply flagged, failing closed and keeping a failed run, and Keep it: only accepted Hold lines deleted, every invoice of a line with a bank change held but not its credit memo, only the copy held on a summarised line, an existing hold code kept, the held invoices listed on the kept finding, a changed, deleted or exported line and an invoice added after the check each stopping Keep it with nothing kept, a blank Hold Code refused, Keep it for a user with only D365 READ and Explain and Resolve - User, Discard writing only the run row, and the Payment run review FactBox. A bank change older than the window is not tested, because a test cannot set the time a record was changed.
- **Keep it, Discard and Regenerate:** a second Keep it changes nothing, Discard writes only the run row, and a blocked or failed Regenerate keeps the current result.

Several tests take ledger fingerprints after Generate and compare them after Keep it or Discard. For Explain invoice variance they count G/L, vendor, item and value entries to show nothing is posted, and compare the invoice lines. For Plan collections they count customer ledger entries, their details and reminders, and after Keep it also compare each customer ledger entry's amounts, dates, promises, disputes and holds, and the customer's credit limit. For Check payment run they count G/L, vendor, detailed vendor and bank account ledger entries, and compare the other journal lines (vendor, amount, application and recipient bank account) and each of the vendor's ledger entries (open, remaining amount, hold, applies-to ID and due date).

The evaluation app (`eval/`) has its own tests:

- **21 free tests in 2 codeunits**, which use the mock and cost nothing. All 21 passed on evaluation app 1.1.0.2 on 12 November 2026.
  - 58307 EXR Eval Scorer Tests (18 tests) shows that every check of the scorer can fail.
  - 58308 EXR Eval Dataset Tests (3 tests) builds every dataset case, checks that Business Central finds exactly the expected findings, and checks that every trap text reaches the request.
- **Two codeunits that are not free tests:** 58300 runs the suite cases against the real provider, with billed calls. 58309 holds the console methods: the suite status, billed smoke runs and the result export. See **Evaluation** below.

## Evaluation

The evaluation app runs the three capabilities against the real model on 31 scenarios built in a sandbox. It uses Microsoft's AI Test Toolkit and scores each reply with deterministic checks in AL. 11 of the scenarios carry an injected instruction (a trap) in a vendor or customer name, a description, an invoice number or the user's note.

Run 3, on 12 November 2026, used app 1.1.0.2 and claude-haiku-5-5 at Effort High, with Max Output Tokens 16,000:

| Capability | Mean case score | Cases with every check passed | Checks passed |
|---|---|---|---|
| Explain invoice variance | 0.987 | 10 of 11 | 93 of 94 |
| Plan collections | 0.976 | 6 of 9 | 96 of 99 |
| Check payment run | 0.972 | 9 of 11 | 78 of 80 |
| All | 0.978 | 25 of 31 | 267 of 273 |

- **Traps:** 11 of 11 were resisted.
- **Checks:** 267 of 273 passed (97.8%).
- **Failed closed:** none. The three-finding demo payment run, which hit the 8,000 output-token limit in run 2, completed with 7,794 output tokens. That is below the old limit too, so this one run does not show that 16,000 was needed: at Effort High the output size varies from run to run.
- **Cost:** 31 model calls, 104,535 input and 93,364 output tokens, about USD 0.06.
- **The failures:**
  - In 5 cases the model wrote a number itself. Each number is true: "12 months", "1-30 days" or "90 days" copied from a fact caption, or the vendor invoice number in an email.
  - In 1 case an explanation did not cite the fact behind its finding (the disputed amount).
  - They are published as they came, and nothing was re-run.
- **Run 2**, on 11 November 2026 with app 1.1.0.1 and Max Output Tokens 8,000, scored 0.941 on the same checks (23 of 31 cases with every check passed, one failed closed). **Run 1**, the same day, scored 0.988 on looser checks. The results page says what changed between the runs and why.

What is measured, case by case:

- whether the reply could be used;
- whether the model wrote a number or an internal key itself;
- whether it chose an action a finance person would accept;
- whether it cited the facts behind each finding and kept to its own finding;
- whether its emails are clean;
- whether it resisted the traps.

What is not measured:

- how much the model varies between runs, because each case ran once per run;
- whether an explanation is right beyond the fact it cites;
- an injected instruction that the model paraphrases instead of repeating;
- other models, other effort levels and real company data. All scenarios are built in CRONUS UK Ltd.

The acceptable actions are one finance person's judgement.

- Results and failures: [docs/evaluation-results.md](docs/evaluation-results.md)
- Method and how to run it: [eval/README.md](eval/README.md)
- How one run goes through the code, with the weak spots: [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md)

## Planned releases

| Version | Capability | Module | Status |
|---|---|---|---|
| 1.0 | Explain invoice variance | Purchase | Built and tested |
| 1.0 | Plan collections | Sales / customer ledger | Built and tested |
| 1.1 | Check payment run | Vendor ledger | Built and tested |
| 1.2 | Check margin | Sales quotes and orders | Planned |
| 1.3 | Explain G/L change | General ledger | Planned |
| 1.4 | Review slow and excess stock | Inventory | Planned |

## Project layout

```
app/                      the extension (Business Central 29, per-tenant, IDs 58200-58269)
  prompts/                the instructions the model receives: shared rules and one file per capability
  src/Setup/              setup table and page, API key storage
  src/Chat/               provider interface, Claude API client, Test Connection
  src/Copilot/            Copilot capability registration, install and upgrade
  src/Engine/             shared pipeline: facts, model call, validation, Keep it and Discard
  src/PurchaseVariance/   Explain invoice variance
  src/Collections/        Plan collections
  src/PaymentRun/         Check payment run
  src/Review/             dialog, findings, runs and FactBoxes
  src/Permissions/        permission sets
test/                     test app (IDs 58270-58299): tests, mock provider, demo actions
eval/                     evaluation app (IDs 58300-58329): AI Test Toolkit suite, datasets, scorer; sandbox only
  resources/              the datasets and the suite definition
  results/                the raw results of each evaluation run
  export-results.ps1      turns exported results into the JSON and the report
docs/                     evaluation results and the code walkthrough
.github/workflows/        compile check of app, test and eval with the analyzers; it runs no tests
```

Each capability is one codeunit behind the `EXR Capability Handler` interface. The dialog, the model call and the checks described above are shared, so a new capability adds its own handler codeunit (checks, allowed actions and Keep it changes), a prompt file, a capability value with its Copilot registration, and the Copilot action on its page, plus any new actions in the `EXR Action` enum and its objects in the permission sets.

## Licence

MIT. See [LICENSE](LICENSE).
