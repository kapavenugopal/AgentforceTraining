# Salesforce DX Project: Next Steps

## Country Details Callout

`CountryDetailsAction.getCountryDetails` is an Apex invocable action labeled **Get Country Details**. Pass `countryName`, such as `Canada`, `India`, or `United Kingdom`, to get one country's details. It uses the current API documented at [REST Countries](https://restcountries.com/docs/countries): `GET https://api.restcountries.com/countries/v5/names.common/{countryName}`. The `/apis/countries` website is documentation, not a callout endpoint. This integration targets authenticated v5, not the older v3.1 JSON format.

The output contains `countryName`, `officialName`, `countryCode` (ISO alpha-2), `countryCodeAlpha3`, `capitals`, `region`, `subregion`, `population`, `areaSquareKilometers`, `currencies`, `languages`, `callingCodes`, `timezones`, and `errorMessage`. Capitals, currencies, languages, calling codes, and timezones are text collections; currencies include code, name, and symbol when available. Population and area are Decimals. Missing optional values remain null or empty; errors return no country details.

### Named Credential And Permissions

1. Obtain your own REST Countries API key. The v5 API requires `Authorization: Bearer YOUR_API_KEY`. Never put the key in Apex, logs, committed metadata, or conversation inputs. The provider's demo key returns sample data; this action rejects demo responses.
2. In **Setup > Named Credentials > External Credentials**, create an External Credential with API name **REST_Countries_Credential** and authentication protocol **Custom**. Create a **Named Principal** named **CountryLookup**. Add an authentication parameter **ApiKey** to that principal and enter the key privately in Setup.
3. Add a custom header to the External Credential: name `Authorization`, value `Bearer {!$Credential.REST_Countries_Credential.ApiKey}`. This lets Salesforce inject the stored secret; Apex does not read it.
4. Create a Named Credential with API name **REST_Countries_API**, URL `https://api.restcountries.com/countries/v5` (no trailing slash), and link it to **REST_Countries_Credential**. Enable callouts. Disable **Generate Authorization Header** so it does not replace the custom bearer header. No Remote Site Setting is needed.
5. In a narrowly scoped permission set, enable **External Credential Principal Access** for **REST_Countries_Credential - CountryLookup**, and **Apex Class Access** for `CountryDetailsAction`. Assign it to the user running Execute Anonymous, Flow, or Agentforce. A principal showing **Configured** is not sufficient: the execution user also needs permission to use it.

Credentials and secrets are configured separately in each org and intentionally not included in source control. No runtime environment variables are required.

### Apex And Agentforce Usage

After deployment and credential setup:

```apex
CountryDetailsAction.Request input = new CountryDetailsAction.Request();
input.countryName = 'India';
CountryDetailsAction.Response result = CountryDetailsAction.getCountryDetails(
	new List<CountryDetailsAction.Request>{ input }
)[0];
System.debug(result);
```

For Agentforce, create an action with reference type **Apex** and select **Get Country Details**. Require and collect `countryName`; enable conversation output for the desired details and `errorMessage`. Instructions: "Collect the full common country name before invoking. Present only returned details. If errorMessage is populated, explain it; do not invent country data or treat missing fields as zero." Flow callouts must run before DML or in a separate transaction after pending writes; the action has `callout=true`.

Names are trimmed, limited to 200 characters, and URL-encoded. The lookup matches the full common name case-insensitively, not partial names, ISO codes, official names, or aliases. An unknown name produces a not-found message. Invalid, demo, mismatched, and multiple-country responses are rejected. The action preserves batch order, uses one callout per valid input with a 10-second timeout, and returns errors when the remaining transaction callout budget is exhausted. Keep batches small: Salesforce's total callout-time limit and the provider's rate and monthly quota limits still apply. There are no automatic retries, persistent caching, or Salesforce record changes.

### Validate And Deploy

Run **Validate Country Details** in VS Code for a check-only deployment. `CountryDetailsActionTest` uses `HttpCalloutMock`, with no live API key or network. Seven tests cover field mapping, URL encoding, optional fields, input validation, ordered batches, HTTP and callout errors, malformed/empty/ambiguous/mismatched/demo responses, and callout limits. Validation passed with 100% action coverage; CI should enforce at least 80% changed-code coverage.

Deploy separately when ready:

