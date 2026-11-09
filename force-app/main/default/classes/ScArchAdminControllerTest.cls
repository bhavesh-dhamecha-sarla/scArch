@IsTest
private class ScArchAdminControllerTest {
    @isTest
    static void registerInstance_usesClientSecretFromCustomSetting() {
        scArch_Admin_Config__c config = new scArch_Admin_Config__c(
            Name = 'Default',
            Named_Credential__c = 'Test_Named_Credential',
            Client_ID__c = 'client-123',
            Client_Name__c = 'Contoso',
            Registered_User_Id__c = 'user',
            Registered_Password__c = 'pass',
            DB_Password__c = 'existing-secret'
        );
        insert config;

        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        Map<String, Object> result = ScArchAdminController.registerInstance('client-123', 'secret-456', '64.0');
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        scArch_Admin_Config__c updatedConfig = scArch_Admin_Config__c.getInstance('Default');
        System.assertEquals('secret-456', String.valueOf(updatedConfig.get('DB_Password__c')));
    }

    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            if (request.getEndpoint().contains('/auth/scArchToken')) {
                response.setBody(JSON.serialize(new Map<String, Object>{
                    'code' => '0',
                    'message' => 'ok',
                    'data' => new Map<String, Object>{
                        'access_token' => 'token-123'
                    }
                }));
            } else {
                response.setBody(JSON.serialize(new Map<String, Object>{
                    'code' => '0',
                    'message' => 'ok',
                    'data' => new Map<String, Object>{
                        'instanceId' => '123',
                        'status' => 'active'
                    }
                }));
            }

            return response;
        }
    }
}
