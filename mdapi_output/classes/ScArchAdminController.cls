public with sharing class ScArchAdminController {
    public class ObjectOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public ObjectOption(String label, String value) {
            this.label = label;
            this.value = value;
        }

        public Integer compareTo(Object obj) {
            ObjectOption other = (ObjectOption) obj;
            return String.valueOf(label).toLowerCase().compareTo(String.valueOf(other.label).toLowerCase());
        }
    }

    @future(callout=true)
    public static void triggerArchiveJobsFuture(String namedCredentialName, List<String> parentConfigNames) {
        submitObjectDetailArchiveJobs(namedCredentialName, parentConfigNames);
    }

    @future(callout=true)
    public static void triggerQuickScheduleJobsFuture(String namedCredentialName, String configJson) {
        if (String.isBlank(namedCredentialName) || String.isBlank(configJson)) {
            return;
        }

        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
        List<Object> configuredObjects = config.get('objectEntries') instanceof List<Object>
            ? (List<Object>) config.get('objectEntries')
            : null;

        submitQuickScheduleArchiveJobs(namedCredentialName, configuredObjects);
    }

    private static void submitObjectDetailArchiveJobs(String namedCredentialName, List<String> parentConfigNames) {
        if (String.isBlank(namedCredentialName) || parentConfigNames == null || parentConfigNames.isEmpty()) {
            return;
        }

        List<scArch_Archive_Configuration__c> parentConfigs = [
            SELECT Id, Name, Object_Name__c, Archive_Frequency__c, Archive_Children__c, First_Archive_Date__c, Last_Archive_Date__c, Field_Set_Name__c
            FROM scArch_Archive_Configuration__c
            WHERE Name IN :parentConfigNames
        ];

        for (scArch_Archive_Configuration__c parentConfig : parentConfigs) {
            List<scArch_Archive_Configuration__c> childConfigs = [
                SELECT Object_Name__c
                FROM scArch_Archive_Configuration__c
                WHERE Parent_Object__c = :parentConfig.Object_Name__c
                AND Is_Parent__c = false
            ];

            List<String> childObjectNames = new List<String>();
            for (scArch_Archive_Configuration__c childConfig : childConfigs) {
                if (!String.isBlank(childConfig.Object_Name__c)) {
                    childObjectNames.add(childConfig.Object_Name__c);
                }
            }

            String payload = ScArchArchiveService.buildArchiveJobPayload(parentConfig, childObjectNames);
            ScArchArchiveService.sendArchiveJobRequest(namedCredentialName, payload);
        }
    }

    private static void submitQuickScheduleArchiveJobs(String namedCredentialName, List<Object> configuredObjects) {
        if (String.isBlank(namedCredentialName) || configuredObjects == null || configuredObjects.isEmpty()) {
            return;
        }

        for (Object obj : configuredObjects) {
            Map<String, Object> objConfig = (Map<String, Object>) obj;
            String objectName = (String) objConfig.get('objectName');
            String frequency = (String) objConfig.get('frequency');
            Object startDateObj = objConfig.get('firstArchiveDate');
            Object endDateObj = objConfig.get('lastArchiveDate');

            if (String.isBlank(objectName) || String.isBlank(frequency)) {
                continue;
            }

            Date startDate = parseDateValue(startDateObj, null);
            Date endDate = parseDateValue(endDateObj, null);
            if (startDate == null) {
                throw new AuraHandledException('First Date of Archive is required for object: ' + objectName);
            }
            if (endDate == null) {
                throw new AuraHandledException('Last Date of Archive is required for object: ' + objectName);
            }

            String correlationId = 'sf-quick-' + objectName + '-' + String.valueOf(Crypto.getRandomLong());
            String payload = ScArchArchiveService.buildDescribeDrivenArchiveJobPayload(
                UserInfo.getOrganizationId(),
                ScArchArchiveService.isSandboxOrganization() ? 'sandbox' : 'production',
                objectName,
                startDate,
                endDate,
                frequency,
                correlationId
            );

            HttpResponse response = ScArchArchiveService.sendDescribeDrivenArchiveJob(namedCredentialName, payload);
            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new AuraHandledException('Quick schedule request failed for ' + objectName + ': ' + response.getBody());
            }
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAllObjectOptions() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        List<ObjectOption> options = new List<ObjectOption>();

        for (Schema.SObjectType sobjectType : globalDescribe.values()) {
            Schema.DescribeSObjectResult describe = sobjectType.getDescribe();
            if (!describe.isQueryable() || describe.isDeprecatedAndHidden() || describe.isCustomSetting()) {
                continue;
            }

            String label = describe.getLabel();
            if (String.isBlank(label) || label.contains('__MISSING LABEL__') || label.contains('not found in section')) {
                label = describe.getName();
            }

            options.add(new ObjectOption(label, describe.getName()));
        }

        options.sort();
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getObjectFields(String objectName) {
        if (String.isBlank(objectName)) {
            return new List<ObjectOption>();
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectName)) {
            return new List<ObjectOption>();
        }

        Map<String, Schema.SObjectField> fieldMap = globalDescribe.get(objectName).getDescribe().fields.getMap();
        List<ObjectOption> options = new List<ObjectOption>();

        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (!fieldDescribe.isAccessible() || fieldDescribe.isDeprecatedAndHidden() || fieldDescribe.getType() == Schema.DisplayType.BASE64) {
                continue;
            }

            String fieldName = fieldDescribe.getName();
            options.add(new ObjectOption(fieldDescribe.getLabel(), fieldName));
        }

        options.sort();
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getRelatedObjects(String objectName) {
        if (String.isBlank(objectName)) {
            return new List<ObjectOption>();
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectName)) {
            return new List<ObjectOption>();
        }

        Schema.DescribeSObjectResult describe = globalDescribe.get(objectName).getDescribe();
        List<Schema.ChildRelationship> childRelationships = describe.getChildRelationships();
        List<ObjectOption> relatedOptions = new List<ObjectOption>();

        for (Schema.ChildRelationship childRel : childRelationships) {
            if (!childRel.isCascadeDelete()) {
                continue;
            }

            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            if (!childDescribe.isQueryable() || childDescribe.isDeprecatedAndHidden()) {
                continue;
            }

            String label = childDescribe.getLabel();
            if (String.isBlank(label) || label.contains('__MISSING LABEL__')) {
                label = childDescribe.getName();
            }

            relatedOptions.add(new ObjectOption(label, childDescribe.getName()));
        }

        relatedOptions.sort();
        return relatedOptions;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean validateNamedCredential(String credentialName) {
        if (String.isBlank(credentialName)) {
            return true;
        }

        try {
            List<SObject> results = [SELECT DeveloperName FROM NamedCredential WHERE DeveloperName = :credentialName LIMIT 1];
            return !results.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    private static String normalizeFieldSelectionValue(Object fieldValue) {
        if (fieldValue == null) {
            return null;
        }

        List<String> values = new List<String>();
        if (fieldValue instanceof String) {
            for (String token : String.valueOf(fieldValue).split(',')) {
                String value = token.trim();
                if (String.isNotBlank(value)) {
                    values.add(value);
                }
            }
        } else if (fieldValue instanceof List<Object>) {
            for (Object item : (List<Object>) fieldValue) {
                if (item != null) {
                    String value = String.valueOf(item).trim();
                    if (String.isNotBlank(value)) {
                        values.add(value);
                    }
                }
            }
        } else {
            String value = String.valueOf(fieldValue).trim();
            if (String.isNotBlank(value)) {
                values.add(value);
            }
        }

        List<String> uniqueValues = new List<String>();
        Set<String> seenValues = new Set<String>();
        for (String value : values) {
            if (seenValues.contains(value)) {
                continue;
            }
            seenValues.add(value);
            uniqueValues.add(value);
        }

        String normalized = String.join(uniqueValues, ',');
        if (normalized.length() > 255) {
            normalized = normalized.substring(0, 255);
            while (normalized.endsWith(',')) {
                normalized = normalized.substring(0, normalized.length() - 1).trim();
            }
        }

        return String.isBlank(normalized) ? null : normalized;
    }

    private static Boolean isSystemField(String fieldName) {
        if (String.isBlank(fieldName)) {
            return true;
        }

        String normalized = fieldName.trim();
        Set<String> systemFields = new Set<String>{
            'Id',
            'IsDeleted',
            'CreatedById',
            'CreatedDate',
            'LastModifiedById',
            'LastModifiedDate',
            'SystemModstamp',
            'OwnerId',
            'LastActivityDate',
            'LastViewedDate',
            'LastReferencedDate'
        };

        return systemFields.contains(normalized) || normalized.startsWith('LastViewed') || normalized.startsWith('LastReferenced') || normalized.startsWith('CreatedBy') || normalized.startsWith('LastModifiedBy') || normalized.startsWith('SystemModstamp');
    }

    private static String getRowKey(Object rawId, String objectName) {
        if (rawId != null && String.valueOf(rawId) != '') {
            return String.valueOf(rawId);
        }
        Long timestamp = System.now().getTime();
        return (String.isNotBlank(objectName) ? objectName + '_' : '') + String.valueOf(timestamp);
    }

    private static String extractRowKeyFromName(String configName) {
        if (String.isBlank(configName)) {
            return null;
        }

        List<String> tokens = configName.split('_');
        if (tokens.size() < 2) {
            return null;
        }

        String possibleKey = tokens[tokens.size() - 1];
        if (possibleKey == 'Parent' || possibleKey == 'Child') {
            possibleKey = tokens[tokens.size() - 2];
        }

        if (String.isBlank(possibleKey) || possibleKey == 'Parent' || possibleKey == 'Child') {
            return null;
        }

        return possibleKey;
    }

    private static Map<String, Object> buildObjectEntry(scArch_Archive_Configuration__c config, Map<String, List<String>> childNamesByRowKey) {
        String rowKey = extractRowKeyFromName(config.Name);
        if (String.isBlank(rowKey)) {
            rowKey = String.valueOf(config.Id);
        }

        Map<String, Object> entry = new Map<String, Object>();
        entry.put('id', rowKey);
        entry.put('objectName', config.Object_Name__c);
        entry.put('frequency', config.Archive_Frequency__c);
        entry.put('fieldSetName', config.Field_Set_Name__c);
        entry.put('isParent', config.Is_Parent__c == true);
        entry.put('archiveChildren', config.Archive_Children__c == true);
        entry.put('hasDocuments', config.Has_Documents__c == true);
        entry.put('firstArchiveDate', config.First_Archive_Date__c);
        entry.put('lastArchiveDate', config.Last_Archive_Date__c);
        entry.put('selectedRelatedObjects', childNamesByRowKey.containsKey(rowKey)
            ? childNamesByRowKey.get(rowKey)
            : new List<String>());

        return entry;
    }

    @AuraEnabled
    public static Map<String, Object> getAdminConfiguration() {
        Map<String, Object> result = new Map<String, Object>();

        try {
            scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');

            if (mainSetting == null) {
                result.put('namedCredential', null);
                result.put('clientId', null);
                result.put('clientSecret', null);
                result.put('clientName', null);
                result.put('productKey', null);
                result.put('registrationStatus', null);
                result.put('subscriptionExpiry', null);
                result.put('objectEntries', new List<Object>());
                return result;
            }

            result.put('namedCredential', mainSetting.Named_Credential__c);
            result.put('clientId', mainSetting.get('Client_ID__c'));
            result.put('clientSecret', mainSetting.get('DB_Password__c'));
            result.put('clientName', mainSetting.get('Client_Name__c'));
            result.put('productKey', mainSetting.Product_Key__c);
            result.put('registrationStatus', mainSetting.Registration_Status__c);
            result.put('subscriptionExpiry', mainSetting.Subscription_Expiry__c);
            result.put('databaseHost', mainSetting.DB_Host__c);
            result.put('databasePort', mainSetting.DB_Port__c);
            result.put('databaseName', mainSetting.DB_Name__c);
            result.put('databaseUser', mainSetting.DB_User__c);

            List<scArch_Archive_Configuration__c> archiveConfigs = [
                SELECT Id, Name, Object_Name__c, Parent_Object__c, Archive_Frequency__c, Field_Set_Name__c,
                    Is_Parent__c, Archive_Children__c, Has_Documents__c, First_Archive_Date__c, Last_Archive_Date__c
                FROM scArch_Archive_Configuration__c
                ORDER BY Object_Name__c
            ];

            Map<String, List<String>> childNamesByRowKey = new Map<String, List<String>>();
            for (scArch_Archive_Configuration__c config : archiveConfigs) {
                if (config.Is_Parent__c != true && String.isNotBlank(config.Parent_Object__c)) {
                    String parentRowKey = extractRowKeyFromName(config.Name);
                    if (String.isBlank(parentRowKey)) {
                        parentRowKey = config.Parent_Object__c + '_' + String.valueOf(config.Id);
                    }
                    if (!childNamesByRowKey.containsKey(parentRowKey)) {
                        childNamesByRowKey.put(parentRowKey, new List<String>());
                    }
                    childNamesByRowKey.get(parentRowKey).add(config.Object_Name__c);
                }
            }

            List<Object> objectEntries = new List<Object>();
            for (scArch_Archive_Configuration__c config : archiveConfigs) {
                if (config.Is_Parent__c == true) {
                    objectEntries.add(buildObjectEntry(config, childNamesByRowKey));
                }
            }

            result.put('objectEntries', objectEntries);

        } catch (Exception e) {
            System.debug('Error fetching admin configuration: ' + e.getMessage());
            result.put('error', e.getMessage());
        }

        return result;
    }

    @AuraEnabled
    public static Boolean saveQuickSchedule(String configJson) {
        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            List<Object> configuredObjects = config.get('objectEntries') instanceof List<Object>
                ? (List<Object>) config.get('objectEntries')
                : null;

            if (configuredObjects == null || configuredObjects.isEmpty()) {
                throw new AuraHandledException('At least one object is required for a quick schedule.');
            }

            scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
            if (mainSetting == null) {
                throw new AuraHandledException('Registration settings must be configured before creating a quick schedule.');
            }

            String namedCredentialName = mainSetting.Named_Credential__c;
            if (String.isBlank(namedCredentialName)) {
                throw new AuraHandledException('Named Credential is required before creating a quick schedule.');
            }

            if (String.isBlank(mainSetting.Registered_User_Id__c) || String.isBlank(mainSetting.Registered_Password__c)) {
                throw new AuraHandledException('Registration credentials are required before creating a quick schedule.');
            }

            triggerQuickScheduleJobsFuture(namedCredentialName, configJson);

            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to submit quick schedule: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Boolean saveObjectDetailConfiguration(String configJson) {
        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);

            scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
            if (mainSetting == null) {
                mainSetting = new scArch_Admin_Config__c(Name = 'Default');
            }

            String clientId = config.containsKey('clientId') ? (String) config.get('clientId') : null;
            String clientSecret = config.containsKey('clientSecret') ? (String) config.get('clientSecret') : null;
            String dbPassword = config.containsKey('databasePassword') ? (String) config.get('databasePassword') : (String) config.get('dbPass');
            String namedCredentialValue = config.containsKey('namedCredential') ? (String) config.get('namedCredential') : null;
            String clientNameValue = config.containsKey('clientName') ? (String) config.get('clientName') : null;
            String dbHostValue = config.containsKey('databaseHost') ? (String) config.get('databaseHost') : null;
            String dbPortValue = config.containsKey('databasePort') ? (String) config.get('databasePort') : null;
            String dbNameValue = config.containsKey('databaseName') ? (String) config.get('databaseName') : null;
            String dbUserValue = config.containsKey('databaseUser') ? (String) config.get('databaseUser') : null;

            if (String.isNotBlank(namedCredentialValue)) {
                mainSetting.Named_Credential__c = namedCredentialValue;
            }
            if (String.isNotBlank(clientId)) {
                mainSetting.put('Client_ID__c', clientId);
            }
            if (String.isNotBlank(clientNameValue)) {
                mainSetting.put('Client_Name__c', clientNameValue);
            }
            if (String.isNotBlank(dbHostValue)) {
                mainSetting.DB_Host__c = dbHostValue;
            }
            if (String.isNotBlank(dbPortValue)) {
                mainSetting.DB_Port__c = dbPortValue;
            }
            if (String.isNotBlank(dbNameValue)) {
                mainSetting.DB_Name__c = dbNameValue;
            }
            if (String.isNotBlank(dbUserValue)) {
                mainSetting.DB_User__c = dbUserValue;
            }

            if (String.isNotBlank(clientSecret)) {
                mainSetting.put('DB_Password__c', clientSecret);
            } else if (String.isNotBlank(dbPassword)) {
                mainSetting.put('DB_Password__c', dbPassword);
            }

            upsert mainSetting;

            List<scArch_Archive_Configuration__c> objectSettingsToInsert = new List<scArch_Archive_Configuration__c>();

            Object configuredObjectsRaw = config.get('objectConfigurations');
            if (configuredObjectsRaw == null) {
                configuredObjectsRaw = config.get('objectEntries');
            }

            List<Object> configuredObjects = configuredObjectsRaw instanceof List<Object>
                ? (List<Object>) configuredObjectsRaw
                : null;

            if (configuredObjects != null) {
                for (Object obj : configuredObjects) {
                    Map<String, Object> objConfig = (Map<String, Object>) obj;
                    Boolean isExisting = objConfig.containsKey('isExisting') ? Boolean.valueOf(objConfig.get('isExisting')) : false;
                    if (isExisting) {
                        continue;
                    }

                    String objectName = (String) objConfig.get('objectName');
                    Boolean isParent = (Boolean) objConfig.get('isParent');
                    Boolean archiveChildren = (Boolean) objConfig.get('archiveChildren');
                    Boolean hasDocuments = (Boolean) objConfig.get('hasDocuments');
                    String frequency = (String) objConfig.get('frequency');
                    String fieldSetName = normalizeFieldSelectionValue(objConfig.get('fieldSetName'));
                    Object firstArchiveDateObj = objConfig.get('firstArchiveDate');
                    Object lastArchiveDateObj = objConfig.get('lastArchiveDate');
                    List<Object> selectedRelatedObjects = objConfig.get('selectedRelatedObjects') instanceof List<Object>
                        ? (List<Object>) objConfig.get('selectedRelatedObjects')
                        : null;
                    String rowKey = getRowKey(objConfig.get('id'), objectName);

                    if (String.isBlank(objectName)) {
                        continue;
                    }

                    Date firstArchiveDateValue = null;
                    if (firstArchiveDateObj instanceof Date) {
                        firstArchiveDateValue = (Date) firstArchiveDateObj;
                    } else if (firstArchiveDateObj instanceof DateTime) {
                        firstArchiveDateValue = ((DateTime) firstArchiveDateObj).date();
                    } else if (firstArchiveDateObj instanceof String && !String.isBlank((String) firstArchiveDateObj)) {
                        try {
                            firstArchiveDateValue = Date.valueOf((String) firstArchiveDateObj);
                        } catch (Exception e) {
                            try {
                                firstArchiveDateValue = DateTime.parse((String) firstArchiveDateObj).date();
                            } catch (Exception e2) {
                            }
                        }
                    }

                    DateTime lastArchiveDateValue = null;
                    if (lastArchiveDateObj instanceof DateTime) {
                        lastArchiveDateValue = (DateTime) lastArchiveDateObj;
                    } else if (lastArchiveDateObj instanceof Date) {
                        lastArchiveDateValue = DateTime.newInstance((Date) lastArchiveDateObj, Time.newInstance(0, 0, 0, 0));
                    } else if (lastArchiveDateObj instanceof String && !String.isBlank((String) lastArchiveDateObj)) {
                        try {
                            Date parsedDate = Date.valueOf((String) lastArchiveDateObj);
                            lastArchiveDateValue = DateTime.newInstance(parsedDate, Time.newInstance(0, 0, 0, 0));
                        } catch (Exception e) {
                            try {
                                lastArchiveDateValue = DateTime.parse((String) lastArchiveDateObj);
                            } catch (Exception e2) {
                            }
                        }
                    }

                    scArch_Archive_Configuration__c parentSetting = new scArch_Archive_Configuration__c();
                    parentSetting.Name = objectName + '_' + rowKey + '_Parent';
                    parentSetting.Object_Name__c = objectName;
                    parentSetting.Archive_Frequency__c = frequency;
                    parentSetting.Field_Set_Name__c = fieldSetName;
                    parentSetting.Is_Parent__c = true;
                    parentSetting.Archive_Children__c = archiveChildren;
                    parentSetting.Has_Documents__c = hasDocuments == true;
                    parentSetting.put('First_Archive_Date__c', firstArchiveDateValue);
                    parentSetting.put('Last_Archive_Date__c', lastArchiveDateValue);
                    parentSetting.Has_Child_Records__c = selectedRelatedObjects != null && !selectedRelatedObjects.isEmpty();
                    objectSettingsToInsert.add(parentSetting);

                    if (selectedRelatedObjects != null && !selectedRelatedObjects.isEmpty()) {
                        for (Object relatedObj : selectedRelatedObjects) {
                            String relatedObjectName = (String) relatedObj;
                            scArch_Archive_Configuration__c childSetting = new scArch_Archive_Configuration__c();
                            childSetting.Name = objectName + '_' + relatedObjectName + '_' + rowKey + '_Child';
                            childSetting.Object_Name__c = relatedObjectName;
                            childSetting.Archive_Frequency__c = frequency;
                            childSetting.Field_Set_Name__c = fieldSetName;
                            childSetting.Is_Parent__c = false;
                            childSetting.Archive_Children__c = false;
                            childSetting.Has_Documents__c = hasDocuments == true;
                            childSetting.put('First_Archive_Date__c', firstArchiveDateValue);
                            childSetting.put('Last_Archive_Date__c', lastArchiveDateValue);
                            childSetting.Has_Child_Records__c = false;
                            childSetting.Parent_Object__c = objectName;
                            objectSettingsToInsert.add(childSetting);
                        }
                    }
                }
            }

            if (!objectSettingsToInsert.isEmpty()) {
                insert objectSettingsToInsert;

                scArch_Admin_Config__c mainConfig = scArch_Admin_Config__c.getInstance('Default');
                String namedCredentialName = mainConfig != null ? mainConfig.Named_Credential__c : null;
                if (String.isNotBlank(namedCredentialName)) {
                    List<String> parentConfigNames = new List<String>();
                    for (scArch_Archive_Configuration__c configRecord : objectSettingsToInsert) {
                        if (configRecord.Is_Parent__c == true) {
                            parentConfigNames.add(configRecord.Name);
                        }
                    }

                    if (!parentConfigNames.isEmpty()) {
                        triggerArchiveJobsFuture(namedCredentialName, parentConfigNames);
                    }
                }
            }

            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Boolean saveAdminConfiguration(String configJson) {
        return saveObjectDetailConfiguration(configJson);
    }

    @AuraEnabled
    public static Boolean updateArchiveConfiguration(Id configId, String configJson) {
        if (configId == null || String.isBlank(configJson)) {
            throw new AuraHandledException('A valid configuration id and payload are required.');
        }

        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            scArch_Archive_Configuration__c existingConfig = [
                SELECT Id, Name, Object_Name__c, Parent_Object__c, Field_Set_Name__c, Archive_Frequency__c,
                    Is_Parent__c, Archive_Children__c, Has_Documents__c, First_Archive_Date__c, Last_Archive_Date__c
                FROM scArch_Archive_Configuration__c
                WHERE Id = :configId
                LIMIT 1
            ];

            if (existingConfig == null) {
                throw new AuraHandledException('Schedule configuration not found.');
            }

            String objectName = (String) config.get('objectName');
            if (String.isBlank(objectName)) {
                objectName = existingConfig.Object_Name__c;
            }

            existingConfig.Object_Name__c = objectName;
            existingConfig.Archive_Frequency__c = (String) config.get('frequency');
            existingConfig.Field_Set_Name__c = normalizeFieldSelectionValue(config.get('fieldSetName'));
            existingConfig.Is_Parent__c = config.containsKey('isParent') ? Boolean.valueOf(config.get('isParent')) : existingConfig.Is_Parent__c;
            existingConfig.Archive_Children__c = config.containsKey('archiveChildren') ? Boolean.valueOf(config.get('archiveChildren')) : existingConfig.Archive_Children__c;
            existingConfig.Has_Documents__c = config.containsKey('hasDocuments') ? Boolean.valueOf(config.get('hasDocuments')) : existingConfig.Has_Documents__c;

            Object firstArchiveDateObj = config.get('firstArchiveDate');
            Object lastArchiveDateObj = config.get('lastArchiveDate');
            existingConfig.First_Archive_Date__c = parseDateValue(firstArchiveDateObj, existingConfig.First_Archive_Date__c);
            existingConfig.Last_Archive_Date__c = parseLastArchiveDateValue(lastArchiveDateObj, existingConfig.Last_Archive_Date__c);

            update existingConfig;

            scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
            String namedCredentialName = mainSetting != null ? mainSetting.Named_Credential__c : null;
            if (!String.isBlank(namedCredentialName)) {
                List<String> childObjectNames = new List<String>();
                List<Object> selectedRelatedObjects = config.get('selectedRelatedObjects') instanceof List<Object>
                    ? (List<Object>) config.get('selectedRelatedObjects')
                    : new List<Object>();

                for (Object relatedObj : selectedRelatedObjects) {
                    String relatedObjectName = String.valueOf(relatedObj).trim();
                    if (String.isNotBlank(relatedObjectName)) {
                        childObjectNames.add(relatedObjectName);
                    }
                }

                String updatePayload = ScArchArchiveService.buildArchiveJobPayload(existingConfig, childObjectNames);
                updatePayload = updatePayload.replaceFirst('"correlationId"\\s*:\\s*"[^"]+"', '"correlationId":"' + String.valueOf(Crypto.getRandomLong()) + '"');
                ScArchArchiveService.sendArchiveJobUpdateRequest(namedCredentialName, String.valueOf(existingConfig.Id), updatePayload);
            }

            List<Object> selectedRelatedObjects = config.get('selectedRelatedObjects') instanceof List<Object>
                ? (List<Object>) config.get('selectedRelatedObjects')
                : new List<Object>();

            if (existingConfig.Is_Parent__c == true) {
                List<scArch_Archive_Configuration__c> childConfigs = [
                    SELECT Id, Object_Name__c, Parent_Object__c, Archive_Frequency__c, Field_Set_Name__c,
                        Is_Parent__c, Archive_Children__c, Has_Documents__c, First_Archive_Date__c, Last_Archive_Date__c
                    FROM scArch_Archive_Configuration__c
                    WHERE Parent_Object__c = :existingConfig.Object_Name__c
                ];

                Set<String> selectedSet = new Set<String>();
                for (Object relatedObj : selectedRelatedObjects) {
                    String value = String.valueOf(relatedObj).trim();
                    if (String.isNotBlank(value)) {
                        selectedSet.add(value);
                    }
                }

                List<scArch_Archive_Configuration__c> childUpdates = new List<scArch_Archive_Configuration__c>();
                for (scArch_Archive_Configuration__c child : childConfigs) {
                    if (!selectedSet.contains(child.Object_Name__c)) {
                        childUpdates.add(child);
                    }
                }

                if (!childUpdates.isEmpty()) {
                    delete childUpdates;
                }

                for (String relatedObjectName : selectedSet) {
                    if (String.isBlank(relatedObjectName)) {
                        continue;
                    }
                    if ([SELECT COUNT() FROM scArch_Archive_Configuration__c WHERE Parent_Object__c = :existingConfig.Object_Name__c AND Object_Name__c = :relatedObjectName LIMIT 1] == 0) {
                        scArch_Archive_Configuration__c child = new scArch_Archive_Configuration__c();
                        child.Name = existingConfig.Object_Name__c + '_' + relatedObjectName + '_' + String.valueOf(System.now().getTime()) + '_Child';
                        child.Object_Name__c = relatedObjectName;
                        child.Parent_Object__c = existingConfig.Object_Name__c;
                        child.Archive_Frequency__c = existingConfig.Archive_Frequency__c;
                        child.Field_Set_Name__c = existingConfig.Field_Set_Name__c;
                        child.Is_Parent__c = false;
                        child.Archive_Children__c = false;
                        child.Has_Documents__c = existingConfig.Has_Documents__c;
                        child.First_Archive_Date__c = existingConfig.First_Archive_Date__c;
                        child.Last_Archive_Date__c = existingConfig.Last_Archive_Date__c;
                        insert child;
                    }
                }
            }

            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update schedule configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Boolean deleteArchiveConfiguration(Id configId) {
        if (configId == null) {
            throw new AuraHandledException('A valid configuration id is required.');
        }

        try {
            scArch_Archive_Configuration__c configToDelete = [
                SELECT Id, Object_Name__c, Is_Parent__c
                FROM scArch_Archive_Configuration__c
                WHERE Id = :configId
                LIMIT 1
            ];

            List<scArch_Archive_Configuration__c> deleteList = new List<scArch_Archive_Configuration__c>();
            deleteList.add(configToDelete);

            if (configToDelete.Is_Parent__c == true) {
                List<scArch_Archive_Configuration__c> childConfigs = [
                    SELECT Id
                    FROM scArch_Archive_Configuration__c
                    WHERE Parent_Object__c = :configToDelete.Object_Name__c
                ];
                if (!childConfigs.isEmpty()) {
                    deleteList.addAll(childConfigs);
                }
            }

            delete deleteList;
            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to delete schedule configuration: ' + e.getMessage());
        }
    }

    private static Date parseDateValue(Object input, Date fallback) {
        if (input == null) {
            return fallback;
        }

        if (input instanceof Date) {
            return (Date) input;
        }
        if (input instanceof DateTime) {
            return ((DateTime) input).date();
        }
        if (input instanceof String && String.isNotBlank((String) input)) {
            try {
                return Date.valueOf((String) input);
            } catch (Exception e) {
                try {
                    return DateTime.parse((String) input).date();
                } catch (Exception e2) {
                    return fallback;
                }
            }
        }
        return fallback;
    }

    private static DateTime parseLastArchiveDateValue(Object input, DateTime fallback) {
        if (input == null) {
            return fallback;
        }

        if (input instanceof DateTime) {
            return (DateTime) input;
        }
        if (input instanceof Date) {
            return DateTime.newInstance((Date) input, Time.newInstance(0, 0, 0, 0));
        }
        if (input instanceof String && String.isNotBlank((String) input)) {
            try {
                return DateTime.newInstance(Date.valueOf((String) input), Time.newInstance(0, 0, 0, 0));
            } catch (Exception e) {
                try {
                    return DateTime.parse((String) input);
                } catch (Exception e2) {
                    return fallback;
                }
            }
        }
        return fallback;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCompanyInformation() {
        Map<String, Object> result = new Map<String, Object>();

        try {
            Organization org = [SELECT Id, Name, IsSandbox, InstanceName, Country, City, State, PostalCode, Phone, Fax, LanguageLocaleKey, TimeZoneSidKey, CreatedDate FROM Organization LIMIT 1];

            result.put('orgId', org.Id);
            result.put('orgName', org.Name);
            result.put('isProd', !org.IsSandbox);
            result.put('instanceName', org.InstanceName);
            result.put('country', org.Country);
            result.put('state', org.State);
            result.put('city', org.City);
            result.put('postalCode', org.PostalCode);
            result.put('phone', org.Phone);
            result.put('fax', org.Fax);
            result.put('language', org.LanguageLocaleKey);
            result.put('timeZone', org.TimeZoneSidKey);
            result.put('createdDate', org.CreatedDate);

            User currentUser = [SELECT Id, FirstName, LastName, Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

            result.put('firstName', currentUser.FirstName);
            result.put('lastName', currentUser.LastName);
            result.put('email', currentUser.Email);

        } catch (Exception e) {
            System.debug('Error fetching company information: ' + e.getMessage());
            result.put('error', e.getMessage());
        }

        return result;
    }

    @AuraEnabled
    public static Map<String, Object> registerOrg(String firstName, String lastName, String email, Boolean dataHosted, String companyName, String companyTimeZone) {
        try {
            Organization org = [SELECT Id, IsSandbox, Name FROM Organization LIMIT 1];
            scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
            String namedCredential = mainSetting != null ? mainSetting.Named_Credential__c : null;

            if (String.isBlank(namedCredential)) {
                throw new AuraHandledException('Named Credential must be configured before registration.');
            }

            Map<String, Object> payload = new Map<String, Object>{
                'orgId' => org.Id ,
                //'orgId' => org.Id + '' + Integer.valueOf(Math.floor(Math.random() * 1000000)),
                'isProd' => !org.IsSandbox,
                'firstName' => firstName,
                'lastName' => lastName,
                'email' => email,
                'dataHosted' => dataHosted,
                'companyName' => companyName,
                'companyTimeZone' => companyTimeZone
            };

            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:' + namedCredential + '/init/scarchregistration');
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setBody(JSON.serialize(payload));

            Http http = new Http();
            HttpResponse response = http.send(request);

            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new AuraHandledException('Registration call failed with status ' + response.getStatusCode());
            }

            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());

            if (responseBody == null || !responseBody.containsKey('code')) {
                throw new AuraHandledException('Invalid response from registration API.');
            }

            String code = (String) responseBody.get('code');
            String message = (String) responseBody.get('message');
            Object dataObj = responseBody.get('data');

            if (code == null || code != '0' || dataObj == null) {
                String errMsg = message != null && message.length() > 0 ? message : 'Registration failed: ' + code;
                throw new AuraHandledException(errMsg);
            }

            Map<String, Object> data = (Map<String, Object>) dataObj;
            String userId = null;
            String password = null;
            if (data.containsKey('credentials') && data.get('credentials') instanceof Map<String, Object>) {
                Map<String, Object> credentials = (Map<String, Object>) data.get('credentials');
                userId = credentials.containsKey('userId') ? String.valueOf(credentials.get('userId')) : null;
                password = credentials.containsKey('password') ? String.valueOf(credentials.get('password')) : null;
            } else {
                userId = data.containsKey('userId') ? String.valueOf(data.get('userId')) : null;
                password = data.containsKey('password') ? String.valueOf(data.get('password')) : null;
            }
            String productKey = null;
            if (data.containsKey('productKey')) {
                productKey = String.valueOf(data.get('productKey'));
            } else if (data.containsKey('licenseKey')) {
                productKey = String.valueOf(data.get('licenseKey'));
            } else if (data.containsKey('key')) {
                productKey = String.valueOf(data.get('key'));
            } else if (data.containsKey('product_key')) {
                productKey = String.valueOf(data.get('product_key'));
            }
            String instanceId = data.containsKey('instanceId') ? (String) data.get('instanceId') : '';
            String expiryDate = data.containsKey('expiryDate')
                ? (String) data.get('expiryDate')
                : data.containsKey('validUntil')
                    ? (String) data.get('validUntil')
                    : data.containsKey('valid_until')
                        ? (String) data.get('valid_until')
                        : null;

            if (mainSetting == null) {
                mainSetting = new scArch_Admin_Config__c(Name = 'Default');
            }

            if (productKey != null && productKey.length() > 0) {
                mainSetting.Product_Key__c = productKey;
            } else if (mainSetting.Product_Key__c == null) {
                mainSetting.Product_Key__c = '';
            }
            if (userId != null) {
                mainSetting.Registered_User_Id__c = userId;
            }
            if (password != null) {
                mainSetting.Registered_Password__c = password;
            }
            mainSetting.Registration_Status__c = 'Registered';
            if (expiryDate != null) {
                mainSetting.Subscription_Expiry__c = expiryDate;
            }
            upsert mainSetting;

            Map<String, Object> result = new Map<String, Object>();
            result.put('status', 'success');
            result.put('registrationStatus', 'Registered');
            result.put('productKey', productKey != null ? productKey : mainSetting.Product_Key__c);
            result.put('instanceId', instanceId);
            result.put('message', message != null && message.length() > 0 ? message : 'Organization registered successfully.');
            if (expiryDate != null) {
                result.put('expiryDate', expiryDate);
            }
            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error during registration: ' + e.getMessage() + ' ' + e.getStackTraceString());
            throw new AuraHandledException('An error occurred during registration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> registerInstance(String runtimeKey, String runtimeToken, String apiVersion) {
        try {
            Organization org = [SELECT Id, IsSandbox, Name FROM Organization LIMIT 1];
            scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
            String namedCredential = mainSetting != null ? mainSetting.Named_Credential__c : null;

            if (String.isBlank(namedCredential)) {
                throw new AuraHandledException('Named Credential must be configured before instance registration.');
            }

            if (String.isBlank(runtimeKey)) {
                runtimeKey = mainSetting != null ? String.valueOf(mainSetting.get('Client_ID__c')) : null;
            }
            if (String.isBlank(runtimeToken)) {
                runtimeToken = mainSetting != null ? String.valueOf(mainSetting.get('DB_Password__c')) : null;
            }
            if (String.isBlank(runtimeKey) || String.isBlank(runtimeToken)) {
                throw new AuraHandledException('Client ID and Client Secret are required for instance registration.');
            }

            if (mainSetting == null) {
                mainSetting = new scArch_Admin_Config__c(Name = 'Default');
            }
            mainSetting.put('Client_ID__c', runtimeKey);
            mainSetting.put('DB_Password__c', runtimeToken);

            String accessToken = ScArchArchiveService.getOdooAccessToken(
                namedCredential,
                mainSetting != null ? mainSetting.Registered_User_Id__c : null,
                mainSetting != null ? mainSetting.Registered_Password__c : null
            );

            Map<String, Object> payload = new Map<String, Object>{
                'orgId' => org.Id,
                'environment' => org.IsSandbox ? 'sandbox' : 'production',
                'orgDomain' => Url.getOrgDomainUrl().toExternalForm(),
                'apiVersion' => String.isBlank(apiVersion) ? '64.0' : apiVersion,
                'runtimeKey' => runtimeKey,
                'runtimeToken' => runtimeToken
            };

            String normalizedCredential = namedCredential.trim();
            String baseEndpoint = 'callout:' + normalizedCredential;
            if (baseEndpoint.endsWith('/')) {
                baseEndpoint = baseEndpoint.substring(0, baseEndpoint.length() - 1);
            }

            String endpointUrl = baseEndpoint + '/instances/clientdetails';

            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpointUrl);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('Authorization', 'Bearer ' + accessToken);
            request.setBody(JSON.serialize(payload));

            System.debug('ScArch registerInstance request endpoint: ' + endpointUrl);
            System.debug('ScArch registerInstance request body: ' + request.getBody());

            Http http = new Http();
            HttpResponse response = http.send(request);

            System.debug('ScArch registerInstance response status: ' + response.getStatusCode());
            System.debug('ScArch registerInstance response body: ' + response.getBody());

            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new AuraHandledException('Instance registration call failed with status ' + response.getStatusCode());
            }

            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            if (responseBody == null || !responseBody.containsKey('code')) {
                throw new AuraHandledException('Invalid response from instance registration API.');
            }

            String code = responseBody.containsKey('code') ? String.valueOf(responseBody.get('code')) : null;
            String message = responseBody.containsKey('message') ? String.valueOf(responseBody.get('message')) : null;
            Object dataObj = responseBody.get('data');

            if (code == null || code != '0' || dataObj == null) {
                String errMsg = message != null && message.length() > 0 ? message : 'Instance registration failed.';
                throw new AuraHandledException(errMsg);
            }

            Map<String, Object> data = (Map<String, Object>) dataObj;
            upsert mainSetting;

            Map<String, Object> result = new Map<String, Object>();
            result.put('status', 'success');
            result.put('message', message != null && message.length() > 0 ? message : 'Instance registered successfully.');
            result.put('instanceId', data.containsKey('instanceId') ? String.valueOf(data.get('instanceId')) : null);
            result.put('orgId', data.containsKey('orgId') ? String.valueOf(data.get('orgId')) : org.Id);
            result.put('environment', data.containsKey('environment') ? String.valueOf(data.get('environment')) : (org.IsSandbox ? 'sandbox' : 'production'));
            result.put('registrationStatus', data.containsKey('status') ? String.valueOf(data.get('status')) : 'active');

            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error during instance registration: ' + e.getMessage() + ' ' + e.getStackTraceString());
            throw new AuraHandledException('An error occurred during instance registration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> renewSubscription(String productKey) {
        try {
            if (String.isBlank(productKey)) {
                throw new AuraHandledException('Product key is required for renewal.');
            }

            Organization org = [SELECT Id FROM Organization LIMIT 1];
            scArch_Admin_Config__c mainSetting = scArch_Admin_Config__c.getInstance('Default');
            String namedCredential = mainSetting != null ? mainSetting.Named_Credential__c : null;

            if (String.isBlank(namedCredential)) {
                throw new AuraHandledException('Named Credential must be configured before subscription renewal.');
            }

            Map<String, Object> payload = new Map<String, Object>{
                'orgId' => org.Id,
                'productKey' => productKey
            };

            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:' + namedCredential + '/init/validatekey');
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setBody(JSON.serialize(payload));

            Http http = new Http();
            HttpResponse response = http.send(request);

            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new AuraHandledException('Key validation failed with status ' + response.getStatusCode());
            }

            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());

            if (responseBody == null || !responseBody.containsKey('code')) {
                throw new AuraHandledException('Invalid response from key validation.');
            }

            Object codeObj = responseBody.get('code');
            String code = codeObj == null ? null : String.valueOf(codeObj);
            Object messageObj = responseBody.get('message');
            String message = messageObj == null ? null : String.valueOf(messageObj);
            Object dataObj = responseBody.get('data');

            if (code == null || code != '0' || dataObj == null) {
                throw new AuraHandledException((message == null || message.length() == 0) ? 'Invalid or expired Product Key.' : message);
            }

            Map<String, Object> data = (Map<String, Object>) dataObj;

            if (mainSetting == null) {
                mainSetting = new scArch_Admin_Config__c(Name = 'Default');
            }

            mainSetting.Product_Key__c = productKey;
            String expiryDate = data.containsKey('expiryDate')
                ? String.valueOf(data.get('expiryDate'))
                : data.containsKey('validUntil')
                    ? String.valueOf(data.get('validUntil'))
                    : data.containsKey('valid_until')
                        ? String.valueOf(data.get('valid_until'))
                        : null;
            if (expiryDate != null) {
                mainSetting.Subscription_Expiry__c = expiryDate;
            }
            upsert mainSetting;

            Map<String, Object> result = new Map<String, Object>();
            result.put('status', 'success');
            result.put('productKey', productKey);
            result.put('licenseStatus', data.containsKey('licenseStatus') ? String.valueOf(data.get('licenseStatus')) : 'Active');
            result.put('message', 'Subscription renewed successfully.');
            if (expiryDate != null) {
                result.put('expiryDate', expiryDate);
                result.put('validUntil', expiryDate);
                result.put('subscriptionExpiry', expiryDate);
            }
            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error during subscription renewal: ' + e.getMessage());
            throw new AuraHandledException('An error occurred during subscription renewal: ' + e.getMessage());
        }
    }
}