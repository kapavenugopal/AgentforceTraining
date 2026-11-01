trigger TransactionTrigger on Transaction__c (after insert) {
if (Trigger.isAfter && Trigger.isInsert) {
        TransactionTriggerHandler.updateBankBalance(Trigger.new);
    }
}