public class TransactionTriggerHandler {
	  public static void updateBankBalance(List<Transaction__c> transactions) {

        Set<Id> bankIds = new Set<Id>();
        for (Transaction__c t : transactions) {
            if (t.Bank_Account__c != null && t.Amount__c != null) {
                bankIds.add(t.Bank_Account__c);
            }
        }

        if (bankIds.isEmpty()) return;

       
        Map<Id, Bank_Account__c> bankMap = new Map<Id, Bank_Account__c>(
            [SELECT Id, Current_Balance__c FROM Bank_Account__c WHERE Id IN :bankIds FOR UPDATE]
        );
          
        for (Transaction__c t : transactions) {
            Bank_Account__c bank = bankMap.get(t.Bank_Account__c);

            if (bank == null) continue;
            
            if (bank.Current_Balance__c == null) {
                bank.Current_Balance__c = 0;
            }

            if (t.Transaction_Type__c == 'Debit') {
                bank.Current_Balance__c -= t.Amount__c;
            }
            else if (t.Transaction_Type__c == 'Credit') {
                bank.Current_Balance__c += t.Amount__c;
            }
        }

        update bankMap.values();
    }
}