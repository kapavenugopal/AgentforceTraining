public with sharing class TransactionTypeAction {
    public class Request {
        @InvocableVariable(required=true label='Transaction Record ID' description='The Salesforce record ID of the Transaction__c record to look up.')
        public Id transactionId;
    }

    public class Response {
        @InvocableVariable(label='Transaction Type' description='The stored Transaction Type, such as Credit or Debit. Empty when unavailable; check errorMessage.')
        public String transactionType;

        @InvocableVariable(label='Error Message' description='A safe explanation when the transaction type cannot be returned. Empty on success.')
        public String errorMessage;
    }

    public virtual class Selector {
        public virtual Map<Id, Transaction__c> fetch(Set<Id> transactionIds) {
            return new Map<Id, Transaction__c>([
                SELECT Id, Transaction_Type__c
                FROM Transaction__c
                WHERE Id IN :transactionIds
                WITH USER_MODE
            ]);
        }
    }

    @TestVisible
    private static Selector selector = new Selector();

    @InvocableMethod(label='Get Transaction Type' description='Retrieve the Transaction Type for a Transaction record ID, enforcing user permissions and record sharing.')
    public static List<Response> getTransactionType(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Set<Id> transactionIds = new Set<Id>();
        for (Request input : requests) {
            if (isValid(input)) {
                transactionIds.add(input.transactionId);
            }
        }
        Map<Id, Transaction__c> records = new Map<Id, Transaction__c>();
        if (!transactionIds.isEmpty()) {
            try {
                records = selector.fetch(transactionIds);
            } catch (QueryException failure) {
                records.clear();
            }
        }
        for (Request input : requests) {
            Response result = new Response();
            if (!isValid(input)) {
                result.errorMessage = 'Provide a valid Transaction record ID.';
            } else {
                Transaction__c entry = records.get(input.transactionId);
                if (entry == null) {
                    result.errorMessage = 'Transaction not found or access unavailable.';
                } else if (String.isBlank(entry.Transaction_Type__c)) {
                    result.errorMessage = 'Transaction Type is not set on this record.';
                } else {
                    result.transactionType = entry.Transaction_Type__c;
                }
            }
            results.add(result);
        }
        return results;
    }

    private static Boolean isValid(Request input) {
        return input != null && input.transactionId != null &&
            input.transactionId.getSObjectType() == Transaction__c.SObjectType;
    }
}