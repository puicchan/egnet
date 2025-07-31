# Event Grid Subscription Module

This standalone Bicep template creates the Event Grid subscription for the Azure Functions Event Grid Blob Trigger application. It must be deployed **after** the main infrastructure is deployed, since it requires the Function App to exist in order to retrieve the necessary system keys.

## Why Standalone Deployment?

The Event Grid subscription requires access to the Function App's system keys (specifically `blobs_extension`) to construct the webhook URL. Since these keys are only available after the Function App is created and running, the Event Grid subscription must be deployed in a separate step.

## What This Module Does

The `subscription.bicep` module creates an Event Grid subscription that:

1. **Retrieves Function Key**: Uses `functionApp.listKeys().systemKeys.blobs_extension` to get the blob extension system key from the existing Function App
2. **Builds Webhook URL**: Constructs the Event Grid webhook endpoint URL:
   ```
   https://{functionAppName}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.ProcessBlobUpload&code={blobs_extension_key}
   ```
3. **Creates Event Subscription**: Sets up an Event Grid subscription that:
   - Listens for `Microsoft.Storage.BlobCreated` events
   - Filters events to only the `unprocessed-pdf` container
   - Forwards matching events to the Function App webhook
   - Configures retry policy (30 attempts, 1440 minutes TTL)

## Deployment Steps

### Step 1: Deploy Main Infrastructure
First, deploy the main infrastructure using AZD:

```bash
azd up
```

### Step 2: Deploy Event Grid Subscription

Navigate to the eventgrid folder and deploy the subscription:

```bash
cd infra/eventgrid
```

**Option A: Using the deployment script (Recommended)**

On Windows (PowerShell):
```powershell
.\deploy.bicep.ps1 -ResourceGroupName "rg-gridnet729b" -FunctionAppName "func-xyz" -SystemTopicName "eventgridpdftopic"
```

**Option B: Using Azure CLI directly (Subscription scope)**

```bash
# Using subscription-level deployment with environment variables
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters @main.parameters.json

# Or with direct parameters
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters \
    resourceGroupName="rg-gridnet729b" \
    functionAppName="func-xyz" \
    systemTopicName="eventgridpdftopic"
```

**Option C: With custom parameters**

```bash
az deployment group create \
  --resource-group "your-resource-group" \
  --template-file main.bicep \
  --parameters functionAppName="your-function-app" systemTopicName="eventgridpdftopic"
```

## Files in This Module

- `main.bicep` - Main Bicep template for the Event Grid subscription deployment
- `subscription.bicep` - The Event Grid subscription module (reusable)
- `main.parameters.json` - Parameters file with default values
- `deploy.ps1` - PowerShell deployment script
- `deploy.sh` - Bash deployment script for cross-platform support
- `README.md` - This documentation

## Parameters

Update `main.parameters.json` or provide these parameters:

- `functionAppName`: Name of the Azure Function App (get from AZD output `AZURE_FUNCTION_APP_NAME`)
- `systemTopicName`: Name of the Event Grid system topic (default: `eventgridpdftopic`)
- `unprocessedContainerName`: Name of the container to monitor (default: `unprocessed-pdf`)
- `eventSubscriptionName`: Name for the event subscription (default: `unprocessed-pdf-topic-subscription`)

## Getting Parameter Values

After running `azd up`, you can get the required parameter values:

```bash
# Get all environment values
azd env get-values

# Get specific values
echo "Function App: $(azd env get-value AZURE_FUNCTION_APP_NAME)"
echo "Resource Group: $(azd env get-value RESOURCE_GROUP)"
echo "System Topic: $(azd env get-value UNPROCESSED_PDF_SYSTEM_TOPIC_NAME)"
```

## Benefits of This Approach

✅ **Reliable Deployment**: Function App is guaranteed to exist before creating the subscription
✅ **Clean Separation**: Main infrastructure and Event Grid subscription are separate concerns
✅ **Reusable**: Can be easily redeployed or updated independently
✅ **No Post-Deployment Scripts**: Still infrastructure-as-code, just in two phases
    functionAppName: functionAppName
    unprocessedContainerName: unprocessedContainerName
  }
  dependsOn: [
    eventgripdftopic
    processor
  ]
}
```

## Parameters

- `systemTopicName`: Name of the Event Grid system topic
- `functionAppName`: Name of the Azure Function App
- `unprocessedContainerName`: Name of the container to monitor for blob events
- `eventSubscriptionName`: Name for the event subscription (optional, defaults to 'unprocessed-pdf-topic-subscription')

## Outputs

- `eventSubscriptionId`: Resource ID of the created event subscription
- `eventSubscriptionName`: Name of the created event subscription
- `webhookEndpointUrl`: The webhook endpoint URL (with masked key for security)

## Migration Notes

After deploying with this Bicep module, you can:

1. Remove or comment out the `postdeploy` hooks from `azure.yaml`
2. Delete the `scripts/post-up.ps1` and `scripts/post-up.sh` files (or keep them for reference)
3. The Event Grid subscription will be created automatically as part of the infrastructure deployment

## Security Considerations

- The function key is retrieved securely using Bicep's `listKeys()` function
- The key is never exposed in logs or outputs (only a masked version)
- Proper dependency management ensures the Function App is deployed before trying to retrieve keys
- Retry policy is configured to handle transient failures
