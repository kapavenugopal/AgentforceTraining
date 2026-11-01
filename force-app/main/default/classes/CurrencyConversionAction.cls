public with sharing class CurrencyConversionAction {
    public class Request {
        @InvocableVariable(required=true label='From Currency')
        public String fromCurrency;
        @InvocableVariable(required=true label='To Currency')
        public String toCurrency;
        @InvocableVariable(required=true label='Amount')
        public Decimal amount;
    }

    public class Response {
        @InvocableVariable(label='From Currency')
        public String fromCurrency;
        @InvocableVariable(label='To Currency')
        public String toCurrency;
        @InvocableVariable(label='Original Amount')
        public Decimal originalAmount;
        @InvocableVariable(label='Exchange Rate')
        public Decimal exchangeRate;
        @InvocableVariable(label='Converted Amount')
        public Decimal convertedAmount;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    private class ApiResponse {
        public String result;
        public String base_code;
        public String target_code;
        public Decimal conversion_rate;
        public Decimal conversion_result;
    }

    @InvocableMethod(label='Convert Currency' description='Convert an amount between two three-letter currency codes using ExchangeRate-API.' callout=true)
    public static List<Response> convertCurrency(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        for (Request input : requests) {
            Response result = new Response();
            results.add(result);
            if (input == null || !isCurrencyCode(input.fromCurrency) || !isCurrencyCode(input.toCurrency)) {
                result.errorMessage = 'Provide three-letter currency codes, such as EUR and GBP.';
                continue;
            }
            if (input.amount == null || input.amount < 0) {
                result.errorMessage = 'Provide an amount of zero or greater.';
                continue;
            }
            result.fromCurrency = input.fromCurrency.trim().toUpperCase();
            result.toCurrency = input.toCurrency.trim().toUpperCase();
            result.originalAmount = input.amount;
            if (result.fromCurrency == result.toCurrency) {
                result.exchangeRate = 1;
                result.convertedAmount = input.amount;
                continue;
            }
            if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                result.errorMessage = 'Currency conversion callout limit reached. Submit a smaller batch.';
                continue;
            }
            convertAmount(result);
        }
        return results;
    }

    private static Boolean isCurrencyCode(String code) {
        return !String.isBlank(code) && Pattern.matches('[A-Za-z]{3}', code.trim());
    }

    private static void convertAmount(Response result) {
        try {
            HttpRequest outbound = new HttpRequest();
            outbound.setEndpoint('callout:ExchangeRate_API/pair/' + result.fromCurrency + '/' +
                result.toCurrency + '/' + String.valueOf(result.originalAmount));
            outbound.setMethod('GET');
            outbound.setHeader('Accept', 'application/json');
            outbound.setTimeout(10000);
            HttpResponse inbound = new Http().send(outbound);
            if (inbound.getStatusCode() != 200) {
                result.errorMessage = 'Currency conversion service is unavailable. Try again later.';
                return;
            }
            ApiResponse payload = (ApiResponse) JSON.deserialize(inbound.getBody(), ApiResponse.class);
            if (payload == null || payload.result != 'success') {
                result.errorMessage = 'Currency conversion failed. Check the supported currency codes and service configuration.';
                return;
            }
            if (payload.base_code != result.fromCurrency || payload.target_code != result.toCurrency ||
                payload.conversion_rate == null || payload.conversion_rate <= 0 ||
                payload.conversion_result == null || payload.conversion_result < 0) {
                result.errorMessage = 'Currency conversion service returned an invalid response.';
                return;
            }
            result.exchangeRate = payload.conversion_rate;
            result.convertedAmount = payload.conversion_result;
        } catch (Exception failure) {
            result.errorMessage = 'Unable to convert currency. Check the service configuration or try again later.';
        }
    }
}