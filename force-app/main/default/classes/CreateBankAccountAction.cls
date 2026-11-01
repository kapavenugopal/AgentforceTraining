public with sharing class CreateBankAccountAction {
    public class Request {
        @InvocableVariable(required=true label='Bank Account Name')
        public String bankAccountName;
        @InvocableVariable(required=true label='Account Type' description='An active Bank Account Account Type picklist value.')
        public String accountType;
        @InvocableVariable(required=true label='Date of Birth')
        public Date dateOfBirth;
    }

    public class Response {
        @InvocableVariable(label='Bank Account ID')
        public Id bankAccountId;
        @InvocableVariable(label='Account Number')
        public String accountNumber;
        @InvocableVariable(label='Current Balance')
        public Decimal currentBalance;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Create Bank Account' description='Create a Bank Account from name, account type, and date of birth with a zero opening balance. Requires explicit user confirmation.')
    public static List<Response> createAccounts(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Set<String> allowedTypes = new Set<String>();
        for (Schema.PicklistEntry option : Bank_Account__c.Account_Type__c.getDescribe().getPicklistValues()) {
            if (option.isActive()) {
                allowedTypes.add(option.getValue());
            }
        }
        List<Bank_Account__c> accounts = new List<Bank_Account__c>();
        List<Integer> positions = new List<Integer>();
        for (Request input : requests) {
            Response result = new Response();
            results.add(result);
            if (input == null || String.isBlank(input.bankAccountName) || String.isBlank(input.accountType) || input.dateOfBirth == null) {
                result.errorMessage = 'Provide Bank Account Name, Account Type, and Date of Birth.';
            } else if (input.bankAccountName.trim().length() > Bank_Account__c.Name.getDescribe().getLength()) {
                result.errorMessage = 'Bank Account Name is too long.';
            } else if (!allowedTypes.contains(input.accountType.trim())) {
                result.errorMessage = 'Provide a valid Account Type.';
            } else {
                accounts.add(new Bank_Account__c(Name = input.bankAccountName.trim(),
                    Account_Type__c = input.accountType.trim(), Date_of_Birth__c = input.dateOfBirth,
                    Current_Balance__c = 0));
                positions.add(results.size() - 1);
            }
        }
        if (accounts.isEmpty()) {
            return results;
        }
        Savepoint checkpoint = Database.setSavepoint();
        try {
            Database.insert(accounts, true, AccessLevel.USER_MODE);
            Set<Id> accountIds = new Map<Id, Bank_Account__c>(accounts).keySet();
            Map<Id, Bank_Account__c> savedAccounts = new Map<Id, Bank_Account__c>([
                SELECT Id, Account_Number__c, Current_Balance__c FROM Bank_Account__c
                WHERE Id IN :accountIds WITH USER_MODE
            ]);
            for (Integer position = 0; position < accounts.size(); position++) {
                Bank_Account__c saved = savedAccounts.get(accounts[position].Id);
                if (saved == null) {
                    throw new QueryException('Created account is not accessible.');
                }
                Response result = results[positions[position]];
                result.bankAccountId = saved.Id;
                result.accountNumber = saved.Account_Number__c;
                result.currentBalance = saved.Current_Balance__c;
            }
        } catch (Exception failure) {
            Database.rollback(checkpoint);
            for (Integer position : positions) {
                Response result = results[position];
                result.bankAccountId = null;
                result.accountNumber = null;
                result.currentBalance = null;
                result.errorMessage = 'Unable to create bank accounts. Check your access and supplied details. No accounts were created by this action.';
            }
        }
        return results;
    }
}