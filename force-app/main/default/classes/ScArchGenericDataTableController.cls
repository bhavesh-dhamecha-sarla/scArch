public with sharing class ScArchGenericDataTableController {
    public class ObjectOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public ObjectOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getConfigObjectOptions() {
        List<scArch_Archive_Configuration__c> configRecords = [
            SELECT Id, Name, Object_Name__c, Is_Parent__c
            FROM scArch_Archive_Configuration__c
            WHERE Object_Name__c != null
            AND Is_Parent__c = true
            ORDER BY Object_Name__c
        ];

        List<ObjectOption> options = new List<ObjectOption>();
        Set<String> usedValues = new Set<String>();

        for (scArch_Archive_Configuration__c configRecord : configRecords) {
            String objectName = configRecord.Object_Name__c;
            if (String.isBlank(objectName) || usedValues.contains(objectName)) {
                continue;
            }

            usedValues.add(objectName);
            options.add(new ObjectOption(objectName, objectName));
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static String getPreferredDateField(String objectName) {
        if (String.isBlank(objectName)) {
            return 'CreatedDate';
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectName)) {
            return 'CreatedDate';
        }

        Map<String, Schema.SObjectField> fieldsMap = globalDescribe.get(objectName).getDescribe().fields.getMap();
        List<String> preferredNames = new List<String>{
            'Call_Date__c',
            'CreatedDate',
            'LastModifiedDate',
            'ActivityDate',
            'Start_Date__c',
            'End_Date__c',
            'Date__c',
            'Event_Date__c'
        };

        for (String fieldName : preferredNames) {
            if (fieldsMap.containsKey(fieldName)) {
                return fieldName;
            }
        }

        for (String fieldName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
            if (fieldDescribe.getType() == Schema.DisplayType.DATE ||
                fieldDescribe.getType() == Schema.DisplayType.DATETIME) {
                return fieldName;
            }
        }

        return 'CreatedDate';
    }

    @AuraEnabled
    public static String getFieldSetNameForObject(String objectName) {
        if (String.isBlank(objectName)) {
            return null;
        }

        List<scArch_Archive_Configuration__c> configs = [
            SELECT Field_Set_Name__c
            FROM scArch_Archive_Configuration__c
            WHERE Object_Name__c = :objectName
            AND Is_Parent__c = true
            ORDER BY LastModifiedDate DESC, CreatedDate DESC
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return null;
        }

        return configs[0].Field_Set_Name__c;
    }

    @AuraEnabled
    public static List<String> getConfiguredFieldNamesForObject(String objectName) {
        if (String.isBlank(objectName)) {
            return new List<String>();
        }

        String fieldSetName = getFieldSetNameForObject(objectName);
        return getFieldNamesForFieldSet(objectName, fieldSetName);
    }

    @AuraEnabled
    public static List<String> getFieldNamesForFieldSet(String objectName, String fieldSetName) {
        if (String.isBlank(objectName) || String.isBlank(fieldSetName)) {
            return new List<String>();
        }

        String normalizedFieldSetName = fieldSetName.trim();
        Boolean hasRealFieldSet = ScArchArchiveService.hasFieldSet(objectName, normalizedFieldSetName);

        if (hasRealFieldSet) {
            List<Map<String, String>> metadata = ScArchArchiveService.getRequestFieldMetadata(objectName, normalizedFieldSetName);
            List<String> fieldNames = new List<String>();
            for (Map<String, String> fieldInfo : metadata) {
                String fieldName = fieldInfo.get('name');
                if (String.isNotBlank(fieldName) && !fieldNames.contains(fieldName)) {
                    fieldNames.add(fieldName);
                }
            }
            if (!fieldNames.isEmpty()) {
                return fieldNames;
            }
        }

        List<String> explicitFields = new List<String>();
        for (String token : normalizedFieldSetName.split(',')) {
            String fieldName = token.trim();
            if (String.isNotBlank(fieldName)) {
                explicitFields.add(fieldName);
            }
        }
        return explicitFields;
    }

    @AuraEnabled
    public static Map<String, Object> getPagedApiData(
        String objectName,
        String endpointPath,
        List<String> fields,
        String dateRangeJson,
        String sortJson,
        Integer page,
        Integer pageSize
    ) {
        try {
            if (String.isBlank(objectName)) {
                throw new AuraHandledException('Object name is required.');
            }

            Integer normalizedPage = page == null || page < 1 ? 1 : page;
            Integer normalizedPageSize = pageSize == null || pageSize < 1 ? 5 : pageSize;
            String normalizedEndpoint = String.isBlank(endpointPath) ? '/archive/read/scArchQuery' : endpointPath;
            if (!normalizedEndpoint.startsWith('/')) {
                normalizedEndpoint = '/' + normalizedEndpoint;
            }

            String namedCredentialName = ScArchArchiveService.getDefaultNamedCredential();
            if (String.isBlank(namedCredentialName)) {
                throw new AuraHandledException('Named Credential is not configured.');
            }

            if (namedCredentialName.endsWith('/api/v1') && normalizedEndpoint.startsWith('/api/v1')) {
                normalizedEndpoint = normalizedEndpoint.substring('/api/v1'.length());
            }

            scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
            String accessToken = ScArchArchiveService.getOdooAccessToken(
                namedCredentialName,
                mainSetting != null ? mainSetting.Registered_User_Id__c : null,
                mainSetting != null ? mainSetting.Registered_Password__c : null
            );

            Object parsedDateRange = String.isBlank(dateRangeJson) ? null : JSON.deserializeUntyped(dateRangeJson);
            Object parsedSort = String.isBlank(sortJson) ? null : JSON.deserializeUntyped(sortJson);

            Map<String, Object> payload = new Map<String, Object>{
                'orgId' => UserInfo.getOrganizationId(),
                'environment' => ScArchArchiveService.isSandboxOrganization() ? 'sandbox' : 'production',
                'objectName' => objectName,
                'fields' => (fields == null || fields.isEmpty()) ? null : fields,
                'dateRange' => parsedDateRange,
                'sort' => parsedSort,
                'page' => new Map<String, Object>{
                    'limit' => normalizedPageSize,
                    'offset' => (normalizedPage - 1) * normalizedPageSize
                }
            };

            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:' + namedCredentialName + normalizedEndpoint);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('Accept', 'application/json');
            request.setHeader('Authorization', 'Bearer ' + accessToken);
            String serializedPayload = JSON.serialize(payload);
            request.setBody(serializedPayload);

            System.debug('ScArch generic table request endpoint: callout:' + namedCredentialName + normalizedEndpoint);
            System.debug('ScArch generic table request body: ' + serializedPayload);

            Http http = new Http();
            HttpResponse response = http.send(request);

            System.debug('ScArch generic table response status: ' + response.getStatusCode());
            System.debug('ScArch generic table response body: ' + response.getBody());

            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new AuraHandledException('External API returned status ' + response.getStatusCode() + ': ' + response.getBody());
            }

            Object parsedBody = JSON.deserializeUntyped(response.getBody());
            Map<String, Object> payloadBody = parsedBody instanceof Map<String, Object>
                ? (Map<String, Object>) parsedBody
                : new Map<String, Object>();

            return buildTableModel(objectName, payloadBody, normalizedPage, normalizedPageSize, fields);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch data: ' + e.getMessage());
        }
    }

    public static Map<String, Object> buildTableModel(String objectName, Object payloadBody, Integer page, Integer pageSize, List<String> requestedFields) {
        Map<String, Object> result = new Map<String, Object>();
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        List<Map<String, Object>> columns = new List<Map<String, Object>>();

        Map<String, Object> body = payloadBody instanceof Map<String, Object>
            ? (Map<String, Object>) payloadBody
            : new Map<String, Object>();

        Map<String, Object> data = new Map<String, Object>();
        Object dataObj = body.get('data');
        if (dataObj instanceof Map<String, Object>) {
            data = (Map<String, Object>) dataObj;
        } else {
            data = body;
        }

        List<Object> rawRows = new List<Object>();
        Object recordsObj = data.get('records');
        if (recordsObj instanceof List<Object>) {
            rawRows = (List<Object>) recordsObj;
        } else if (data.containsKey('rows') && data.get('rows') instanceof List<Object>) {
            rawRows = (List<Object>) data.get('rows');
        } else if (body.containsKey('rows') && body.get('rows') instanceof List<Object>) {
            rawRows = (List<Object>) body.get('rows');
        }

        List<String> resolvedFields = new List<String>();
        if (requestedFields != null && !requestedFields.isEmpty()) {
            resolvedFields.addAll(requestedFields);
        }

        Integer rowIndex = 0;
        for (Object rowObj : rawRows) {
            if (!(rowObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> record = (Map<String, Object>) rowObj;
            Map<String, Object> row = new Map<String, Object>();

            if (resolvedFields.isEmpty()) {
                for (String fieldName : record.keySet()) {
                    resolvedFields.add(fieldName);
                }
            }

            for (String fieldName : resolvedFields) {
                row.put(fieldName, getFieldValue(record, fieldName));
            }

            Object recordId = getFieldValue(record, 'Id');
            if (recordId == null) {
                recordId = 'row-' + rowIndex;
            }
            row.put('Id', String.valueOf(recordId));
            rows.add(row);
            rowIndex++;
        }

        if (resolvedFields.isEmpty()) {
            resolvedFields.add('Id');
        }

        for (String fieldName : resolvedFields) {
            columns.add(new Map<String, Object>{
                'label' => toColumnLabel(fieldName),
                'fieldName' => fieldName,
                'type' => mapToLightningType(fieldName)
            });
        }

        Map<String, Object> paginationInfo = new Map<String, Object>();
        Object paginationObj = data.get('pagination');
        if (paginationObj instanceof Map<String, Object>) {
            paginationInfo = (Map<String, Object>) paginationObj;
        } else if (data.containsKey('page') && data.get('page') instanceof Map<String, Object>) {
            paginationInfo = (Map<String, Object>) data.get('page');
        } else if (body.containsKey('page') && body.get('page') instanceof Map<String, Object>) {
            paginationInfo = (Map<String, Object>) body.get('page');
        }

        Integer totalRows = toInteger(paginationInfo.get('totalRows'));
        if (totalRows == 0) {
            totalRows = toInteger(data.get('totalRows'));
        }
        if (totalRows == 0) {
            totalRows = toInteger(body.get('totalRows'));
        }

        Integer rowCount = toInteger(paginationInfo.get('rowCount'));
        if (rowCount == 0) {
            rowCount = toInteger(data.get('rowCount'));
        }
        if (rowCount == 0) {
            rowCount = toInteger(body.get('rowCount'));
        }

        Integer nextOffset = toInteger(paginationInfo.get('nextOffset'));
        if (nextOffset == 0) {
            nextOffset = toInteger(data.get('nextOffset'));
        }
        if (nextOffset == 0) {
            nextOffset = toInteger(body.get('nextOffset'));
        }

        Integer offset = toInteger(paginationInfo.get('offset'));
        if (offset == 0) {
            offset = toInteger(data.get('offset'));
        }
        if (offset == 0) {
            offset = toInteger(body.get('offset'));
        }

        Integer pageLimit = toInteger(paginationInfo.get('limit'));
        if (pageLimit == 0) {
            pageLimit = toInteger(data.get('limit'));
        }
        if (pageLimit == 0) {
            pageLimit = toInteger(body.get('limit'));
        }
        if (pageLimit == 0) {
            pageLimit = pageSize;
        }
        if (offset == 0 && page > 1) {
            offset = (page - 1) * pageLimit;
        }

        Boolean hasNext = false;
        if (totalRows > 0) {
            hasNext = (offset + rows.size()) < totalRows;
        }
        if (!hasNext && nextOffset != null && nextOffset > 0 && totalRows > 0) {
            hasNext = nextOffset < totalRows;
        }
        if (!hasNext && rowCount > 0 && pageLimit > 0) {
            hasNext = rows.size() == pageLimit && (offset + rows.size()) < totalRows;
        }
        Boolean hasPrevious = page > 1;

        result.put('columns', columns);
        result.put('rows', rows);
        result.put('pagination', new Map<String, Object>{
            'page' => page,
            'pageSize' => pageSize,
            'limit' => pageLimit,
            'offset' => offset,
            'totalRows' => totalRows,
            'rowCount' => rowCount,
            'nextOffset' => nextOffset,
            'hasNext' => hasNext,
            'hasPrevious' => hasPrevious
        });
        result.put('objectName', objectName);
        result.put('success', true);
        result.put('message', 'Data loaded successfully.');
        return result;
    }

    private static Object getFieldValue(Map<String, Object> record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }

        if (record.containsKey(fieldName)) {
            return record.get(fieldName);
        }

        String lowerName = fieldName.toLowerCase();
        if (record.containsKey(lowerName)) {
            return record.get(lowerName);
        }

        String snakeName = fieldName.replace('__c', '').replace(' ', '_').replace('-', '_').toLowerCase();
        if (record.containsKey(snakeName)) {
            return record.get(snakeName);
        }

        return null;
    }

    private static String toColumnLabel(String fieldName) {
        if (String.isBlank(fieldName)) {
            return 'Field';
        }
        if (fieldName == 'Id') {
            return 'Record Id';
        }
        return fieldName;
    }

    private static String mapToLightningType(String fieldName) {
        if (String.isBlank(fieldName)) {
            return 'text';
        }

        String normalized = fieldName.toUpperCase();
        if (normalized.contains('DATE') || normalized.contains('CREATEDDATE') || normalized.contains('MODIFIEDDATE')) {
            return 'date';
        }
        if (normalized.contains('AMOUNT') || normalized.contains('REVENUE') || normalized.contains('TOTAL') || normalized.contains('COUNT')) {
            return 'number';
        }
        return 'text';
    }

    private static Integer toInteger(Object value) {
        if (value == null) {
            return 0;
        }

        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).intValue();
        }
        if (value instanceof Long) {
            return Integer.valueOf((Long) value);
        }
        if (value instanceof String) {
            try {
                return Integer.valueOf((String) value);
            } catch (Exception e) {
                return 0;
            }
        }
        return 0;
    }
}
