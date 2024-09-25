public without sharing class OKYCHandler implements IntegrationHandlerInterface{

    private Map<String, String[]> attributeMappingPoA = new Map<String, String[]>{
        
        'Address_Line_1__c' => new String[]{'house', 'street', 'postoffice'},
        'Address_Line_2__c' => new String[]{'location', 'subdist', 'dist'},
        'Landmark__c' => new String[]{'landmark'},
        'District__c' => new String[]{'dist'},
        'State__c' => new String[]{'state'},
        'Pincode__c' => new String[]{'pincode'}
    };

    public List<sObject> generatePlatformEvents(List<Object> recordList) {
        return null;
    } 

    public List<Object> generateCallouts(List<Object> recordList) {
        // To be returned
        List<IntegrationUtility.RequestWrapper> requestWrappers = new List<IntegrationUtility.RequestWrapper>();

        // Also, only one Record will be passed here.
        List<CommonCalloutEventPublisher.AutoIntegrationsInputWrapper> wrappers = (List<CommonCalloutEventPublisher.AutoIntegrationsInputWrapper>)recordList;

        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper wrapper = wrappers[0];
        Integration_Checklist__c intChecklist = wrapper.integrationChecklistRecord;
        IntegrationUtility.RequestWrapper returnWrapper = new IntegrationUtility.RequestWrapper();
        returnWrapper.endpointURL =  wrapper.integrationMasterRecord.End_Point_URL__c;
        returnWrapper.method = Constants.POST_METHOD;
        returnWrapper.headersMap = new Map<String, String>{
            'ConversationID' => intChecklist.Id,
            'SourceName' => wrapper.integrationMasterRecord.SourceName__c,
            'Authorization' => wrapper.integrationMasterRecord.Authorization_Key__c
        };

        returnWrapper.masterRecord = wrapper.integrationMasterRecord;
        returnWrapper.checklistRecord = intChecklist;
        returnWrapper.contentType =  wrapper.integrationMasterRecord.Content_Type__c;
        returnWrapper.request = intChecklist.Request__c;
        returnWrapper.captureResponseInAttachment = true;
        requestWrappers.add(returnWrapper);

        return requestWrappers;
    }

    public List<Object> generateRequest(List<Object> recordList) {
        return null;
    }

    public List<String> validateInputData(List<Object> recordList) {
        List<String> result = new List<String>();
        return result;
    }

    private OKYCResponse processOkycResponse(Integration_Checklist__c checklistRecord, String jsonStr){

        OKYCResponse resp = (OKYCResponse)JSON.deserialize(jsonStr, OKYCResponse.class);
        // Populate Integration Checklist Address Fields

        if(resp.transactionStatus == 'SUCCESS' && resp.data != null){
            for(String fieldName : attributeMappingPoA.keySet()){
                String fieldVal = '';
                for(String attributeName : attributeMappingPoA.get(fieldName)){
    
                    String attributeValue = resp.data.getValue(attributeName);
                    if(attributeValue != null){
                        fieldVal += ', ' + attributeValue;
                    }
                } 
                checklistRecord.put(fieldName, fieldVal.removeStart(',').trim());
                System.debug(checklistRecord);
            }
        }

        return resp;
    }

    public void callbackService(List<Integration_Checklist__c> checklistRecords, List<ContentVersion> responseFiles) {
    
        Map<Id, String> applicantIdAccount = new Map<Id, String>();
        List<OKYCResponse> result = new List<OKYCResponse>();
        Integration_Checklist__c checklistRecord = checklistRecords[0];   
        List<ContentVersion> newImagesFromResponse = new List<ContentVersion>();

        String responseData = (responseFiles != null && responseFiles.size() > 0 && responseFiles[0] != null) ?responseFiles[0].VersionData.toString() :checklistRecord.Response__c;
        OKYCResponse resp = processOkycResponse(checklistRecord, responseData);
        
        // First find the Applicant
        Integration_Checklist__c oldChecklist = [
            SELECT Id, Applicant__c
            FROM Integration_Checklist__c
            WHERE Id =: resp.requestId
        ];

        if(resp.transactionStatus == 'SUCCESS'){
            checklistRecord.Status__c = Constants.INTEGRATION_CHECKLIST_COMPLETED;
            checklistRecord.Applicant__c = oldChecklist.Applicant__c;
            // Other fields will populated from the method above

            Applicant__c applicantData = [
                SELECT Id, Loan__c
                FROM Applicant__c
                WHERE Id =: oldChecklist.Applicant__c
            ];

            // Get Document Checklist or Create new One
            Id docChecklist = getDocumentChecklist(applicantData);

            // Insert a New Content Verion (Image)
            ContentVersion version = new ContentVersion();
            version.FirstPublishLocationId = checklistRecord.Id;
            version.Title = 'OKYC_KYC_Photo';
            version.PathOnClient = 'okyc_kyc_photo.jpeg';
            version.Document_Checklist__c = docChecklist;
            version.VersionData = EncodingUtil.base64Decode(resp.data.photo);
            newImagesFromResponse.add(version);

            applicantData.OKYC_Status__c = 'Verification Successful';
            applicantData.OKYC_Id__c = 'Aadhaar';
            applicantData.OKYC_Completed_Date__c = Datetime.now();
            //applicant.OKYC_Id_Number__c = resp.data.;
            insert version;
            TriggerHandler.bypass('ApplicantTriggerHandler');
            update applicantData;
            TriggerHandler.clearBypass('ApplicantTriggerHandler');

        }
        else{
            checklistRecord.Status__c = Constants.INTEGRATION_CHECKLIST_FAILED;
            checklistRecord.Failure_Reason__c = 'OKYC could not be completed';
            checklistRecord.Applicant__c = oldChecklist.Applicant__c;
        }

        update checklistRecord;

    }

    private String getDocumentChecklist(Applicant__c applicant){


        List<Document_Master__c> masters = [
                                                SELECT Id, Document_Name__c, Document_Type__c,
                                                DMS_Document_Type__c, Document_Flag__c, Collection_Stage__c
                                                FROM Document_Master__c
                                                WHERE Document_Name__c = 'CKYC Photo'
                                                AND Document_Type__c = 'Customer Photograph'
                                                LIMIT 1
                                            ];

        if(masters.size() == 1){


            List<Document_Checklist__c> docCheck = [
                SELECT Id, Applicant__c, Document_Master__c
                FROM Document_Checklist__c
                WHERE Document_Master__r.Document_Name__c = 'CKYC Photo'
                AND Applicant__c =: applicant.Id
                ORDER BY CreatedDate desc
                LIMIT 1
            ];
            
            if(docCheck.size() != 0){
                return docCheck[0].Id;
            }

            Document_Checklist__c newDocCheck = new Document_Checklist__c();
            newDocCheck.Document_Type__c = masters[0].Document_Type__c;
            newDocCheck.Document_Name__c = masters[0].Document_Name__c;
            newDocCheck.DMS_Document_Type__c = masters[0].DMS_Document_Type__c;
            newDocCheck.Document_Source__c = masters[0].Document_Flag__c;
            newDocCheck.Collection_Stage__c = masters[0].Collection_Stage__c;
            newDocCheck.Status__c = 'Uploaded';
            newDocCheck.Applicant__c = applicant.Id;
            newDocCheck.Document_Master__c = masters[0].Id;
            newDocCheck.Loan__c = applicant.Loan__c;

            insert newDocCheck;
            return newDocCheck.Id;
        }

        return null;
    }

    // Implement the beforeUpdateService method
    public void beforeUpdateService(Integration_Checklist__c checklistRecord, ContentVersion responseFile) {
    } 

    public class OKYCResponse{
        public String clientId;
        public String requestId;
        public Boolean error;
        public String transactionStatus;
        public OKYCDetails data;
    }

    public class OKYCDetails{
        public string kycType;
        public string name;
        public string address;
        public string photo;
        public string careOf;
        public string house;
        public string street;
        public string postoffice;
        public string landmark;
        public string location;
        public string subdist;
        public string dist;
        public string pincode;
        public string state;

        public String getValue(String variableName) {
            String jsonString = toJSON();
            Map<String, Object> untyped_instance = (Map<String, Object>)JSON.deserializeUntyped(jsonString);
            return (String)untyped_instance.get(variableName);
        }
        
        public string toJSON() {
            return JSON.serialize(this);
        }
    }

}