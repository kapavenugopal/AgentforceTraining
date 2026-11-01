@IsTest
private class BankAccountSummaryActionTest {
    private static final Id ACCOUNT_ID = 'a00000000000001AAA';

    private class FakeSelector extends BankAccountSummaryAction.Selector {
        Map<Id, BankAccountSummaryAction.Snapshot> snapshots = new Map<Id, BankAccountSummaryAction.Snapshot>();
        Boolean failQuery = false;

        public override Map<Id, BankAccountSummaryAction.Snapshot> fetch(Set<Id> accountIds) {
            if (failQuery) {
                throw new QueryException('Private database details');
            }
            return snapshots;
        }
    }

    private static FakeSelector configure(Decimal balance, List<Transaction__c> transactions) {
        FakeSelector selector = new FakeSelector();
        BankAccountSummaryAction.Snapshot snapshot = new BankAccountSummaryAction.Snapshot();
        snapshot.account = (Bank_Account__c) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Id' => ACCOUNT_ID, 'Account_Type__c' => 'Savings',
            'Current_Balance__c' => balance, 'Account_Number__c' => 'ACC-10045'
        }), Bank_Account__c.class);
        snapshot.transactions = transactions;
        selector.snapshots.put(ACCOUNT_ID, snapshot);
        BankAccountSummaryAction.selector = selector;
        return selector;
    }

    private static BankAccountSummaryAction.Request request(Id accountId) {
        BankAccountSummaryAction.Request input = new BankAccountSummaryAction.Request();
        input.bankAccountId = accountId;
        return input;
    }

    private static Transaction__c buildTransaction(String description, Decimal amount, String kind, Integer day) {
        return new Transaction__c(
            Description__c = description, Amount__c = amount,
            Transaction_Type__c = kind, Transaction_Date__c = Date.newInstance(2026, 1, day)
        );
    }

    @IsTest
    static void matchesRequestedFormat() {
        configure(24350, new List<Transaction__c>{
            buildTransaction('Salary Deposit', 3200, 'Credit', 30),
            buildTransaction('Rent Payment', 1100, 'Debit', 28),
            buildTransaction('Online Shopping', 245, 'Debit', 25),
            buildTransaction('Freelance Payment', 800, 'Credit', 22),
            buildTransaction('Electricity Bill', 120, 'Debit', 20)
        });
        List<BankAccountSummaryAction.Response> results = BankAccountSummaryAction.summarize(
            new List<BankAccountSummaryAction.Request>{ request(ACCOUNT_ID) }
        );
        Assert.areEqual(
            'Account: ACC-10045 (Savings)\nBalance: $24,350.00\n\nLast 5 Transactions:\n' +
            '1. Salary Deposit  +$3,200  (Jan 30)\n' +
            '2. Rent Payment  -$1,100  (Jan 28)\n' +
            '3. Online Shopping  -$245  (Jan 25)\n' +
            '4. Freelance Payment  +$800  (Jan 22)\n' +
            '5. Electricity Bill  -$120  (Jan 20)', results[0].accountSummary
        );
    }

    @IsTest
    static void handlesEmptyHistoryAndNegativeBalance() {
        configure(-1234567.8, new List<Transaction__c>());
        String summary = BankAccountSummaryAction.summarize(
            new List<BankAccountSummaryAction.Request>{ request(ACCOUNT_ID) }
        )[0].accountSummary;
        Assert.areEqual(
            'Account: ACC-10045 (Savings)\nBalance: -$1,234,567.80\n\nLast 5 Transactions:\nNo transactions found.',
            summary
        );
    }

    @IsTest
    static void handlesMissingOptionalFieldsAndCents() {
        configure(null, new List<Transaction__c>{
            new Transaction__c(Amount__c = 12.34, Transaction_Type__c = 'Debit'),
            new Transaction__c(Description__c = 'Line one\nLine two', Transaction_Type__c = 'Credit')
        });
        String summary = BankAccountSummaryAction.summarize(
            new List<BankAccountSummaryAction.Request>{ request(ACCOUNT_ID) }
        )[0].accountSummary;
        Assert.isTrue(summary.contains('Balance: $0.00'));
        Assert.isTrue(summary.contains('1. Transaction  -$12.34  (Date unavailable)'));
        Assert.isTrue(summary.contains('2. Line one Line two  +$0  (Date unavailable)'));
    }

    @IsTest
    static void preservesBulkResponseOrderAndHandlesMissingAccounts() {
        configure(10, new List<Transaction__c>());
        List<BankAccountSummaryAction.Response> results = BankAccountSummaryAction.summarize(
            new List<BankAccountSummaryAction.Request>{ request(null), request(ACCOUNT_ID), request(null) }
        );
        Assert.areEqual(3, results.size());
        Assert.areEqual('Unable to retrieve the account summary.', results[0].accountSummary);
        Assert.isTrue(results[1].accountSummary.startsWith('Account: ACC-10045'));
        Assert.areEqual(results[0].accountSummary, results[2].accountSummary);
        BankAccountSummaryAction.selector = new FakeSelector();
        Assert.areEqual(results[0].accountSummary, BankAccountSummaryAction.summarize(
            new List<BankAccountSummaryAction.Request>{ request(ACCOUNT_ID) }
        )[0].accountSummary);
    }

    @IsTest
    static void doesNotExposeQueryErrors() {
        FakeSelector selector = configure(10, new List<Transaction__c>());
        selector.failQuery = true;
        Assert.areEqual('Unable to retrieve the account summary.', BankAccountSummaryAction.summarize(
            new List<BankAccountSummaryAction.Request>{ request(ACCOUNT_ID) }
        )[0].accountSummary);
    }
}