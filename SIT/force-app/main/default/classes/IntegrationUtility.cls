/**
* @author        Joshna Palla
* @date          09/08/2022
* @description   Utility class that provides methods for encryption & header generation
* Modification Log:
--------------------------------------------------------------------------------------------
Developer            Date            Description
--------------------------------------------------------------------------------------------
Joshna Palla         09/08/2022      Initial Version
Suresh Kumar V       15/08/20222     Updated to support blob request
*/
public without sharing class IntegrationUtility {
    public static Boolean MULTIPLE_IE = false;
    static final String STATUS_PENDING = 'Pending';
    
    public ResponseWrapper initiateCallout(RequestWrapper requestInstance) {

        
        if (requestInstance.masterRecord == null) {
            throw new HandledException('Integration Master details are mandatory for initiating an interface');
        }

        if (String.isBlank(requestInstance.method)) {
            throw new HandledException('Method is mandatory for initiating an interface');
        }

        if (String.isBlank(requestInstance.endpointURL) && String.isBlank(requestInstance.masterRecord.End_Point_URL__c)) {
            throw new HandledException('Endpoint URL is mandatory. Update these details in master or in the input parameters');
        }
        List<ContentVersion> calloutDetails = new List<ContentVersion>();
        ResponseWrapper responseInstance = new ResponseWrapper();
        HTTPResponse response;
        Boolean isBlobRequest = false;

        Integration_Checklist__c checklistRecord = requestInstance.checklistRecord ?? new Integration_Checklist__c();

        checklistRecord.Is_Latest__c = true;

        checklistRecord.Integration_Master__c = requestInstance.masterRecord.Id;
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod(requestInstance.method);
            request.setTimeout(requestInstance.timeOut);

            if(requestInstance.urlParamterMap != NULL && !requestInstance.urlParamterMap.isEmpty()){
                String query = '';
                for(String key : requestInstance.urlParamterMap.keySet()){
                    String value = requestInstance.urlParamterMap.get(key);
                    query += '&' + key + '=' + value;
                }
                checklistRecord.URL_Parameters__c = query.substring(1);
                query = '?' + query.substring(1);
                String endPoint = requestInstance.masterRecord.End_Point_URL__c + query;
                request.setEndPoint(endPoint);
                            }
            else{
                //request.setEndPoint(requestInstance.masterRecord.End_Point_URL__c);
                request.setEndPoint(requestInstance.endpointURL);
            }
            
            if (String.isNotBlank(requestInstance.contentType)) {
                request.setHeader('Content-Type', requestInstance.contentType);
            }

           if(requestInstance.headersMap != null && !requestInstance.headersMap.isEmpty()) {
                for(String header : requestInstance.headersMap.keySet()) {   
                    if(requestInstance.headersMap.get(header) != '' && requestInstance.headersMap.get(header) != null) {
                        request.setHeader( header, requestInstance.headersMap.get(header));
                    }    
                }
            }
            
            if(requestInstance.request != null) {
                request.setBody(requestInstance.request); 
            }

            if(requestInstance.requestBlob != null) {            
                request.setBodyAsBlob(requestInstance.requestBlob);
                isBlobRequest = true;
            }

            checklistRecord.Request_Initiated_At__c = System.now();

            if (requestInstance.captureRequestInAttachment || checklistRecord.Is_Request_In_Attachment__c) {
                checklistRecord.Is_Request_In_Attachment__c = true;
            }
             else {
                checklistRecord.Request__c = requestInstance.request;
            }
        
            Http http = new Http();

            //Rahul Adding logic for mocking service start
            if(!checklistRecord.Is_Mocking_Service__c){
                response = http.send(request);
                system.debug('response***123 '+response);
            }
            else{
				System.debug('in mock:');
                response = generateMockingResponse(checklistRecord);
            }
            //Rahul Adding logic for mocking service end
            checklistRecord.Status__c = Constants.INTEGRATION_CHECKLIST_ESBCOMPLETE; // trigger layer uses callback service to set this to failed if response is not intact
            checklistRecord.Response_Received_At__c = System.now();
            
            if (requestInstance.captureResponseInAttachment) {
                checklistRecord.Is_Response_In_Attachment__c = true;
            }
            else {
                checklistRecord.Response__c = response.getBody();
            }
    
            if (requestInstance.applicantId != null) {
                checklistRecord.Applicant__c = requestInstance.applicantId;
            }
    
            if (requestInstance.loanApplicationId != null) {
                checklistRecord.Loan__c = requestInstance.loanApplicationId;
            }
            
            responseInstance.checklistRecord = checklistRecord;
            responseInstance.statusCode = response.getStatusCode();
            responseInstance.response = response.getBody();
            responseInstance.responsebody = response;
            Id networkId = [select NetworkId from NetworkMember where MemberId = :UserInfo.getUserId() LIMIT 1]?.NetworkId;

            if (requestInstance.captureRequestInAttachment || requestInstance.captureResponseInAttachment || checklistRecord.Is_Request_In_Attachment__c) {
                if (requestInstance.captureRequestInAttachment || checklistRecord.Is_Request_In_Attachment__c) {
                    ContentVersion cvObj = new ContentVersion(VersionData = (isBlobRequest ? requestInstance.requestBlob : Blob.valueOf(requestInstance.request)), Title = 'Request', Document_Type__c = 'Callout Request', PathOnClient = 'Request.txt');                
                    if(networkId != null)
                        cvObj.NetworkId = networkId;
                    calloutDetails.add(cvobj);
                }
    
                if (requestInstance.captureResponseInAttachment) {
                    ContentVersion cvObj = new ContentVersion(VersionData = Blob.valueOf(response.getBody()), Title = 'Response', Document_Type__c = 'Callout Response', PathOnClient = 'Response.txt');
                    if(networkId != null)
                        cvObj.NetworkId = networkId;
                    calloutDetails.add(cvobj);
                }

                if(MULTIPLE_IE != false){
                    responseInstance.calloutDetails = calloutDetails;
                }
            }

        }
        catch(CalloutException ex) {
            System.debug('*** Exception 1 --> ' + ex.getMessage() + '  Line No ---> ' + ex.getLineNumber());
            checklistRecord.Status__c = 'Failed';
            responseInstance.response = ex.getMessage();
        } 
        catch (Exception ex) {
            System.debug('*** Exception 2 --> ' + ex.getMessage() + '  Line No ---> ' + ex.getLineNumber());
            checklistRecord.Status__c = 'Failed';
            responseInstance.response = ex.getMessage();
        }

        
        //checklistRecord.Request__c = requestInstance.request;
        if(MULTIPLE_IE == false ){
            upsert checklistRecord;
            if(!calloutDetails.isEmpty()){
                for(ContentVersion cv: calloutDetails){
                    cv.FirstPublishLocationId = checklistRecord.Id;
                }
                upsert calloutDetails;
            }
        }
        return responseInstance;
    }
    
    public class ResponseWrapper {
        public HttpResponse responsebody;
        public String response;
        public Integer statusCode;
        public Integration_Checklist__c checklistRecord;
        public List<ContentVersion> calloutDetails;
    }
    
    public class HTTPRequestWrapper {
        public String request;
        public String preRequisites;
    }
    
    public class RequestWrapper {
        public String request;
        public Blob requestBlob;
        public Map<String,String> headersMap;        
        public String contentType;
        public Id applicantId;
        public Id obligationId;
        public Id loanApplicationId;
        public Id tataCardsLeadId;
        public Integer timeOut = 120000;
        public String method;
        public Integration_Master__c masterRecord;
        public Boolean captureResponseInAttachment = false;
        public Boolean captureRequestInAttachment = false;
        // use this when URL should include request parameters. If this is not set, the method will use URL in master
        public String endpointURL;
        public Integration_Checklist__c checklistRecord;
        public map<String,String> urlParamterMap; 
    }
    
    public HTTPRequestWrapper constructRequest(CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper) {
        if (inputWrapper == null) {
            throw new HandledException('Input details are mandatory for constructing request');	
        }
        if (String.isBlank(inputWrapper.integrationMasterRecord.Apex_Class_Name__c)) {
            throw new HandledException('Handler name is mandatory for constructing request. Please update in master');
        }
        HTTPRequestWrapper responseInstance = new HTTPRequestWrapper();
        IntegrationHandlerInterface service = (IntegrationHandlerInterface) Type.forName(inputWrapper.integrationMasterRecord.Apex_Class_Name__c).newInstance();
        List<String> preRequisites = service.validateInputData(new List<Object>{inputWrapper});
       
        if(preRequisites == null || preRequisites.size() == 0 || String.isBlank(preRequisites[0])){
            responseInstance.request = (String) service.generateRequest(new List<Object>{inputWrapper}).get(0);
        }
        else{
            responseInstance.preRequisites = String.join(preRequisites,',');
        }
        
        return responseInstance;
    } 
    
    public Map<String,String> getDefaultHeaders(String conversationID, Integration_Master__c integrationMasterRecord){
        Map<String,String> header = new Map<String,String>();
        header.put('Accept-Encoding', integrationMasterRecord.Accept_Encoding__c);
        header.put('ConversationID', conversationID);
        header.put('SourceName', integrationMasterRecord.SourceName__c);
        header.put('Content-Type', integrationMasterRecord.Content_Type__c);
        if(integrationMasterRecord.Authorization_Key__c != null){
            header.put('Authorization', integrationMasterRecord.Authorization_Key__c);
        }
        return header;
    }

    // Wrapper class used for all generate platform events methods in integration handlers
    public class InputWrapper {
        public Applicant__c applicantRecord;
        public Lead leadRecord;
        public Integration_Checklist__c integrationChecklistRecord;
        public Integration_Master__c integrationMasterRecord;
        public Opportunity loanRecord;
        public Object dynamicQueryInput;
        public List<Applicant__c> relatedApplicants;
        public Map<String, Object> dynamicInputs;
        public Map<String,String>  defaultData;
    }
    
    public static RequestWrapper createRequestWrapper(CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper,String calloutMethod) {
        RequestWrapper makeCallout = new RequestWrapper();
        //makeCallout.request = request;
        makeCallout.masterRecord = inputWrapper.integrationMasterRecord;
        makeCallout.endpointURL = inputWrapper.integrationMasterRecord.End_Point_URL__c;
        makeCallout.method = calloutMethod;
        makeCallout.contentType = inputWrapper.integrationMasterRecord.Content_Type__c;
        //makeCallout.applicantId = inputWrapper.applicantRecord.Id;
        makeCallout.checklistRecord = inputWrapper.integrationChecklistRecord;
        //IntegrationUtility utillity = new IntegrationUtility();
        //makeCallout.headersMap = utillity.deafultHeaders(inputWrapper.integrationChecklistRecord.Id, inputWrapper.integrationMasterRecord);
        return makeCallout;
    }
    
    public static IntegrationUtility.RequestWrapper createRequestWrapperForObligation(CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper) {
        IntegrationUtility.RequestWrapper makeCallout = new IntegrationUtility.RequestWrapper();
        makeCallout.masterRecord = inputWrapper.integrationMasterRecord;
        makeCallout.endpointURL = inputWrapper.integrationMasterRecord.End_Point_URL__c;
        makeCallout.method = Constants.POST_METHOD;
        makeCallout.contentType = inputWrapper.integrationMasterRecord.Content_Type__c;
        makeCallout.applicantId = inputWrapper?.applicantRecord?.Id;
        makeCallout.loanApplicationId = inputWrapper.loanRecord?.Id;
        makeCallout.obligationId = inputWrapper?.obligationRecord?.Id;
        makeCallout.checklistRecord = inputWrapper.integrationChecklistRecord;
        return makeCallout;
    }

    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForLoan(String loanRecordId, String integrationMasterType) {
        Opportunity oloanRecord = OpportunitySelector.getOpportunityById(loanRecordId);
        if(oloanRecord == null){
            return null;
        }
        
        // Since this is a common method called for all Loan Integrations from Rule Framework
        // Adding check here for specific ones and returning thus.
        // This is for Mandate Integrations. Others can be added in a similar way if needed

        if(integrationMasterType == 'Penny Drop - Repayment' || 
            integrationMasterType == 'Penny Drop - Disbursement' || 
            integrationMasterType == 'Enquiry API'){

                return createInputWrapperForLoanForMandate(loanRecordId, integrationMasterType);
        }

        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
        inputWrapper.loanRecord = oloanRecord;
        Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByOpportunityIdWithCheckListItems(oloanRecord.Id, integrationMasterType, STATUS_PENDING);
        if(integrationMaster == null){
            return inputWrapper;
        }
        inputWrapper.integrationMasterRecord = integrationMaster;
        inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size()>0?integrationMaster.Integration_Checklists__r[0]:null;
        system.debug('inputWrapper.integrationChecklistRecord*55* '+inputWrapper.integrationChecklistRecord);
        return inputWrapper;
    }
    
    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForLoan(String loanRecordId, Integration_Master__c masterRecord) {
        Opportunity oloanRecord = OpportunitySelector.getOpportunityById(loanRecordId);
        if(oloanRecord == null){
            return null;
        }

        // Since this is a common method called for all Loan Integrations from Rule Framework
        // Adding check here for specific ones and returning thus.
        // This is for Mandate Integrations. Others can be added in a similar way if needed

        if(masterRecord.Type__c == 'Penny Drop - Repayment' || 
            masterRecord.Type__c == 'Penny Drop - Disbursement' || 
            masterRecord.Type__c == 'Enquiry API'){

                return createInputWrapperForLoanForMandate(loanRecordId, masterRecord.Type__c);
        }
        

        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
        inputWrapper.loanRecord = oloanRecord;
        
        inputWrapper.integrationMasterRecord = masterRecord;
        inputWrapper.integrationChecklistRecord = null;
        return inputWrapper;
    }
   
   /* 
   public static Map<Id,CommonCalloutEventPublisher.AutoIntegrationsInputWrapper> createInputWrapperForLoan(Set<Id> setloanRecordId, String integrationMasterType){
        List<Opportunity> oppList = OpportunitySelector.getOpportunityListById(setloanRecordId);
        Map<Id,CommonCalloutEventPublisher.AutoIntegrationsInputWrapper> mapLoanIdWithInputWrapper = new Map<Id,CommonCalloutEventPublisher.AutoIntegrationsInputWrapper>();
        for(Opportunity opp : oppList){
            CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.loanRecord = opp;
            
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByOpportunityIdWithCheckListItems(opp.Id, integrationMasterType, STATUS_PENDING);
            // if(integrationMaster == null){
            //     return integrationMaster;
            // }
            inputWrapper.integrationMasterRecord = integrationMaster;
            inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size()>0?integrationMaster.Integration_Checklists__r[0]:null;
            mapLoanIdWithInputWrapper.put(opp.id, inputWrapper);
        }
        System.debug('mapLoanIdWithInputWrapper245'+ mapLoanIdWithInputWrapper);
        return mapLoanIdWithInputWrapper;
    }
    */


    //SLS-238
    /*
    public static Map<Id,CommonCalloutEventPublisher.AutoIntegrationsInputWrapper> createInputWrapperForLoan(set<Id> setloanRecordId, String integrationMasterType) {
        List<Opp> oppList = OpportunitySelector.getOpportunitiesByIdSet(setloanRecordId);
        Map<Id,CommonCalloutEventPublisher.AutoIntegrationsInputWrapper> mapLoanIdWithInputWrapper
        for(Opp :oppList){
            CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.loanRecord = opp;
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithCheckListItems(opp.Id, integrationMasterType, STATUS_PENDING);
            if(integrationMaster == null){
                return inputWrapper;
            }
            inputWrapper.integrationMasterRecord = integrationMaster;
            inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size()>0?integrationMaster.Integration_Checklists__r[0]:null;
            mapLoanIdWithInputWrapper.put(opp.id, inputWrapper);
        }
        
        return mapLoanIdWithInputWrapper;
    }
        */

    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForObligation(String obligationRecordId, String integrationMasterType, String loanId, String offerId) { //SJ PAPL added loanId
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper;
        Obligation__c obligation = ObligationSelector.getObligationById(obligationRecordId);
                if(obligation != NULL){
            inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            Applicant__c applicant = ApplicantSelector.getApplicantById(obligation?.Applicant_Type__c );
            if(applicant != null){
                inputWrapper.applicantRecord = applicant;
            }
            Opportunity oloanRecord = OpportunitySelector.getOpportunityById(obligation?.Applicant_Type__r?.Loan__c);
            if(oloanRecord != null){
                inputWrapper.loanRecord = oloanRecord;
            }
            inputWrapper.obligationRecord = obligation;
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithCheckListItemsForObligation(applicant.Id, integrationMasterType, STATUS_PENDING, loanId); //SJ PAPL added loanId
            if(integrationMaster != NULL){
                inputWrapper.integrationMasterRecord = integrationMaster;
                inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
            }
        }else if(loanId != null && offerId != null){ //SJ PAPL 
            inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.offerRecord = OfferMasterSelector.getOfferById(offerId);
            Opportunity oloanRecord = OpportunitySelector.getOpportunityById(loanId);
            if(oloanRecord != null){
                inputWrapper.loanRecord = oloanRecord;
            }
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithCheckListItemsForObligation(null, integrationMasterType, STATUS_PENDING, loanId);
            if(integrationMaster != NULL){
                inputWrapper.integrationMasterRecord = integrationMaster;
                inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
            }
        }
        return inputWrapper;
    }

    
    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForApplicant(String applicantRecordId, String integrationMasterType) {
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper;
        Applicant__c applicant = ApplicantSelector.getApplicantById(applicantRecordId);
        if(applicant != NULL){
            inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.applicantRecord = applicant;
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithCheckListItems(applicant.Id, integrationMasterType, STATUS_PENDING);
            if(integrationMaster != NULL){
                inputWrapper.integrationMasterRecord = integrationMaster;
                inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
            }
        }
        
        return inputWrapper;
    }
    //Added by Kishan for VideoPD Id logic
    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForApplicantVidePD(String applicantRecordId, Video_PD__c videopdData, String integrationMasterType) {
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper;
        Applicant__c applicant = ApplicantSelector.getApplicantById(applicantRecordId);
        if(applicant != NULL){
            inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.applicantRecord = applicant;
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithCheckListItems(applicant.Id, integrationMasterType, STATUS_PENDING);
            if(integrationMaster != NULL){
                inputWrapper.integrationMasterRecord = integrationMaster;
                inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
            }
            inputWrapper.dynamicQueryInput = videopdData; //populate VideoPD Data
        }
        return inputWrapper;
    }
    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForApplicant(String applicantRecordId, Integration_Master__c masterRecord) {
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper;
        Applicant__c applicant = ApplicantSelector.getApplicantById(applicantRecordId);
        if(applicant != NULL){
            inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.applicantRecord = applicant;
            inputWrapper.integrationMasterRecord = masterRecord;
            inputWrapper.integrationChecklistRecord = NULL;
        }
        return inputWrapper;
    }
    
    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForTataCardsLead(String tataCardsLeadRecordId, String integrationMasterType) {
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper;
        Tata_Cards_Lead__c leadRec;
        List<Tata_Cards_Lead__c> leadRecList = [SELECT Name, Salutation__c, First_Name__c, Last_Name__c, Gender__c, Date_of_Birth__c, PAN__c,
                                                Mother_s_Name__c, Mobile_Number__c, Personal_Email_Id__c,Residence_Address_Line_1_HouseNo__c,
                                                Residence_Address_Line_2__c, Residence_Address_Line_3_Locality__c,Residence_Pincode_Text__c,
                                                Residence_City__c,Occupation_Type__c, Company_Name__c, Designation_Text__c,
                                                Office_Pincode_Text__c, Office_City__c, Official_Email_Id__c, Net_Annual_Income__c,
                                                Customer_Consent_Status__c
                                                FROM Tata_Cards_Lead__c
                                                WHERE Id =: tataCardsLeadRecordId
                                                LIMIT 1];
        if(leadRecList != NULL && !leadRecList.isEmpty()){
            leadRec = leadRecList[0];
            inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.tataCardsLeadRecord = leadRec;
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithCheckListItemsForTC(leadRec.Id, integrationMasterType, STATUS_PENDING);
            if(integrationMaster != NULL){
                inputWrapper.integrationMasterRecord = integrationMaster;
                inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
            }
        }
        return inputWrapper;
    }

    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createShortenURLInputForApplicant(String applicantRecordId,String communicationId, String integrationMasterType) {
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper;
        Applicant__c applicant = ApplicantSelector.getApplicantById(applicantRecordId);
        if(applicant != NULL){
            inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.applicantRecord = applicant;
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithParameters(applicant.Id,communicationId, integrationMasterType, STATUS_PENDING);
            if(integrationMaster != NULL){
                inputWrapper.integrationMasterRecord = integrationMaster;
                inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
            }
        }
        return inputWrapper;
    }
    
    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createShortenURLInputForTataCardsLead(String tataCardsLeadRecordId, 
                                                                                                                 String communicationId,
                                                                                                                 String integrationMasterType)
    {
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper;
        Tata_Cards_Lead__c leadRec;
        List<Tata_Cards_Lead__c> leadRecList = [SELECT Name, Salutation__c, First_Name__c, Last_Name__c, Gender__c, Date_of_Birth__c, PAN__c,
                                                Mother_s_Name__c, Mobile_Number__c, Personal_Email_Id__c,Residence_Address_Line_1_HouseNo__c,
                                                Residence_Address_Line_2__c, Residence_Address_Line_3_Locality__c,Residence_Pincode_Text__c,
                                                Residence_City__c,Occupation_Type__c, Company_Name__c, Designation_Text__c,
                                                Office_Pincode_Text__c, Office_City__c, Official_Email_Id__c, Net_Annual_Income__c,
                                                Customer_Consent_Status__c
                                                FROM Tata_Cards_Lead__c
                                                WHERE Id =: tataCardsLeadRecordId
                                                LIMIT 1];
        if(leadRecList != NULL && !leadRecList.isEmpty()){
            leadRec = leadRecList[0];
            inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
            inputWrapper.tataCardsLeadRecord = leadRec;
            Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithParametersTC(leadRec.Id, communicationId, integrationMasterType, STATUS_PENDING);
            if(integrationMaster != NULL){
                inputWrapper.integrationMasterRecord = integrationMaster;
                inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
            }
        }
        return inputWrapper;
    }

    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapper(String integrationMasterType) {
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
        Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByType(integrationMasterType, STATUS_PENDING);
        if(integrationMaster == null){
            return inputWrapper;
        }
        inputWrapper.integrationMasterRecord = integrationMaster;
        inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size()>0?integrationMaster.Integration_Checklists__r[0]:null;
        return inputWrapper;
    }


    public static HttpResponse generateMockingResponse(Integration_Checklist__c localChecklist){

            //Create a local variable for returning the response
                HTTPResponse localResponse = new HTTPResponse();
                //Check if the response is present on the checklist else return default response
                
                List<ContentDocumentLink> link = [
                                                    SELECT Id, ContentDocumentId 
                                                    FROM ContentDocumentLink 
                                                    WHERE LinkedEntityId =: localChecklist.Integration_Master__c
                                                    LIMIT 1
                                                ];
                
                if(link.size() == 1){
                    List<ContentVersion> response = [
                                                        SELECT Id, VersionData 
                                                        FROM ContentVersion 
                                                        WHERE ContentDocumentId = :link[0].ContentDocumentId
                                                    ];
                    if(response !=null && !response.isEmpty() && response[0].VersionData != null){
                        localResponse.setBody(response[0].VersionData.toString());
                    }
                    else if(String.isNotBlank(localChecklist.Mocking_service_response__c)){
                        localResponse.setBody(localChecklist.Mocking_service_response__c);
                    }
                    else{
                        localResponse.setBody('{"status":"There has been an error}');
                    }
                }
        
                else if(String.isNotBlank(localChecklist.Mocking_service_response__c)){
                    localResponse.setBody(localChecklist.Mocking_service_response__c);
                }
                else{
                    localResponse.setBody('{"status":"There has been an error}');
                }
                
                
                //Check if the status is present on the checklist else return default status as "Service Unavailable"
                if(String.isNotBlank(localChecklist.Mocking_Service_Status__c)){
                    localResponse.setStatus(localChecklist.Mocking_Service_Status__c);
                }else{
                    localResponse.setStatus('Service unavailable');
                }
                //Check if the statuscode is present on the checklist else return default statuscode as 500
                if(localChecklist.Mocking_Service_Status_Code__c != null){
                    localResponse.setStatusCode(Integer.valueof(localChecklist.Mocking_Service_Status_Code__c));
                }else{
                    localResponse.setStatusCode(500);
                }
                return localResponse;
}
//Added by Kishan For VideoPD Initiation
public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForApplicantVideoPD(String applicantRecordId,String mobileNumber ,String integrationMasterType) {
    CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper;
    Applicant__c applicant = ApplicantSelector.getApplicantById(applicantRecordId);
    if(applicant != NULL){
       // applicant.Mobile_No__c = mobileNumber;
        inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
        inputWrapper.applicantRecord = applicant;
        inputWrapper.applicantRecord.Mobile_No__c = mobileNumber;
        System.debug('Updated Mobile No---'+inputWrapper.applicantRecord.Mobile_No__c+'----'+mobileNumber);
        Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByTypeWithCheckListItems(applicant.Id, integrationMasterType, STATUS_PENDING);
        System.debug('Input Wrapper IUtility2--'+integrationMaster);
        if(integrationMaster != NULL){
            inputWrapper.integrationMasterRecord = integrationMaster;
            inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size() > 0 ? integrationMaster.Integration_Checklists__r[0] : NULL;
        }
    }
    System.debug('Input Wrapper IUtility--'+inputWrapper);
    
    return inputWrapper;
}

    public static List<sObject> generatePlatformEvents(List<Object> recordList) {

        // Generate Platform Event Records for CKYC Search
        List<Common_Callout__e> callOuts = new List<Common_Callout__e>();

        for(Integration_Checklist__c integrationChecklist :(List<Integration_Checklist__c>) recordList){
        
            Common_Callout__e peEvent = new Common_Callout__e();
            peEvent.Conversation_ID__c = integrationChecklist.Id;
            peEvent.Authorization__c = integrationChecklist.Authorization_Key__c;
            peEvent.Endpoint__c = integrationChecklist.End_Point_URL__c;
            peEvent.Content_Type__c = integrationChecklist.Content_Type__c;
            peEvent.Source_Name__c = integrationChecklist.SourceName__c;
            peEvent.Request__c = integrationChecklist.Request__c;
            // TODO, Add Event Type
            peEvent.Event_Type__c = '';            
            callOuts.add(peEvent);

        }
        return callOuts;
    }
    //Create Integration Checklist record with the Pending status.
    public static Integration_Checklist__c createIntegrationChecklistRecordFromIntegrationMasterForLoan(Id loanId, String integrationType, Boolean insertRecord) {
        /*List<Integration_Checklist__c> oldIntegrationChecklists = new List<Integration_Checklist__c>();
            for(Integration_Checklist__c oldIntCheck :[SELECT Id,Integration_Master__r.Name, Status__c,
                                                        Loan__c FROM Integration_Checklist__c 
                                                        WHERE Integration_Master__r.Type__c = :integrationType AND
                                                        Loan__c =: loanId AND 
                                                        Is_Latest__c = true 
                                                        ORDER BY CreatedDate desc]){
                oldIntCheck.Status__c = Constants.INTEGRATION_CHECKLIST_OBSOLETE;
                oldIntCheck.Is_Latest__c = false;
                oldIntegrationChecklists.add(oldIntCheck);
            }*/
        Integration_Master__c master = IntegrationSelector.getMasterByType(integrationType);
        Integration_Checklist__c checklist = new Integration_Checklist__c();
        checklist.Loan__c = loanId;
        checklist.Status__c = Constants.INTEGRATION_CHECKLIST_PENDING;
        checklist.Is_Mocking_Service__c = master.Is_Mocking_Service__c;
        checklist.Mocking_Service_Response__c = master.Mocking_Service_Response__c;
        checklist.Mocking_Service_Status__c = master.Mocking_Service_Status__c;
        checklist.Mocking_Service_Status_Code__c = master.Mocking_Service_Status_Code__c;
        checklist.Integration_Master__c = master.Id;
        /*if(!oldIntegrationChecklists.isEmpty()){
            update oldIntegrationChecklists;
        }*/
        if(insertRecord){
            insert checklist;
        }
        return checklist;
    }  
    
    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForLoanForMandate(String loanRecordId, String integrationMasterType) {
        Opportunity oloanRecord = OpportunitySelector.getOpportunityByIdForMandate(loanRecordId);
        if(oloanRecord == null){
            return null;
        }
        

        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
        inputWrapper.loanRecord = oloanRecord;
        Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByOpportunityIdWithCheckListItems(oloanRecord.Id, integrationMasterType, STATUS_PENDING);
        if(integrationMaster == null){
            return inputWrapper;
        }
        inputWrapper.integrationMasterRecord = integrationMaster;
        inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size()>0?integrationMaster.Integration_Checklists__r[0]:null;
        system.debug('inputWrapper.integrationChecklistRecord*55* '+inputWrapper.integrationChecklistRecord);
        return inputWrapper;
    }

    public static CommonCalloutEventPublisher.AutoIntegrationsInputWrapper createInputWrapperForStamping(String loanRecordId, String integrationMasterType) {
        Opportunity loanRecordById = OpportunitySelector.getOpportunityById(loanRecordId);
        if(loanRecordById == null){
            return null;
        }
        CommonCalloutEventPublisher.AutoIntegrationsInputWrapper inputWrapper = new CommonCalloutEventPublisher.AutoIntegrationsInputWrapper();
        inputWrapper.loanRecord = loanRecordById;
        Integration_Master__c integrationMaster = IntegrationSelector.getIntegrationMasterRecordByOpportunityIdWithCheckListItems(loanRecordById.Id, integrationMasterType, STATUS_PENDING);
        if(integrationMaster == null){
            return inputWrapper;
        }
        inputWrapper.integrationMasterRecord = integrationMaster;
        inputWrapper.integrationChecklistRecord = integrationMaster.Integration_Checklists__r.size()>0?integrationMaster.Integration_Checklists__r[0]:null;
        inputWrapper.dynamicQueryInput = loanRecordById.Primary_Applicant__c != null ? AddressSelector.getPrimaryAddressByApplicantId(String.valueOf(loanRecordById.Primary_Applicant__c)) : null;
        return inputWrapper;
    }
}