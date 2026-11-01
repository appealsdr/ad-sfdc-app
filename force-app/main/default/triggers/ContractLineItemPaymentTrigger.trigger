trigger ContractLineItemPaymentTrigger on ContractLineItem (after insert) {
    ContractLineItemPaymentService.createInitialPayments(Trigger.new);
}