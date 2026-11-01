public with sharing class BankAccountSummaryAction {
    private static final String UNAVAILABLE = 'Unable to retrieve the account summary.';
    private static final List<String> MONTHS = new List<String>{
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    };

    public class Request {
        @InvocableVariable(required=true label='Bank Account ID')
        public Id bankAccountId;
    }

    public class Response {
        @InvocableVariable(label='Account Summary')
        public String accountSummary;
    }

    public class Snapshot {
        public Bank_Account__c account;
        public List<Transaction__c> transactions;
    }

    public virtual class Selector {
        public virtual Map<Id, Snapshot> fetch(Set<Id> accountIds) {
            Map<Id, Snapshot> snapshots = new Map<Id, Snapshot>();
            for (Bank_Account__c account : [
                SELECT Id, Account_Number__c, Account_Type__c, Current_Balance__c,
                    (SELECT Description__c, Amount__c, Transaction_Type__c, Transaction_Date__c
                     FROM Transactions__r
                     ORDER BY Transaction_Date__c DESC NULLS LAST, CreatedDate DESC, Id DESC
                     LIMIT 5)
                FROM Bank_Account__c
                WHERE Id IN :accountIds
                WITH USER_MODE
            ]) {
                Snapshot snapshot = new Snapshot();
                snapshot.account = account;
                snapshot.transactions = account.Transactions__r;
                snapshots.put(account.Id, snapshot);
            }
            return snapshots;
        }
    }

    @TestVisible
    private static Selector selector = new Selector();

    @InvocableMethod(label='Build Bank Account Summary' description='Return the balance and five newest visible transactions for matched bank accounts.')
    public static List<Response> summarize(List<Request> requests) {
        Set<Id> accountIds = new Set<Id>();
        for (Request input : requests) {
            if (input != null && input.bankAccountId != null) {
                accountIds.add(input.bankAccountId);
            }
        }
        Map<Id, Snapshot> snapshots = new Map<Id, Snapshot>();
        if (!accountIds.isEmpty()) {
            try {
                snapshots = selector.fetch(accountIds);
            } catch (QueryException failure) {
                snapshots.clear();
            }
        }
        List<Response> results = new List<Response>();
        for (Request input : requests) {
            Snapshot snapshot = input == null ? null : snapshots.get(input.bankAccountId);
            Response result = new Response();
            result.accountSummary = snapshot == null ? UNAVAILABLE : formatSummary(snapshot);
            results.add(result);
        }
        return results;
    }

    private static String formatSummary(Snapshot snapshot) {
        Bank_Account__c account = snapshot.account;
        List<String> lines = new List<String>{
            'Account: ' + account.Account_Number__c +
                (String.isBlank(account.Account_Type__c) ? '' : ' (' + account.Account_Type__c + ')'),
            'Balance: ' + money(account.Current_Balance__c, true),
            '',
            'Last 5 Transactions:'
        };
        Integer position = 0;
        for (Transaction__c entry : snapshot.transactions) {
            position++;
            String description = String.isBlank(entry.Description__c)
                ? 'Transaction' : entry.Description__c.replaceAll('[\\r\\n]+', ' ');
            String sign = entry.Transaction_Type__c == 'Debit' ? '-' : '+';
            Decimal amount = entry.Amount__c == null ? 0 : entry.Amount__c.abs();
            Date posted = entry.Transaction_Date__c;
            String dateLabel = posted == null ? 'Date unavailable' : MONTHS[posted.month() - 1] + ' ' + posted.day();
            lines.add(position + '. ' + description + '  ' + sign + money(amount, false) + '  (' + dateLabel + ')');
        }
        if (position == 0) {
            lines.add('No transactions found.');
        }
        return String.join(lines, '\n');
    }

    private static String money(Decimal amount, Boolean alwaysShowCents) {
        Decimal value = (amount == null ? 0 : amount).setScale(2);
        List<String> parts = String.valueOf(value.abs()).split('\\.');
        String whole = parts[0];
        String grouped = '';
        while (whole.length() > 3) {
            grouped = ',' + whole.right(3) + grouped;
            whole = whole.left(whole.length() - 3);
        }
        String cents = parts.size() > 1 ? parts[1] : '00';
        return (value < 0 ? '-$' : '$') + whole + grouped +
            (alwaysShowCents || cents != '00' ? '.' + cents : '');
    }
}