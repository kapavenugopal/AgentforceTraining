public with sharing class BankAccountSuspensionAction {
    public class Request {
        @InvocableVariable(required=true label='Account Number')
        public String accountNumber;
        @InvocableVariable(required=true label='Is Active' description='False temporarily suspends the account; true reactivates it.')
        public Boolean isActive;
        @InvocableVariable(required=true label='User Confirmed' description='Set true only after the user explicitly confirms this account status change.')
        public Boolean userConfirmed;
    }

    public class Response {
        @InvocableVariable(label='Is Active')
        public Boolean isActive;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Set Bank Account Active Status' description='Suspend or reactivate the specified Bank Account only after explicit user confirmation. Use the read-only suspicious activity action first for suspicious-transaction enquiries.')
    public static List<Response> setAccountStatus(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Map<String, Boolean> desiredStatuses = new Map<String, Boolean>();
        Set<String> conflicts = new Set<String>();
        Set<String> accountNumbers = new Set<String>();
        for (Request input : requests) {
            Response result = new Response();
            results.add(result);
            if (input == null || String.isBlank(input.accountNumber) || input.isActive == null) {
                result.errorMessage = 'Provide Bank Account Number and the desired Is Active value.';
            } else if (input.userConfirmed != true) {
                result.errorMessage = 'Explicit user confirmation is required before changing account status.';
            } else {
                String key = input.accountNumber.trim().toLowerCase();
                if (desiredStatuses.containsKey(key) && desiredStatuses.get(key) != input.isActive) {
                    conflicts.add(key);
                }
                desiredStatuses.put(key, input.isActive);
                accountNumbers.add(input.accountNumber.trim());
            }
        }
        if (accountNumbers.isEmpty()) {
            return results;
        }
        Savepoint checkpoint = Database.setSavepoint();
        try {
            Map<String, Bank_Account__c> accountsByNumber = new Map<String, Bank_Account__c>();
            List<Bank_Account__c> updates = new List<Bank_Account__c>();
            for (Bank_Account__c account : [SELECT Id, Account_Number__c, Is_Active__c
                FROM Bank_Account__c WHERE Account_Number__c IN :accountNumbers WITH USER_MODE]) {
                String key = account.Account_Number__c.toLowerCase();
                accountsByNumber.put(key, account);
                if (!conflicts.contains(key)) {
                    updates.add(new Bank_Account__c(Id = account.Id, Is_Active__c = desiredStatuses.get(key)));
                }
            }
            if (!updates.isEmpty()) {
                Database.update(updates, true, AccessLevel.USER_MODE);
            }
            for (Integer position = 0; position < requests.size(); position++) {
                Response result = results[position];
                if (result.errorMessage != null) {
                    continue;
                }
                Request input = requests[position];
                String key = input.accountNumber.trim().toLowerCase();
                if (conflicts.contains(key)) {
                    result.errorMessage = 'Conflicting status changes were requested for this account. No change was made to it.';
                } else if (!accountsByNumber.containsKey(key)) {
                    result.errorMessage = 'Bank account not found or access unavailable.';
                } else {
                    result.isActive = input.isActive;
                    result.message = input.isActive ? 'Bank account reactivated.' : 'Bank account temporarily suspended (Is Active is false).';
                }
            }
        } catch (Exception failure) {
            Database.rollback(checkpoint);
            for (Response result : results) {
                if (result.errorMessage == null) {
                    result.isActive = null;
                    result.message = null;
                    result.errorMessage = 'Unable to change account status with your current access. No status changes were made.';
                }
            }
        }
        return results;
    }
}