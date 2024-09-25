global without sharing class Applicant_OVDNotificationBatchJob implements Database.Batchable<SObject>, Database.Stateful, Schedulable, Database.AllowsCallouts, Database.RaisesPlatformEvents {
    public Communication_Master__c cMaster;
    public Boolean isSandbox;
    public Integer OVD_MAX_REMAINDER_COUNT;
    public Integer OVD_NO_DAYS_TO_START_REMAINDER;
    public Applicant_OVDNotificationBatchJob()
    {
        cMaster = [SELECT Id, Name, Communication_Type__c
                   FROM Communication_Master__c
                   WHERE Name='OVD (KYC) Document Collection' LIMIT 1];
        isSandbox = ApplicationUtility.isCurrentOrgSandbox();
        OVD_MAX_REMAINDER_COUNT = Integer.valueOf(ApplicationUtility.getApplIntgConfigMdtValue('OVD_MAX_REMAINDER_COUNT', isSandbox));
        OVD_NO_DAYS_TO_START_REMAINDER = Integer.valueOf(ApplicationUtility.getApplIntgConfigMdtValue('OVD_NO_DAYS_TO_START_REMAINDER', isSandbox));
    }
    
    // Query to fetch relevant applicants
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Date previousDate = system.today().addDays(-OVD_NO_DAYS_TO_START_REMAINDER);
        String query = 'SELECT Id,Name,OVD_Status__c,Loan__c,Encryption_Key__c,OVD_Reminder_Count__c,Communication_Email__c,Loan__r.Disbursal_Entry_Date__c,Loan__r.Product_Category__c,Loan__r.Product_Name__c,Loan__r.Loan_Application_Number__c ' +
            'FROM Applicant__c ' +
            'WHERE OVD_Status__c != \'OVD\' '+
            'AND Communication_Email__c != Null ' +
            'AND Loan__r.StageName = \'Disbursed\' ' +
            'AND Loan__r.Disbursal_Entry_Date__c <=:previousDate  ' +
            'AND ( OVD_Reminder_Count__c < :OVD_MAX_REMAINDER_COUNT Or OVD_Reminder_Count__c=null or OVD_Reminder_Count__c=0)';
        return Database.getQueryLocator(query);
    }
    
    // Process each batch of records
    global void execute(Database.BatchableContext bc, List<Applicant__c> scope) {
        List<Document_Upload_Request__c> applicantDocUploadReqList = new List<Document_Upload_Request__c>();
        Map<Id,Applicant__c> applicantMap = new Map<Id,Applicant__c>(scope);
        Map<Id, Document_Checklist__c> mapApplicantwithChecklist = new Map<Id, Document_Checklist__c>();
        for(Document_Checklist__c docChckLst : [SELECT Id, Applicant__c
                                               FROM Document_Checklist__c  
                                               WHERE Applicant__c IN: applicantMap.keySet()
                                               AND Document_Type__c = 'Proof of Address (POA) - OVD'
                                               AND Status__c = 'Pending'
                                               AND Is_Active__c = true])
        {
            mapApplicantwithChecklist.put(docChckLst.Applicant__c, docChckLst);
        }
        List<Document_Checklist__c> docChckLstList = new List<Document_Checklist__c>();
        for(Id applicant : applicantMap.keySet()){
            if(!mapApplicantwithChecklist.containskey(applicant)){
                Document_Checklist__c docChckLst = new Document_Checklist__c();
                docChckLst.Applicant__c = applicant;
                docChckLst.Document_Type__c = 'Proof of Address (POA) - OVD';
                docChckLst.Is_Active__c = true;
                docChckLst.Status__c = 'Pending';
                docChckLst.Loan__c = applicantMap.get(applicant).Loan__c;
                docChckLstList.add(docChckLst);
            }
        }
        if(!docChckLstList.isEmpty()){
            insert docChckLstList;
        }
        docChckLstList.addall(mapApplicantwithChecklist.values());
        List<Document_Checklist__c> applicantDocPOAPendingList = [SELECT Id,Name,Document_Type__c,Applicant__c,Applicant__r.Loan__c,Applicant__r.Applicant_Name__c  
                                                                  FROM Document_Checklist__c
                                                                  WHERE ID IN: docChckLstList];
        if(!applicantDocPOAPendingList.isEmpty()){
            Document_Upload_Request__c docUploadRequest;
            for(Document_Checklist__c applicantDocPOAPending : applicantDocPOAPendingList){
                if(!mapApplicantwithChecklist.containskey(applicantDocPOAPending.Applicant__c)){
                    docUploadRequest = new Document_Upload_Request__c();
                    docUploadRequest.Applicant__c = applicantDocPOAPending.Applicant__c;
                    docUploadRequest.Applicant_Name__c = applicantDocPOAPending.Applicant__r.Applicant_Name__c;
                    docUploadRequest.Document_Checklist__c = applicantDocPOAPending.Id;
                    docUploadRequest.Loan_Application__c = applicantDocPOAPending.Applicant__r.Loan__c;
                    applicantDocUploadReqList.add(docUploadRequest);
                }  
            }
            if(!applicantDocUploadReqList.isEmpty()){
                insert applicantDocUploadReqList;
            }
        }
        //Start Digilocker
        Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByType('Digilocker OVD', Constants.INTEGRATION_CHECKLIST_PENDING);
        IntegrationUtility utility = new IntegrationUtility();
        List<Integration_Checklist__c> intchckList = new List<Integration_Checklist__c>();
        for(Id applicantId : applicantMap.keyset()){
            CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            if(integrationMaster != NULL){
                inputWrapper.integrationMasterRecord = integrationMaster;
                inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
            }
            inputWrapper.applicantRecord = applicantMap.get(applicantId);
            IntegrationUtility.HTTPRequestWrapper httpRequestWrapper = utility.constructRequest(inputWrapper);
            Integration_Checklist__c intcheck = new Integration_Checklist__c();
            intcheck.Applicant__c = applicantId;
            intcheck.Status__c = Constants.INTEGRATION_CHECKLIST_PENDING;
            intcheck.Is_Latest__c = true;
            intcheck.Integration_Master__c = inputWrapper.integrationMasterRecord.Id;
            intcheck.Request__c = httpRequestWrapper.request;
            intchckList.add(intcheck);
        }
        if(!intchckList.isEmpty()){
            insert intchckList;
        }
        //End Digilocker
        List<Communication__e> lstCommunicationEvts = new List<Communication__e>();
        for (Applicant__c applicant : scope) {
            if(applicant.Encryption_Key__c != null){
                Communication__e evt = new Communication__e();
                evt.Communication_Master__c = cMaster.Id;
                evt.Communication_Type__c = cMaster.Communication_Type__c;
                evt.Applicant_Email__c = applicant.Communication_Email__c;
                evt.Applicant_Name__c = applicant.Name;
                evt.Encryption_Key__c = applicant.Encryption_Key__c;
                evt.ProductCategory__c = applicant.Loan__r.Product_Category__c;
                evt.Applicant__c = applicant.Id;
                evt.Is_Shorten_API_Required_c__c = true;
                evt.Merge_Field_1__c = applicant.Loan__r.Product_Name__c;
                evt.Merge_Field_2__c = applicant.Loan__r.Loan_Application_Number__c;
                lstCommunicationEvts.add(evt);
                applicant.OVD_Reminder_Count__c = applicant.OVD_Reminder_Count__c == null?1:applicant.OVD_Reminder_Count__c+1;
            }       
        }
        
        // Update applicants with the new reminder count
        if (!scope.isEmpty()) {
            update scope;
        }
        if(!lstCommunicationEvts.isEmpty()){
            List<Database.SaveResult> results = EventBus.publish(lstCommunicationEvts);
        }
    }
    
    // Finish method
    global void finish(Database.BatchableContext bc) {
        // Optional: Add any final operations or logging here
    }
    
    // Schedulable method
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new Applicant_OVDNotificationBatchJob());
    }
    
    // Method to schedule the batch job
    global static void scheduleBatch() {
        String cronExpression = '0 0 0 * * ?'; // Every day at midnight
        System.schedule('Daily Applicant OVD Notification Batch Job', cronExpression, new Applicant_OVDNotificationBatchJob());
    }
}