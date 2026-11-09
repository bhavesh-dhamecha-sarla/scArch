@isTest
private class ScArchArchiveConfigTriggerTest {
    @isTest static void testChildConfigsCreatedForParent() {
        // Choose a known object that typically has child relationships
        String parentObjectName = 'Account';

        scArch_Archive_Configuration__c parent = new scArch_Archive_Configuration__c();
        parent.Name = 'TestParent_' + String.valueOf(Crypto.getRandomLong()) + '_Parent';
        parent.Object_Name__c = parentObjectName;
        parent.Archive_Frequency__c = 'Daily';
        parent.Is_Parent__c = true;
        parent.Archive_Children__c = true;
        parent.First_Archive_Date__c = Date.today().addDays(-7);
        parent.Last_Archive_Date__c = Date.today();

        Test.startTest();
        insert parent;
        Test.stopTest();

        // Verify that at least one child config was created for the parent object
        List<scArch_Archive_Configuration__c> createdChildren = [
            SELECT Id, Object_Name__c, Parent_Object__c
            FROM scArch_Archive_Configuration__c
            WHERE Parent_Object__c = :parentObjectName
            AND Is_Parent__c = false
        ];

        System.assert(createdChildren.size() > 0, 'Expected child configuration records to be created for ' + parentObjectName);
    }

    @isTest static void testBulkParentInsertionCreatesChildren() {
        String objA = 'Account';
        String objB = 'Contact';

        scArch_Archive_Configuration__c p1 = new scArch_Archive_Configuration__c(
            Name = 'BulkParent1_' + String.valueOf(Crypto.getRandomLong()) + '_Parent',
            Object_Name__c = objA,
            Archive_Frequency__c = 'Weekly',
            Is_Parent__c = true,
            Archive_Children__c = true,
            First_Archive_Date__c = Date.today().addDays(-30),
            Last_Archive_Date__c = Date.today()
        );

        scArch_Archive_Configuration__c p2 = new scArch_Archive_Configuration__c(
            Name = 'BulkParent2_' + String.valueOf(Crypto.getRandomLong()) + '_Parent',
            Object_Name__c = objB,
            Archive_Frequency__c = 'Weekly',
            Is_Parent__c = true,
            Archive_Children__c = true,
            First_Archive_Date__c = Date.today().addDays(-30),
            Last_Archive_Date__c = Date.today()
        );

        Test.startTest();
        insert new List<scArch_Archive_Configuration__c>{ p1, p2 };
        Test.stopTest();

        Integer countChildren = [SELECT COUNT() FROM scArch_Archive_Configuration__c WHERE Is_Parent__c = false AND Parent_Object__c IN :new List<String>{objA, objB}];
        System.assert(countChildren > 0, 'Expected child configs to be created for bulk parents');
    }
}
