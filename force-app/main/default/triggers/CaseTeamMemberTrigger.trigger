trigger CaseTeamMemberTrigger on Case_Team_Member__c (before insert, after insert, before delete) {
    TriggerFrameworkService.triggerObj = 'CaseTeamMember';
    new CaseTeamMemberHandler().run();
}