```powershell
& 'C:\Program Files\sf\bin\sf.cmd' project deploy start --source-dir force-app/main/default/classes/CountryDetailsAction.cls --source-dir force-app/main/default/classes/CountryDetailsActionTest.cls --test-level RunSpecifiedTests --tests CountryDetailsActionTest --api-version 68.0 --wait 10
```

## Currency Conversion Callout

`CurrencyConversionAction.convertCurrency` is available to Apex, Flow, and Agentforce as **Convert Currency**. It makes a GET request to ExchangeRate-API's pair conversion endpoint, including the amount: `/pair/EUR/GBP/100`.

| Variable | Direction | Purpose |
| --- | --- | --- |
| `fromCurrency` | Input | Required three-letter source code, such as EUR. |
| `toCurrency` | Input | Required three-letter target code, such as GBP. |
| `amount` | Input | Required nonnegative Decimal to convert. |
| `fromCurrency`, `toCurrency`, `originalAmount` | Output | Normalized currency codes and supplied amount for valid requests. |
| `exchangeRate`, `convertedAmount` | Output | Provider's rate and converted amount; null on failure. |
| `errorMessage` | Output | Safe error explanation; null on success. |

### Required Salesforce Configuration

1. Obtain an ExchangeRate-API key. Do not place it in Apex, test fixtures, logs, environment files committed to Git, or conversation inputs.
2. In **Setup > Named Credentials**, create a Named Credential with API name **ExchangeRate_API** and URL `https://v6.exchangerate-api.com/v6/YOUR-API-KEY`, replacing the placeholder privately in Setup. Do not add `/pair` or a trailing slash. Enable callouts. Use a linked External Credential with **No Authentication** because this endpoint authenticates using the key in its URL; do not generate an Authorization header.
3. Grant the execution user access to the linked External Credential principal where required by your credential configuration, and Apex class access to `CurrencyConversionAction` through a narrowly scoped permission set. Named Credentials remove the need for a Remote Site Setting.
4. Restrict administration of the Named Credential. Its URL contains the key, so treat configuration exports and callout debug logs as sensitive; do not retrieve or commit that credential metadata. For stricter secret-storage requirements, use a gateway that injects a securely stored key instead of keeping it in a Salesforce endpoint URL.
5. For Agentforce, create an Apex action named **Convert Currency**, collect all three inputs, and show `convertedAmount`, `toCurrency`, `exchangeRate`, and `errorMessage`. Never treat an error as a successful conversion. For Flow, callouts must run before DML or in a separate transaction after pending writes; the method is marked `callout=true`.

The credential is configured separately in each org and is intentionally not included in source control. No Apex runtime environment variables are required.

### Apex Example

After deployment and credential setup, run:

```apex
CurrencyConversionAction.Request input = new CurrencyConversionAction.Request();
input.fromCurrency = 'EUR';
input.toCurrency = 'GBP';
input.amount = 100;
CurrencyConversionAction.Response result = CurrencyConversionAction.convertCurrency(
	new List<CurrencyConversionAction.Request>{ input }
)[0];
System.debug(result);
```

Codes are trimmed and uppercased; only three-letter ASCII codes are accepted. The provider determines whether different currency codes are supported. Equal codes return the original amount and rate 1 without a callout, so that path checks code format only. Zero is valid; negative amounts are rejected. Provider precision is preserved rather than rounded to two decimals.
Responses retain input order, including errors. Each valid different-currency request uses one callout, with a 10-second timeout and no automatic retries. Requests beyond the transaction's remaining callout budget return errors rather than exceeding the 100-callout limit; total callout-time limits still apply, so keep batches small. No records are read or changed. This is a rate lookup, not a money transfer or executable financial quote.

### Validate And Deploy

Run the VS Code task **Validate Currency Conversion** for a check-only deployment. `CurrencyConversionActionTest` uses only `HttpCalloutMock`; no live API key or network is needed. Seven tests cover conversion, normalization, invalid inputs, same-currency and zero amounts, ordered batches, HTTP/provider failures, malformed or mismatched responses, callout exceptions, and the callout budget. The focused validation passed with 100% action coverage; CI should enforce at least 80% changed-code coverage.

Deploy separately when ready:

```powershell
& 'C:\Program Files\sf\bin\sf.cmd' project deploy start --source-dir force-app/main/default/classes/CurrencyConversionAction.cls --source-dir force-app/main/default/classes/CurrencyConversionActionTest.cls --test-level RunSpecifiedTests --tests CurrencyConversionActionTest --api-version 68.0 --wait 10
```

