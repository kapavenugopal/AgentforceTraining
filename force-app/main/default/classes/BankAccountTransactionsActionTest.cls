@IsTest
private class BankAccountTransactionsActionTest {
    private class FakeSelector extends BankAccountTransactionsAction.Selector {
        List<Bank_Account__c> accounts = new List<Bank_Account__c>();
        List<Transaction__c> entries = new List<Transaction__c>();
        Boolean failQuery = false;

        public override List<Bank_Account__c> findAccounts(Set<String> numbers) {
            if (failQuery) {
                throw new QueryException('Private details');
            }
            return accounts;
        }

        public override List<Transaction__c> findTransactions(Set<Id> accountIds, Date fromDate, Date toDate) {
            return entries;
        }
    }

    private static BankAccountTransactionsAction.Request request(String accountNumber, Date fromDate, Date toDate) {
        BankAccountTransactionsAction.Request input = new BankAccountTransactionsAction.Request();
        input.accountNumber = accountNumber;
        input.fromDate = fromDate;
        input.toDate = toDate;
        return input;
    }

    private static Date day(Integer value) {
        return Date.newInstance(2026, 1, value);
    }

    private static Id accountId(Integer suffix) {
        return Id.valueOf(Bank_Account__c.SObjectType.getDescribe().getKeyPrefix() +
            String.valueOf(suffix).leftPad(12, '0'));
    }

    private static FakeSelector configure() {
        FakeSelector selector = new FakeSelector();
        selector.accounts.add((Bank_Account__c) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{ 'Id' => accountId(1), 'Account_Number__c' => 'ACC-10045' }),
            Bank_Account__c.class
        ));
        BankAccountTransactionsAction.selector = selector;
        return selector;
    }

    @IsTest
    static void filtersEachRangeAndPreservesBulkOrder() {
        FakeSelector selector = configure();
        selector.entries.add(new Transaction__c(Bank_Account__c = accountId(1), Transaction_Date__c = day(3)));
        selector.entries.add(new Transaction__c(Bank_Account__c = accountId(1), Transaction_Date__c = day(2)));
        selector.entries.add(new Transaction__c(Bank_Account__c = accountId(1), Transaction_Date__c = day(1)));
        List<BankAccountTransactionsAction.Response> results = BankAccountTransactionsAction.getTransactions(
            new List<BankAccountTransactionsAction.Request>{
                request(' ACC-10045 ', day(1), day(2)), request('ACC-10045', day(3), day(3)),
                request('UNKNOWN', day(1), day(3)), request('ACC-10045', day(4), day(4))
            }
        );
        Assert.areEqual(4, results.size());
        Assert.areEqual(2, results[0].transactions.size());
        Assert.areEqual(day(2), results[0].transactions[0].Transaction_Date__c);
        Assert.areEqual(1, results[1].transactions.size());
        Assert.isNull(results[0].errorMessage);
        Assert.areEqual('Bank account not found or access unavailable.', results[2].errorMessage);
        Assert.areEqual(0, results[3].transactions.size());
        Assert.isNull(results[3].errorMessage);
    }

    @IsTest
    static void rejectsInvalidInputs() {
        List<BankAccountTransactionsAction.Response> results = BankAccountTransactionsAction.getTransactions(
            new List<BankAccountTransactionsAction.Request>{ null, request(' ', day(1), day(2)),
                request('ACC-10045', null, day(2)), request('ACC-10045', day(1), null),
                request('ACC-10045', day(3), day(1)) }
        );
        for (BankAccountTransactionsAction.Response result : results) {
            Assert.isNotNull(result.errorMessage);
            Assert.areEqual(0, result.transactions.size());
        }
        Assert.areEqual('From Date must be on or before To Date.', results[4].errorMessage);
        Assert.areEqual(0, BankAccountTransactionsAction.getTransactions(null).size());
        Assert.areEqual(0, BankAccountTransactionsAction.getTransactions(new List<BankAccountTransactionsAction.Request>()).size());
    }

    @IsTest
    static void handlesQueryFailuresAndOversizedResults() {
        FakeSelector selector = configure();
        selector.failQuery = true;
        Assert.areEqual('Unable to retrieve transactions with your current access.',
            BankAccountTransactionsAction.getTransactions(new List<BankAccountTransactionsAction.Request>{
                request('ACC-10045', day(1), day(3))
            })[0].errorMessage);
        selector.failQuery = false;
        for (Integer position = 0; position < 10001; position++) {
            selector.entries.add(new Transaction__c());
        }
        BankAccountTransactionsAction.Response result = BankAccountTransactionsAction.getTransactions(
            new List<BankAccountTransactionsAction.Request>{ request('ACC-10045', day(1), day(3)) }
        )[0];
        Assert.areEqual('Too many transactions. Please use a narrower date range.', result.errorMessage);
        Assert.areEqual(0, result.transactions.size());
    }

    @IsTest
    static void queriesOnlyLinkedTransactionsWithinInclusiveDates() {
        List<Bank_Account__c> accounts = new List<Bank_Account__c>{
            new Bank_Account__c(Name = 'Range test'), new Bank_Account__c(Name = 'Other account')
        };
        insert accounts;
        List<Transaction__c> entries = new List<Transaction__c>();
        for (Integer position = 1; position <= 4; position++) {
            entries.add(new Transaction__c(Bank_Account__c = accounts[0].Id,
                Transaction_Date__c = day(position), Transaction_Type__c = 'Credit', Amount__c = 10));
        }
        entries.add(new Transaction__c(Bank_Account__c = accounts[1].Id, Transaction_Date__c = day(2)));
        entries.add(new Transaction__c(Bank_Account__c = accounts[0].Id));
        insert entries;
        Bank_Account__c account = [SELECT Account_Number__c FROM Bank_Account__c WHERE Id = :accounts[0].Id];
        Test.startTest();
        BankAccountTransactionsAction.Response result = BankAccountTransactionsAction.getTransactions(
            new List<BankAccountTransactionsAction.Request>{ request(account.Account_Number__c, day(2), day(3)) }
        )[0];
        Test.stopTest();
        Assert.isNull(result.errorMessage);
        Assert.areEqual(2, result.transactions.size());
        Assert.areEqual(day(3), result.transactions[0].Transaction_Date__c);
        Assert.areEqual(day(2), result.transactions[1].Transaction_Date__c);
        Assert.areEqual(accounts[0].Id, result.transactions[0].Bank_Account__c);
        Assert.areEqual('Credit', result.transactions[0].Transaction_Type__c);
    }
}