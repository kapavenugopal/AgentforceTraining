@IsTest
private class BankAccountSuspensionActionTest {
    private static BankAccountSuspiciousActivityAction.Request checkRequest(String accountNumber) {
        BankAccountSuspiciousActivityAction.Request input = new BankAccountSuspiciousActivityAction.Request();
        input.accountNumber = accountNumber;
        return input;
    }

    private static BankAccountSuspensionAction.Request statusRequest(String accountNumber, Boolean isActive, Boolean confirmed) {
        BankAccountSuspensionAction.Request input = new BankAccountSuspensionAction.Request();
        input.accountNumber = accountNumber;
        input.isActive = isActive;
        input.userConfirmed = confirmed;
        return input;
    }

    private static Bank_Account__c account() {
        Bank_Account__c record = new Bank_Account__c(Name = 'Suspension test');
        insert record;
        return [SELECT Id, Account_Number__c, Is_Active__c FROM Bank_Account__c WHERE Id = :record.Id];
    }

    @IsTest
    static void reportsThreeWithoutSuspendingThenRequiresConfirmation() {
        Bank_Account__c record = account();
        insert new List<Transaction__c>{
            new Transaction__c(Bank_Account__c = record.Id),
            new Transaction__c(Bank_Account__c = record.Id),
            new Transaction__c(Bank_Account__c = record.Id)
        };
        Test.startTest();
        BankAccountSuspiciousActivityAction.Response check = BankAccountSuspiciousActivityAction.checkAccounts(
            new List<BankAccountSuspiciousActivityAction.Request>{ checkRequest(' ' + record.Account_Number__c + ' ') }
        )[0];
        Assert.isNull(check.errorMessage);
        Assert.areEqual(3, check.recentTransactionCount);
        Assert.areEqual(3, check.transactions.size());
        Assert.areEqual(true, check.suspiciousActivityFound);
        Assert.isTrue(check.message.contains('Suspicious activity found'));
        Assert.areEqual(true, [SELECT Is_Active__c FROM Bank_Account__c WHERE Id = :record.Id].Is_Active__c);
        BankAccountSuspensionAction.Response result = BankAccountSuspensionAction.setAccountStatus(
            new List<BankAccountSuspensionAction.Request>{ statusRequest(record.Account_Number__c, false, false) }
        )[0];
        Assert.isNotNull(result.errorMessage);
        Assert.areEqual(true, [SELECT Is_Active__c FROM Bank_Account__c WHERE Id = :record.Id].Is_Active__c);
        result = BankAccountSuspensionAction.setAccountStatus(
            new List<BankAccountSuspensionAction.Request>{ statusRequest(record.Account_Number__c, false, true) }
        )[0];
        Assert.isNull(result.errorMessage);
        Assert.areEqual(false, result.isActive);
        Assert.areEqual(false, [SELECT Is_Active__c FROM Bank_Account__c WHERE Id = :record.Id].Is_Active__c);
        result = BankAccountSuspensionAction.setAccountStatus(
            new List<BankAccountSuspensionAction.Request>{ statusRequest(record.Account_Number__c, true, true) }
        )[0];
        Test.stopTest();
        Assert.isNull(result.errorMessage);
        Assert.areEqual(true, result.isActive);
        Assert.areEqual(true, [SELECT Is_Active__c FROM Bank_Account__c WHERE Id = :record.Id].Is_Active__c);
    }

    @IsTest
    static void appliesInclusiveHourBoundaryAndAccountIsolation() {
        Bank_Account__c first = account();
        Bank_Account__c second = account();
        Datetime referenceTime = Datetime.newInstance(2026, 10, 9, 12, 0, 0);
        BankAccountSuspiciousActivityAction.referenceTime = referenceTime;
        List<Transaction__c> entries = new List<Transaction__c>{
            new Transaction__c(Bank_Account__c = first.Id), new Transaction__c(Bank_Account__c = first.Id),
            new Transaction__c(Bank_Account__c = first.Id), new Transaction__c(Bank_Account__c = second.Id)
        };
        insert entries;
        Test.setCreatedDate(entries[0].Id, referenceTime.addMinutes(-60));
        Test.setCreatedDate(entries[1].Id, referenceTime.addMinutes(-30));
        Test.setCreatedDate(entries[2].Id, referenceTime.addMinutes(-60).addSeconds(-1));
        Test.setCreatedDate(entries[3].Id, referenceTime);
        List<BankAccountSuspiciousActivityAction.Response> results = BankAccountSuspiciousActivityAction.checkAccounts(
            new List<BankAccountSuspiciousActivityAction.Request>{ checkRequest(first.Account_Number__c),
                checkRequest(second.Account_Number__c) }
        );
        Assert.areEqual(2, results[0].recentTransactionCount);
        Assert.areEqual(1, results[1].recentTransactionCount);
        Assert.areEqual(false, results[0].suspiciousActivityFound);
        Assert.areEqual(false, results[1].suspiciousActivityFound);
        Assert.areEqual(referenceTime.addMinutes(-30), results[0].transactions[0].CreatedDate);
        update new Bank_Account__c(Id = first.Id, Is_Active__c = false);
        BankAccountSuspiciousActivityAction.checkAccounts(
            new List<BankAccountSuspiciousActivityAction.Request>{ checkRequest(first.Account_Number__c) }
        );
        Assert.areEqual(false, [SELECT Is_Active__c FROM Bank_Account__c WHERE Id = :first.Id].Is_Active__c);
    }