## Suspicious Activity Review And Confirmed Suspension

This is a two-step Agentforce workflow. Detection is read-only; the agent must show the findings and obtain explicit confirmation before changing account status.

| Action | Inputs | Outputs |
| --- | --- | --- |
| **Check Bank Account Suspicious Activity** (`BankAccountSuspiciousActivityAction.checkAccounts`) | `accountNumber` only | `recentTransactionCount`, `suspiciousActivityFound`, `transactions`, `detailsTruncated`, `windowStart`, `windowEnd`, `message`, `errorMessage` |
| **Set Bank Account Active Status** (`BankAccountSuspensionAction.setAccountStatus`) | `accountNumber`, `isActive`, `userConfirmed` | `isActive`, `message`, `errorMessage` |

The check flags **more than two (three or more)** visible linked Transaction records with `CreatedDate` between the time of invocation minus one hour and the time of invocation, inclusive.
It uses the Salesforce **record creation timestamp**, not `Transaction_Date__c`, which stores only a Date. Imported/backdated records are therefore evaluated by when they were created in Salesforce, not when money moved.
The count is exact for records visible to the execution user; the newest 200 transaction details are returned per account, including ID, name, bank account ID, description, amount, type, transaction date, and CreatedDate.
If details are capped, `detailsTruncated` is true and the message discloses the cap. Do not describe the displayed list as the entire history when truncated.
The check never changes `Is_Active__c`, even when activity is flagged or when the account is already inactive. It runs on demand, not automatically on transaction insertion.

For example, the check returns: "Suspicious activity found: 3 transactions were created in the last hour. Review the transaction details and confirm whether to temporarily suspend this account. Account status has not been changed."
The separate status action sets `Is_Active__c=false` only when `userConfirmed=true` and `isActive=false` are supplied. Confirmed reactivation uses `isActive=true` and `userConfirmed=true`.
The status action is a general confirmed status update; it does not require a stored detection result or recheck the one-hour threshold. This permits the user to act on previously reviewed findings even if the time window has moved.
Missing confirmation causes no status update. Conflicting status requests for the same account in a batch are rejected. If a database/permission failure occurs, all updates made by the status invocation are rolled back.
Both actions use user-mode queries/DML and enforce sharing. Missing and inaccessible accounts use the same generic message; no raw fault details are exposed.

### Agentforce Setup

1. Create two actions with reference type **Apex**, selecting the labels above. Add both to a **Suspicious Activity Review** topic/subagent.
2. For the check, make `accountNumber` required and collect it from the user. Show `message`, `recentTransactionCount`, `transactions`, and `errorMessage` in conversation. Present transaction CreatedDate, description, type, amount, and record identifier; show the evaluation window and truncation notice where relevant.
3. Topic instructions: "First call Check Bank Account Suspicious Activity using the account number. If errorMessage is present, explain it and stop. Show the returned count and transaction details. If suspiciousActivityFound is true, ask whether the user recognizes these transactions and explicitly wants this account temporarily suspended. Do not suspend merely because the threshold was exceeded."
4. Enable **Require user confirmation** for **Set Bank Account Active Status** where available. Input instructions: "Use the same account number that was reviewed. Set isActive=false only after the user confirms suspension. Set userConfirmed=true only after explicit confirmation; never infer it from the detection message. If the user declines, do not call this action."
5. For reactivation, obtain explicit confirmation to reactivate that account and use `isActive=true`, `userConfirmed=true`. Show the returned message only on success; otherwise show the error.
6. Assign **Bank Activity Check Access** for detection. Separately assign **Bank Account Status Access** only to users authorized to suspend/reactivate accounts. Both require appropriate record sharing; neither grants View All or Modify All.
7. Test 0, 2, and 3 recent transactions, old transactions, another account, confirmed/declined suspension, reactivation, and inaccessible accounts in Preview before activating.

Confirmation is an action input, not cryptographic proof of consent. Enforce trusted identity, customer account ownership, and any approval/audit requirements outside the model before exposing financial records or status updates to customers.
Setting `Is_Active__c=false` marks the account inactive only. The existing transaction creation action and trigger do **not** block new transactions for inactive accounts; enforcing a transaction freeze is a separate server-side rule.

### Validation And Deployment

