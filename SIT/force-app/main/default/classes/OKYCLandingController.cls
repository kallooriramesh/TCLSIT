public without sharing class OKYCLandingController {
    

    @AuraEnabled
    public static Integration_Checklist__c getIntegrationChecklist(String customerKey){
        try {

            if(String.isNotBlank(customerKey)){
                CustomerKeyWrapper custKeyInst = CustomerSiteUtility.parseCustomerKey(customerKey);
                if(String.isNotBlank(custKeyInst.applicantNo)){
                
                    List<Integration_Checklist__c> intCheck = [
                        SELECT Id, CreatedDate,Integration_Master__r.Type__c, Status__c, Applicant__r.OKYC_Status__c
                        FROM Integration_Checklist__c
                        WHERE Applicant__r.Name =: custKeyInst.applicantNo
                        AND Is_Latest__c = true
                        AND (Integration_Master__r.Type__c = 'OKYC - Init')
                        ORDER BY CreatedDate desc
                        LIMIT 1
                    ];
                    if(intCheck.size() == 1 && intCheck[0].Status__c == Constants.INTEGRATION_CHECKLIST_PENDING){


                        KYC_Settings__mdt setting = [SELECT OKYC_Expiry_Hours__c FROM KYC_Settings__mdt LIMIT 1];

                        Long currentDateTime =  DateTime.now().getTime();
                        Long lastLinkSent = intCheck[0].CreatedDate.getTime();
                        Long milliseconds = currentDateTime - lastLinkSent;
                        Long minutes = milliseconds / 60000;
                        Long hours = minutes / 60;
                        Decimal expiryHours = setting.OKYC_Expiry_Hours__c;
                        if(hours > expiryHours){
                            throw CustomAuraHandledException('The OKYC link has been expired. Please contact your Sales Representative to Re-Initiate the same.');
                        }

                        return intCheck[0]; 
                    }
                    else if(intCheck.size() == 1 && intCheck[0].Applicant__r.OKYC_Status__c == 'Verification Successful'){
                        throw CustomAuraHandledException('OKYC has already been completed. Thank you.');
                    }
                    else{
                        throw CustomAuraHandledException('No Pending OKYC request found for this Applicant. Please contact your Sales Representative');
                    }
                }
                else{
                    throw CustomAuraHandledException('Invalid URL. No Applicant found. Please contact your Sales Representative');    
                }
            }
            else{
                throw CustomAuraHandledException('Invalid URL. No Applicant found. Please contact your Sales Representative');
            }
        } catch (Exception e) {
            throw CustomAuraHandledException(e.getMessage());
        }
    }


    /*
    @AuraEnabled
    public static string getApplicantIdFromKey(String customerKey){
        try {

            String urlParameter = EncodingUtil.base64Decode(customerKey).toString();
            CustomerKeyWrapper custKeyInst = (CustomerKeyWrapper)JSON.deserialize(urlParameter, CustomerKeyWrapper.class);
            String applicantNo = custKeyInst.applicantNo;
            List<Applicant__c> applicantRecordList = [
                                            SELECT Id, Name, Email_Verified__c, OKYC_Status__c
                                            FROM Applicant__c 
                                            WHERE Name =: applicantNo 
                                            LIMIT 1
                                        ];
            if(applicantRecordList.size() == 1){
                if(applicantRecordList[0].OKYC_Status__c == 'Verification Successful'){
                    throw CustomAuraHandledException('OKYC Has been completed Successfully. Thank you');
                }
                return applicantRecordList[0].Id;
            }
            throw CustomAuraHandledException('Invalid URL. No Applicant found. Please contact your Sales Representative');
            
        } catch (Exception e) {
            throw CustomAuraHandledException(e.getMessage());
        }
    }
        */


    /**
      * Creates the Integration Checklist
      * Common method for both Block Mandate and Save New Mandate.
      * the Mandate Type determines the Integration Master Type to create the Checklist
      */
      @AuraEnabled
      public static string createIntegrationChecklist(Id applicantId, String okycType){
      
          try {
              
              CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = IntegrationUtility.createInputWrapperForApplicant(applicantId, okycType);
              IntegrationUtility utility = new IntegrationUtility();
              IntegrationUtility.HTTPRequestWrapper responseInstance = utility.constructRequest(inputWrapper);
  
  
              // Not Inserting the INtegration Checklist Before
              // Just creating an Object in memory to store the Reqeust Parameter
  
              Integration_Checklist__c intCheck = new Integration_Checklist__c();
              if(String.isBlank(responseInstance.preRequisites) || responseInstance.preRequisites == null){
  
                  intcheck.Applicant__c = applicantId;
                  intcheck.Status__c = Constants.INTEGRATION_CHECKLIST_PENDING;
                  intcheck.Is_Latest__c = true;
                  intcheck.Integration_Master__c = inputWrapper.integrationMasterRecord.Id;
                  intcheck.Request__c = responseInstance.request;
              }
              else{
  
                  intcheck.Applicant__c = applicantId;
                  intcheck.Status__c = Constants.INTEGRATION_CHECKLIST_MISSING_PREREQ;
                  intcheck.Is_Latest__c = true;
                  intcheck.Integration_Master__c = inputWrapper.integrationMasterRecord.Id;
              }
  
              insert intcheck;
  
              return 'success';
          } catch (Exception e) {
              throw CustomAuraHandledException(e.getMessage());
          }
      }



      @AuraEnabled
      public static string initiateOKYCInit(String applicantId){
          try {
              
              String result;
              CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = IntegrationUtility.createInputWrapperForApplicant(applicantId, 'OKYC - Init');
             
              String className = inputWrapper.integrationMasterRecord.Apex_Class_Name__c;
              IntegrationHandlerInterface service = (IntegrationHandlerInterface) Type.forName(className).newInstance();
  
              List<IntegrationUtility.RequestWrapper> calloutRequests = 
                  (List<IntegrationUtility.RequestWrapper>)service.generateCallouts(new List<CommonCalloutEventPublisher.AutoIntegrationsInputWrapper>{inputWrapper});
              
              IntegrationUtility utility = new IntegrationUtility();
              
  
              // ONLY one Request Wrapper will be receieved
              if(calloutRequests.size() != 0){
  
                  IntegrationUtility.RequestWrapper requestWrapper = calloutRequests[0];
                  IntegrationUtility.ResponseWrapper response = utility.initiateCallout(requestWrapper);
  
  
                  OKYCInitHandler obj = new OKYCInitHandler();
                  // Call Callback method to Process the Response. In turn, it will also update the Integration Checklist Record
                  List<OKYCInitHandler.OKYCInitResponseWrapper> callBackResponses =  obj.callbackServiceOverload(new List<Integration_Checklist__c>{response.checklistRecord}, null);
                  OKYCInitHandler.OKYCInitResponseWrapper callbackResponse = callBackResponses[0];
                  result = JSON.serialize(callbackResponse);
              }
              
              return result;
  
          } catch (Exception e) {
              throw CustomAuraHandledException(e.getMessage());
          }
      }


    @AuraEnabled
    public static String getoKYCPostData(Integration_Checklist__c intCheck){
        try {
            
            // Instantiate a new Http object
            Http h = new Http();

            // Instantiate a new HTTP request
            // Specify request properties such as the endpoint, the POST method, etc. 
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://okyc-uat-apicast.apps.tclnprdservices.tatacapital.com/rest/v1.0/okycfe/slosOkyc');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('ConversationID', '1306241220_t7777');
            req.setHeader('SourceName', 'OKYC');
            req.setHeader('Authorization', 'Basic YmFzaWN1YXQ6YmFzaWN1YXQ=');
            req.setBody('{"clientId":"SLOS_OKYC", "requestType":"AADHAAR_ZIP_UPLOAD", "responseURL":"https://tatacapitalfinancialservices-singl--devpl.sandbox.my.site.com/customer/services/apexrest/okyccallback", "faceAuth":true,"eAadhaarImage":true,"otpAuth":false}');

            // Send the request, and return a response
            HttpResponse res = h.send(req);
            system.debug(res.getBody());
            
            return 'success';
            
        } catch (Exception e) {
            throw CustomAuraHandledException(e.getMessage());
        }
    }

    private static AuraHandledException CustomAuraHandledException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

}