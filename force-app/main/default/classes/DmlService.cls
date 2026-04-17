/**
 * DmlService
 *
 * Centralised DML utility that uses the Database class for granular control.
 * Partial success is the default for all operations — pass allOrNone=true to
 * override. Any record-level failures are persisted to Error_Log__c in the
 * same transaction before the results are returned to the caller.
 */
public without sharing class DmlService {

    private static final String OP_INSERT = 'INSERT';
    private static final String OP_UPDATE = 'UPDATE';
    private static final String OP_UPSERT = 'UPSERT';
    private static final String OP_DELETE = 'DELETE';

    public static Database.SaveResult[] insertRecords(List<SObject> records) {
        return insertRecords(records, false);
    }

    public static Database.SaveResult[] insertRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        Database.SaveResult[] results = Database.insert(records, allOrNone);
        logSaveFailures(records, results, OP_INSERT);
        return results;
    }

    public static Database.SaveResult[] updateRecords(List<SObject> records) {
        return updateRecords(records, false);
    }

    public static Database.SaveResult[] updateRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        Database.SaveResult[] results = Database.update(records, allOrNone);
        logSaveFailures(records, results, OP_UPDATE);
        return results;
    }

    public static Database.UpsertResult[] upsertRecords(List<SObject> records) {
        return upsertRecords(records, false);
    }

    public static Database.UpsertResult[] upsertRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) {
            return new List<Database.UpsertResult>();
        }
        Database.UpsertResult[] results = Database.upsert(records, allOrNone);
        logUpsertFailures(records, results, OP_UPSERT);
        return results;
    }

    public static Database.DeleteResult[] deleteRecords(List<SObject> records) {
        return deleteRecords(records, false);
    }

    public static Database.DeleteResult[] deleteRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) {
            return new List<Database.DeleteResult>();
        }
        Database.DeleteResult[] results = Database.delete(records, allOrNone);
        logDeleteFailures(records, results, OP_DELETE);
        return results;
    }

    private static void logSaveFailures(
        List<SObject> records,
        Database.SaveResult[] results,
        String operation
    ) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        Map<Schema.SObjectType, String> typeCache = new Map<Schema.SObjectType, String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                logs.add(buildLog(records[i], resolveTypeName(records[i], typeCache), results[i].getErrors(), operation));
            }
        }
        persistLogs(logs);
    }

    private static void logUpsertFailures(
        List<SObject> records,
        Database.UpsertResult[] results,
        String operation
    ) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        Map<Schema.SObjectType, String> typeCache = new Map<Schema.SObjectType, String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                logs.add(buildLog(records[i], resolveTypeName(records[i], typeCache), results[i].getErrors(), operation));
            }
        }
        persistLogs(logs);
    }

    private static void logDeleteFailures(
        List<SObject> records,
        Database.DeleteResult[] results,
        String operation
    ) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        Map<Schema.SObjectType, String> typeCache = new Map<Schema.SObjectType, String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                logs.add(buildLog(records[i], resolveTypeName(records[i], typeCache), results[i].getErrors(), operation));
            }
        }
        persistLogs(logs);
    }

    private static String resolveTypeName(SObject record, Map<Schema.SObjectType, String> typeCache) {
        Schema.SObjectType soType = record.getSObjectType();
        if (!typeCache.containsKey(soType)) {
            typeCache.put(soType, soType.getDescribe().getName());
        }
        return typeCache.get(soType);
    }

    private static Error_Log__c buildLog(
        SObject record,
        String typeName,
        List<Database.Error> errors,
        String operation
    ) {
        List<String> messages = new List<String>();
        List<String> codes    = new List<String>();
        List<String> fields   = new List<String>();

        for (Database.Error err : errors) {
            messages.add(err.getMessage());
            codes.add(err.getStatusCode().name());
            if (!err.getFields().isEmpty()) {
                fields.add(String.join(err.getFields(), ', '));
            }
        }

        return new Error_Log__c(
            Object_Type__c   = typeName,
            Record_Id__c     = record.Id,
            Operation__c     = operation,
            Error_Message__c = String.join(messages, '\n'),
            Status_Code__c   = String.join(codes, '\n'),
            Fields__c        = String.join(fields, '\n')
        );
    }

    private static void persistLogs(List<Error_Log__c> logs) {
        if (logs.isEmpty()) {
            return;
        }
        Database.insert(logs, false);
    }
}
