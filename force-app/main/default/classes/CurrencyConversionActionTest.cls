@IsTest
private class CurrencyConversionActionTest {
    private class ConversionMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        String expectedEndpoint;
        Boolean failCallout = false;
        Integer calls = 0;

        ConversionMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest outbound) {
            calls++;
            Assert.areEqual('GET', outbound.getMethod());
            Assert.areEqual('application/json', outbound.getHeader('Accept'));
            if (expectedEndpoint != null) {
                Assert.areEqual(expectedEndpoint, outbound.getEndpoint());
            }
            if (failCallout) {
                throw new CalloutException('Sensitive endpoint and API key');
            }
            HttpResponse inbound = new HttpResponse();
            inbound.setStatusCode(statusCode);
            inbound.setBody(body);
            return inbound;
        }
    }

    private static CurrencyConversionAction.Request request(String fromCode, String toCode, Decimal amount) {
        CurrencyConversionAction.Request input = new CurrencyConversionAction.Request();
        input.fromCurrency = fromCode;
        input.toCurrency = toCode;
        input.amount = amount;
        return input;
    }

    private static String successBody() {
        return '{"result":"success","base_code":"EUR","target_code":"GBP",' +
            '"conversion_rate":0.8412,"conversion_result":84.12}';
    }

    @IsTest
    static void convertsAmountAndNormalizesCodes() {
        ConversionMock mock = new ConversionMock(200, successBody());
        mock.expectedEndpoint = 'callout:ExchangeRate_API/pair/EUR/GBP/100';
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        CurrencyConversionAction.Response result = CurrencyConversionAction.convertCurrency(
            new List<CurrencyConversionAction.Request>{ request(' eur ', 'gbp', 100) }
        )[0];
        Test.stopTest();
        Assert.areEqual('EUR', result.fromCurrency);
        Assert.areEqual('GBP', result.toCurrency);
        Assert.areEqual(100, result.originalAmount);
        Assert.areEqual(0.8412, result.exchangeRate);
        Assert.areEqual(84.12, result.convertedAmount);
        Assert.isNull(result.errorMessage);
        Assert.areEqual(1, mock.calls);
    }

    @IsTest
    static void rejectsInvalidInputsWithoutCallouts() {
        ConversionMock mock = new ConversionMock(200, successBody());
        Test.setMock(HttpCalloutMock.class, mock);
        List<CurrencyConversionAction.Response> results = CurrencyConversionAction.convertCurrency(
            new List<CurrencyConversionAction.Request>{ null, request(null, 'GBP', 1),
                request('EU', 'GBP', 1), request('EUR', 'GB/P', 1), request('EUR', ' ', 1),
                request('EUR', 'GBP', null), request('EUR', 'GBP', -1) }
        );
        Assert.areEqual(7, results.size());
        for (CurrencyConversionAction.Response result : results) {
            Assert.isNotNull(result.errorMessage);
            Assert.isNull(result.convertedAmount);
        }
        Assert.areEqual(0, mock.calls);
        Assert.areEqual(0, CurrencyConversionAction.convertCurrency(null).size());
        Assert.areEqual(0, CurrencyConversionAction.convertCurrency(new List<CurrencyConversionAction.Request>()).size());
    }

    @IsTest
    static void handlesSameCurrencyAndPreservesBatchOrder() {
        ConversionMock mock = new ConversionMock(200, successBody());
        Test.setMock(HttpCalloutMock.class, mock);
        List<CurrencyConversionAction.Response> results = CurrencyConversionAction.convertCurrency(
            new List<CurrencyConversionAction.Request>{ request('USD', 'usd', 12.345), null,
                request('EUR', 'GBP', 100), request('EUR', 'EUR', 0) }
        );
        Assert.areEqual(4, results.size());
        Assert.areEqual(1, results[0].exchangeRate);
        Assert.areEqual(12.345, results[0].convertedAmount);
        Assert.isNotNull(results[1].errorMessage);
        Assert.areEqual(84.12, results[2].convertedAmount);
        Assert.areEqual(0, results[3].convertedAmount);
        Assert.areEqual(1, mock.calls);
    }

    private static void assertFailure(ConversionMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        CurrencyConversionAction.Response result = CurrencyConversionAction.convertCurrency(
            new List<CurrencyConversionAction.Request>{ request('EUR', 'GBP', 100) }
        )[0];
        Assert.isNotNull(result.errorMessage);
        Assert.isFalse(result.errorMessage.contains('Sensitive'));
        Assert.isNull(result.exchangeRate);
        Assert.isNull(result.convertedAmount);
    }

    @IsTest
    static void handlesHttpAndProviderFailures() {
        assertFailure(new ConversionMock(429, 'Sensitive error details'));
        assertFailure(new ConversionMock(200, '{"result":"error","error-type":"invalid-key"}'));
        assertFailure(new ConversionMock(200, '{"result":"error","error-type":"unsupported-code"}'));
    }

    @IsTest
    static void rejectsMalformedOrMismatchedResponses() {
        for (String body : new List<String>{ 'not json', 'null', '[]', '{}',
            '{"result":"success","base_code":"EUR","target_code":"GBP"}',
            successBody().replace('"GBP"', '"USD"'),
            successBody().replace('0.8412', '-0.8412'),
            successBody().replace('84.12', '-84.12') }) {
            assertFailure(new ConversionMock(200, body));
        }
    }

    @IsTest
    static void handlesCalloutExceptionsSafely() {
        ConversionMock mock = new ConversionMock(200, successBody());
        mock.failCallout = true;
        assertFailure(mock);
    }

    @IsTest
    static void respectsRemainingCalloutBudget() {
        ConversionMock mock = new ConversionMock(200, successBody());
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        List<CurrencyConversionAction.Request> inputs = new List<CurrencyConversionAction.Request>();
        for (Integer position = 0; position < 101; position++) {
            inputs.add(request('EUR', 'GBP', 100));
        }
        List<CurrencyConversionAction.Response> results = CurrencyConversionAction.convertCurrency(inputs);
        Assert.areEqual(101, results.size());
        Assert.isNull(results[99].errorMessage);
        Assert.isNotNull(results[100].errorMessage);
        Assert.areEqual(100, Limits.getCallouts());
        Test.stopTest();
    }
}