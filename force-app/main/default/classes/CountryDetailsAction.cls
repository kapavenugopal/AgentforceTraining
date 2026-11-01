public with sharing class CountryDetailsAction {
    public class Request {
        @InvocableVariable(required=true label='Country Name')
        public String countryName;
    }

    public class Response {
        @InvocableVariable(label='Country Name')
        public String countryName;
        @InvocableVariable(label='Official Name')
        public String officialName;
        @InvocableVariable(label='ISO Alpha-2 Code')
        public String countryCode;
        @InvocableVariable(label='ISO Alpha-3 Code')
        public String countryCodeAlpha3;
        @InvocableVariable(label='Capitals')
        public List<String> capitals = new List<String>();
        @InvocableVariable(label='Region')
        public String region;
        @InvocableVariable(label='Subregion')
        public String subregion;
        @InvocableVariable(label='Population')
        public Decimal population;
        @InvocableVariable(label='Area in Square Kilometers')
        public Decimal areaSquareKilometers;
        @InvocableVariable(label='Currencies')
        public List<String> currencies = new List<String>();
        @InvocableVariable(label='Languages')
        public List<String> languages = new List<String>();
        @InvocableVariable(label='Calling Codes')
        public List<String> callingCodes = new List<String>();
        @InvocableVariable(label='Timezones')
        public List<String> timezones = new List<String>();
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    private class ApiResponse {
        public CountryData data;
    }
    private class CountryData {
        public List<Country> objects;
        public PageMetadata meta;
    }
    private class PageMetadata {
        public Integer total;
        public Boolean more;
    }
    private class Country {
        public Names names;
        public Codes codes;
        public List<NamedValue> capitals;
        public String region;
        public String subregion;
        public Decimal population;
        public CountryArea area;
        public List<CurrencyValue> currencies;
        public List<NamedValue> languages;
        public List<String> calling_codes;
        public List<String> timezones;
    }
    private class Names {
        public String common;
        public String official;
    }
    private class Codes {
        public String alpha_2;
        public String alpha_3;
    }
    private class NamedValue {
        public String name;
    }
    private class CountryArea {
        public Decimal kilometers;
    }
    private class CurrencyValue {
        public String code;
        public String name;
        public String symbol;
    }

    @InvocableMethod(label='Get Country Details' description='Look up details by exact common country name using REST Countries v5.' callout=true)
    public static List<Response> getCountryDetails(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        for (Request input : requests) {
            if (input == null || String.isBlank(input.countryName) || input.countryName.trim().length() > 200) {
                results.add(failure('Provide a country name between 1 and 200 characters.'));
            } else if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                results.add(failure('Country lookup callout limit reached. Submit a smaller batch.'));
            } else {
                results.add(fetchCountry(input.countryName.trim()));
            }
        }
        return results;
    }

    private static Response failure(String message) {
        Response result = new Response();
        result.errorMessage = message;
        return result;
    }

    private static Response fetchCountry(String countryName) {
        try {
            HttpRequest outbound = new HttpRequest();
            outbound.setEndpoint('callout:REST_Countries_API/names.common/' +
                EncodingUtil.urlEncode(countryName, 'UTF-8').replace('+', '%20') +
                '?response_fields=names.common,names.official,codes.alpha_2,codes.alpha_3,' +
                'capitals,region,subregion,population,area.kilometers,currencies,languages,calling_codes,timezones&limit=2');
            outbound.setMethod('GET');
            outbound.setHeader('Accept', 'application/json');
            outbound.setTimeout(10000);
            HttpResponse inbound = new Http().send(outbound);
            if (inbound.getStatusCode() != 200) {
                return failure('Country service is unavailable. Check service access or try again later.');
            }
            ApiResponse payload = (ApiResponse) JSON.deserialize(inbound.getBody(), ApiResponse.class);
            Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(inbound.getBody());
            Map<String, Object> dataFields = envelope == null ? null : (Map<String, Object>) envelope.get('data');
            if (payload == null || payload.data == null || payload.data.objects == null ||
                dataFields.containsKey('_demo')) {
                return failure('Country service returned an invalid or demo response. Check the service configuration.');
            }
            if (payload.data.objects.isEmpty()) {
                return failure('Country not found. Provide the full common country name, such as Canada.');
            }
            if (payload.data.objects.size() != 1 || (payload.data.meta != null &&
                (payload.data.meta.more == true || payload.data.meta.total > 1))) {
                return failure('Country lookup returned multiple matches. Provide a unique common country name.');
            }
            Country country = payload.data.objects[0];
            if (country == null || country.names == null || String.isBlank(country.names.common) ||
                !country.names.common.equalsIgnoreCase(countryName)) {
                return failure('Country service returned an unexpected country response.');
            }
            Response result = new Response();
            result.countryName = country.names.common;
            result.officialName = country.names.official;
            if (country.codes != null) {
                result.countryCode = country.codes.alpha_2;
                result.countryCodeAlpha3 = country.codes.alpha_3;
            }
            result.capitals = namesFrom(country.capitals);
            result.region = country.region;
            result.subregion = country.subregion;
            result.population = country.population;
            result.areaSquareKilometers = country.area == null ? null : country.area.kilometers;
            if (country.currencies != null) {
                for (CurrencyValue currencyInfo : country.currencies) {
                    if (currencyInfo != null && !String.isBlank(currencyInfo.code)) {
                        result.currencies.add(currencyInfo.code +
                            (String.isBlank(currencyInfo.name) ? '' : ' - ' + currencyInfo.name) +
                            (String.isBlank(currencyInfo.symbol) ? '' : ' (' + currencyInfo.symbol + ')'));
                    }
                }
            }
            result.languages = namesFrom(country.languages);
            if (country.calling_codes != null) {
                result.callingCodes.addAll(country.calling_codes);
            }
            if (country.timezones != null) {
                result.timezones.addAll(country.timezones);
            }
            return result;
        } catch (Exception problem) {
            return failure('Unable to get country details. Check the service configuration or try again later.');
        }
    }

    private static List<String> namesFrom(List<NamedValue> values) {
        List<String> names = new List<String>();
        if (values != null) {
            for (NamedValue value : values) {
                if (value != null && !String.isBlank(value.name)) {
                    names.add(value.name);
                }
            }
        }
        return names;
    }
}