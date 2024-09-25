import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { subscribe, MessageContext } from 'lightning/messageService';
import TataCap from '@salesforce/resourceUrl/TataCap';
import Aadhaar from '@salesforce/resourceUrl/Digi_Aadhaar';
import oKyc from '@salesforce/resourceUrl/oKYCOffline';
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from 'lightning/navigation';
import getoKYCPostData from '@salesforce/apex/OKYCLandingController.getoKYCPostData';
import initiateOKYCInit from '@salesforce/apex/OKYCLandingController.initiateOKYCInit';
import createIntegrationChecklist from '@salesforce/apex/OKYCLandingController.createIntegrationChecklist';
import getIntegrationChecklist from '@salesforce/apex/OKYCLandingController.getIntegrationChecklist';
import CustomerSiteModeChangeChannel from '@salesforce/messageChannel/CustomerSiteModeChangeChannel__c';


export default class OKYCLanding extends NavigationMixin(LightningElement) {

    errorMessage;
    tataCapLogo = TataCap;
    aadhaarLogo = Aadhaar;
    oKYCLogo = oKyc;
    isConsent = false;
    formUrl;
    formWebRequest;
    urlkey;
    isRenderedCallbackExecuted;
    applicantId;
    isInitOkycComplete = false;
    cardClass=`slds-box slds-box_x-small slds-text-align_center slds-m-around_x-small kyc-container`;
    stepContainerClass=`step-container`;
    listCls="custom-list"
    inputCls="input-check-cls"

    @wire(MessageContext)
    messageContext;
    get isErrorMessage(){
      return (this.errorMessage != null);
    }

    renderedCallback(){
      if(this.isRenderedCallbackExecuted){
        return;
      }
      this.isRenderedCallbackExecuted = true;
      const verifyUser = this.template.querySelector('c-verify-customer');
      console.log('verifyUser', verifyUser);
      if(verifyUser){
          const sessionKey = this.getCookie('ccnvd');
          console.log(sessionKey);

          if(this.urlkey === undefined || this.urlkey === '' || this.urlkey === null){
            if(sessionKey != '' && sessionKey != null && sessionKey != undefined){
                this.urlkey = sessionKey;
            }
          }
          console.log(this.urlkey);
          verifyUser.verify(this.urlkey);
      }
      
    }

    connectedCallback(){
      this.subscribeToModeChannel(); 
    }

    handleMessage(message){
      console.log(`hehehe message abc 123jeiojo`);
      if(message.isDarkModeActive){
        this.cardClass=`slds-box slds-box_x-small slds-text-align_center slds-m-around_x-small kyc-container container-dark`
        this.stepContainerClass=`step-container clr-white`;
        this.listCls=`custom-list clr-white`;
        
        this.inputCls=`input-check-cls clr-white`;
        console.log('the dark mode');        
      }
      else{
        this.cardClass=`slds-box slds-box_x-small slds-text-align_center slds-m-around_x-small kyc-container`
        this.stepContainerClass=`step-container`;
        this.listCls=`custom-list`;
        this.inputCls=`input-check-cls`;
        console.log('the light mode');
      }
   }
   subscribeToModeChannel(){
    this.subscription = subscribe(
        this.messageContext,
        CustomerSiteModeChangeChannel,
        (message) => this.handleMessage(message)
    );
}

    getCookie(cookieName) {
      let cookieString = "; " + document.cookie;
      let splitArray = cookieString.split("; " + cookieName + "=");
      if (splitArray.length === 2) {
          return decodeURIComponent(splitArray.pop().split(";").shift());
      }
      return null;
    }


    confirmOkycInit(){
      console.log(this.applicantId);
      initiateOKYCInit({applicantId:this.applicantId})
      .then((okycResult) => {
          console.log('OKYC Result', okycResult);
          if(okycResult){
            console.log('OKYC Result', okycResult);
            this.showToast("Success", 'You are set to start the OKYC', 'success');
            this.formUrl = 'https://okyc.tatacapital.com/EcsOkycWeb/ProcessRequest.jsp';
            this.formWebRequest = okycResult;
            this.isInitOkycComplete = true;
          }
      })
      .catch((error) =>{
          console.log(JSON.stringify(error));
          this.errorMessage = error?.body?.message;
          this.showToast("Error", error?.body?.message, 'error');
      })
  }


    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
       if (currentPageReference) {
          
        this.urlkey = currentPageReference.state?.key;
       }
    }

    handleVerifyCustomer(event){
      console.log('Handle Verify Customer');
      if(event.detail){
        
        getIntegrationChecklist({customerKey : this.urlkey})
        .then((result) =>{
          this.applicantId = result.Applicant__c;
        })
        .catch((error) =>{
          this.errorMessage = error?.body?.message;
          console.log(JSON.stringify(this.errorMessage));
          this.showToast("Error", this.errorMessage, 'error');
        })
      }
    }

    getCookie(cookieName) {
      let cookieString = "; " + document.cookie;
      let splitArray = cookieString.split("; " + cookieName + "=");
      if (splitArray.length === 2) {
          return decodeURIComponent(splitArray.pop().split(";").shift());
      }
      return null;
    }

    showToast(title, message, variant) {
      const evt = new ShowToastEvent({
          title: title,
          message: message,
          variant: variant,
      });
      this.dispatchEvent(evt);
    }

    handleConfirmChange(event){
        this.isConsent = event.target.checked;
    }

    get disableButton(){
        return (!this.isConsent);
    }

    handleSubmit(){
      return true;
    }

    proceedToKyc(){
      this.template.querySelector('form').submit(); 
    }

}