Use **Validate Bank Account Suspension** for check-only validation and **Deploy Bank Account Suspension** for deployment.
`BankAccountSuspensionActionTest` uses isolated test records and an injected reference time to verify inclusive boundaries, account isolation, exact counts with capped details, read-only detection, confirmation, suspension/reactivation, invalid requests, and denied access.
The access-denied test expects the **Minimum Access - Salesforce** profile available in the training org. Run these focused tests in CI with the 80% changed-code coverage gate. No new environment variables are required.

## Bank Account Write Actions

Two separate Apex invocable actions support account creation and transaction entry. Salesforce permits one invocable method per class, so each operation has its own Agentforce action.

| Action | Required Inputs | Optional Inputs | Success Outputs |
| --- | --- | --- | --- |
| **Create Bank Account** (`CreateBankAccountAction.createAccounts`) | `bankAccountName` (Text), `accountType` (Text), `dateOfBirth` (Date) | None | `bankAccountId`, generated `accountNumber`, `currentBalance` (zero) |
| **Add Bank Account Transaction** (`AddBankAccountTransactionAction.addTransactions`) | `accountNumber` (Text), `transactionType` (Credit/Debit), `amount` (positive Decimal), `transactionDate` (Date) | `description` (Text) | `transactionId`, `bankAccountId`, `currentBalance` |

Both actions also return `errorMessage`, which is null on success. Dates should be passed as Dates in `YYYY-MM-DD` format.
Account Type must match an active picklist value; the current metadata includes Savings, Checking, Fixed, and Deposit.
Transaction amounts must be positive and have at most two decimal places. Credit adds the amount; Debit subtracts it. Negative balances are allowed, matching existing trigger behavior.
Account numbers are generated by Salesforce, not supplied during creation. The account holder lookup is not populated because it is not an input to this action.

`TransactionTrigger` remains the sole balance updater. The transaction action inserts records but does **not** update the balance again.
`TransactionTriggerHandler` locks the affected Bank Account rows with `FOR UPDATE` before reading and updating balances, preventing concurrent insert operations from overwriting each other's changes.
If an account starts with a null balance, the trigger treats it as zero. The returned balance is the final account balance after all accepted transactions in the action batch, not a running balance after each individual entry.
These actions cover creation/insertion only; editing or deleting existing transactions does not recalculate balances in the existing trigger.

Input-invalid requests return errors without writes; other valid requests in the batch can proceed. A database, trigger, permission, or post-write read failure rolls back all writes made by that action invocation, including trigger balance changes. Raw failure details are not returned.
The actions use user-mode DML and queries. Transaction entry additionally requires Bank Account balance update permissions because the trigger performs that mutation.
Savepoints apply separately to each action; creating an account and adding a transaction are not one combined atomic operation.

### Agentforce Configuration

1. Create two Agentforce actions with reference type **Apex**: **Create Bank Account** and **Add Bank Account Transaction**.
2. Mark each action's required inputs as required and enable collection from the user where appropriate. For creation, collect name, account type, and birth date. For transaction entry, collect account number, Credit/Debit, positive amount, and transaction date; description is optional.
3. Enable **Require user confirmation** for both write actions where available. Topic instructions: "Before creating an account or adding a transaction, present the supplied details and obtain explicit confirmation. Never guess values or retry a successful write. Use the accountNumber returned by creation when adding a transaction to that account."
4. Show the generated account number or transaction ID and updated balance on success; show `errorMessage` on failure. Do not echo the birth date unnecessarily.
5. Assign **Bank Account Write Actions Access** only to authorized execution users. It grants account creation/edit and transaction creation, including field access; it grants no deletion, View All, or Modify All. It also permits direct balance editing, so do not assign it broadly.
6. Separately enforce authenticated identity, authorized account ownership, record-level access, and applicable financial approval rules. An account number alone is not authorization. Topic instructions and confirmation are not substitutes for server-side ownership checks in a production customer-facing deployment.
7. Preview with account creation, a credit, a debit, missing/invalid inputs, unauthorized users, and a failed write. Verify the persisted balance and transaction links before activating the agent.

Each confirmed invocation creates new records; there is no idempotency key or duplicate prevention. A production financial integration should add durable request IDs and duplicate protection before allowing automated retries.

### Testing And Deployment

Run **Validate Bank Account Write Actions** in VS Code for a check-only deployment. The focused integration tests use isolated test-only records to check bulk account creation, credit/debit balance arithmetic, links, null balances, invalid inputs, denied access, and rollback.
The access-denied test expects the standard **Minimum Access - Salesforce** profile available in the training org.
For deployment, use **Deploy Bank Account Write Actions**. The existing Transaction trigger and object metadata must already be installed.
CI should run these tests plus the existing summary, transaction-type, and date-range tests because the balance handler is shared; enforce at least 80% changed-code coverage. No new environment variables are required.

