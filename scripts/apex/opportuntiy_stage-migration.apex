// AD-1937 one-time Opportunity stage migration.
// Run only after exporting the Opportunity and Payment__c backups and after
// deploying the six destination stage values. The trigger guard suppresses
// outbound webhooks and ServiceContract creation for this transaction.

Set<String> targetStages = new Set<String>{
    'Meeting Booked', 'Proposal Sent', 'Negotiation',
    'Contract Sent', 'Closed Won', 'Closed Lost'
};

Map<String, String> legacyStageMappings = new Map<String, String>{
    'New' => 'Meeting Booked',
    'In Progress' => 'Meeting Booked',
    'Meeting Scheduled' => 'Meeting Booked',
    'BAMFAM' => 'Meeting Booked',
    'Qualification' => 'Meeting Booked',
    'Active' => 'Meeting Booked',
    'On Hold' => 'Meeting Booked',
    'Proposal' => 'Proposal Sent',
    'Audit Complete' => 'Proposal Sent',
    'In Review' => 'Proposal Sent',
    'Negotiation/Review' => 'Negotiation',
    'Approved' => 'Negotiation',
    'Invoice Sent' => 'Contract Sent',
    'Invoiced' => 'Contract Sent',
    'Won' => 'Closed Won',
    'Closed - Won' => 'Closed Won',
    'Closed' => 'Closed Won',
    'Completed' => 'Closed Won',
    'Lost' => 'Closed Lost',
    'Unqualified' => 'Closed Lost',
    'Closed - Unqualified' => 'Closed Lost',
    'Cancelled' => 'Closed Lost'
};

List<Opportunity> sourceOpportunities = [
    SELECT Id, Name, StageName, Store__c
    FROM Opportunity
    WHERE StageName NOT IN :targetStages
    ORDER BY Id
];

Set<Id> sourceOpportunityIds = new Map<Id, Opportunity>(sourceOpportunities).keySet();
Set<Id> paidOpportunityIds = new Set<Id>();
if (!sourceOpportunityIds.isEmpty()) {
    for (Payment__c payment : [
        SELECT Opportunity__c
        FROM Payment__c
        WHERE Opportunity__c IN :sourceOpportunityIds
        AND Status__c = 'Paid'
    ]) {
        paidOpportunityIds.add(payment.Opportunity__c);
    }
}

Set<String> unmappedStages = new Set<String>();
Set<Id> storeAccessStoreIds = new Set<Id>();
Map<String, Integer> migratedCounts = new Map<String, Integer>();
List<Opportunity> updates = new List<Opportunity>();

for (Opportunity source : sourceOpportunities) {
    String newStage;
    if (source.StageName == 'Store Access') {
        newStage = paidOpportunityIds.contains(source.Id) ? 'Closed Won' : 'Contract Sent';
        if (source.Store__c != null) {
            storeAccessStoreIds.add(source.Store__c);
        }
    } else {
        newStage = legacyStageMappings.get(source.StageName);
    }

    if (newStage == null) {
        unmappedStages.add(source.StageName);
        continue;
    }

    updates.add(new Opportunity(Id = source.Id, StageName = newStage));
    String countKey = source.StageName + ' -> ' + newStage;
    migratedCounts.put(countKey, (migratedCounts.containsKey(countKey) ? migratedCounts.get(countKey) : 0) + 1);
}

if (!unmappedStages.isEmpty()) {
    throw new IllegalArgumentException('Migration aborted; unmapped Opportunity stages: ' + unmappedStages);
}

OpportunityTriggerHandler.skipWebhookFiring = true;
try {
    if (!updates.isEmpty()) {
        update updates;
    }
} finally {
    OpportunityTriggerHandler.skipWebhookFiring = false;
}

// SF-10 has not added an onboarding-status field to Store__c yet. The Store
// IDs originating from Store Access are retained here and in the CSV backup
// so SF-10 can copy the legacy status without reclassifying Opportunities.
System.debug(LoggingLevel.INFO, 'AD-1937 migrated counts: ' + migratedCounts);
System.debug(LoggingLevel.INFO, 'AD-1937 Store Access Store IDs for SF-10: ' + storeAccessStoreIds);
