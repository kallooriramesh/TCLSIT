/**
 * @description       : 
 * @author            : Manish Jadhav
 * @group             : 
 * @last modified on  : 03-28-2024
 * @last modified by  : Manish Jadhav
 * Modifications Log
 * Ver   Date         Author          Modification
 * 1.0   03-14-2024   Manish Jadhav   Initial Version
**/
public with sharing class CaseTriggerService implements ServiceInterface{
    public void beforeInsert(List<sObject> newRecordList){
    }
    
    public void afterInsert(List<sObject> newRecordList,Map<Id,sObject> newRecordMap){
    }
    
    public void beforeUpdate(List<sObject> newRecordList,Map<Id,sObject> oldRecordMap,Map<Id,sObject> newRecordMap){
        List<Case> updateCaseOwnerList = new List<Case>();
        Boolean isSandbox = ApplicationUtility.isCurrentOrgSandbox();
        String recordTypeDevNameStr = ApplicationUtility.getApplIntgConfigMdtValue('VALIDATE_CASE_OWNER_RECORD_TYPE_DEV_NAME', isSandbox);
        Map<String, String> caseRecordTypeDevNameIDMap = new Map<String, String>();
        for(String recordTypeDevName : recordTypeDevNameStr.split(';')){
            caseRecordTypeDevNameIDMap.put(recordTypeDevName, Schema.getGlobalDescribe().get('Case').getDescribe().getRecordTypeInfosByName().get(recordTypeDevName).getRecordTypeId());
        }
        for(Case newCase:(List<Case>) newRecordList){
            Case oldCase = (Case)oldRecordMap.get(newCase.Id);
            if(newCase.OwnerId != oldCase.OwnerId
                && newCase.Loan__c != NULL
                && caseRecordTypeDevNameIDMap.values().contains(newCase.RecordTypeId)
                && String.valueOf(newCase.OwnerId).startsWith('005')
               )
            {
				updateCaseOwnerList.add(newCase);
            }
        }
        if(!updateCaseOwnerList.isEmpty()){
            validateCaseOwnerUpdate(updateCaseOwnerList, caseRecordTypeDevNameIDMap,oldRecordMap);
        }
    }
    
    public void afterUpdate(List<sObject> newRecordList,Map<Id,sObject> oldRecordMap,Map<Id,sObject> newRecordMap){
        List<String> reProcessCaseIdList = new List<String>();
        Id OVD_Review_RequestRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('OVD_Review_Request').getRecordTypeId();
        Id OperationsRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Operations').getRecordTypeId();
        for(Case newCase : (List<Case>) newRecordList){
            Case oldCase = (Case)oldRecordMap.get(newCase.Id);
            if((newCase.RecordTypeId == OVD_Review_RequestRecordTypeId
            || newCase.RecordTypeId == OperationsRecordTypeId)
            && newCase.OwnerId != oldCase.OwnerId)
            {
                reProcessCaseIdList.add(newCase.Id);
            }
        }
        if(!reProcessCaseIdList.isEmpty()){
            reprocessOVDCaseSharingOnOwnerChange(reProcessCaseIdList);
        }
        CaseTriggerServiceHelper.executeAfterUpdate(newRecordList, oldRecordMap); //Added By Jabir 19-Sep-2024
    }
    
    public void beforeDelete(Map<Id,sObject> oldRecordMap){
    }
    
    public void afterDelete(Map<Id,sObject> oldRecordMap){
    }
    
    public void afterUndelete(Map<Id,sObject> newRecordList){
    }

    /* 
    @author : Manish Jadhav
    @description : Method to check Changed Case owner. case owner should be tagged to product and branch
    @param : new case List, old case map
    @Context : before update
    @User-Story : SLS-2808
    */
    public static void validateCaseOwnerUpdate(List<Case> newRecordList, Map<String, String> caseRecordTypeDevNameIDMap, Map<Id,sObject> oldCaseMap){
        Set<String> loanIdSet = new Set<String>();
        Set<String> caseOwnerIdSet = new Set<String>();
        List<String> branchCodeList = new List<String>();
        List<String> productIdList = new List<String>();
        List<String> productCategoryList = new List<String>();
        String operationsRecordTypeId = caseRecordTypeDevNameIDMap.get('Operations');
        String creditRequestRecordTypeId = caseRecordTypeDevNameIDMap.get('Credit Access Request');
        Map<String, String> existingDisbursalCheckerOwnerMap = new Map<String, String>();
        for(Case newCase : newRecordList){
            loanIdSet.add(newCase.Loan__c);
            caseOwnerIdSet.add(newCase.ownerId);
            branchCodeList.add(newCase.HUB_Branch_Code__c);
            productIdList.add(newCase.Product__c);
            productCategoryList.add(newCase.Product_Category__c);
        }
        Map<String, User> userMap = new Map<String, User>([SELECT Id, Function__c, Threshold_Limit__c, UserRoleId, UserRole.Name
                                                           FROM User
                                                           WHERE Id IN : caseOwnerIdSet
                                                           OR Id =: UserInfo.getUserId()
                                                          ]);
        Map<String,Id> branchCodeMap = fetchUserSelector.getBranchCodeMap(branchCodeList);
        List<String> branchIds = branchCodeMap.values();
        
        if(!loanIdSet.isEmpty()){
            for(Case otherCase: [SELECT Id, Loan__c, OwnerId
                                 FROM Case
                                 WHERE Loan__c IN : loanIdSet
                                 AND RecordTypeId =: operationsRecordTypeId
                                 AND Loan_Sub_Stage__c = 'Disbursal Maker'
                                 AND OwnerId IN : caseOwnerIdSet])
            {
                existingDisbursalCheckerOwnerMap.put(otherCase.Loan__c, otherCase.OwnerId);
            }
        }
        Map<String,List<Id>> branchUserMap = fetchUserSelector.fetchBranchUser(branchIds);
        Map<String,List<Id>> productUserMap = fetchUserSelector.fetchProductUser(productIdList, productCategoryList);
        for(Case newCase : newRecordList){
            Boolean isScreeningMaker = false;
            //Throwing error if owner is not tagged to Branch and Product both
            if(!checkIfUserIsTaggedToBranchAndProduct(productUserMap, branchUserMap, newCase, newCase.OwnerId,branchCodeMap)){
                if(newCase.Loan_Sub_Stage__c == 'Screening Maker' && userMap.get(newCase.OwnerId).Function__c.contains('Screening Maker')) 
                {
                    isScreeningMaker = true;
                } 
                if(!isScreeningMaker){
                    newCase.addError(Label.CaseOwnerNotTaggedToProductBranch);
                }
            }
            //Case owner validation for Operation
            else if(newCase.RecordTypeId == operationsRecordTypeId){
                if(String.isNotBlank(userMap.get(newCase.ownerId).Function__c)){
                    List<String> userFunctionList = userMap.get(newCase.ownerId).Function__c.split(';');
                    if(userFunctionList.contains('Operations Supervisor')
                       || userFunctionList.contains(newCase.Loan_Sub_Stage__c))
                    {
                        //validate sanction loan amount with user threshold amount
                        if(newCase.Sanctioned_Loan_Amount__c > userMap.get(newCase.ownerId).Threshold_Limit__c){
                            newCase.addError('Selected user is not authorised to process the sanctioned loan amount.');
                        }
                        //validate Disbursal make & checker can not be same user
                        else if(newCase.Loan_Sub_Stage__c == 'Disbursal Checker'
                                && existingDisbursalCheckerOwnerMap.get(newCase.Loan__c) == newCase.OwnerId)
                        {
                            newCase.addError('Selected user can not be a Checker user because the same user was maker for the loan application.');
                        }
                    }
                    else{
                        newCase.addError('Selected user does not belong to '+newCase.Loan_Sub_Stage__c+' queue.');
                    }
                }
                else{
                    newCase.addError('Function is missing on the selected user.');
                }
            }
            else if(newCase.RecordTypeId == creditRequestRecordTypeId){
                Case oldCase = (Case)oldCaseMap.get(newCase.Id); 
                if(String.isNotBlank(userMap.get(UserInfo.getUserId()).Function__c) 
                   && userMap.get(UserInfo.getUserId()).Function__c.contains('Credit Manager')
                   && userMap.get(UserInfo.getUserId()).UserRole.Name == 'Credit Manager'
                   && String.valueOf(oldCase.OwnerId).startsWith('005') && newCase.OwnerId != UserInfo.getUserId()
                  ){ 
                    newCase.addError('Credit Manager cannot re-assign the Case.');
                }
            }
        }
    }

    //This method returns false value if user is not tagged to Product or Branch and true when user tagged to both product and branch
    private static Boolean checkIfUserIsTaggedToBranchAndProduct(Map<String, List<Id>> mapOfProductAndUser, Map<String, List<Id>> mapOfBranchAndUser, Case c, Id userId, Map<String,Id> branchCodeMap) {
        return fetchUserSelector.checkIfUserHasBranchMapping(mapOfBranchAndUser, userId, branchCodeMap.get(c.HUB_Branch_Code__c))
            || fetchUserSelector.checkIfUserHasProductMapping(mapOfProductAndUser, userId, c.Product__c, c.Product_Category__c);
    }
    //SLS-2808 Ends

    /* 
    @author : Ramesh Kalloori
    @description : Re-process the sharing records when Case owner is changed for Operations and OVD record types.
    @param : old case map, new case map
    @Context : after update
    @User-Story : SLS-17473
    */
    public static void reprocessOVDCaseSharingOnOwnerChange(List<String> newRecordIdList){
        if(!newRecordIdList.isEmpty()){
            ShareCaseToPublicGroup.shareCase(newRecordIdList);
        }
    }

}