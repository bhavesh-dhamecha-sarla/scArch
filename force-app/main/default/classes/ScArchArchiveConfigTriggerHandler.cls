public with sharing class ScArchArchiveConfigTriggerHandler {
    public static void afterInsert(List<scArch_Archive_Configuration__c> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        // Collect parent object names for newly inserted parent configs that request child creation
        Set<String> parentObjectNames = new Set<String>();
        Map<String, List<scArch_Archive_Configuration__c>> parentsByObject = new Map<String, List<scArch_Archive_Configuration__c>>();

        for (scArch_Archive_Configuration__c rec : newRecords) {
            if (rec == null) continue;
            // Only consider parent configs (ignore Archive_Children__c flag per request)
            if (rec.Is_Parent__c == true && String.isNotBlank(rec.Object_Name__c)) {
                String objName = rec.Object_Name__c;
                parentObjectNames.add(objName);
                if (!parentsByObject.containsKey(objName)) {
                    parentsByObject.put(objName, new List<scArch_Archive_Configuration__c>());
                }
                parentsByObject.get(objName).add(rec);
            }
        }

        if (parentObjectNames.isEmpty()) {
            return;
        }

        // Build child object map using describe information (only include cascade-delete child relationships that are queryable)
        Map<String, Set<String>> childObjectsByParent = new Map<String, Set<String>>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String parentObj : parentObjectNames) {
            try {
                if (!globalDescribe.containsKey(parentObj)) {
                    continue;
                }
                Schema.DescribeSObjectResult parentDesc = globalDescribe.get(parentObj).getDescribe();
                List<Schema.ChildRelationship> childRels = parentDesc.getChildRelationships();
                for (Schema.ChildRelationship rel : childRels) {
                    if (!rel.isCascadeDelete()) continue;
                    Schema.DescribeSObjectResult childDesc = rel.getChildSObject().getDescribe();
                    if (!childDesc.isQueryable() || childDesc.isDeprecatedAndHidden()) continue;
                    String childName = childDesc.getName();
                    if (!childObjectsByParent.containsKey(parentObj)) {
                        childObjectsByParent.put(parentObj, new Set<String>());
                    }
                    childObjectsByParent.get(parentObj).add(childName);
                }
            } catch (Exception e) {
                // Ignore describe failures for a specific object
                System.debug('Failed to describe child relationships for ' + parentObj + ': ' + e.getMessage());
            }
        }

        if (childObjectsByParent.isEmpty()) {
            return;
        }

        // Query existing child configuration records to avoid duplicates
        Set<String> parentNames = new Set<String>();
        parentNames.addAll(childObjectsByParent.keySet());

        // Build a set of existing parentObj|childObj combos
        Set<String> existingPairs = new Set<String>();
        List<scArch_Archive_Configuration__c> existingChildConfigs = [
            SELECT Id, Parent_Object__c, Object_Name__c
            FROM scArch_Archive_Configuration__c
            WHERE Parent_Object__c IN :parentNames
              AND Is_Parent__c = false
        ];
        for (scArch_Archive_Configuration__c ex : existingChildConfigs) {
            String key = String.valueOf(ex.Parent_Object__c) + '|' + String.valueOf(ex.Object_Name__c);
            existingPairs.add(key);
        }

        List<scArch_Archive_Configuration__c> toInsert = new List<scArch_Archive_Configuration__c>();

        for (String parentObj : childObjectsByParent.keySet()) {
            Set<String> childSet = childObjectsByParent.get(parentObj);
            if (childSet == null || childSet.isEmpty()) continue;

            List<scArch_Archive_Configuration__c> parents = parentsByObject.get(parentObj);
            if (parents == null || parents.isEmpty()) continue;

            for (scArch_Archive_Configuration__c parentRec : parents) {
                for (String childObjName : childSet) {
                    String pairKey = parentObj + '|' + childObjName;
                    if (existingPairs.contains(pairKey)) {
                        continue;
                    }

                    scArch_Archive_Configuration__c child = new scArch_Archive_Configuration__c();
                    // Copy most fields from parent, but set object name and parent link appropriately
                    child.Name = parentRec.Object_Name__c + '_' + childObjName + '_' + String.valueOf(System.now().getTime()) + '_Child';
                    child.Object_Name__c = childObjName;
                    child.Parent_Object__c = parentRec.Object_Name__c;
                    child.Archive_Frequency__c = parentRec.Archive_Frequency__c;
                    child.Field_Set_Name__c = parentRec.Field_Set_Name__c;
                    child.Is_Parent__c = false;
                    child.Status__c = parentRec.Status__c != null ? parentRec.Status__c : 'Active';
                    child.Archive_Children__c = false;
                    child.Has_Documents__c = parentRec.Has_Documents__c;
                    child.First_Archive_Date__c = parentRec.First_Archive_Date__c;
                    child.Last_Archive_Date__c = parentRec.Last_Archive_Date__c;
                    child.Has_Child_Records__c = false;

                    toInsert.add(child);
                    // Mark as existing so siblings created in same transaction are not duplicated
                    existingPairs.add(pairKey);
                }
            }
        }

        if (!toInsert.isEmpty()) {
            try {
                insert toInsert;
            } catch (Exception e) {
                // Do not prevent parent insert; log and continue
                System.debug('Failed to insert child scArch_Archive_Configuration__c records: ' + e.getMessage());
            }
        }
    }
}
