@isTest
private class ScArchGenericDataTableControllerTest {
    @isTest
    static void testBuildTableModelUsesFieldSetFallbackAndPagination() {
        Map<String, Object> payloadBody = new Map<String, Object>{
            'data' => new Map<String, Object>{
                'records' => new List<Object>{
                    new Map<String, Object>{'Id' => '001000000000001', 'Name' => 'Acme', 'CreatedDate' => '2024-01-01T00:00:00.000Z'},
                    new Map<String, Object>{'Id' => '001000000000002', 'Name' => 'Globex', 'CreatedDate' => '2024-01-02T00:00:00.000Z'}
                },
                'totalCount' => 2,
                'hasNext' => false
            }
        };

        Test.startTest();
        Map<String, Object> model = ScArchGenericDataTableController.buildTableModel(
            'Account',
            payloadBody,
            1,
            200,
            new List<String>{'Id', 'Name', 'CreatedDate'}
        );
        Test.stopTest();

        System.assertNotEquals(null, model.get('columns'));
        System.assertEquals(2, ((List<Map<String, Object>>) model.get('rows')).size());
        Map<String, Object> pagination = (Map<String, Object>) model.get('pagination');
        System.assertEquals(1, pagination.get('page'));
        System.assertEquals(false, pagination.get('hasNext'));
    }
}
