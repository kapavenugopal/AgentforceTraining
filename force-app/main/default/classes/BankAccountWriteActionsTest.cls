@IsTest
private class BankAccountWriteActionsTest {
    private static CreateBankAccountAction.Request accountRequest(String nameValue) {
        CreateBankAccountAction.Request input = new CreateBankAccountAction.Request();
        input.bankAccountName = nameValue;
        input.accountType = 'Savings';
        input.dateOfBirth = Date.newInstance(1990, 1, 1);
        return input;
    }

    private static AddBankAccountTransactionAction.Request entryRequest(String accountNumber, String kind, Decimal amount) {
        AddBankAccountTransactionAction.Request input = new AddBankAccountTransactionAction.Request();
        input.accountNumber = accountNumber;
        input.transactionType = kind;
        input.amount = amount;
        input.transactionDate = Date.newInstance(2026, 1, 1);
        input.description = 'Action test';
        return input;
    }

    @IsTest
    static void createsAccountsAndAppliesCreditDebitExactlyOnce() {
        Test.startTest();
        List<CreateBankAccountAction.Response> accounts = CreateBankAccountAction.createAccounts(
            new List<CreateBankAccountAction.Request>{ accountRequest('First account'), accountRequest('Second account') }
        );
        Assert.areEqual(2, accounts.size());
        Assert.isNull(accounts[0].errorMessage);
        Assert.isNotNull(accounts[0].bankAccountId);
        Assert.isNotNull(accounts[0].accountNumber);
        Assert.areEqual(0, accounts[0].currentBalance);
        List<AddBankAccountTransactionAction.Response> results = AddBankAccountTransactionAction.addTransactions(
            new List<AddBankAccountTransactionAction.Request>{
                entryRequest(accounts[0].accountNumber, 'Credit', 100),
                entryRequest(accounts[0].accountNumber, 'Debit', 25.50),
                entryRequest(accounts[1].accountNumber, 'Credit', 30)
            }
        );
        Test.stopTest();
        Assert.areEqual(3, results.size());
        for (AddBankAccountTransactionAction.Response result : results) {
            Assert.isNull(result.errorMessage);
            Assert.isNotNull(result.transactionId);
        }
        Assert.areEqual(74.50, results[0].currentBalance);
        Assert.areEqual(74.50, results[1].currentBalance);
        Assert.areEqual(30, results[2].currentBalance);
        Bank_Account__c account = [SELECT Name, Account_Type__c, Date_of_Birth__c, Current_Balance__c
            FROM Bank_Account__c WHERE Id = :accounts[0].bankAccountId];
        Assert.areEqual('First account', account.Name);
        Assert.areEqual('Savings', account.Account_Type__c);
        Assert.areEqual(Date.newInstance(1990, 1, 1), account.Date_of_Birth__c);
        Assert.areEqual(74.50, account.Current_Balance__c);
        Transaction__c entry = [SELECT Bank_Account__c, Description__c, Transaction_Date__c, Amount__c, Transaction_Type__c
            FROM Transaction__c WHERE Id = :results[1].transactionId];
        Assert.areEqual(accounts[0].bankAccountId, entry.Bank_Account__c);
        Assert.areEqual('Debit', entry.Transaction_Type__c);
        Assert.areEqual(25.50, entry.Amount__c);
    }

    @IsTest
    static void rejectsInvalidAccountInputsWithoutWriting() {
        CreateBankAccountAction.Request badType = accountRequest('Bad type');
        badType.accountType = 'Invalid';
        CreateBankAccountAction.Request noDate = accountRequest('No date');
        noDate.dateOfBirth = null;
        List<CreateBankAccountAction.Response> results = CreateBankAccountAction.createAccounts(
            new List<CreateBankAccountAction.Request>{ null, accountRequest(' '), badType, noDate }
        );
        for (CreateBankAccountAction.Response result : results) {
            Assert.isNotNull(result.errorMessage);
            Assert.isNull(result.bankAccountId);
        }
        Assert.areEqual(0, [SELECT count() FROM Bank_Account__c]);
        Assert.areEqual(0, CreateBankAccountAction.createAccounts(null).size());
    }

