public with sharing class BankAccountSuspiciousActivityAction {
    @TestVisible
    private static Datetime referenceTime;

    public class Request {
        @InvocableVariable(required=true label='Account Number')
        public String accountNumber;
    }

    public class Response {
        @InvocableVariable(label='Recent Transaction Count')
        public Integer recentTransactionCount;
        @InvocableVariable(label='Suspicious Activity Found')
        public Boolean suspiciousActivityFound;
        @InvocableVariable(label='Transactions' description='Up to 200 newest transactions created in the inclusive one-hour window. Includes CreatedDate timestamps.')
        public List<Transaction__c> transactions = new List<Transaction__c>();
        @InvocableVariable(label='Details Truncated')
        public Boolean detailsTruncated;
        @InvocableVariable(label='Window Start')
        public Datetime windowStart;
        @InvocableVariable(label='Window End')
        public Datetime windowEnd;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Check Bank Account Suspicious Activity' description='Read-only check for more than two transactions created in the last hour. Returns count and details; never changes account status.')
    public static List<Response> checkAccounts(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Datetime windowEnd = referenceTime == null ? System.now() : referenceTime;
        Datetime windowStart = windowEnd.addHours(-1);
        Set<String> accountNumbers = new Set<String>();
        for (Request input : requests) {
            Response result = new Response();
            results.add(result);
            if (input == null || String.isBlank(input.accountNumber)) {
                result.errorMessage = 'Provide a Bank Account Number.';
            } else {
                accountNumbers.add(input.accountNumber.trim());
            }
        }
        if (accountNumbers.isEmpty()) {
            return results;
        }
        Map<String, Bank_Account__c> accountsByNumber = new Map<String, Bank_Account__c>();
        Map<Id, List<Transaction__c>> detailsByAccount = new Map<Id, List<Transaction__c>>();
        Map<Id, Integer> counts = new Map<Id, Integer>();
        String queryError;
        try {
            Set<Id> accountIds = new Set<Id>();
            for (Bank_Account__c account : [
                SELECT Id, Account_Number__c,
                    (SELECT Id, Name, Bank_Account__c, Description__c, Amount__c,
                        Transaction_Type__c, Transaction_Date__c, CreatedDate
                     FROM Transactions__r
                     WHERE CreatedDate >= :windowStart AND CreatedDate <= :windowEnd
                     ORDER BY CreatedDate DESC, Id DESC LIMIT 200)
                FROM Bank_Account__c WHERE Account_Number__c IN :accountNumbers WITH USER_MODE
            ]) {
                accountsByNumber.put(account.Account_Number__c.toLowerCase(), account);
                accountIds.add(account.Id);
                List<Transaction__c> details = new List<Transaction__c>();
                for (Transaction__c entry : account.Transactions__r) {
                    details.add(entry);
                }
                detailsByAccount.put(account.Id, details);
            }
            if (!accountIds.isEmpty()) {
                for (AggregateResult groupResult : [
                    SELECT Bank_Account__c accountId, COUNT(Id) total
                    FROM Transaction__c
                    WHERE Bank_Account__c IN :accountIds
                        AND CreatedDate >= :windowStart AND CreatedDate <= :windowEnd
                    WITH USER_MODE GROUP BY Bank_Account__c
                ]) {
                    counts.put((Id) groupResult.get('accountId'), (Integer) groupResult.get('total'));
                }
            }
        } catch (QueryException failure) {
            queryError = 'Unable to check transactions with your current access.';
        }
        for (Integer position = 0; position < requests.size(); position++) {
            Response result = results[position];
            if (result.errorMessage != null) {
                continue;
            }
            Bank_Account__c account = accountsByNumber.get(requests[position].accountNumber.trim().toLowerCase());
            if (queryError != null) {
                result.errorMessage = queryError;
            } else if (account == null) {
                result.errorMessage = 'Bank account not found or access unavailable.';
            } else {
                result.windowStart = windowStart;
                result.windowEnd = windowEnd;
                result.recentTransactionCount = counts.containsKey(account.Id) ? counts.get(account.Id) : 0;
                result.suspiciousActivityFound = result.recentTransactionCount > 2;
                result.transactions.addAll(detailsByAccount.get(account.Id));
                result.detailsTruncated = result.recentTransactionCount > result.transactions.size();
                result.message = (result.suspiciousActivityFound ? 'Suspicious activity found' : 'No suspicious activity found') +
                    ': ' + result.recentTransactionCount + ' transactions were created in the last hour.' +
                    (result.suspiciousActivityFound ? ' Review the transaction details and confirm whether to temporarily suspend this account.' : '') +
                    (result.detailsTruncated ? ' Only the newest 200 transaction details are shown.' : '') +
                    ' Account status has not been changed.';
            }
        }
        return results;
    }
}