trigger ScArchArchiveConfigTrigger on scArch_Archive_Configuration__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ScArchArchiveConfigTriggerHandler.afterInsert(Trigger.new);
    }
}