## Bank Account Transactions By Date

`BankAccountTransactionsAction.getTransactions` is an invocable Apex method exposed as **Get Bank Account Transactions**.
It finds the visible Bank Account by `Account_Number__c`, then returns linked Transaction records whose `Transaction_Date__c` falls within the inclusive date range.
No records are changed, and this action does not require a flow.

| Variable | Type | Direction | Purpose |
| --- | --- | --- | --- |
| `accountNumber` | Text | Input | Required bank account number, such as `ACC-10045`; surrounding spaces are trimmed. |
| `fromDate` | Date | Input | Required first date to include, supplied as `YYYY-MM-DD`. |
| `toDate` | Date | Input | Required last date to include, supplied as `YYYY-MM-DD`; must be on or after `fromDate`. |
| `transactions` | Transaction record collection | Output | Matching records ordered by date descending, then CreatedDate and ID descending. |
| `errorMessage` | Text | Output | Safe failure explanation; null on success, including no matching transactions. |

Each returned record contains `Id`, `Name`, `Bank_Account__c`, `Description__c`, `Amount__c`, `Transaction_Type__c`, and `Transaction_Date__c`.
Records without a Transaction Date are excluded. An existing account with no transactions in the range returns an empty collection and no error.
Missing/inaccessible accounts produce the same generic error. Sharing and object/field permissions are enforced through user-mode queries.

The action supports batches, preserving request order and applying each request's own date range.
It performs at most two queries: an account lookup and a transaction query across the batch's earliest/latest dates.
If that combined query finds more than 10,000 transactions, valid requests return an error asking for a narrower date range; no partial results are returned.
In bulk calls, transactions between disjoint requested ranges may count toward this safety limit. This is a synchronous lookup, not a full-history export or pagination API.

### Agentforce Setup

1. Create an Agentforce action with reference type **Apex** and select **Get Bank Account Transactions** (`BankAccountTransactionsAction`).
2. Action instructions: "Retrieve transactions for the supplied bank account number between From Date and To Date, inclusive. Collect all three inputs before invoking. Never guess dates, account numbers, or transactions."
3. Mark all three inputs required and enable **Collect data from user** where appropriate. Clarify ambiguous dates and pass them as Dates in `YYYY-MM-DD` format; an account number is not a Salesforce record ID.
4. Enable **Show in conversation** for `transactions` and `errorMessage`. Output instructions: "Present only returned records, showing date, description, type, and amount. If errorMessage is populated, explain it. An empty collection without an error means no transactions in this period."
5. Add the action to your agent's bank enquiries topic/subagent. Assign **Bank Account Transactions Access** to the execution user and grant record-level access separately. This permission set grants only read access to the necessary objects/fields and Apex class access.
6. Preview with a valid range, a same-day range, reversed/missing dates, an unknown account, an empty history, and an unauthorized account before activating.

An account number alone is **not customer authentication**. Before customer-facing use, verify identity and enforce account ownership using trusted session context. This action relies on the execution user's sharing and permissions; those may be broader than the customer's entitlements.

### Validation And Deployment

Run **Validate Bank Account Transactions** in VS Code for a check-only deployment. To deploy:

```powershell
sf project deploy start --source-dir force-app/main/default/classes/BankAccountTransactionsAction.cls --source-dir force-app/main/default/classes/BankAccountTransactionsActionTest.cls --source-dir force-app/main/default/permissionsets/Bank_Account_Transactions_Access.permissionset-meta.xml --test-level RunSpecifiedTests --tests BankAccountTransactionsActionTest --api-version 68.0 --wait 10
```

The test class includes three hermetic unit tests using a fake selector and one isolated integration test with test-only records.
Tests cover inclusive boundaries, ordering, batch-specific filtering, account isolation, empty results, input validation, safe query failures, and oversized results.
Run these focused tests in CI with the 80% changed-code coverage gate. No new environment variables or runtime configuration are needed.

## Transaction Type Agentforce Action

`TransactionTypeAction.getTransactionType` is an Apex invocable method exposed as **Get Transaction Type**.
It reads `Transaction__c.Transaction_Type__c` without changing any records.

