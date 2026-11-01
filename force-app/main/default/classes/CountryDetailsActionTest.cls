@IsTest
private class CountryDetailsActionTest {
    private class CountryMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        String expectedPath;
        Boolean failCallout = false;
        Integer calls = 0;

        CountryMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest outbound) {
            calls++;
            Assert.areEqual('GET', outbound.getMethod());
            Assert.areEqual('application/json', outbound.getHeader('Accept'));
            Assert.isTrue(outbound.getEndpoint().startsWith('callout:REST_Countries_API/names.common/'));
            Assert.isTrue(outbound.getEndpoint().contains('?response_fields='));
            if (expectedPath != null) {
                Assert.isTrue(outbound.getEndpoint().contains(expectedPath));
            }
            if (failCallout) {
                throw new CalloutException('Sensitive credential details');
            }
            HttpResponse inbound = new HttpResponse();
            inbound.setStatusCode(statusCode);
            inbound.setBody(body);
            return inbound;
        }
    }

    private static CountryDetailsAction.Request request(String name) {
        CountryDetailsAction.Request input = new CountryDetailsAction.Request();
        input.countryName = name;
        return input;
    }

    private static String countryBody() {
        return '{"data":{"objects":[{"names":{"common":"Canada","official":"Canada"},' +
            '"codes":{"alpha_2":"CA","alpha_3":"CAN"},"capitals":[{"name":"Ottawa"}],'+
            '"region":"Americas","subregion":"North America","population":38005238,' +
            '"area":{"kilometers":9984670},"currencies":[{"code":"CAD","name":"Canadian dollar","symbol":"$"}],' +
            '"languages":[{"name":"English"},{"name":"French"}],"calling_codes":["1"],' +
            '"timezones":["UTC-05:00"]}],"meta":{"total":1,"more":false}}}';
    }

    @IsTest
    static void returnsCountryDetails() {
        CountryMock mock = new CountryMock(200, countryBody());
        mock.expectedPath = '/names.common/canada?';
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        CountryDetailsAction.Response result = CountryDetailsAction.getCountryDetails(
            new List<CountryDetailsAction.Request>{ request(' canada ') }
        )[0];
        Test.stopTest();
        Assert.isNull(result.errorMessage);
        Assert.areEqual('Canada', result.countryName);
        Assert.areEqual('Canada', result.officialName);
        Assert.areEqual('CA', result.countryCode);
        Assert.areEqual('CAN', result.countryCodeAlpha3);
        Assert.areEqual(new List<String>{ 'Ottawa' }, result.capitals);
        Assert.areEqual('Americas', result.region);
        Assert.areEqual('North America', result.subregion);
        Assert.areEqual(38005238, result.population);
        Assert.areEqual(9984670, result.areaSquareKilometers);
        Assert.areEqual(new List<String>{ 'CAD - Canadian dollar ($)' }, result.currencies);
        Assert.areEqual(new List<String>{ 'English', 'French' }, result.languages);
        Assert.areEqual(new List<String>{ '1' }, result.callingCodes);
        Assert.areEqual(new List<String>{ 'UTC-05:00' }, result.timezones);
        Assert.areEqual(1, mock.calls);
    }

    @IsTest
    static void encodesNameAndAllowsMissingOptionalFields() {
        CountryMock mock = new CountryMock(200,
            '{"data":{"objects":[{"names":{"common":"United Kingdom"}}]}}');
        mock.expectedPath = '/names.common/United%20Kingdom?';
        Test.setMock(HttpCalloutMock.class, mock);
        CountryDetailsAction.Response result = CountryDetailsAction.getCountryDetails(
            new List<CountryDetailsAction.Request>{ request('United Kingdom') }
        )[0];
        Assert.isNull(result.errorMessage);
        Assert.areEqual('United Kingdom', result.countryName);
        Assert.areEqual(0, result.capitals.size());
        Assert.areEqual(0, result.currencies.size());
        Assert.areEqual(0, result.languages.size());
        Assert.isNull(result.population);
        mock.body = '{"data":{"objects":[{"names":{"common":"A/B?"}}]}}';
        mock.expectedPath = '/names.common/A%2FB%3F?';
        Assert.isNull(CountryDetailsAction.getCountryDetails(
            new List<CountryDetailsAction.Request>{ request('A/B?') }
        )[0].errorMessage);
    }

    @IsTest
    static void rejectsInvalidInputsAndPreservesOrder() {
        CountryMock mock = new CountryMock(200, countryBody());
        Test.setMock(HttpCalloutMock.class, mock);
        List<CountryDetailsAction.Response> results = CountryDetailsAction.getCountryDetails(
            new List<CountryDetailsAction.Request>{ null, request(' '), request(''),
                request('Canada'.leftPad(201, 'x')), request('Canada') }
        );
        Assert.areEqual(5, results.size());
        for (Integer position = 0; position < 4; position++) {
            Assert.isNotNull(results[position].errorMessage);
            Assert.isNull(results[position].countryName);
        }
        Assert.areEqual('Canada', results[4].countryName);
        Assert.areEqual(1, mock.calls);
        Assert.areEqual(0, CountryDetailsAction.getCountryDetails(null).size());
        Assert.areEqual(0, CountryDetailsAction.getCountryDetails(new List<CountryDetailsAction.Request>()).size());
    }

    private static void assertFailure(CountryMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        CountryDetailsAction.Response result = CountryDetailsAction.getCountryDetails(
            new List<CountryDetailsAction.Request>{ request('Canada') }
        )[0];
        Assert.isNotNull(result.errorMessage);
        Assert.isFalse(result.errorMessage.contains('Sensitive'));
        Assert.isNull(result.countryName);
        Assert.areEqual(0, result.capitals.size());
    }

    @IsTest
    static void handlesServiceAndCalloutErrorsSafely() {
        for (Integer statusCode : new List<Integer>{ 401, 403, 404, 429, 500 }) {
            assertFailure(new CountryMock(statusCode, 'Sensitive provider details'));
        }
        CountryMock mock = new CountryMock(200, countryBody());
        mock.failCallout = true;
        assertFailure(mock);
    }

    @IsTest
    static void rejectsMalformedEmptyAmbiguousAndWrongCountryResponses() {
        for (String body : new List<String>{ 'not json', 'null', '[]', '{}',
            '{"errors":[{"message":"Sensitive"}]}', '{"data":{}}',
            '{"data":{"objects":[],"_demo":{"message":"Sample data"}}}',
            '{"data":{"objects":[]}}', '{"data":{"objects":[null]}}',
            '{"data":{"objects":[{}]}}', countryBody().replace('Canada', 'Germany'),
            '{"data":{"objects":[{"names":{"common":"Canada"},"capitals":[null]}]}}',
            '{"data":{"objects":[{"names":{"common":"Canada"}},{"names":{"common":"Canada"}}]}}',
            countryBody().replace('"more":false', '"more":true'),
            countryBody().replace('"total":1', '"total":2') }) {
            assertFailure(new CountryMock(200, body));
        }
    }

    @IsTest
    static void toleratesEmptyOptionalEntries() {
        CountryMock mock = new CountryMock(200,
            '{"data":{"objects":[{"names":{"common":"Canada"},"capitals":[{}],' +
            '"currencies":[{}, {"code":"CAD","name":"Canadian dollar"}],' +
            '"languages":[{}]}]}}');
        Test.setMock(HttpCalloutMock.class, mock);
        CountryDetailsAction.Response result = CountryDetailsAction.getCountryDetails(
            new List<CountryDetailsAction.Request>{ request('Canada') }
        )[0];
        Assert.isNull(result.errorMessage);
        Assert.areEqual(0, result.capitals.size());
        Assert.areEqual(0, result.languages.size());
        Assert.areEqual(new List<String>{ 'CAD - Canadian dollar' }, result.currencies);
    }

    @IsTest
    static void respectsRemainingCalloutBudget() {
        Test.setMock(HttpCalloutMock.class, new CountryMock(200, countryBody()));
        Test.startTest();
        List<CountryDetailsAction.Request> inputs = new List<CountryDetailsAction.Request>();
        for (Integer position = 0; position < 101; position++) {
            inputs.add(request('Canada'));
        }
        List<CountryDetailsAction.Response> results = CountryDetailsAction.getCountryDetails(inputs);
        Assert.areEqual(101, results.size());
        Assert.isNull(results[99].errorMessage);
        Assert.isNotNull(results[100].errorMessage);
        Assert.areEqual(100, Limits.getCallouts());
        Test.stopTest();
    }
}