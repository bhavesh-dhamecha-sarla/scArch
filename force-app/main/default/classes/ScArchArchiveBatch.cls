public with sharing class ScArchArchiveBatch implements Database.Batchable<scArch_Archive_Configuration__c>, Database.AllowsCallouts {
    private String namedCredentialName;

    public ScArchArchiveBatch() {
        this.namedCredentialName = ScArchArchiveService.getDefaultNamedCredential();
    }

    public ScArchArchiveBatch(String namedCredentialName) {
        this.namedCredentialName = namedCredentialName;
    }

    public Iterable<scArch_Archive_Configuration__c> start(Database.BatchableContext bc) {
        return [
            SELECT Id, Name, Object_Name__c, Archive_Frequency__c, Archive_Children__c,
                   Has_Documents__c, First_Archive_Date__c, Last_Archive_Date__c, Field_Set_Name__c
            FROM scArch_Archive_Configuration__c
            WHERE Is_Parent__c = true AND Object_Name__c != null
        ];
    }

    public void execute(Database.BatchableContext bc, List<scArch_Archive_Configuration__c> scope) {
        if (String.isBlank(namedCredentialName)) {
            System.debug('ScArchArchiveBatch skipped because no Named Credential is configured.');
            return;
        }

        List<scArch_Archive_Configuration__c> updates = new List<scArch_Archive_Configuration__c>();

        for (scArch_Archive_Configuration__c parentConfig : scope) {
            try {
                List<scArch_Archive_Configuration__c> childConfigs = new List<scArch_Archive_Configuration__c>();
                if (parentConfig.Archive_Children__c) {
                    childConfigs = [
                        SELECT Object_Name__c
                        FROM scArch_Archive_Configuration__c
                        WHERE Parent_Object__c = :parentConfig.Object_Name__c
                          AND Is_Parent__c = false
                    ];
                }

                List<String> childObjectNames = new List<String>();
                for (scArch_Archive_Configuration__c childConfig : childConfigs) {
                    childObjectNames.add(childConfig.Object_Name__c);
                }

                String payload = ScArchArchiveService.buildArchiveJobPayload(parentConfig, childObjectNames);
                HttpResponse response = ScArchArchiveService.sendArchiveJobRequest(namedCredentialName, payload);

                if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    parentConfig.Last_Archive_Date__c = System.now();
                    updates.add(parentConfig);
                } else {
                    System.debug('Archive push failed for ' + parentConfig.Object_Name__c + ' with status ' + response.getStatusCode() + ' and body: ' + response.getBody());
                }
            } catch (Exception e) {
                System.debug('Archive push exception for ' + parentConfig.Object_Name__c + ': ' + e.getMessage());
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('ScArchArchiveBatch finished.');
    }
}
