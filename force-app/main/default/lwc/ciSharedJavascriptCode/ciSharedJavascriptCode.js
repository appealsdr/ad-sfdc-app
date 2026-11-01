const isEmpty = (value) => {
    return (value ==undefined || value == null || (typeof value === "string" && value.trim().length === 0) || (value.constructor === Array && value.length==0) );
 };

  function isInputValid(className,lwctemplate) {

    let isValid = true;
    let inputFields = lwctemplate.querySelectorAll('.'+className);
   console.log('inputFields==>',inputFields);
 //  let inputFields = lwctemplate.querySelectorAll('lightning-input');
  
    (inputFields || []).forEach(inputField => {
        //console.log('inputField==>'+inputField.label );
        if(!inputField.checkValidity() && isEmpty(inputField.value)) {
            inputField.setCustomValidity(inputField.label +' is required');
            inputField.reportValidity();
            isValid = false;
           // console.log( 'if::inputField==>'+inputField.label +'----Value----'+inputField.value );
        } else {
            //console.log( 'else::inputField==>'+inputField.label +'----Value----'+inputField.value );
           
            inputField.setCustomValidity('');
            inputField.reportValidity();
        }
        
    });
    console.log('isValid==>'+isValid);
    return isValid;
    
  }

  export function areRequiredInputHasvalue(className,lwctemplate) {

    let isValid = true;
    let inputFields = lwctemplate.querySelectorAll('.'+className);
    inputFields.forEach(inputField => {
        console.log('inputField.value==>'+inputField.value);
        if(isEmpty(inputField.value)) {    
            isValid = false;
         
        }
        
    });
    return isValid;
    
  }

  export function isStringNumeric(str){
    if (typeof str != "string") return false 
    return !isNaN(str) && 
           !isNaN(parseFloat(str)) 
  }

  function isSpecialCharter(starValue){
    var format = /[ `!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~]/;
    return format.test(starValue);
  }

  function childInputValidate(childCompName, lwctemplate){
    let isValid = true;
    let inputFields = lwctemplate.querySelectorAll('');
    console.log('1inputFields==>'+JSON.stringify(inputFields));
    Array.from(inputFields).forEach(inputField => {
        console.log('inputField==>'+JSON.stringify(inputField));
        if(inputField)
        if(!inputField.validate()) {
            inputField.reportValidity();
            isValid = false;
        }
    });
    return isValid;
  }

  function makeMutiselectOptions(listData){
    let mutiselectOptions = listData.map((item) => {
        return {"label":item, "value":item}
        }
    );
   return mutiselectOptions;
  }
   //CH for
   function validateEmail(email) {
        const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailPattern.test(email);
    }

    function validatePhone(phoneNumber) {
        let isValid = false;
         const phoneRegex = /^[+]?[(]?[0-9]{1,4}[)]?[-\s.]?[0-9]{1,4}[-\s.]?[0-9]{1,9}$/;
            if (phoneRegex.test(phoneNumber)) {
                isValid = true;
                console.log('Valid phone number');
            } else {
                  console.log('Invalid phone number');
            }
            return isValid;
    }

    function validateMobileNumber(mobileNumber) {
        let isValid = false;
        const regex = /^\+?[6-9]\d{9}$/;
        if (regex.test(mobileNumber)) {
            isValid = true;
            console.log('Valid Mobile number');
        } else {
            console.log('Invalid Mobile number');
        }
        return isValid;
    }

    function isSelectDateInPast(selectedDate){
		console.log('selectedDate ==>', selectedDate);
		const selected = new Date(selectedDate);
		const today = new Date();
		selected.setHours(0, 0, 0, 0);
		today.setHours(0, 0, 0, 0);
		const isSelectedDateInPast = selected < today;
		console.log(isSelectedDateInPast ? "It's in the past." : "It's today or in the future.");
		return isSelectedDateInPast;
    }

    function isDate1equalDate2(d1, d2) {
		console.log('d1 ==>', d1);
		let selected = new Date(d1);
		let vistDate = new Date(d2);
         // vistDate = vistDate.toISOString();
		selected.setHours(0, 0, 0, 0);
		vistDate.setHours(0, 0, 0, 0);
        console.log('selected ==>', selected);
        console.log('vistDate ==>', vistDate);
		const isEqualVisitDate = selected+'' == vistDate+''
		console.log(isEqualVisitDate ? "D1 equal D2" : "D1 not equal D2");
		return isEqualVisitDate;
    }

    function isDateWithinNDays(dateStr, nDay) {
        const inputDate = new Date(dateStr);
        const now = new Date();

        // Remove time portion for accurate day comparison
        now.setHours(0, 0, 0, 0);
        inputDate.setHours(0, 0, 0, 0);

        const nDaysAgo = new Date(now);
        nDaysAgo.setDate(now.getDate() - nDay);

        // Check: date must be between nDaysAgo and today
        return inputDate >= nDaysAgo 
        //&& inputDate <= now;
    }

    function isDateTodayOrFuture(dateToCheck) {
        const today = new Date();
        today.setHours(0, 0, 0, 0); // Normalize to start of today
        const inputDate = new Date(dateToCheck);
        inputDate.setHours(0, 0, 0, 0); // Normalize input date

        return inputDate >= today;
    }

    function isToday(selectedDate) {
       selectedDate = new Date(selectedDate);
       const today = new Date();
       return (
       selectedDate.getDate() === today.getDate() &&
       selectedDate.getMonth() === today.getMonth() &&
       selectedDate.getFullYear() === today.getFullYear()
       );
    }

    function  isFutureDate(selectedDate) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        selectedDate.setHours(0, 0, 0, 0);
        return selectedDate > today;   
    }

export function restrictInvalidKeysForNumberInput(event) {
        // Block 'e', 'E', '+', '-', and '.'
        const fieldName = event.target.name;
        const input = event.target;
        const value = input.value
        const key = event.key;
        console.log('fieldName' + fieldName);
 
        if (( ['e', 'E', '+', '-', '.','t','k','m','b', ].includes(event.key))) {
            event.preventDefault();
        }
}

export function restrictNumberUpto2Decimal(event) {
    // Block 'e', 'E', '+', '-', and '.'
    const fieldName = event.target.name;
    const input = event.target;
    const value = input.value ?? '' ;
    const key = event.key;
    console.log('fieldName: ' + fieldName);
    const step = input.step ? parseFloat(input.step) : null;

    if ( ['e', 'E', '+', '-', 't','k','m','b'].includes(event.key)) {
        event.preventDefault();
    }

    if (value.includes('.') && /[0-9]/.test(key)) {
        const decimals = value.split('.')[1];
        const cursorPos = input.selectionStart;
        const decimalIndex = value.indexOf('.');
        if (cursorPos > decimalIndex && decimals.length >= 2) {
            event.preventDefault();
            return;
        }
    }

    else if (step === 0.01) {
    // Prevent more than one decimal point
        if (key === '.' && value.includes('.')) {
            event.preventDefault();
            return;
        }

        // If there's a decimal point, restrict to 3 digits after it
        if (value.includes('.') && /[0-9]/.test(key)) {
            const decimals = value.split('.')[1];
            const cursorPos = input.selectionStart;
            const decimalIndex = value.indexOf('.');
            if (cursorPos > decimalIndex && decimals.length >= 2) {
                event.preventDefault();
                return;
            }
        }
    }
       
}

export function restrictNumberUpto3Decimal(event) {
    // Block 'e', 'E', '+', '-', and '.'
    const fieldName = event.target.name;
    const input = event.target;
    const value = input.value ?? '' ;
    const key = event.key;
    console.log('fieldName: ' + fieldName);
    const step = input.step ? parseFloat(input.step) : null;

    if ( ['e', 'E', '+', '-', 't','k','m','b'].includes(event.key)) {
        event.preventDefault();
    }

    if (value.includes('.') && /[0-9]/.test(key)) {
        const decimals = value.split('.')[1];
        const cursorPos = input.selectionStart;
        const decimalIndex = value.indexOf('.');
        if (cursorPos > decimalIndex && decimals.length >= 3) {
            event.preventDefault();
            return;
        }
    }

    else if (step === 0.001) {
    // Prevent more than one decimal point
        if (key === '.' && value.includes('.')) {
            event.preventDefault();
            return;
        }

        // If there's a decimal point, restrict to 3 digits after it
        if (value.includes('.') && /[0-9]/.test(key)) {
            const decimals = value.split('.')[1];
            const cursorPos = input.selectionStart;
            const decimalIndex = value.indexOf('.');
            if (cursorPos > decimalIndex && decimals.length >= 3) {
                event.preventDefault();
                return;
            }
        }
    }
       
}

export function  refreshChoosenPicklist(_this, className) {
    console.log('refreshChossenPicklist==>');
    let pickEle = _this.template.querySelector('.'+className);
    console.log('pickEle==>'+pickEle);
    pickEle.refreshChosenPicklist(className);
    setTimeout(() => {
       console.log('In=pickEle=>'+pickEle);
       pickEle.openDropdown(className); 
    }, 100); 
}

export function diffInDays(fromDate, toDate) {
    const start = new Date(fromDate);
    const end = new Date(toDate);

    // Normalize time to 00:00:00
    start.setHours(0,0,0,0);
    end.setHours(0,0,0,0);
      console.log('fromDate==>',fromDate);
        console.log('toDate==>',toDate);
    const msPerDay = 1000 * 60 * 60 * 24;
    let diffInDay = Math.floor((end - start) / msPerDay);
    console.log('diffInDay==>',diffInDay);
    return diffInDay;
}


export function splitNumber(value) {
    const num = Number(value);

    const integerPart = Math.floor(num);
    const fractionPart = +(num - integerPart).toFixed(2);
    const hasFraction = fractionPart > 0;

    return { integerPart, fractionPart, hasFraction };
}


export{ isEmpty, isInputValid,childInputValidate, makeMutiselectOptions, isSpecialCharter
         ,validateEmail,validatePhone,validateMobileNumber,isSelectDateInPast,isDate1equalDate2,isDateWithinNDays
         , isDateTodayOrFuture, isToday, isFutureDate
 };