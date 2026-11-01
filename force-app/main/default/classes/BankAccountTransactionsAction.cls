public with sharing class BankAccountTransactionsAction {
    private static final Integer MAX_RESULTS = 10000;

    public class Request {
        @InvocableVariable(required=true label='Account Number' description='The bank account number, for example ACC-10045. Not a Salesforce record ID.')
        public String accountNumber;

        @InvocableVariable(required=true label='From Date' description='First transaction date to include, supplied as a Date in YYYY-MM-DD format.')
        public Date fromDate;

        @InvocableVariable(required=true label='To Date' description='Last transaction date to include, supplied as a Date in YYYY-MM-DD format.')
        public Date toDate;
    }

    public class Response {
        @InvocableVariable(label='Transactions' description='Matching Transaction records, newest first. Both date boundaries are included. Empty if no matches or an error occurs.')
        public List<Transaction__c> transactions = new List<Transaction__c>();

        @InvocableVariable(label='Error Message' description='Safe explanation when transactions cannot be returned. Null on success, including an empty history.')
        public String errorMessage;
    }

    public virtual class Selector {
        public virtual List<Bank_Account__c> findAccounts(Set<String> accountNumbers) {
            return [SELECT Id, Account_Number__c FROM Bank_Account__c
                WHERE Account_Number__c IN :accountNumbers WITH USER_MODE];
        }

        public virtual List<Transaction__c> findTransactions(Set<Id> accountIds, Date fromDate, Date toDate) {
            return [SELECT Id, Name, Bank_Account__c, Description__c, Amount__c,
                    Transaction_Type__c, Transaction_Date__c
                FROM Transaction__c
                WHERE Bank_Account__c IN :accountIds
                    AND Transaction_Date__c >= :fromDate AND Transaction_Date__c <= :toDate
                WITH USER_MODE
                ORDER BY Transaction_Date__c DESC, CreatedDate DESC, Id DESC
                LIMIT 10001];
        }
    }

    @TestVisible
    private static Selector selector = new Selector();

    @InvocableMethod(label='Get Bank Account Transactions' description='Find transactions for a bank account number between inclusive From Date and To Date, enforcing user permissions and sharing.')
    public static List<Response> getTransactions(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Set<String> accountNumbers = new Set<String>();
        Date earliestDate;
        Date latestDate;
        for (Request input : requests) {
            Response result = new Response();
            result.errorMessage = validationError(input);
            results.add(result);
            if (result.errorMessage == null) {
                accountNumbers.add(input.accountNumber.trim());
                earliestDate = earliestDate == null || input.fromDate < earliestDate ? input.fromDate : earliestDate;
                latestDate = latestDate == null || input.toDate > latestDate ? input.toDate : latestDate;
            }
        }
        if (accountNumbers.isEmpty()) {
            return results;
        }
        Map<String, Id> accountsByNumber = new Map<String, Id>();
        Map<Id, List<Transaction__c>> entriesByAccount = new Map<Id, List<Transaction__c>>();
        String queryError;
        try {
            Set<Id> accountIds = new Set<Id>();
            for (Bank_Account__c account : selector.findAccounts(accountNumbers)) {
                accountsByNumber.put(account.Account_Number__c.toLowerCase(), account.Id);
                accountIds.add(account.Id);
            }
            if (!accountIds.isEmpty()) {
                List<Transaction__c> entries = selector.findTransactions(accountIds, earliestDate, latestDate);
                if (entries.size() > MAX_RESULTS) {
                    queryError = 'Too many transactions. Please use a narrower date range.';
                } else {
                    for (Transaction__c entry : entries) {
                        if (!entriesByAccount.containsKey(entry.Bank_Account__c)) {
                            entriesByAccount.put(entry.Bank_Account__c, new List<Transaction__c>());
                        }
                        entriesByAccount.get(entry.Bank_Account__c).add(entry);
                    }
                }
            }
        } catch (QueryException failure) {
            queryError = 'Unable to retrieve transactions with your current access.';
        }
        for (Integer position = 0; position < requests.size(); position++) {
            Response result = results[position];
            if (result.errorMessage != null) {
                continue;
            }
            Request input = requests[position];
            Id accountId = accountsByNumber.get(input.accountNumber.trim().toLowerCase());
            if (queryError != null) {
                result.errorMessage = queryError;
            } else if (accountId == null) {
                result.errorMessage = 'Bank account not found or access unavailable.';
            } else if (entriesByAccount.containsKey(accountId)) {
                for (Transaction__c entry : entriesByAccount.get(accountId)) {
                    if (entry.Transaction_Date__c >= input.fromDate && entry.Transaction_Date__c <= input.toDate) {
                        result.transactions.add(entry);
                    }
                }
            }
        }
        return results;
    }

    private static String validationError(Request input) {
        if (input == null || String.isBlank(input.accountNumber) || input.fromDate == null || input.toDate == null) {
            return 'Provide an account number, From Date, and To Date.';
        }
        return input.fromDate > input.toDate ? 'From Date must be on or before To Date.' : null;
    }
}