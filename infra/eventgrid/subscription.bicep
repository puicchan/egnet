@description('Name of the Event Grid system topic')
param systemTopicName string

@description('Name of the Azure Function App')
param functionAppName string

@description('Name of the unprocessed PDF container')
param unprocessedContainerName string

@description('Name for the event subscription')
param eventSubscriptionName string = 'unprocessed-pdf-topic-subscription'

// Reference to the existing Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' existing = {
  name: functionAppName
}

// Reference to the Function App host (this is key for getting the extension keys)
resource functionAppHost 'Microsoft.Web/sites/host@2022-09-01' existing = {
  name: 'default'
  parent: functionApp
}

// Reference to the existing Event Grid system topic
resource systemTopic 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' existing = {
  name: systemTopicName
}

// Create the Event Grid subscription
// This replaces the az eventgrid system-topic event-subscription create command
resource eventSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2024-06-01-preview' = {
  name: eventSubscriptionName
  parent: systemTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        // Build the webhook URL using the function app host listKeys approach
        endpointUrl: 'https://${functionAppName}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.ProcessBlobUpload&code=${functionAppHost.listKeys().systemKeys.blobs_extension}'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      // Filter events to only the unprocessed-pdf container
      subjectBeginsWith: '/blobServices/default/containers/${unprocessedContainerName}'
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

@description('The resource ID of the created event subscription')
output eventSubscriptionId string = eventSubscription.id

@description('The name of the created event subscription')
output eventSubscriptionName string = eventSubscription.name

@description('The endpoint URL used for the webhook')
output webhookEndpointUrl string = 'https://${functionAppName}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.ProcessBlobUpload&code=***'
