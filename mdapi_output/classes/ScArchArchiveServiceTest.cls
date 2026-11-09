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

            if (request.getEndpoint().contains('/auth/token')) {
                response.setBody('{"code":"0","message":"success","data":{"access_token":"abc123","expires_in":600}}');
                return response;
            }

            if (request.getEndpoint().contains('/api/v2/archive/jobs')) {
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

            if (request.getEndpoint().contains('/auth/token')) {
                response.setBody('{"code":"0","message":"success","data":{"access_token":"legacy_token_123","expires_in":600}}');
                return response;
            }

            if (request.getEndpoint().contains('/archive/jobs')) {
                response.setBody('{"code":"0","message":"success","data":{"status":"Accepted","jobId":"legacy_job_123"}}');
                return response;
            }

            response.setBody('{"code":"0","message":"ok"}');
            return response;
        }
    }

    @isTest
    static void saveAdminConfiguration_convertsSelectedFieldListToString() {
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
