trigger ErrorLogTrigger on Error_Log__c (after update) {
    List<Error_Log__c> retryLogs = new List<Error_Log__c>();
    for (Error_Log__c log : Trigger.new) {
        Error_Log__c old = Trigger.oldMap.get(log.Id);
        if (log.Status__c == 'Retry' && old.Status__c == 'Open') {
            retryLogs.add(log);
        }
    }
    if (!retryLogs.isEmpty()) {
        ErrorLogRetryHandler.handleRetry(retryLogs);
    }
}
