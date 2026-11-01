@IsTest
private class TransactionTypeActionTest {
    private class FakeSelector extends TransactionTypeAction.Selector {
        Map<Id, Transaction__c> records = new Map<Id, Transaction__c>();
        Boolean failQuery = false;

        public override Map<Id, Transaction__c> fetch(Set<Id> transactionIds) {
            if (failQuery) {
                throw new QueryException('Sensitive internal details');
            }
            return records;
        }
    }

    private static Id fakeId(Integer suffix) {
        return Id.valueOf(Transaction__c.SObjectType.getDescribe().getKeyPrefix() +
            String.valueOf(suffix).leftPad(12, '0'));
    }

    private static TransactionTypeAction.Request request(Id recordId) {
        TransactionTypeAction.Request input = new TransactionTypeAction.Request();
        input.transactionId = recordId;
        return input;
    }

    @IsTest
    static void returnsTypesInInputOrderIncludingDuplicates() {
        FakeSelector selector = new FakeSelector();
        selector.records.put(fakeId(1), new Transaction__c(Id = fakeId(1), Transaction_Type__c = 'Credit'));
        selector.records.put(fakeId(2), new Transaction__c(Id = fakeId(2), Transaction_Type__c = 'Debit'));
        TransactionTypeAction.selector = selector;
        List<TransactionTypeAction.Response> results = TransactionTypeAction.getTransactionType(
            new List<TransactionTypeAction.Request>{ request(fakeId(2)), request(fakeId(1)), request(fakeId(2)) }
        );
        Assert.areEqual(3, results.size());
        Assert.areEqual('Debit', results[0].transactionType);
        Assert.areEqual('Credit', results[1].transactionType);
        Assert.areEqual('Debit', results[2].transactionType);
        Assert.isNull(results[0].errorMessage);
    }

    @IsTest
    static void handlesInvalidMissingAndBlankRecords() {
        FakeSelector selector = new FakeSelector();
        selector.records.put(fakeId(1), new Transaction__c(Id = fakeId(1)));
        TransactionTypeAction.selector = selector;
        List<TransactionTypeAction.Response> results = TransactionTypeAction.getTransactionType(
            new List<TransactionTypeAction.Request>{ null, request(null), request('001000000000001'),
                request(fakeId(2)), request(fakeId(1)) }
        );
        Assert.areEqual(5, results.size());
        for (Integer position = 0; position < 3; position++) {
            Assert.areEqual('Provide a valid Transaction record ID.', results[position].errorMessage);
            Assert.isNull(results[position].transactionType);
        }
        Assert.areEqual('Transaction not found or access unavailable.', results[3].errorMessage);
        Assert.areEqual('Transaction Type is not set on this record.', results[4].errorMessage);
        Assert.areEqual(0, TransactionTypeAction.getTransactionType(null).size());
        Assert.areEqual(0, TransactionTypeAction.getTransactionType(new List<TransactionTypeAction.Request>()).size());
    }

    @IsTest
    static void doesNotExposePermissionOrQueryErrors() {
        FakeSelector selector = new FakeSelector();
        selector.failQuery = true;
        TransactionTypeAction.selector = selector;
        TransactionTypeAction.Response result = TransactionTypeAction.getTransactionType(
            new List<TransactionTypeAction.Request>{ request(fakeId(1)) }
        )[0];
        Assert.isNull(result.transactionType);
        Assert.areEqual('Transaction not found or access unavailable.', result.errorMessage);
    }

    @IsTest
    static void queriesTheRequestedTransaction() {
        Transaction__c entry = new Transaction__c(Transaction_Type__c = 'Debit');
        insert entry;
        Test.startTest();
        TransactionTypeAction.Response result = TransactionTypeAction.getTransactionType(
            new List<TransactionTypeAction.Request>{ request(entry.Id) }
        )[0];
        Test.stopTest();
        Assert.areEqual('Debit', result.transactionType);
        Assert.isNull(result.errorMessage);
    }
}