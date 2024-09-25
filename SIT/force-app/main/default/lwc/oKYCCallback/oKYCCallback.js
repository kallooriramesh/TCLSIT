import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { subscribe, MessageContext } from 'lightning/messageService';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import TataCap from '@salesforce/resourceUrl/TataCap';
import ADDRESS_OBJECT from '@salesforce/schema/Address__c';
import processOKYCResponse from '@salesforce/apex/OKYCCallbackController.processOKYCResponse';
import getIntegrationChecklist from '@salesforce/apex/OKYCCallbackController.getIntegrationChecklist';
import initiateLiveliness from '@salesforce/apex/OKYCCallbackController.initiateLiveliness';
import getKycPhoto from '@salesforce/apex/OKYCCallbackController.getKycPhoto';
import createAddress from '@salesforce/apex/OKYCCallbackController.createAddress';
import CustomerSiteModeChangeChannel from '@salesforce/messageChannel/CustomerSiteModeChangeChannel__c';
import checkDistribution from '@salesforce/apex/DigilockerCallbackController.checkDistribution';
import createFaceMatchPdf from '@salesforce/apex/KYCResponseDocumentController.createFaceMatchPDFDigiLocker';

export default class OKYCCallback extends NavigationMixin(LightningElement) {

    dtls = null;
    errorMessage;
    tataCapLogo = TataCap;
    isRenderedCallbackExecuted;
    urlkey;
    intCheckId;
    kycPhoto;
    selectedOption = 'SAME';
    kycContChecklistId;
    isConsent = false;
    pinCode;
    state;
    code;
    urlkey;
    addressObj = ADDRESS_OBJECT;
    isOVDVerification = false;
    intChecklist;
    cardClass=`slds-box slds-box_x-small slds-text-align_center slds-m-around_x-small kyc-container`;
    adrClass="demogValue";
    cnfrmCls="slds-form-element__label info-label";
    chckbxCls="input-check-cls"
    
    @track ipAddressFromVF;

    @wire(MessageContext)
    messageContext;


    get isErrorMessage(){
      return (this.errorMessage != null);
    }

    get isSameAddress() {
        return (this.selectedOption == 'SAME');
    }

    get isDetailsReceived() {
        return (this.intChecklist != null);
    }

    get options() {
        return [
            { label: 'I confirm that the address shown above is my current residential address', value: 'SAME' },
            { label: 'Please take my current address as per application form', value: 'DIFF' },
        ];
    }

    get isCheckedOption1() {
        return this.selectedOption === 'SAME';
    }

    get isCheckedOption2() {
        return this.selectedOption === 'DIFF';
    }

    get option1Container() {
        if(this.adrClass==="demogValue")
        return this.selectedOption === 'SAME'? "slds-radio slds-radio_add-button default-container radio-container ":"slds-radio slds-radio_add-button default-container";
        return this.selectedOption === 'SAME'? "slds-radio slds-radio_add-button default-container radio-container dark-radio":"slds-radio slds-radio_add-button default-container";

    }

    get option2Container() {
        if(this.adrClass==="demogValue")
        return this.selectedOption === 'DIFF' ?"slds-radio slds-radio_add-button  default-container radio-container":"slds-radio slds-radio_add-button default-container";
        return this.selectedOption === 'DIFF' ?"slds-radio slds-radio_add-button  default-container radio-container dark-radio":"slds-radio slds-radio_add-button default-container";
    }

    renderedCallback(){
      
        window.addEventListener("message", (message) => {
            console.log('in window msg');
            if (message.origin !== window.location.origin) {
                console.log('in first Ip addr if');
                //Not the expected origin
                return;
            }
            if (message.data.name === "VFToLWCMessageIP") {
                console.log('in second Ip addr if ',message.data.payload);
                this.ipAddressFromVF = message.data.payload;
            }
        });
        
        if(this.isRenderedCallbackExecuted){
            return;
        }
        this.isRenderedCallbackExecuted = true;
        const verifyUser = this.template.querySelector('c-verify-customer');
        console.log('verifyUser', verifyUser);
        if(verifyUser){
            const sessionKey = this.getCookie('ccnvd');
            console.log(sessionKey);
            if(sessionKey != '' && sessionKey != null && sessionKey != undefined){
                this.urlkey = sessionKey;
                verifyUser.verify(this.urlkey);
            }
            else{
                this.errorMessage = 'User not authenticated for this session. Please start the KYC again'
                this.showToast("Error", this.errorMessage, 'error');
            }
        }
    }

    connectedCallback(){
        this.subscribeToModeChannel(); 
    }
  
