public with sharing class AddBankAccountTransactionAction {
    public class Request {
        @InvocableVariable(required=true label='Account Number')
        public String accountNumber;
        @InvocableVariable(required=true label='Transaction Type' description='Credit adds to balance; Debit subtracts from balance.')
        public String transactionType;
        @InvocableVariable(required=true label='Amount' description='Positive amount with at most two decimal places.')
        public Decimal amount;
        @InvocableVariable(required=true label='Transaction Date')
        public Date transactionDate;
        @InvocableVariable(label='Description')
        public String description;
    }

    public class Response {
        @InvocableVariable(label='Transaction ID')
        public Id transactionId;
        @InvocableVariable(label='Bank Account ID')
        public Id bankAccountId;
        @InvocableVariable(label='Current Balance' description='Account balance after all successful transactions in this action batch.')
        public Decimal currentBalance;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Add Bank Account Transaction' description='Create a linked Credit or Debit transaction. The existing trigger updates the balance once. Requires explicit user confirmation.')
    public static List<Response> addTransactions(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Set<String> accountNumbers = new Set<String>();
        for (Request input : requests) {
            Response result = new Response();
            result.errorMessage = validationError(input);
            results.add(result);
            if (result.errorMessage == null) {
                accountNumbers.add(input.accountNumber.trim());
            }
        }
        if (accountNumbers.isEmpty()) {
            return results;
        }
        List<Integer> positions = new List<Integer>();
        List<Transaction__c> entries = new List<Transaction__c>();
        Savepoint checkpoint = Database.setSavepoint();
        try {
            if (!Bank_Account__c.SObjectType.getDescribe().isUpdateable() ||
                !Bank_Account__c.Current_Balance__c.getDescribe().isUpdateable()) {
                throw new SecurityException('Balance update access required.');
            }
            Map<String, Bank_Account__c> accountsByNumber = new Map<String, Bank_Account__c>();
            for (Bank_Account__c account : [SELECT Id, Account_Number__c, Current_Balance__c
                FROM Bank_Account__c WHERE Account_Number__c IN :accountNumbers WITH USER_MODE]) {
                accountsByNumber.put(account.Account_Number__c.toLowerCase(), account);
            }
            for (Integer position = 0; position < requests.size(); position++) {
                if (results[position].errorMessage != null) {
                    continue;
                }
                Request input = requests[position];
                Bank_Account__c account = accountsByNumber.get(input.accountNumber.trim().toLowerCase());
                if (account == null) {
                    results[position].errorMessage = 'Bank account not found or access unavailable.';
                } else {
                    entries.add(new Transaction__c(Bank_Account__c = account.Id,
                        Transaction_Type__c = input.transactionType.trim(), Amount__c = input.amount,
                        Transaction_Date__c = input.transactionDate, Description__c = input.description));
                    positions.add(position);
                }
            }
            if (!entries.isEmpty()) {
                Database.insert(entries, true, AccessLevel.USER_MODE);
                Set<Id> accountIds = new Set<Id>();
                for (Transaction__c entry : entries) {
                    accountIds.add(entry.Bank_Account__c);
                }
                Map<Id, Bank_Account__c> savedAccounts = new Map<Id, Bank_Account__c>([
                    SELECT Id, Current_Balance__c FROM Bank_Account__c WHERE Id IN :accountIds WITH USER_MODE
                ]);
                for (Integer position = 0; position < entries.size(); position++) {
                    Transaction__c entry = entries[position];
                    Bank_Account__c account = savedAccounts.get(entry.Bank_Account__c);
                    if (account == null) {
                        throw new QueryException('Updated account is not accessible.');
                    }
                    Response result = results[positions[position]];
                    result.transactionId = entry.Id;
                    result.bankAccountId = account.Id;
                    result.currentBalance = account.Current_Balance__c;
                }
            }
        } catch (Exception failure) {
            Database.rollback(checkpoint);
            for (Response result : results) {
                if (result.errorMessage == null) {
                    result.transactionId = null;
                    result.bankAccountId = null;
                    result.currentBalance = null;
                    result.errorMessage = 'Unable to add transactions. Check your access and supplied details. No transactions were added by this action.';
                }
            }
        }
        return results;
    }

    private static String validationError(Request input) {
        if (input == null || String.isBlank(input.accountNumber) || String.isBlank(input.transactionType) ||
            input.amount == null || input.transactionDate == null) {
            return 'Provide Account Number, Transaction Type, Amount, and Transaction Date.';
        }
        if (input.transactionType.trim() != 'Credit' && input.transactionType.trim() != 'Debit') {
            return 'Transaction Type must be Credit or Debit.';
        }
        if (input.amount <= 0 || input.amount != input.amount.setScale(2)) {
            return 'Amount must be positive with at most two decimal places.';
        }
        if (input.description != null && input.description.length() > Transaction__c.Description__c.getDescribe().getLength()) {
            return 'Description is too long.';
        }
        return null;
    }
}