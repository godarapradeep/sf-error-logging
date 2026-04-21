@IsTest
private class ErrorLogRetryHandlerTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Error_Log__c buildLog(
        String operation,
        String objectType,
        List<SObject> records,
        List<Map<String, Object>> errorDetails
    ) {
        Error_Log__c log = new Error_Log__c(
            Object_Type__c = objectType,
            Operation__c   = operation,
            Error_Count__c = records.size(),
            Status__c      = 'Open',
            Retry_Count__c = 0
        );
        insert log;

        Map<String, Object> payload = new Map<String, Object>{
            'records' => records,
            'errors'  => errorDetails
        };
        ContentVersion cv = new ContentVersion(
            Title          = 'error_payload',
            PathOnClient   = 'error_payload.json',
            VersionData    = Blob.valueOf(JSON.serialize(payload)),
            IsMajorVersion = true
        );
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            LinkedEntityId    = log.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType         = 'V'
        );

        return log;
    }

    private static Map<String, Object> stubError(Id recordId) {
        return new Map<String, Object>{
            'recordId'    => recordId,
            'messages'    => new List<String>{ 'simulated error' },
            'statusCodes' => new List<String>{ 'FIELD_CUSTOM_VALIDATION_EXCEPTION' },
            'fields'      => new List<String>()
        };
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    @IsTest
    static void retry_insertSuccess_resolvesLog() {
        Account a = new Account(Name = 'Retry Insert');
        Error_Log__c log = buildLog(
            'INSERT', 'Account',
            new List<SObject>{ a },
            new List<Map<String, Object>>{ stubError(null) }
        );

        Test.startTest();
        ErrorLogRetryHandler.handleRetry(new List<Error_Log__c>{ log });
        Test.stopTest();

        log = [SELECT Status__c, Retry_Count__c FROM Error_Log__c WHERE Id = :log.Id];
        Assert.areEqual('Resolved', log.Status__c);
        Assert.areEqual(1, (Integer) log.Retry_Count__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'Retry Insert']);
    }

    @IsTest
    static void retry_updateFailure_failsLog() {
        Account ghost = new Account(Id = '001000000000000AAA', Name = 'Ghost');
        Error_Log__c log = buildLog(
            'UPDATE', 'Account',
            new List<SObject>{ ghost },
            new List<Map<String, Object>>{ stubError('001000000000000AAA') }
        );

        Test.startTest();
        ErrorLogRetryHandler.handleRetry(new List<Error_Log__c>{ log });
        Test.stopTest();

        log = [SELECT Status__c, Retry_Count__c FROM Error_Log__c WHERE Id = :log.Id];
        Assert.areEqual('Failed', log.Status__c);
        Assert.areEqual(1, (Integer) log.Retry_Count__c);
    }

    @IsTest
    static void retry_retryCountIncrementsFromExisting() {
        Account ghost = new Account(Id = '001000000000000AAA', Name = 'Ghost');
        Error_Log__c log = buildLog(
            'UPDATE', 'Account',
            new List<SObject>{ ghost },
            new List<Map<String, Object>>{ stubError('001000000000000AAA') }
        );
        log.Retry_Count__c = 2;
        update log;

        Test.startTest();
        ErrorLogRetryHandler.handleRetry(new List<Error_Log__c>{ log });
        Test.stopTest();

        log = [SELECT Retry_Count__c FROM Error_Log__c WHERE Id = :log.Id];
        Assert.areEqual(3, (Integer) log.Retry_Count__c);
    }

    @IsTest
    static void retry_noAttachment_failsLog() {
        Error_Log__c log = new Error_Log__c(
            Object_Type__c = 'Account',
            Operation__c   = 'INSERT',
            Error_Count__c = 1,
            Status__c      = 'Open',
            Retry_Count__c = 0
        );
        insert log;

        Test.startTest();
        ErrorLogRetryHandler.handleRetry(new List<Error_Log__c>{ log });
        Test.stopTest();

        log = [SELECT Status__c FROM Error_Log__c WHERE Id = :log.Id];
        Assert.areEqual('Failed', log.Status__c);
    }

    @IsTest
    static void statusChange_toRetry_triggersHandler() {
        Account a = new Account(Name = 'Trigger Retry');
        Error_Log__c log = buildLog(
            'INSERT', 'Account',
            new List<SObject>{ a },
            new List<Map<String, Object>>{ stubError(null) }
        );

        Test.startTest();
        log.Status__c = 'Retry';
        update log;
        Test.stopTest();

        log = [SELECT Status__c FROM Error_Log__c WHERE Id = :log.Id];
        Assert.areEqual('Resolved', log.Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'Trigger Retry']);
    }
}
