@isTest
private class AccountTriggerTest {
    @TestSetup
    static void makeData() {
        insert new Account(Name = 'Test Co');
    }
    @isTest
    static void keepsDefaultIndustry() {
        // Arrange
        Account acc = [SELECT Id FROM Account LIMIT 1];
        // Act
        Test.startTest();
        update acc;
        Test.stopTest();
        // Assert
        Account r = [SELECT Industry FROM Account
                     WHERE Id = :acc.Id];
        System.assertEquals('Other', r.Industry);
    }
}