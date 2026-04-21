public class ErrorLogRetryHandler {

    private static final String OP_INSERT = 'INSERT';
    private static final String OP_UPDATE = 'UPDATE';
    private static final String OP_UPSERT = 'UPSERT';
    private static final String OP_DELETE = 'DELETE';

    public static void handleRetry(List<Error_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;

        Set<Id> logIds = new Map<Id, Error_Log__c>(logs).keySet();

        Map<Id, String> payloadByLogId = new Map<Id, String>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId, ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :logIds
            ORDER BY SystemModstamp DESC
        ]) {
            if (!payloadByLogId.containsKey(cdl.LinkedEntityId)) {
                payloadByLogId.put(
                    cdl.LinkedEntityId,
                    cdl.ContentDocument.LatestPublishedVersion.VersionData.toString()
                );
            }
        }

        List<Error_Log__c> toUpdate = new List<Error_Log__c>();
        for (Error_Log__c log : logs) {
            String jsonStr = payloadByLogId.get(log.Id);
            Boolean allSuccess = false;

            if (jsonStr == null) {
                System.debug(LoggingLevel.ERROR, 'ErrorLogRetryHandler: no payload found for log ' + log.Id);
            } else {
                Type listType = Type.forName('List<' + log.Object_Type__c + '>');
                if (listType == null) {
                    System.debug(LoggingLevel.ERROR, 'ErrorLogRetryHandler: unresolvable type ' + log.Object_Type__c);
                } else {
                    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
                    List<Object> rawRecords = (List<Object>) payload.get('records');
                    List<SObject> records = (List<SObject>) JSON.deserialize(JSON.serialize(rawRecords), listType);
                    allSuccess = runOperation(log.Operation__c, records);
                }
            }

            toUpdate.add(new Error_Log__c(
                Id             = log.Id,
                Status__c      = allSuccess ? 'Resolved' : 'Failed',
                Retry_Count__c = (log.Retry_Count__c == null ? 0 : log.Retry_Count__c) + 1
            ));
        }

        update toUpdate;
    }

    private static Boolean runOperation(String operation, List<SObject> records) {
        if (operation == OP_INSERT) {
            return allSaveSucceeded(DmlService.insertRecords(records));
        } else if (operation == OP_UPDATE) {
            return allSaveSucceeded(DmlService.updateRecords(records));
        } else if (operation == OP_UPSERT) {
            for (Database.UpsertResult r : DmlService.upsertRecords(records)) {
                if (!r.isSuccess()) return false;
            }
            return true;
        } else if (operation == OP_DELETE) {
            for (Database.DeleteResult r : DmlService.deleteRecords(records)) {
                if (!r.isSuccess()) return false;
            }
            return true;
        }
        return false;
    }

    private static Boolean allSaveSucceeded(Database.SaveResult[] results) {
        for (Database.SaveResult r : results) {
            if (!r.isSuccess()) return false;
        }
        return true;
    }
}