    handleMessage(message){
        console.log(`hehehe message abc 123jeiojo`);
        if(message.isDarkModeActive){
            this.cardClass=`slds-box slds-box_x-small slds-text-align_center slds-m-around_x-small kyc-container container-dark`
            this.adrClass="demogValue clr-white";
            this.cnfrmCls="slds-form-element__label info-label clr-white";
            this.chckbxCls=`input-check-cls clr-white`;
            console.log('the dark mode');        
        }
        else{
            this.cardClass=`slds-box slds-box_x-small slds-text-align_center slds-m-around_x-small kyc-container`
            this.adrClass="demogValue";
            this.cnfrmCls="slds-form-element__label info-label";
            this.chckbxCls=`input-check-cls`;
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

    checkDistributionTimer(){
        console.log('TIMER');
        checkDistribution({contentCheckId: this.kycContChecklistId})
        .then((result) => {
            if(result){
                clearInterval(this.interval);
                // Generate PDF Here
                console.log('Distribution created', this.applicantId);
                createFaceMatchPdf({intcheckId: this.integrationChecklistId, 
                                    ipAddress: this.ipAddressFromVF, 
                                    applicantId: this.applicantId,
                                    selectedOption: this.selectedOption})
                .then((result) => {
                    // Call Livelienss
                    console.log('PDF Created');
                    initiateLiveliness({applicantId:this.applicantId})
                    .then((result) =>{
                        // Redirect to Liveliness
                        console.log(result);
                        // Clear Cookies here
                        this.navigateToRecordPage(result);
                    })
                    .catch((error) =>{
                        console.log('Create error', error);
                    })
                })
                .catch((error) => {
                    console.log('in error ', JSON.stringify(error));
                })
            }
        })
        .catch((error) => {
            this.errorMessage = error?.body?.message;
            console.log(error);
            this.showToast("Error", error?.body?.message, 'error');
        })
    }

    handleSelectedOption(event) {
        console.log(event.target.value);
        this.selectedOption = event.target.value;
    }

    handleConfirmChange(event) {
        this.isConsent = event.target.checked;
    }

    handleAddressChange(event) {
        let fieldApiName = event.target.dataset.fieldvalue;
        if(fieldApiName == 'Pincode'){
            this.pinCode = event.target.value;
        }
        else{
            this.addressObj[fieldApiName] = event.target.value;
        }
    }

    continueToLiveliness(event) {

        console.log('Continue to Liveliness');

        console.log(this.selectedOption);
        // If The Address is SAME, copy from Integration Checklist
        if(this.selectedOption == 'SAME'){
            this.addressObj.KYC_Source_Name__c = 'oKYC';
            this.addressObj.Address_Line_1__c = this.intChecklist.Address_Line_1__c;
            this.addressObj.Address_Line_2__c = this.intChecklist.Address_Line_2__c;
            this.addressObj.Address_Line_3__c = this.intChecklist.Address_Line_3__c;
            this.addressObj.District__c = this.intChecklist.District__c;
            this.pinCode = this.intChecklist.Pincode__c;
            this.addressObj.Applicant__c = this.applicantId;
            this.addressObj.KYC_Source_Name__c = 'Self Provided';
            this.addressObj.KYC_Source_Id__c = this.intChecklist.Id; 
            
            // Create Address First, then start Distribution Timer

            createAddress({address: this.addressObj, pincode: this.pinCode})
            .then((result) =>{
                if(!this.isOVDVerification){
                    this.consentReceived = false;
                    
                    // Here, check with time interval if Distribution Record is created
                    this.interval = setInterval(() => {
                        this.checkDistributionTimer();
                    }, 2000);
                }
                else{
                    this.consentReceived = true;
                }
                
            })
            .catch((error) =>{
                console.log('Craete error', error);
            })
        }
        else{
            // Directly call Distribution
            if(!this.isOVDVerification){
                this.consentReceived = false;
                
                // Here, check with time interval if Distribution Record is created
                this.interval = setInterval(() => {
                    this.checkDistributionTimer();
                }, 2000);
            }
            else{
                this.consentReceived = true;
            }
        }

    }

    async navigateToRecordPage(urlStr) {

        const url = await this[NavigationMixin.GenerateUrl]({
            type: "standard__webPage",
            attributes: {
                url: urlStr,
            }
        });
        window.open(url, '_self');
    }

  
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
          console.log(currentPageReference);
          this.intCheckId = currentPageReference.state?.id;
        }
    }

    handleVerifyCustomer(event){

        console.log('EVENT DETAIL', event.detail);
        if(event.detail){
        
            processOKYCResponse({ intChecklistId: this.intCheckId})
            .then((result) => {
                
                if(result.isError){
                    this.showToast("Error", result.errorMessage, 'error');
                    this.errorMessage = result.errorMessage;
                }
                else{
                    this.integrationChecklistId = result.integrationChecklistId;

                    getIntegrationChecklist({ intCheck: this.integrationChecklistId })
                    .then((result) => {
                        console.log('Setting Integration Checklist Variable');
                        this.intChecklist = result;
                        console.log(result);
                        this.applicantId = result.Applicant__c;

                        let contentDocIds = this.intChecklist.ContentDocumentLinks?.map((element) =>{
                            return element.ContentDocumentId
                        });

                        //Fetch the Customer KYC Photo also, for display
                        getKycPhoto({contentDocIds : contentDocIds})
                        .then((result) =>{
                            console.log(result);
                            this.kycPhoto = result.base64Data;
                            this.kycContChecklistId = result.contentChecklistId;
                        })
                        .catch((error) => {
                            this.errorMessage = error?.body?.message;
                            console.log(error);
                            this.showToast("Error", error?.body?.message, 'error');
                        })

                    })
                    .catch((error) => {
                        this.errorMessage = error?.body?.message;
                        console.log(error);
                        this.showToast("Error", error?.body?.message, 'error');
                    })
                }
            })
            .catch((error) => {
                this.errorMessage = error?.body?.message;
                console.log(error);
                this.showToast("Error", error?.body?.message, 'error');
            })
      }
  }

  showToast(title, message, variant) {
      const evt = new ShowToastEvent({
          title: title,
          message: message,
          variant: variant,
      });
      this.dispatchEvent(evt);
  }

  getCookie(cookieName) {
      let cookieString = "; " + document.cookie;
      let splitArray = cookieString.split("; " + cookieName + "=");
      if (splitArray.length === 2) {
          return decodeURIComponent(splitArray.pop().split(";").shift());
      }
      return null;
  }


}