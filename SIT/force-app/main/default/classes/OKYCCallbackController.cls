public without sharing class OKYCCallbackController {
    public OKYCCallbackController() {

    }

    public class OKYCRespWrapper{
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Boolean isError;
        @AuraEnabled public Id integrationChecklistId;
    }


    @AuraEnabled
    public static OKYCRespWrapper processOKYCResponse(String intChecklistId){

        // Based on the Integration Checklist Id, Initiate the Callout
        OKYCRespWrapper wrapper = new OKYCRespWrapper();
        try {

            if(intChecklistId == null){
                throw newMessageException('Invalid URL');
            }
        
            List<Integration_Checklist__c> checklist = [
                                                    SELECT Id, Applicant__c, Applicant__r.Office_Email__c,Is_Request_in_Attachment__c, Request__c,
                                                    Mocking_Service_Response__c, Mocking_Service_Status__c,Mocking_Service_Status_Code__c,Integration_Master__c,
                                                    End_Point_URL__c, Accept_Encoding__c,Content_Type__c, SourceName__c, Is_Mocking_Service__c
                                                    FROM Integration_Checklist__c
                                                    WHERE Id =: intChecklistId
                                                ];


            if(checklist.size() == 1){
                // Fetch the Auth Code now
                // Call ESB API for Next Step

                String result = invokeOKYCDecryptApi(checklist[0]);
                if(result != 'Success'){
                    wrapper.isError = true;
                    wrapper.errorMessage = result;
                }
                else{
                    wrapper.isError = false;
                    wrapper.integrationChecklistId = checklist[0].Id;
                }
                return wrapper;
            }
            else{
                throw newMessageException('Invalid URL');
            }

        } catch (Exception e) {
            throw newMessageException(e.getMessage());
        }
    }

    // Directly Calling API instead of Framework, as its 
    // Not dependent on Applicant / Other Values needed
    public static String invokeOKYCDecryptApi(Integration_Checklist__c intChecklist){

        String resultMessage = '';

        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = IntegrationUtility.createInputWrapper('OKYC');
        inputWrapper.integrationChecklistRecord = intChecklist;
        
        String className = inputWrapper.integrationMasterRecord.Apex_Class_Name__c;
        IntegrationHandlerInterface service = (IntegrationHandlerInterface) Type.forName(className).newInstance();

        IntegrationUtility util = new IntegrationUtility();

        List<IntegrationUtility.RequestWrapper> calloutRequests = 
            (List<IntegrationUtility.RequestWrapper>)service.generateCallouts(new List<CommonCalloutEventPublisher.AutoIntegrationsInputWrapper>{inputWrapper});
        
        IntegrationUtility.RequestWrapper requestWrapper = calloutRequests[0];
        requestWrapper.checklistRecord = intChecklist;
        //requestWrapper.captureResponseInAttachment = true;
        IntegrationUtility.ResponseWrapper response = util.initiateCallout(requestWrapper);

        if(response.statusCode == 200){

            List<ContentDocumentLink> link = [
                                                SELECT ContentDocumentId 
                                                FROM ContentDocumentLink 
                                                WHERE LinkedEntityId =: intChecklist.Id 
                                                LIMIT 1
                                            ];
            if(link.size() == 1){
                List<ContentVersion> version = [
                                                SELECT Id, VersionData
                                                FROM ContentVersion
                                                WHERE ContentDocumentId =: link[0].ContentDocumentId
                                                LIMIT 1
                                            ];
                                            
                OKYCHandler handler = new OKYCHandler();
                handler.callbackService(new List<Integration_Checklist__c>{intChecklist}, version);
                if(intChecklist.Status__c == 'Completed'){
                    resultMessage = 'Success';
                }
                else{
                    resultMessage = 'OKYC Verification Failed.' + intChecklist.Failure_Reason__c;   
                }
            }
            else{
                resultMessage = 'OKYC Verification Failed.';
            }
        }
        else{
            resultMessage = 'OKYC Verification Failed. '+ response.response;
        }

        return resultMessage;
    }


    @AuraEnabled
    public static Integration_Checklist__c getIntegrationChecklist(Id intCheck){
        try {
            return [
                        SELECT Id, Address_Line_1__c, Address_Line_2__c, Address_Line_3__c,
                            Pincode__c, District__c, City__c, State__c, Applicant__c,
                            (SELECT ContentDocumentId
                             FROM ContentDocumentLinks)
                        FROM Integration_Checklist__c
                        WHERE Id =: intCheck
            ];
        } catch (Exception e) {
            throw newMessageException(e.getMessage());
        }
    }


    public class KYCWrapper{
        @AuraEnabled
        public String base64Data;
        @AuraEnabled
        public String contentChecklistId;
    }

    @AuraEnabled
    public static KYCWrapper getKycPhoto(List<Id> contentDocIds){
        try {
            KYCWrapper wrapper = new KYCWrapper();
            ContentVersion cont = [
                SELECT Id, VersionData, ContentDocument.FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId in: contentDocIds
                AND Document_Checklist__r.Document_Master__r.Document_Name__c = 'CKYC Photo'
                AND IsLatest = true
                LIMIT 1
            ];

            String base64Data = 'data:image/' + cont.ContentDocument.FileExtension + ';charset=utf-8;base64, ';
            base64Data += EncodingUtil.base64Encode(cont.VersionData);
            wrapper.base64Data = base64Data;
            wrapper.contentChecklistId = cont.Id;

            // Aslo Insert a Content Dostribution Here, to
            // Display in PDF for Digilocker
            ContentManager__e peRec = new ContentManager__e();
            peRec.KYC_Content_Version_Id__c = cont.Id;
            EventBus.publish(peRec);

            return wrapper;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    
    /**
     * DLTS received from URL to be base 64 decoded, 
     * And Address Values to be retrieved as URL Params
     */
    /*
    @AuraEnabled
    public static OKYCDetails getOkycDetails(string dlts){
        try {
            
            OKYCDetails details = new OKYCDetails();
            String sUrl = EncodingUtil.urlDecode(dlts, 'utf-8');
            Blob t = EncodingUtil.base64Decode(sUrl);
            System.debug(t.toString());
            
            // Creating a URL for fetching parameters
            String url = 'www.test.com?'+t.toString();
            PageReference urlPR = new PageReference(url);

            Map<String, String> params = urlPR.getParameters();
            String jsonStr = JSON.serialize(params);
            details = (OKYCDetails)JSON.deserialize(jsonStr, OKYCDetails.class);
            return details;

        } catch (Exception e) {
            System.debug(e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }
    */

    @AuraEnabled
    public static string createAddress(Address__c address, Integer pincode){
        try {
            Pincode_Master__c master = new Pincode_Master__c(Pincode__c = String.valueOf(pinCode));
            address.Pincode__r = master;
            insert address;
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static string initiateLiveliness(String applicantId){
        try {
            
            String url = LivelinessCheckController.initiateLivelinessFromDigilocker(applicantId);
            return url;
            
        } catch (Exception e) {
            throw newMessageException(e.getMessage());
        }
    }

    private static AuraHandledException newMessageException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    public class OKYCDetails{
        @AuraEnabled public string address {get; set;}
        @AuraEnabled public string pincode {get; set;}
        @AuraEnabled public string city {get; set;}
        @AuraEnabled public string state {get; set;}
    }
    
}