# Explain and Resolve for Business Central

Copilot features in Business Central for the finance team of a business that buys and sells stock: the accounts payable clerk who checks purchase invoices and the credit controller who chases overdue customers. Business Central computes every figure from its own documents and ledgers, and decides what needs attention. The AI model explains the findings, suggests one action for each from a fixed list and drafts the emails. A person reviews the result and chooses **Keep it** or **Discard**. Until then Business Central saves only a run record: the usage figures, the summary, your note and, for Explain invoice variance, the vendor email text. Findings and customer reminders are saved only when you choose Keep it. Nothing is ever posted, and no email is ever sent: emails are saved as drafts for a person to send.

**Status:** the two v1.0 capabilities are built and covered by automated tests. The app is still in development and is not yet on AppSource. Both capabilities are registered as Preview in Copilot & agent capabilities.

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

Both capabilities work the same way:

1. You choose the Copilot action, set the options and choose **Generate**.
2. Business Central reads the data, runs fixed checks and computes every figure.
3. The model receives those figures and writes a summary, an explanation per finding, one action per finding from a fixed list, a confidence and the email text.
4. You review the result in the dialog. You can untick findings in the **Accept** column and change the email subject and text. The action of a finding cannot be changed in the dialog: untick the finding, or add a note and choose **Regenerate**. Regenerate starts a new run: Business Central computes the findings again and calls the provider again, which is billed and counts toward the daily limits. Your ticks and email changes are reset, and a previous generated run is marked Discarded.
5. **Keep it** saves the accepted findings and makes the few changes listed below. **Discard** saves no findings and no drafts. The run record stays on the Runs page.

Both dialogs show a **When you keep it** note that says what Keep it will save and change, because the web client does not show a message while the dialog closes.

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

Where: the **Plan collections** Copilot action on the **Customer List** page. In the dialog you can filter on **Salesperson** and **Customer posting group**, and set **Max. customers** (10 by default, at most 25). With the default Max Output Tokens of 8,000, a plan with more than 23 customers stops before the call (see **Output size** below).

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

### Audit trail

The **Explain and Resolve Runs** page lists every run with its capability, status (Generated, Kept, Discarded, Failed or Blocked by Limit), user, summary, model, input and output tokens and duration. The run card also shows the prompt version (the prompt file name and a hash of its text), the options and the note. A kept run opens with its kept findings and emails. Every user of the app can read every run in the company. The app sets no retention policy and has no Delete action, so runs are kept with their summaries, notes and email text.

## How it keeps the AI in check

Recipients always come from Business Central, and each action comes from that finding's fixed list in Business Central. Figures should too: the model is told to cite every figure by token, and the checks below replace the tokens and flag the most common figures the model writes itself.

