public with sharing class ScArchArchiveScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ScArchArchiveBatch(), 10);
    }

    public static void scheduleDaily() {
        String cronExpression = '0 0 2 * * ?';
        System.schedule('ScArch Archive Daily', cronExpression, new ScArchArchiveScheduler());
    }
}
