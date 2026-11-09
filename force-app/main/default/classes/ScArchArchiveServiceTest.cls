@IsTest
private class ScArchArchiveServiceTest {
    @isTest
    static void buildArchiveJobPayload_excludesOrgDomain() {
        scArch_Archive_Configuration__c config = new scArch_Archive_Configuration__c(
            Object_Name__c = 'Account',
            Archive_Frequency__c = 'Daily',
            Archive_Children__c = false
        );

        Test.startTest();
        String payloadJson = ScArchArchiveService.buildArchiveJobPayload(config, new List<String>{ 'Contact' });
        Test.stopTest();

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        System.assertEquals('Account', payload.get('objectName'));
        System.assertEquals('Daily', payload.get('frequency'));
        System.assertEquals(false, payload.containsKey('orgDomain'));
    }

    @isTest
    static void saveQuickSchedule_callsDescribeDrivenApiWithoutNamedCredential() {
        scArch_Admin_Config__c setting = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'scArch_Integration',
            Registered_User_Id__c = 'api_user',
            Registered_Password__c = 'secret'
        );
        insert setting;

        String configJson = JSON.serialize(new Map<String, Object>{
            'objectEntries' => new List<Object>{
                new Map<String, Object>{
                    'objectName' => 'Opportunity',
                    'frequency' => 'manual',
                    'firstArchiveDate' => Date.today().addDays(-5),
                    'lastArchiveDate' => Date.today(),
                    'archiveChildren' => true
                }
            }
        });

        Test.setMock(HttpCalloutMock.class, new QuickScheduleApiMock());

        Test.startTest();
        Boolean result = ScArchAdminController.saveQuickSchedule(configJson);
        Test.stopTest();