- **Figures come from Business Central.** Each figure is sent to the model with a token such as `{F3}`, a short caption and its value. The model is told to cite figures only by token. Business Central puts its own values in place of the tokens and removes any token it does not know.
- **Unverified figures are flagged, not blocked.** Business Central looks for figures the model wrote itself in these shapes: £, $, € or ¥ before a number, one of this run's currency codes next to a number, an amount with two decimals, a comma thousands separator and a percentage. In emails it also looks for email addresses, IBAN-shaped text and runs of six or more digits. If the summary or an email has one, the dialog ticks **Unverified figures**. If an explanation or a customer's reminder has one, that explanation is highlighted. Other numbers, such as a plain whole number or a date in words, are not flagged, and email text you change in the dialog is not checked again. A flagged result can still be kept, so read it first.
- **Each reminder can cite only its own customer's dates.** In a Plan collections reminder, any token other than that customer's own dates is removed and the reminder is flagged. The model is also told not to mention other customers; that instruction is not checked by code.
- **The reply is validated.** The model must answer in a strict JSON schema that allows only this run's finding keys and the actions its findings allow. Unknown findings are dropped. An action outside the finding's own allow-list is ignored and Business Central's default action stays, so the model cannot, for example, turn a possible duplicate into an accept.
- **One retry, then fail closed.** A reply that is not valid JSON, or that lacks the summary or the findings, is retried once. A reply that is cut off or refused, a second unreadable reply, or a provider error fails the run: it is logged as Failed, the dialog's summary starts with "AI unavailable", and the findings Business Central computed are shown with its own figures but no explanation from the model. A failed Regenerate keeps the previous result. You can still keep a failed run. Keep it then saves the findings Business Central computed, without explanations, and for Explain invoice variance puts the invoice on hold when a finding needs the vendor's answer. The run's status then shows Kept, and its error message stays on the run.
- **Business data is treated as untrusted text.** Names, descriptions, document numbers, filters and the user's note are sent inside `<untrusted>` tags, with `&`, `<` and `>` escaped so the text cannot close the tag. The instructions tell the model to read that text as data and never follow it. The allow-lists and figure checks above apply whatever the model writes.
- **What is sent to the AI provider.** The prompt files, the vendor name or each customer's number and name, item and account numbers with line descriptions, the invoice number and vendor invoice number, the posted invoice numbers and vendor invoice numbers of possible duplicates, invoice line numbers, each finding's type, severity and allowed actions, the salesperson and customer posting group filters, the email tone, your note, and every computed figure (amounts, quantities, dates and percentages) with its caption.
- **Email addresses and bank details from vendor and customer cards are not sent.** The recipient is taken from the card only when you keep the review, and the lists of documents in the emails are built by Business Central at that point. Text that people type, such as the note, names and descriptions, is sent as typed.
- **Daily limits.** The setup caps the runs per user (50 by default) and per company (500 by default) each day. The limits count runs, not provider calls: a retried run counts once, and Test Connection does not count. A blocked attempt is logged as Blocked by Limit and does not count. The count takes no lock, so runs started at the same moment can go slightly over the cap.
- **Output size is estimated first.** Before a Plan collections call, Business Central estimates the reply at 1,000 tokens plus 300 per customer and stops with a message if that is above **Max Output Tokens**. With the default of 8,000 the estimate allows up to 23 customers. The estimate is rough: in the measured demo run at Effort High, 4 customers used 3,760 output tokens. A reply that is still cut off fails the run, so at higher effort review fewer customers or raise Max Output Tokens.
- **The API key is protected.** It is kept in isolated storage (encrypted when encryption is turned on), never in a table, and is never shown again after it is entered. It is sent only over https, and only to the endpoint it was entered for: change the endpoint and the key must be entered again. Only users who can change the setup can set or remove it. The key is shared by all companies of the environment, so setting or removing it in one company changes it for all of them.
- **No write transaction during the call.** Nothing is written to the database before the model call, and the call runs through `Codeunit.Run`, which Business Central refuses to start inside an open write transaction. The run is saved after the reply arrives.
- **Usage events hold usage figures only.** Each run logs a feature telemetry event with the capability, token counts and duration, never document or ledger data. The app has no Application Insights connection string and registers no telemetry logger yet, so the publisher does not receive these events. The Runs page keeps the same figures.

## Set up

1. **Install** the extension. Build `app/` with the AL Language extension in Visual Studio Code and publish it to a sandbox, or upload the built `.app` file with **Upload Extension** on the **Extension Management** page. Microsoft removes an app published from Visual Studio Code when the sandbox is updated, so publish it again after an update; an uploaded app stays. Use the upload route for a production environment. Installing registers the two Copilot capabilities.
2. **Assign permission sets** on top of the users' normal Business Central permissions.

   | Permission set | For |
   |---|---|
   | Explain and Resolve - User | People who use the features. Reads the purchase and receivables data the checks need, lets Keep it set On Hold on the invoice (indirect permission), writes runs and findings, and includes Email - Edit so Keep it can save drafts. Can read all runs in the company. |
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
   | Max Output Tokens | 8000 | The most tokens one reply may use, thinking included (256 to 128,000). A reply cut off at this limit cannot be used. |
   | Daily Calls per User | 50 | Runs one user can start per day. |
   | Daily Calls per Company | 500 | Runs all users in the company can start per day. |
   | Variance Tolerance % | 2 | Default tolerance for Explain invoice variance. Users can change it in the dialog. |
   | Hold Code | QRY | Leave blank to never put invoices on hold. |
   | Default Email Tone | Neutral | Users can change it in the dialog. |

5. Choose **Test Connection**. It sends one short request and shows the model, the time taken and the tokens used.
6. Choose **Copilot & agent capabilities** and check that **Explain invoice variance** and **Plan collections** are active. The Copilot actions are hidden while a capability is off.

## Try it with demo data

The test app (`test/`) adds two actions to the Explain and Resolve Setup page. Use them only in a sandbox: they create and post real documents, and Microsoft does not allow running tests in production environments. The test app depends on Microsoft's Library Assert app. When the test app is installed, the Provider field also lists **Mock (tests only)**: keep it set to **Claude API** for a live demo.