| Variable | Type | Direction | Purpose |
| --- | --- | --- | --- |
| `transactionId` | ID | Input | Required 15- or 18-character Salesforce Transaction record ID, not the transaction name or account ID. |
| `transactionType` | Text | Output | Stored picklist value (`Credit` or `Debit`); null when unavailable. |
| `errorMessage` | Text | Output | Safe explanation for a missing/wrong-object ID, unavailable record/access, or blank Transaction Type; null on success. |

Malformed ID strings are rejected by Salesforce when binding the typed ID input. The method handles missing IDs and IDs belonging to a different object.
The action performs one user-mode query per batch and returns one response per input in the original order, including duplicates.
Sharing and object/field permissions are enforced. Missing and inaccessible records return the same generic message; internal query errors are not exposed.

### Configure The Agentforce Action

1. In **Setup > Agentforce Actions**, create an action with reference action type **Apex** and select **Get Transaction Type** (`TransactionTypeAction`). No flow is needed.
2. Action instructions: "Retrieve the Transaction Type for the supplied Transaction record ID. Never guess the ID or type. If errorMessage is populated, explain that message instead of inventing a result."
3. Mark `transactionId` required. Input instructions: "The Salesforce record ID of the Transaction__c record, not a bank account ID or transaction number." Enable **Collect data from user** if the ID will be supplied conversationally; otherwise map it from trusted context or another action.
4. Enable **Show in conversation** for `transactionType` and `errorMessage`. Describe the first as "The actual stored Transaction Type: Credit or Debit" and the second as "An error explanation; not a transaction type."
5. Add the action to the appropriate agent topic/subagent. Assign **Transaction Type Action Access** to the agent's execution user, and separately grant appropriate record-level access. The permission set grants only action access and read access to Transaction and its Transaction Type field.
6. Test in Agentforce Preview with Credit, Debit, missing/unknown IDs, an ID from another object, a blank Transaction Type, and an unauthorized record before activating the agent. An ID is not proof of ownership; use authenticated customer context and enforce ownership before customer-facing use.

### Validate And Deploy

Run the VS Code task **Validate Transaction Type Action** for a check-only deployment. To deploy:

```powershell
sf project deploy start --source-dir force-app/main/default/classes/TransactionTypeAction.cls --source-dir force-app/main/default/classes/TransactionTypeActionTest.cls --source-dir force-app/main/default/permissionsets/Transaction_Type_Action_Access.permissionset-meta.xml --test-level RunSpecifiedTests --tests TransactionTypeActionTest --api-version 68.0 --wait 10
```

`TransactionTypeActionTest` contains three hermetic unit tests using a fake selector and one isolated integration test using a test-only Transaction record.
These cover Credit/Debit, batch ordering and duplicates, null/empty inputs, wrong-object/missing records, blank values, and safe query failures.
Run the focused tests in CI with the 80% changed-code coverage gate. No new environment variables or runtime configuration are required.

## Bank Account Summary Flow

`Fetch_Bank_Account_Summary` is an active autolaunched flow (no screens) for use as an Agentforce action.

| Variable | Flow Type | Direction | Purpose |
| --- | --- | --- | --- |
| `accountNumber` | Text | Input | Required account number, for example `ACC-10045`; surrounding spaces are trimmed. |
| `dateOfBirth` | Date | Input | Required date matching `Bank_Account__c.Date_of_Birth__c`; use `YYYY-MM-DD` when mapping from an action. |
| `accountSummary` | Text | Output | Plain-text summary or a safe missing-input, no-match, or unavailable message. |

The flow matches **both** fields on `Bank_Account__c` before calling `BankAccountSummaryAction`.
The Apex action uses one bulk-capable, user-mode parent/child query with `LIMIT 5` per account.
Transactions are ordered by `Transaction_Date__c` descending (null dates last), then `CreatedDate` and `Id` descending to break ties.
Only transactions linked through `Transaction__c.Bank_Account__c` are returned. No records are changed.
If fewer than five transactions exist, all available transactions are shown. Empty history returns `No transactions found.`
The displayed balance comes from `Current_Balance__c`, not a sum of the five transactions.

Output uses dollar notation and English month abbreviations to match the requested format; this assumes dollar-denominated accounts.
Balances always include two decimal places; whole transaction amounts omit cents, while fractional amounts retain them.
Credits display `+` and debits display `-`. Example:

