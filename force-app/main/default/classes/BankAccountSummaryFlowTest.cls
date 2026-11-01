@IsTest
private class BankAccountSummaryFlowTest {
    private static String runFlow(String accountNumber, Date birthDate) {
        Flow.Interview interview = Flow.Interview.createInterview('Fetch_Bank_Account_Summary', new Map<String, Object>{
            'accountNumber' => accountNumber, 'dateOfBirth' => birthDate
        });
        interview.start();
        return (String) interview.getVariableValue('accountSummary');
    }

    @IsTest
    static void returnsOnlyFiveNewestAssociatedTransactions() {
        Date birthDate = Date.newInstance(1990, 5, 15);
        List<Bank_Account__c> accounts = new List<Bank_Account__c>{
            new Bank_Account__c(Name = 'Summary test', Date_of_Birth__c = birthDate, Account_Type__c = 'Savings'),
            new Bank_Account__c(Name = 'Other account', Date_of_Birth__c = birthDate, Account_Type__c = 'Savings')
        };
        insert accounts;
        List<Transaction__c> transactions = new List<Transaction__c>();
        for (Integer day = 1; day <= 7; day++) {
            transactions.add(new Transaction__c(
                Bank_Account__c = accounts[0].Id, Description__c = 'Payment ' + day,
                Amount__c = 10, Transaction_Type__c = 'Credit',
                Transaction_Date__c = Date.newInstance(2026, 1, day)
            ));
        }
        transactions.add(new Transaction__c(
            Bank_Account__c = accounts[1].Id, Description__c = 'Other account payment',
            Amount__c = 999, Transaction_Type__c = 'Credit', Transaction_Date__c = Date.newInstance(2026, 2, 1)
        ));
        insert transactions;
        Bank_Account__c account = [SELECT Account_Number__c FROM Bank_Account__c WHERE Id = :accounts[0].Id];
        Test.startTest();
        String summary = runFlow('  ' + account.Account_Number__c + '  ', birthDate);
        Test.stopTest();
        Assert.isTrue(summary.startsWith('Account: ' + account.Account_Number__c + ' (Savings)'));
        Assert.isTrue(summary.contains('1. Payment 7  +$10  (Jan 7)'));
        Assert.isTrue(summary.contains('5. Payment 3  +$10  (Jan 3)'));
        Assert.isFalse(summary.contains('Payment 2'));
        Assert.isFalse(summary.contains('Other account payment'));
        Assert.areEqual(9, summary.split('\n').size());
    }

    @IsTest
    static void requiresBothInputsAndExactBirthDate() {
        Date birthDate = Date.newInstance(1990, 5, 15);
        Bank_Account__c account = new Bank_Account__c(
            Name = 'Summary test', Date_of_Birth__c = birthDate, Account_Type__c = 'Savings'
        );
        insert account;
        account = [SELECT Account_Number__c FROM Bank_Account__c WHERE Id = :account.Id];
        Test.startTest();
        Assert.areEqual('Please provide an account number and date of birth.', runFlow('   ', birthDate));
        Assert.areEqual('Please provide an account number and date of birth.', runFlow(account.Account_Number__c, null));
        Assert.areEqual('No matching bank account found for the supplied details.',
            runFlow(account.Account_Number__c, birthDate.addDays(1)));
        Assert.areEqual('No matching bank account found for the supplied details.', runFlow('UNKNOWN', birthDate));
        Assert.isTrue(runFlow(account.Account_Number__c, birthDate).endsWith('No transactions found.'));
        Test.stopTest();
    }
}