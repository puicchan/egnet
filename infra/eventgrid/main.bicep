targetScope = 'subscription'

@description('Name of the resource group containing the resources')
param resourceGroupName string

@description('Name of the existing Azure Function App')
param functionAppName string

@description('Name of the existing Event Grid system topic')
param systemTopicName string

@description('Name of the unprocessed PDF container')
param unprocessedContainerName string = 'unprocessed-pdf'

@description('Name for the event subscription')
param eventSubscriptionName string = 'unprocessed-pdf-topic-subscription'

// Import the Event Grid subscription module
module eventGridSubscription 'subscription.bicep' = {
  name: 'eventGridSubscription'
  scope: resourceGroup(resourceGroupName)
  params: {
    systemTopicName: systemTopicName
    functionAppName: functionAppName
    unprocessedContainerName: unprocessedContainerName
    eventSubscriptionName: eventSubscriptionName
  }
}

// Outputs
@description('The resource ID of the created event subscription')
output eventSubscriptionId string = eventGridSubscription.outputs.eventSubscriptionId

@description('The name of the created event subscription')
output eventSubscriptionName string = eventGridSubscription.outputs.eventSubscriptionName

@description('The webhook endpoint URL (with masked key)')
output webhookEndpointUrl string = eventGridSubscription.outputs.webhookEndpointUrl

@description('Deployment summary')
output summary object = {
  eventSubscriptionName: eventGridSubscription.outputs.eventSubscriptionName
  functionAppName: functionAppName
  systemTopicName: systemTopicName
  containerName: unprocessedContainerName
  status: 'Event Grid subscription created successfully'
}