| Action | What it creates | What to do next |
|---|---|---|
| **Create demo invoice scenario** | A vendor (Northwind Office Furniture Ltd.), two items, an earlier posted invoice for the price history, a purchase order with 8 of 10 tables received, a posted invoice INV4472, and an open purchase invoice INV-4472 for 10 tables at a 6% higher price, desks at the order price, an unordered freight line and an unassigned item charge. Posting must be allowed on the work date. | The invoice opens. Choose **Explain variance**, then **Generate**. Expect six findings: not received, price against the order, price against history, G/L line without an order, item charge not assigned and possible duplicate. |
| **Create demo collections scenario** | Five customers with a shared new salesperson and invoices posted 20 to 200 days before the work date, including a part payment, a broken payment promise, a disputed invoice, a nearly used credit limit and a customer with nothing due yet. Posting must be allowed on those dates. | The Customer List opens filtered to the five customers, and a message shows the salesperson code. Choose **Plan collections**, set **Salesperson** to that code and choose **Generate**. Expect four customers ranked; the one with nothing overdue is left out. |

The demo vendor and customers use example.com email addresses. The demo collections invoices are posted as customer journal lines, so there is no posted sales invoice to open from their entries.

## Usage and cost

One measured run of each capability on the demo data above, on 2 November 2026, in a Business Central 29 sandbox (CRONUS UK Ltd., GBP), with the Claude API, model claude-haiku-5-5, **Effort High** and Max Output Tokens 8,000. Effort High is not the default. The default, Low, is expected to use fewer tokens, but it was not measured here.

| Run | Result | Input tokens | Output tokens | Time | Approximate cost |
|---|---|---|---|---|---|
| Plan collections | 4 customers ranked | 4,065 | 3,760 | about 18 seconds | about USD 0.002 |
| Explain invoice variance | 6 findings | 3,651 | 3,859 | about 17 seconds | about USD 0.002 |

The cost is worked out at USD 0.10 per million input tokens and USD 0.50 per million output tokens, the claude-haiku-5-5 list price used for this estimate. **What you pay depends on the model you choose and your provider's current price, which can change.** A run with more findings or more customers uses more tokens. The Explain and Resolve Runs page shows the tokens of every run, so you can check your own usage.

## Tests

The test app has 97 automated tests in 13 test codeunits. All of them passed in a Business Central 29 sandbox on 2 November 2026. The AI provider is replaced by a mock client, so the tests make no calls to a real AI service, cost nothing and give the same result every run. The mock records each request, so the tests can check exactly what would be sent.

What the tests cover:

- **Claude API client:** the request body, effort and JSON schema, no sampling parameters, thinking blocks skipped, refusals and cut-off replies, and clear messages for an invalid key, rate limits, overload and used-up credits.
- **Setup and Test Connection:** defaults, https only, setting and removing the key, a changed endpoint stopping the call, and replies outside the schema.
- **Engine:** capability switched off, missing key, daily limits per user and company, the strict reply schema, unknown findings, tokens and actions dropped, untrusted text tagged and escaped, stray figures, currency codes, percentages, addresses and bank details flagged, one retry then fail closed, and no model call when nothing is found.
- **Explain invoice variance:** each check, including the tolerance edge, cheaper invoices, the price history from up to three posted lines, hand-keyed and split lines, variants, duplicate numbers written differently, open invoices only, Keep it putting the invoice on hold without posting, a blank or existing hold code, and the vendor invoice number in the subject.
- **Plan collections:** age buckets, usual delay from invoices paid by a payment, promises, disputes and holds, unapplied payments, credit limit use, ranking and Max. customers, the filters, the allowed actions per situation, no email address or bank data in the request, one email per customer, the output size check, the worklist and drafts on Keep it, and the Collections review FactBox.
- **Keep it, Discard and Regenerate:** a second Keep it changes nothing, Discard writes only the run row, and a blocked or failed Regenerate keeps the current result.

Several tests take ledger fingerprints after Generate and compare them after Keep it or Discard. For Explain invoice variance they count G/L, vendor, item and value entries to show nothing is posted, and compare the invoice lines. For Plan collections they count customer ledger entries, their details and reminders, and after Keep it also compare each customer ledger entry's amounts, dates, promises, disputes and holds, and the customer's credit limit.

## Planned releases

| Version | Capability | Module | Status |
|---|---|---|---|
| 1.0 | Explain invoice variance | Purchase | Built and tested |
| 1.0 | Plan collections | Sales / customer ledger | Built and tested |
| 1.1 | Check payment run | Vendor ledger | Planned |
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
  src/Review/             dialog, findings, runs and FactBoxes
  src/Permissions/        permission sets
test/                     test app (IDs 58270-58299): tests, mock provider, demo actions
```

Each capability is one codeunit behind the `EXR Capability Handler` interface. The dialog, the model call and the checks described above are shared, so a new capability adds its own handler codeunit (checks, allowed actions and Keep it changes), a prompt file, a capability value with its Copilot registration, and the Copilot action on its page, plus any new actions in the `EXR Action` enum and its objects in the permission sets.

## Licence

MIT. See [LICENSE](LICENSE).