    @IsTest
    static void rejectsInvalidTransactionInputsWithoutWriting() {
        AddBankAccountTransactionAction.Request noDate = entryRequest('ACC-00001', 'Credit', 10);
        noDate.transactionDate = null;
        List<AddBankAccountTransactionAction.Response> results = AddBankAccountTransactionAction.addTransactions(
            new List<AddBankAccountTransactionAction.Request>{ null, entryRequest(' ', 'Credit', 10),
                entryRequest('ACC-00001', 'Invalid', 10), entryRequest('ACC-00001', 'Debit', -10),
                entryRequest('ACC-00001', 'Credit', 0), entryRequest('ACC-00001', 'Credit', 1.001),
                noDate, entryRequest('UNKNOWN', 'Credit', 10) }
        );
        for (AddBankAccountTransactionAction.Response result : results) {
            Assert.isNotNull(result.errorMessage);
            Assert.isNull(result.transactionId);
        }
        Assert.areEqual(0, [SELECT count() FROM Transaction__c]);
        Assert.areEqual(0, AddBankAccountTransactionAction.addTransactions(null).size());
    }

    @IsTest
    static void debitCanProduceNegativeBalanceAndHandlesNullOpeningBalance() {
        Bank_Account__c account = new Bank_Account__c(Name = 'Null balance');
        insert account;
        account = [SELECT Account_Number__c FROM Bank_Account__c WHERE Id = :account.Id];
        AddBankAccountTransactionAction.Response result = AddBankAccountTransactionAction.addTransactions(
            new List<AddBankAccountTransactionAction.Request>{ entryRequest(account.Account_Number__c, 'Debit', 20) }
        )[0];
        Assert.isNull(result.errorMessage);
        Assert.areEqual(-20, result.currentBalance);
    }

    @IsTest
    static void rollsBackTransactionsWhenOneWriteFails() {
        CreateBankAccountAction.Response account = CreateBankAccountAction.createAccounts(
            new List<CreateBankAccountAction.Request>{ accountRequest('Rollback account') }
        )[0];
        List<AddBankAccountTransactionAction.Response> results = AddBankAccountTransactionAction.addTransactions(
            new List<AddBankAccountTransactionAction.Request>{
                entryRequest(account.accountNumber, 'Credit', 10),
                entryRequest(account.accountNumber, 'Credit', Decimal.valueOf('999999999999999999999999999'))
            }
        );
        for (AddBankAccountTransactionAction.Response result : results) {
            Assert.isNotNull(result.errorMessage);
            Assert.isNull(result.transactionId);
        }
        Assert.areEqual(0, [SELECT count() FROM Transaction__c]);
        Assert.areEqual(0, [SELECT Current_Balance__c FROM Bank_Account__c WHERE Id = :account.bankAccountId].Current_Balance__c);
    }

    @IsTest
    static void rejectsWritesForUserWithoutObjectAccess() {
        Profile restrictedProfile = [SELECT Id FROM Profile
            WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User restrictedUser = new User(
            Username = 'bank.actions.' + UserInfo.getOrganizationId() + '@example.invalid',
            Email = 'bank.actions@example.invalid', Alias = 'banktest', LastName = 'Restricted',
            ProfileId = restrictedProfile.Id, TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert restrictedUser;
        System.runAs(restrictedUser) {
            CreateBankAccountAction.Response account = CreateBankAccountAction.createAccounts(
                new List<CreateBankAccountAction.Request>{ accountRequest('Denied') }
            )[0];
            Assert.isNotNull(account.errorMessage);
            Assert.isNull(account.bankAccountId);
            AddBankAccountTransactionAction.Response entry = AddBankAccountTransactionAction.addTransactions(
                new List<AddBankAccountTransactionAction.Request>{ entryRequest('ACC-00001', 'Credit', 10) }
            )[0];
            Assert.isNotNull(entry.errorMessage);
            Assert.isNull(entry.transactionId);
        }
    }
}