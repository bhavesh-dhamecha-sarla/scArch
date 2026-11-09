public with sharing class ScArchArchiveService {
    public class ArchiveResult {
        public Id configId;
        public Boolean success;
        public String message;
    }

    public static String getDefaultNamedCredential() {
        scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
        return mainSetting != null ? mainSetting.Named_Credential__c : null;
    }

    public static Boolean isSandboxOrganization() {
        Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
        return org.IsSandbox;
    }

    public static String buildDescribeDrivenArchiveJobPayload(
        String orgId,
        String environment,
        String objectName,
        Date startDate,
        Date endDate,
        String frequency,
        String correlationId
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('orgId', orgId);
        payload.put('environment', environment);
        payload.put('objectName', objectName);
        payload.put('startDate', startDate != null ? String.valueOf(startDate) : null);
        payload.put('endDate', endDate != null ? String.valueOf(endDate) : null);
        payload.put('frequency', frequency);
        payload.put('correlationId', correlationId);
        return JSON.serialize(payload);
    }

    public static String buildArchiveJobPayload(scArch_Archive_Configuration__c parentConfig, List<String> childObjectNames) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('orgId', UserInfo.getOrganizationId());
        payload.put('environment', isSandboxOrganization() ? 'sandbox' : 'production');
        payload.put('objectName', parentConfig.Object_Name__c);
        payload.put('frequency', parentConfig.Archive_Frequency__c);
        payload.put('dateField', 'CreatedDate');
        payload.put('startDate', parentConfig.First_Archive_Date__c);
        payload.put('endDate', parentConfig.Last_Archive_Date__c != null ? parentConfig.Last_Archive_Date__c.date() : Date.today());
        payload.put('archiveChildren', parentConfig.Archive_Children__c);
        payload.put('childObjects', childObjectNames);
        payload.put('childRelationships', getChildRelationshipMetadata(parentConfig.Object_Name__c, childObjectNames));
        payload.put('fields', ensureRequiredRequestFields(parentConfig.Object_Name__c, getRequestFieldMetadata(parentConfig.Object_Name__c, parentConfig.Field_Set_Name__c)));
        payload.put('correlationId', String.valueOf(Crypto.getRandomLong()));
        payload.put('externalStorageEnabled', false);

        return JSON.serialize(payload);
    }

    private static List<Map<String, String>> ensureRequiredRequestFields(String objectName, List<Map<String, String>> fieldMetadata) {
        if (fieldMetadata == null) {
            fieldMetadata = new List<Map<String, String>>();
        }

        Set<String> existingFieldNames = new Set<String>();
        for (Map<String, String> field : fieldMetadata) {
            if (field != null && field.containsKey('name')) {
                existingFieldNames.add(String.valueOf(field.get('name')));
            }
        }

        if (!existingFieldNames.contains('Id')) {
            fieldMetadata.add(new Map<String, String>{
                'name' => 'Id',
                'type' => 'Id',
                'object' => objectName,
                'length' => '18'
            });
        }

        if (!existingFieldNames.contains('CreatedDate')) {
            fieldMetadata.add(new Map<String, String>{
                'name' => 'CreatedDate',
                'type' => 'DateTime',
                'object' => objectName,
                'length' => '0'
            });
        }

        return fieldMetadata;
    }

    public static List<Map<String, String>> getChildRelationshipMetadata(String parentObjectName, List<String> childObjectNames) {
        List<Map<String, String>> metadata = new List<Map<String, String>>();
        if (childObjectNames == null || childObjectNames.isEmpty()) {
            return metadata;
        }

        for (String childObjectName : childObjectNames) {
            if (String.isBlank(childObjectName)) {
                continue;
            }
            String relationshipField = getChildRelationshipField(parentObjectName, childObjectName);
            if (String.isBlank(relationshipField)) {
                continue;
            }
            metadata.add(new Map<String, String>{
                'childObject' => childObjectName,
                'relationshipField' => relationshipField
            });
        }
        return metadata;
    }

    public static HttpResponse sendDescribeDrivenArchiveJob(String namedCredentialName, String payloadJson) {
        scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
        if (mainSetting == null || String.isBlank(mainSetting.Registered_User_Id__c) || String.isBlank(mainSetting.Registered_Password__c)) {
            throw new IllegalArgumentException('Registration credentials are required before sending a describe-driven archive job.');
        }

        String accessToken = getOdooAccessTokenFromPublicApi(mainSetting.Registered_User_Id__c, mainSetting.Registered_Password__c);

        HttpRequest request = new HttpRequest();
        request.setEndpoint('https://scarchdev.freemyip.com/api/v2/archive/jobs');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Authorization', 'Bearer ' + accessToken);
        request.setBody(payloadJson);

        System.debug('ScArch describe-driven archive request endpoint: ' + request.getEndpoint());
        System.debug('ScArch describe-driven archive request headers: ' + request.getHeader('Content-Type') + '; Authorization=Bearer ' + accessToken.substring(0, Math.min(accessToken.length(), 12)) + '...');
        System.debug('ScArch describe-driven archive request body: ' + payloadJson);

        Http http = new Http();
        HttpResponse response = http.send(request);

        System.debug('ScArch describe-driven archive response status: ' + response.getStatusCode());
        System.debug('ScArch describe-driven archive response body: ' + response.getBody());

        return response;
    }

    public static HttpResponse sendArchiveJobRequest(String namedCredentialName, String payloadJson) {
        if (String.isBlank(namedCredentialName)) {
            throw new IllegalArgumentException('Named credential name is required for archive job request.');
        }

        scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
        if (mainSetting == null || String.isBlank(mainSetting.Registered_User_Id__c) || String.isBlank(mainSetting.Registered_Password__c)) {
            throw new IllegalArgumentException('Registration credentials are required before sending an archive job.');
        }

        String accessToken = getOdooAccessToken(namedCredentialName, mainSetting.Registered_User_Id__c, mainSetting.Registered_Password__c);

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + namedCredentialName + '/archive/jobs');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Authorization', 'Bearer ' + accessToken);
        request.setHeader('X-Principal', 'scArch_Principal');
        request.setBody(payloadJson);

        System.debug('ScArch archive request endpoint: callout:' + namedCredentialName + '/archive/jobs');
        System.debug('ScArch archive request body: ' + payloadJson);

        Http http = new Http();
        HttpResponse response = http.send(request);

        System.debug('ScArch archive response status: ' + response.getStatusCode());
        System.debug('ScArch archive response body: ' + response.getBody());

        return response;
    }

    public static HttpResponse sendArchiveJobUpdateRequest(String namedCredentialName, String jobId, String payloadJson) {
        if (String.isBlank(namedCredentialName)) {
            throw new IllegalArgumentException('Named credential name is required for archive job update request.');
        }
        if (String.isBlank(jobId)) {
            throw new IllegalArgumentException('Job id is required for archive job update request.');
        }

        scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
        if (mainSetting == null || String.isBlank(mainSetting.Registered_User_Id__c) || String.isBlank(mainSetting.Registered_Password__c)) {
            throw new IllegalArgumentException('Registration credentials are required before updating an archive job.');
        }

        String accessToken = getOdooAccessToken(namedCredentialName, mainSetting.Registered_User_Id__c, mainSetting.Registered_Password__c);

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + namedCredentialName + '/archive/jobs/' + jobId);
        request.setMethod('PUT');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Authorization', 'Bearer ' + accessToken);
        request.setHeader('X-Principal', 'scArch_Principal');
        request.setBody(payloadJson);

        System.debug('ScArch archive update request endpoint: callout:' + namedCredentialName + '/archive/jobs/' + jobId);
        System.debug('ScArch archive update request body: ' + payloadJson);

        Http http = new Http();
        HttpResponse response = http.send(request);

        System.debug('ScArch archive update response status: ' + response.getStatusCode());
        System.debug('ScArch archive update response body: ' + response.getBody());

        return response;
    }

    public static String getOdooAccessToken(String namedCredentialName, String userId, String password) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + namedCredentialName + '/auth/token');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('X-Principal', 'scArch_Principal');
        request.setBody(JSON.serialize(new Map<String, Object>{
            'userId' => userId,
            'password' => password
        }));

        Http http = new Http();
        HttpResponse response = http.send(request);

        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new CalloutException('Token request failed with status ' + response.getStatusCode() + '.');
        }

        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        if (responseBody == null || !responseBody.containsKey('code')) {
            throw new CalloutException('Token response did not include a code.');
        }

        String code = String.valueOf(responseBody.get('code'));
        String message = responseBody.containsKey('message') ? String.valueOf(responseBody.get('message')) : '';
        Object dataObj = responseBody.get('data');

        if (code != '0' || dataObj == null) {
            throw new CalloutException(String.isBlank(message) ? 'Token request failed.' : message);
        }

        Map<String, Object> data = (Map<String, Object>) dataObj;
        if (data == null || !data.containsKey('access_token')) {
            throw new CalloutException('Token response did not include access_token.');
        }

        return String.valueOf(data.get('access_token'));
    }

    public static String getOdooAccessTokenFromPublicApi(String userId, String password) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('https://scarchdev.freemyip.com/api/v1/auth/token');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('X-Principal', 'scArch_Principal');

        String tokenRequestBody = JSON.serialize(new Map<String, Object>{
            'userId' => userId,
            'password' => password
        });
        request.setBody(tokenRequestBody);

        System.debug('ScArch token request endpoint: ' + request.getEndpoint());
        System.debug('ScArch token request body: ' + tokenRequestBody);

        Http http = new Http();
        HttpResponse response = http.send(request);

        System.debug('ScArch token response status: ' + response.getStatusCode());
        System.debug('ScArch token response body: ' + response.getBody());

        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new CalloutException('Token request failed with status ' + response.getStatusCode() + '.');
        }

        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        if (responseBody == null || !responseBody.containsKey('code')) {
            throw new CalloutException('Token response did not include a code.');
        }

        String code = String.valueOf(responseBody.get('code'));
        String message = responseBody.containsKey('message') ? String.valueOf(responseBody.get('message')) : '';
        Object dataObj = responseBody.get('data');

        if (code != '0' || dataObj == null) {
            throw new AuraHandledException(String.isBlank(message) ? 'Token request failed.' : message);
        }

        Map<String, Object> data = (Map<String, Object>) dataObj;
        if (data == null || !data.containsKey('access_token')) {
            throw new AuraHandledException('Token response did not include access_token.');
        }

        return String.valueOf(data.get('access_token'));
    }

    public static List<Map<String, String>> getRequestFieldMetadata(String objectName, String fieldSetName) {
        if (String.isBlank(objectName)) {
            return new List<Map<String, String>>();
        }

        List<Map<String, String>> fieldMetadata;

        if (String.isBlank(fieldSetName)) {
            fieldMetadata = getQueryableFieldMetadata(objectName);
        } else {
            List<String> fieldNames = parseConfiguredFieldNames(fieldSetName);
            if (!fieldNames.isEmpty() && !hasFieldSet(objectName, fieldSetName)) {
                fieldMetadata = getMetadataForSelectedFieldNames(objectName, fieldNames);
            } else {
                fieldMetadata = getFieldSetMetadata(objectName, fieldSetName);
                if (fieldMetadata == null || fieldMetadata.isEmpty()) {
                    if (!fieldNames.isEmpty()) {
                        fieldMetadata = getMetadataForSelectedFieldNames(objectName, fieldNames);
                    } else {
                        fieldMetadata = getQueryableFieldMetadata(objectName);
                    }
                }
            }
        }

        return ensureRequiredRequestFields(objectName, fieldMetadata);
    }

    public static Boolean hasFieldSet(String objectName, String fieldSetName) {
        if (String.isBlank(objectName) || String.isBlank(fieldSetName)) {
            return false;
        }

        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectName);
        if (sobjectType == null) {
            return false;
        }

        Map<String, Schema.FieldSet> fieldSets = sobjectType.getDescribe().fieldSets.getMap();
        return fieldSets != null && fieldSets.containsKey(fieldSetName.trim());
    }

    private static List<String> parseConfiguredFieldNames(String fieldSetName) {
        if (String.isBlank(fieldSetName)) {
            return new List<String>();
        }

        List<String> result = new List<String>();
        for (String token : fieldSetName.split(',')) {
            String fieldName = token.trim();
            if (String.isNotBlank(fieldName)) {
                result.add(fieldName);
            }
        }
        return result;
    }

    private static List<Map<String, String>> getMetadataForSelectedFieldNames(String objectName, List<String> fieldNames) {
        if (String.isBlank(objectName) || fieldNames == null || fieldNames.isEmpty()) {
            return new List<Map<String, String>>();
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectName)) {
            return new List<Map<String, String>>();
        }

        Map<String, Schema.SObjectField> fieldMap = globalDescribe.get(objectName).getDescribe().fields.getMap();
        List<Map<String, String>> fieldMetadata = new List<Map<String, String>>();
        Set<String> seen = new Set<String>();

        for (String fieldName : fieldNames) {
            if (String.isBlank(fieldName) || seen.contains(fieldName)) {
                continue;
            }
            if (!fieldMap.containsKey(fieldName)) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            fieldMetadata.add(new Map<String, String>{
                'name' => fieldDescribe.getName(),
                'type' => String.valueOf(fieldDescribe.getType()),
                'object' => objectName,
                'length' => String.valueOf(fieldDescribe.getLength())
            });
            seen.add(fieldName);
        }

        return fieldMetadata;
    }

    public static List<Map<String, String>> getFieldSetMetadata(String objectName, String fieldSetName) {
        if (String.isBlank(objectName) || String.isBlank(fieldSetName)) {
            return new List<Map<String, String>>();
        }

        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectName);
        if (sobjectType == null) {
            return new List<Map<String, String>>();
        }

        Map<String, Schema.FieldSet> fieldSets = sobjectType.getDescribe().fieldSets.getMap();
        if (fieldSets == null || !fieldSets.containsKey(fieldSetName)) {
            return new List<Map<String, String>>();
        }

        List<Map<String, String>> fieldMetadata = new List<Map<String, String>>();
        Set<String> seenFields = new Set<String>();

        for (Schema.FieldSetMember member : fieldSets.get(fieldSetName).getFields()) {
            String fieldPath = member.getFieldPath();
            if (String.isBlank(fieldPath) || seenFields.contains(fieldPath)) {
                continue;
            }

            fieldMetadata.add(new Map<String, String>{
                'name' => fieldPath,
                'type' => String.valueOf(member.getType()),
                'object' => objectName,
                'length' => '0'
            });
            seenFields.add(fieldPath);
        }

        return fieldMetadata;
    }

    public static List<String> getQueryableFieldNames(String objectName) {
        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectName);
        if (sobjectType == null) {
            return new List<String>{'Id'};
        }

        List<String> fieldNames = new List<String>();
        Schema.DescribeSObjectResult describe = sobjectType.getDescribe();
        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (!fieldDescribe.isAccessible() || fieldDescribe.isDeprecatedAndHidden()) {
                continue;
            }
            if (fieldDescribe.getType() == Schema.DisplayType.BASE64) {
                continue;
            }
            fieldNames.add(fieldDescribe.getName());
        }

        if (!fieldNames.contains('Id')) {
            fieldNames.add('Id');
        }
        return fieldNames;
    }

    public static List<Map<String, String>> getQueryableFieldMetadata(String objectName) {
        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectName);
        if (sobjectType == null) {
            return new List<Map<String, String>>{
                new Map<String, String>{'name' => 'Id', 'type' => 'Id'}
            };
        }
        List<Map<String, String>> fieldMetadata = new List<Map<String, String>>();
        Schema.DescribeSObjectResult describe = sobjectType.getDescribe();
        Boolean hasId = false;

        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (!fieldDescribe.isAccessible() || fieldDescribe.isDeprecatedAndHidden()) {
                continue;
            }
            if (fieldDescribe.getType() == Schema.DisplayType.BASE64) {
                continue;
            }

            String fieldName = fieldDescribe.getName();
            String fieldType = String.valueOf(fieldDescribe.getType());
            Integer fldLength = 0;
            try {
                fldLength = fieldDescribe.getLength();
            } catch (Exception e) {
                fldLength = 0;
            }

            fieldMetadata.add(new Map<String, String>{
                'name' => fieldName,
                'type' => fieldType,
                'object' => objectName,
                'length' => String.valueOf(fldLength)
            });
            if (fieldName == 'Id') {
                hasId = true;
            }
        }

        if (!hasId) {
            fieldMetadata.add(new Map<String, String>{'name' => 'Id', 'type' => 'Id', 'object' => objectName, 'length' => '0'});
        }
        return fieldMetadata;
    }

    public static List<SObject> queryArchiveRecords(String objectName, Date firstArchiveDate, Datetime lastArchiveDate) {
        List<String> fields = getQueryableFieldNames(objectName);
        String fieldList = String.join(fields, ', ');

        List<String> whereClauses = new List<String>();
        if (lastArchiveDate != null) {
            whereClauses.add('LastModifiedDate > ' + formatDatetimeLiteral(lastArchiveDate));
        }
        if (firstArchiveDate != null) {
            Datetime upperBound = Datetime.newInstance(firstArchiveDate, Time.newInstance(23, 59, 59, 999));
            whereClauses.add('LastModifiedDate <= ' + formatDatetimeLiteral(upperBound));
        }

        String query = 'SELECT ' + fieldList + ' FROM ' + objectName;
        if (!whereClauses.isEmpty()) {
            query += ' WHERE ' + String.join(whereClauses, ' AND ');
        }

        return Database.query(query);
    }

    public static List<SObject> queryChildRecords(String childObjectName, String childForeignKey, Set<Id> parentIds, Date firstArchiveDate, Datetime lastArchiveDate) {
        List<String> fields = getQueryableFieldNames(childObjectName);
        if (!fields.contains(childForeignKey)) {
            fields.add(childForeignKey);
        }
        String fieldList = String.join(fields, ', ');

        List<String> whereClauses = new List<String>();
        whereClauses.add(childForeignKey + ' IN (' + buildIdListLiteral(parentIds) + ')');
        if (lastArchiveDate != null) {
            whereClauses.add('LastModifiedDate > ' + formatDatetimeLiteral(lastArchiveDate));
        }
        if (firstArchiveDate != null) {
            Datetime upperBound = Datetime.newInstance(firstArchiveDate, Time.newInstance(23, 59, 59, 999));
            whereClauses.add('LastModifiedDate <= ' + formatDatetimeLiteral(upperBound));
        }

        String query = 'SELECT ' + fieldList + ' FROM ' + childObjectName + ' WHERE ' + String.join(whereClauses, ' AND ');
        return Database.query(query);
    }

    public static String formatDatetimeLiteral(Datetime dt) {
        return '\'' + dt.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\'';
    }

    public static String buildIdListLiteral(Set<Id> ids) {
        List<String> quotedIds = new List<String>();
        for (Id recordId : ids) {
            quotedIds.add('\'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\'');
        }
        return String.join(quotedIds, ', ');
    }

    public static String getChildRelationshipField(String parentObjectName, String childObjectName) {
        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(parentObjectName);
        if (parentType == null) {
            return null;
        }

        Schema.DescribeSObjectResult parentDescribe = parentType.getDescribe();
        for (Schema.ChildRelationship childRel : parentDescribe.getChildRelationships()) {
            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            if (childDescribe.getName() == childObjectName) {
                Schema.SObjectField childField = childRel.getField();
                return childField.getDescribe().getName();
            }
        }
        return null;
    }

    public static Map<String, Object> serializeSObject(SObject record) {
        Map<String, Object> serialized = new Map<String, Object>();
        for (String fieldName : record.getPopulatedFieldsAsMap().keySet()) {
            serialized.put(fieldName, record.get(fieldName));
        }
        return serialized;
    }

    public static String buildArchivePayload(scArch_Archive_Configuration__c parentConfig, List<SObject> parentRecords, Map<Id, List<SObject>> childRecordsByParentId) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('archiveRunAt', System.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
        payload.put('objectName', parentConfig.Object_Name__c);
        payload.put('frequency', parentConfig.Archive_Frequency__c);
        payload.put('archiveChildren', parentConfig.Archive_Children__c);
        payload.put('hasDocuments', parentConfig.Has_Documents__c);
        payload.put('firstArchiveDate', parentConfig.First_Archive_Date__c);
        payload.put('previousArchiveDate', parentConfig.Last_Archive_Date__c);

        List<Map<String, Object>> parentPayloadRecords = new List<Map<String, Object>>();
        for (SObject parentRecord : parentRecords) {
            Map<String, Object> recordMap = serializeSObject(parentRecord);
            Map<String, Object> children = new Map<String, Object>();
            if (childRecordsByParentId.containsKey((Id) parentRecord.get('Id'))) {
                for (SObject childRecord : childRecordsByParentId.get((Id) parentRecord.get('Id'))) {
                    String childObjectName = String.valueOf(childRecord.getSObjectType());
                    if (!children.containsKey(childObjectName)) {
                        children.put(childObjectName, new List<Object>());
                    }
                    ((List<Object>) children.get(childObjectName)).add(serializeSObject(childRecord));
                }
            }
            if (!children.isEmpty()) {
                recordMap.put('childRecords', children);
            }
            parentPayloadRecords.add(recordMap);
        }

        payload.put('records', parentPayloadRecords);
        return JSON.serialize(payload);
    }

    public static HttpResponse sendArchivePayload(String namedCredentialName, String payloadJson) {
        if (String.isBlank(namedCredentialName)) {
            throw new IllegalArgumentException('Named credential name is required for archive push.');
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + namedCredentialName + '/archive');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(payloadJson);

        Http http = new Http();
        return http.send(request);
    }
}