    @IsTest
    static void rejectsMissingUnknownAndConflictingRequests() {
        Bank_Account__c record = account();
        List<BankAccountSuspensionAction.Response> results = BankAccountSuspensionAction.setAccountStatus(
            new List<BankAccountSuspensionAction.Request>{ null, statusRequest(' ', false, true), statusRequest('UNKNOWN', false, true),
                statusRequest(record.Account_Number__c, false, true), statusRequest(record.Account_Number__c, true, true),
                statusRequest(record.Account_Number__c, null, true) }
        );
        for (BankAccountSuspensionAction.Response result : results) {
            Assert.isNotNull(result.errorMessage);
            Assert.isNull(result.isActive);
        }
        Assert.areEqual(0, BankAccountSuspensionAction.setAccountStatus(null).size());
        List<BankAccountSuspiciousActivityAction.Response> checks = BankAccountSuspiciousActivityAction.checkAccounts(
            new List<BankAccountSuspiciousActivityAction.Request>{ null, checkRequest(' '), checkRequest('UNKNOWN'), checkRequest(record.Account_Number__c) }
        );
        Assert.isNotNull(checks[0].errorMessage);
        Assert.isNotNull(checks[1].errorMessage);
        Assert.isNotNull(checks[2].errorMessage);
        Assert.areEqual(0, checks[3].recentTransactionCount);
        Assert.areEqual(false, checks[3].suspiciousActivityFound);
        Assert.areEqual(0, BankAccountSuspiciousActivityAction.checkAccounts(null).size());
    }

    @IsTest
    static void deniesUnauthorizedUserWithoutChangingStatus() {
        Bank_Account__c record = account();
        Profile restrictedProfile = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User restrictedUser = new User(
            Username = 'suspension.' + UserInfo.getOrganizationId() + '@example.invalid',
            Email = 'suspension@example.invalid', Alias = 'suspend', LastName = 'Restricted',
            ProfileId = restrictedProfile.Id, TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        System.runAs(restrictedUser) {
            BankAccountSuspensionAction.Response result = BankAccountSuspensionAction.setAccountStatus(
                new List<BankAccountSuspensionAction.Request>{ statusRequest(record.Account_Number__c, false, true) }
            )[0];
            Assert.isNotNull(result.errorMessage);
            Assert.isNull(result.isActive);
            Assert.isNotNull(BankAccountSuspiciousActivityAction.checkAccounts(
                new List<BankAccountSuspiciousActivityAction.Request>{ checkRequest(record.Account_Number__c) }
            )[0].errorMessage);
        }
        Assert.areEqual(true, [SELECT Is_Active__c FROM Bank_Account__c WHERE Id = :record.Id].Is_Active__c);
    }

    @IsTest
    static void preservesExactCountWhenDetailsAreTruncated() {
        Bank_Account__c record = account();
        List<Transaction__c> entries = new List<Transaction__c>();
        for (Integer position = 0; position < 201; position++) {
            entries.add(new Transaction__c(Bank_Account__c = record.Id, Description__c = 'Recent entry'));
        }
        insert entries;
        Test.startTest();
        BankAccountSuspiciousActivityAction.Response result = BankAccountSuspiciousActivityAction.checkAccounts(
            new List<BankAccountSuspiciousActivityAction.Request>{ checkRequest(record.Account_Number__c) }
        )[0];
        Test.stopTest();
        Assert.isNull(result.errorMessage);
        Assert.areEqual(201, result.recentTransactionCount);
        Assert.areEqual(200, result.transactions.size());
        Assert.areEqual(true, result.detailsTruncated);
        Assert.isTrue(result.message.contains('Only the newest 200'));
        Assert.areEqual(true, [SELECT Is_Active__c FROM Bank_Account__c WHERE Id = :record.Id].Is_Active__c);
    }
}