```text
Account: ACC-10045 (Savings)
Balance: $24,350.00

Last 5 Transactions:
1. Salary Deposit  +$3,200  (Jan 30)
2. Rent Payment  -$1,100  (Jan 28)
3. Online Shopping  -$245  (Jan 25)
4. Freelance Payment  +$800  (Jan 22)
5. Electricity Bill  -$120  (Jan 20)
```

### Deployment And Tests

Requires an authenticated Salesforce org supporting API 68.0 with the Bank Account and Transaction metadata already deployed.
Run the VS Code task **Validate Bank Account Summary** for a check-only deployment with focused tests.
To deploy these components to your selected org:

```powershell
sf project deploy start --source-dir force-app/main/default/classes/BankAccountSummaryAction.cls --source-dir force-app/main/default/classes/BankAccountSummaryActionTest.cls --source-dir force-app/main/default/classes/BankAccountSummaryFlowTest.cls --source-dir force-app/main/default/flows/Fetch_Bank_Account_Summary.flow-meta.xml --source-dir force-app/main/default/permissionsets/Bank_Account_Summary_Access.permissionset-meta.xml --test-level RunSpecifiedTests --tests BankAccountSummaryActionTest --tests BankAccountSummaryFlowTest --api-version 68.0 --wait 10
```

`BankAccountSummaryActionTest` uses an in-memory fake selector; it performs no database IO.
`BankAccountSummaryFlowTest` is an isolated integration test with test-only records, covering matching, invalid inputs, empty history, transaction ordering, account isolation, and the five-record limit.
Use these same tests in CI and retain the deployment coverage report; changed-code coverage must meet the 80% target.
No new environment variables or runtime configuration are required. Deploy through your normal review and release pipeline.

### Agentforce Setup

1. In Setup, open **Agentforce Actions** and create a new action. Choose **Flow** as the reference action type and **Fetch Bank Account Summary** as the reference action. In some builders, this is available under the agent's action library as **New Action**.
2. Name it **Get Bank Account Summary**. Action instructions: "Retrieve the balance and latest five transactions for a bank account after collecting the account number and date of birth. Return accountSummary without changing amounts, signs, dates, or ordering."
3. Mark both inputs as required and enable **Collect data from user** where available. For `accountNumber`, use instructions "The user's bank account number, including the ACC- prefix." For `dateOfBirth`, use "The account holder's date of birth as a Date in YYYY-MM-DD format; ask for clarification if ambiguous."
4. For `accountSummary`, enable **Show in conversation**. Output instructions: "Display this text verbatim, preserving line breaks. Do not invent transactions or reveal the date of birth."
5. In **Agentforce Agents**, create or open an agent and add a **Bank Account Enquiries** topic (or subagent in the newer builder). Scope it to balances and recent transactions, and add this action from the library. Do not select the underlying Apex action directly: doing so bypasses the flow's account-number/birth-date check.
6. Topic instructions: "Collect both account number and date of birth before invoking Get Bank Account Summary. Never guess either value. Only return data from this action. If no account matches, ask the user to verify their details. Do not perform transfers or update records."
7. Assign **Bank Account Summary Access** to the user that executes agent actions. Ensure that user also has the platform permissions required by your agent type and record-level access to the intended Bank Account and Transaction records. This permission set does not grant View All or bypass sharing.
8. Test in Agentforce Preview with a valid match, incorrect birth date, unknown account number, no transactions, and more than five transactions. Activate the agent only after these checks succeed.

Account number plus date of birth is a lookup check, **not strong authentication**. Before exposing financial data to customers, enforce authenticated identity and authorized account ownership using trusted session context or your existing verification process. Do not rely on this flow alone for production customer authorization.
The flow does not override the caller's execution context, and its Apex query explicitly enforces user-mode permissions and sharing. Raw fault details and the supplied birth date are never included in the returned summary.

### Changes

- Added the bank account summary flow, bounded transaction query/formatter, read-only permission set, and focused unit/integration tests.

Now that you’ve created a Salesforce DX project, what’s next? Here are some documentation resources to get you started.

## How Do You Plan to Deploy Your Changes?

Do you want to deploy a set of changes, or create a self-contained application? Choose a [development model](https://developer.salesforce.com/tools/vscode/en/user-guide/development-models).

## Configure Your Salesforce DX Project

The `sfdx-project.json` file contains useful configuration information for your project. See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm) in the _Salesforce DX Developer Guide_ for details about this file.

## Read All About It

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