        System.assertEquals(true, result);
    }

    @isTest
    static void saveQuickSchedule_createsChildConfigRecordsForMasterAndLookupRelations() {
        scArch_Admin_Config__c setting = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'scArch_Integration',
            Registered_User_Id__c = 'api_user',
            Registered_Password__c = 'secret'
        );
        insert setting;

        String configJson = JSON.serialize(new Map<String, Object>{
            'objectEntries' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'relation-check-001',
                    'objectName' => 'Account',
                    'frequency' => 'Daily',
                    'firstArchiveDate' => Date.today().addDays(-5),
                    'lastArchiveDate' => Date.today(),
                    'archiveChildren' => true,
                    'masterRelatedObjects' => new List<Object>{ 'Contact', 'Opportunity' },
                    'lookupRelatedObjects' => new List<Object>{ 'Case' }
                }
            }
        });

        Test.startTest();
        Boolean result = ScArchAdminController.saveQuickSchedule(configJson);
        Test.stopTest();

        System.assertEquals(true, result);

        List<scArch_Archive_Configuration__c> childConfigs = [
            SELECT Id, Name, Object_Name__c, Parent_Object__c
            FROM scArch_Archive_Configuration__c
            WHERE Parent_Object__c = 'Account'
        ];

        Set<String> childObjectNames = new Set<String>();
        Integer matchingChildRows = 0;
        for (scArch_Archive_Configuration__c config : childConfigs) {
            if (config.Name != null && config.Name.contains('relation-check-001')) {
                matchingChildRows++;
                childObjectNames.add(config.Object_Name__c);
            }
        }

        System.assertEquals(3, matchingChildRows);
        System.assert(childObjectNames.contains('Contact'));
        System.assert(childObjectNames.contains('Opportunity'));
        System.assert(childObjectNames.contains('Case'));
    }

    @isTest
    static void saveQuickSchedule_updatesExistingParentRecordInsteadOfDuplicatingIt() {
        scArch_Admin_Config__c setting = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'scArch_Integration',
            Registered_User_Id__c = 'api_user',
            Registered_Password__c = 'secret'
        );
        insert setting;

        insert new scArch_Archive_Configuration__c(
            Name = 'Account_existing_parent',
            Object_Name__c = 'Account',
            Archive_Frequency__c = 'Weekly',
            Is_Parent__c = true,
            Archive_Children__c = true
        );

        String configJson = JSON.serialize(new Map<String, Object>{
            'objectEntries' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'update-existing-account',
                    'objectName' => 'Account',
                    'frequency' => 'Monthly',
                    'firstArchiveDate' => Date.today().addDays(-10),
                    'lastArchiveDate' => Date.today(),
                    'archiveChildren' => false
                }
            }
        });

        Test.startTest();
        Boolean result = ScArchAdminController.saveQuickSchedule(configJson);
        Test.stopTest();

        System.assertEquals(true, result);

        List<scArch_Archive_Configuration__c> rows = [
            SELECT Id, Object_Name__c, Archive_Frequency__c, Archive_Children__c
            FROM scArch_Archive_Configuration__c
            WHERE Object_Name__c = 'Account' AND Is_Parent__c = true
        ];

        System.assertEquals(1, rows.size());
        System.assertEquals('Monthly', rows[0].Archive_Frequency__c);
        System.assertEquals(false, rows[0].Archive_Children__c);
    }

    @isTest
    static void saveQuickSchedule_promotesExistingChildRecordToParentWithoutDuplication() {
        scArch_Admin_Config__c setting = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'scArch_Integration',
            Registered_User_Id__c = 'api_user',
            Registered_Password__c = 'secret'
        );
        insert setting;

        insert new scArch_Archive_Configuration__c(
            Name = 'Contact_Account_legacy_child',
            Object_Name__c = 'Account',
            Parent_Object__c = 'Contact',
            Is_Parent__c = false,
            Status__c = 'Inactive',
            Archive_Frequency__c = 'Weekly'
        );

        String configJson = JSON.serialize(new Map<String, Object>{
            'objectEntries' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'promote-account-child',
                    'objectName' => 'Account',
                    'frequency' => 'Daily',
                    'firstArchiveDate' => Date.today().addDays(-2),
                    'lastArchiveDate' => Date.today(),
                    'archiveChildren' => false
                }
            }
        });

        Test.startTest();
        Boolean result = ScArchAdminController.saveQuickSchedule(configJson);
        Test.stopTest();

        System.assertEquals(true, result);

        List<scArch_Archive_Configuration__c> parentRows = [
            SELECT Id, Object_Name__c, Parent_Object__c, Is_Parent__c, Status__c, Archive_Frequency__c
            FROM scArch_Archive_Configuration__c
            WHERE Object_Name__c = 'Account'
        ];

        System.assertEquals(1, parentRows.size(), 'Expected a single active parent row for Account after promotion.');
        System.assertEquals(true, parentRows[0].Is_Parent__c);
        System.assertEquals('Active', String.valueOf(parentRows[0].Status__c));
        System.assertEquals('Daily', parentRows[0].Archive_Frequency__c);
        System.assertEquals(null, parentRows[0].Parent_Object__c);
    }

    @isTest
    static void saveQuickSchedule_setsStatusToActiveForParentAndChildRows() {
        scArch_Admin_Config__c setting = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'scArch_Integration',
            Registered_User_Id__c = 'api_user',
            Registered_Password__c = 'secret'
        );
        insert setting;

        String configJson = JSON.serialize(new Map<String, Object>{
            'objectEntries' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'status-check-001',
                    'objectName' => 'Account',
                    'frequency' => 'Daily',
                    'firstArchiveDate' => Date.today().addDays(-3),
                    'lastArchiveDate' => Date.today(),
                    'archiveChildren' => true,
                    'masterRelatedObjects' => new List<Object>{ 'Contact' },
                    'lookupRelatedObjects' => new List<Object>{ 'Case' }
                }
            }
        });

        Test.startTest();
        Boolean result = ScArchAdminController.saveQuickSchedule(configJson);
        Test.stopTest();

        System.assertEquals(true, result);

        List<scArch_Archive_Configuration__c> rows = Database.query(
            'SELECT Id, Object_Name__c, Parent_Object__c, Status__c FROM scArch_Archive_Configuration__c WHERE Object_Name__c IN (\'Account\', \'Contact\', \'Case\') OR Parent_Object__c = \'Account\''
        );

        System.assert(rows.size() >= 3, 'Expected at least the parent and its related child rows to be created. Actual count=' + rows.size());
        Set<String> seenObjects = new Set<String>();
        for (scArch_Archive_Configuration__c row : rows) {
            if (row.Object_Name__c == 'Account' || row.Object_Name__c == 'Contact' || row.Object_Name__c == 'Case' || row.Parent_Object__c == 'Account') {
                seenObjects.add(String.valueOf(row.Object_Name__c));
            }
            System.assertEquals('Active', String.valueOf(row.get('Status__c')));
        }
        System.assert(seenObjects.contains('Account'), 'Expected Account to be present among active rows.');
        System.assert(seenObjects.contains('Contact') || seenObjects.contains('Case'), 'Expected at least one related child object to be present among active rows.');
    }

    @isTest
    static void saveAdminConfiguration_triggersLegacyNamedCredentialCallout() {
        scArch_Admin_Config__c setting = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'scArch_Integration',
            Registered_User_Id__c = 'api_user',
            Registered_Password__c = 'secret'
        );
        insert setting;

        String configJson = JSON.serialize(new Map<String, Object>{
            'namedCredential' => 'scArch_Integration',
            'clientId' => 'client-123',
            'clientSecret' => 'secret-456',
            'clientName' => 'Contoso',
            'objectEntries' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'row-1',
                    'objectName' => 'Account',
                    'isParent' => true,
                    'archiveChildren' => false,
                    'hasDocuments' => false,
                    'frequency' => 'Daily',
                    'fieldSetName' => 'Name',
                    'firstArchiveDate' => Date.today().addDays(-5),
                    'lastArchiveDate' => Date.today(),
                    'selectedRelatedObjects' => new List<Object>()
                }
            }
        });

        Test.setMock(HttpCalloutMock.class, new LegacyArchiveApiMock());

        Test.startTest();
        Boolean saved = ScArchAdminController.saveAdminConfiguration(configJson);
        Test.stopTest();

        System.assertEquals(true, saved);
    }

    @isTest
    static void saveAdminConfiguration_persistsClientCredentials() {
        String configJson = JSON.serialize(new Map<String, Object>{
            'namedCredential' => 'My_Named_Credential',
            'clientId' => 'client-123',
            'clientSecret' => 'secret-456',
            'clientName' => 'Contoso',
            'objectConfigurations' => new List<Object>()
        });

        Test.startTest();
        Boolean saved = ScArchAdminController.saveAdminConfiguration(configJson);
        Map<String, Object> loaded = ScArchAdminController.getAdminConfiguration();
        Test.stopTest();

        System.assertEquals(true, saved);
        System.assertEquals('client-123', loaded.get('clientId'));
        System.assertEquals('secret-456', loaded.get('clientSecret'));
        System.assertEquals('Contoso', loaded.get('clientName'));
    }

    public class QuickScheduleApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            if (request.getEndpoint().contains('/auth/scArchToken')) {
                response.setBody('{"code":"0","message":"success","data":{"access_token":"abc123","expires_in":600}}');
                return response;
            }

            if (request.getEndpoint().contains('/api/v2/archive/scArchCreateArchiveJob')) {
                response.setBody('{"code":"0","message":"success","data":{"status":"Accepted","jobId":"job_123"}}');
                return response;
            }

            response.setBody('{"code":"0","message":"ok"}');
            return response;
        }
    }

    public class LegacyArchiveApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            if (request.getEndpoint().contains('/auth/scArchToken')) {
                response.setBody('{"code":"0","message":"success","data":{"access_token":"legacy_token_123","expires_in":600}}');
                return response;
            }

            if (request.getEndpoint().contains('/archive/scArchCreateArchiveJob')) {
                response.setBody('{"code":"0","message":"success","data":{"status":"Accepted","jobId":"legacy_job_123"}}');
                return response;
            }

            response.setBody('{"code":"0","message":"ok"}');
            return response;
        }
    }

    @isTest
    static void saveAdminConfiguration_convertsSelectedFieldListToString() {
        scArch_Admin_Config__c defaultConfig = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'scArch_Integration',
            Registered_User_Id__c = 'api_user',
            Registered_Password__c = 'secret'
        );
        insert defaultConfig;

        Test.setMock(HttpCalloutMock.class, new LegacyArchiveApiMock());

        Map<String, Object> payload = new Map<String, Object>{
            'namedCredential' => 'My_Named_Credential',
            'clientId' => 'client-123',
            'clientSecret' => 'secret-456',
            'clientName' => 'Contoso',
            'objectConfigurations' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'row-1',
                    'objectName' => 'Account',
                    'isParent' => true,
                    'archiveChildren' => false,
                    'hasDocuments' => false,
                    'frequency' => 'Daily',
                    'fieldSetName' => new List<Object>{ 'Name', 'Phone', 'CreatedDate' },
                    'firstArchiveDate' => null,
                    'lastArchiveDate' => null,
                    'selectedRelatedObjects' => new List<Object>()
                }
            }
        };

        String configJson = JSON.serialize(payload);

        Test.startTest();
        Boolean saved = ScArchAdminController.saveAdminConfiguration(configJson);
        Map<String, Object> loaded = ScArchAdminController.getAdminConfiguration();
        Test.stopTest();

        System.assertEquals(true, saved);
        List<Object> objectEntries = (List<Object>) loaded.get('objectEntries');
        System.assertNotEquals(null, objectEntries);
        System.assertEquals(1, objectEntries.size());
    }

    @isTest
    static void saveAdminConfiguration_preservesExistingRecordsWhenAddingNewOnly() {
        scArch_Admin_Config__c defaultConfig = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'scArch_Integration',
            Registered_User_Id__c = 'api_user',
            Registered_Password__c = 'secret'
        );
        insert defaultConfig;

        scArch_Archive_Configuration__c existing = new scArch_Archive_Configuration__c(
            Name = 'Account_existing_Parent',
            Object_Name__c = 'Account',
            Archive_Frequency__c = 'Daily',
            Field_Set_Name__c = 'Name',
            Is_Parent__c = true,
            Archive_Children__c = false,
            Has_Documents__c = false,
            First_Archive_Date__c = Date.today().addDays(-10),
            Last_Archive_Date__c = Date.today()
        );
        insert existing;

        Test.setMock(HttpCalloutMock.class, new LegacyArchiveApiMock());

        Map<String, Object> payload = new Map<String, Object>{
            'namedCredential' => 'My_Named_Credential',
            'clientId' => 'client-123',
            'clientSecret' => 'secret-456',
            'clientName' => 'Contoso',
            'objectConfigurations' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'row-2',
                    'objectName' => 'Contact',
                    'isParent' => true,
                    'archiveChildren' => false,
                    'hasDocuments' => false,
                    'frequency' => 'Weekly',
                    'fieldSetName' => 'Name',
                    'firstArchiveDate' => Date.today().addDays(-5),
                    'lastArchiveDate' => Date.today(),
                    'selectedRelatedObjects' => new List<Object>()
                }
            }
        };

        Test.startTest();
        Boolean saved = ScArchAdminController.saveAdminConfiguration(JSON.serialize(payload));
        Map<String, Object> loaded = ScArchAdminController.getAdminConfiguration();
        Test.stopTest();

        System.assertEquals(true, saved);
        List<Object> objectEntries = (List<Object>) loaded.get('objectEntries');
        System.assertNotEquals(null, objectEntries);
        System.assertEquals(2, objectEntries.size());
    }
}
