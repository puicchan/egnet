# Event Grid Infrastructure Conversion Summary

## Overview

This document summarizes the conversion process from imperative PowerShell scripts to declarative Bicep infrastructure-as-code for Event Grid subscription management in the Azure Functions Event Grid Blob Trigger application.

## What is Event Grid and Why Do You Need It?

### 🎯 **Purpose of Event Grid Subscription**

The Event Grid subscription is the **critical connector** that makes your blob processing automation work. Here's what it does:

#### **The Application Flow**
1. **User uploads PDF** → `unprocessed-pdf` container in Azure Storage
2. **Storage emits event** → "Hey, a new blob was created!"
3. **Event Grid receives event** → From the storage account's system topic
4. **Event Grid subscription filters** → "Is this in the `unprocessed-pdf` container?"
5. **Event Grid subscription forwards** → HTTP webhook call to your Function App
6. **Function App processes** → Downloads PDF, processes it, moves to `processed-pdf` container

#### **Without Event Grid Subscription**
❌ **No automation** - Files sit in `unprocessed-pdf` forever  
❌ **No triggers** - Function never knows new files exist  
❌ **Manual process** - You'd have to manually call the function or poll for files  

#### **With Event Grid Subscription**
✅ **Instant triggers** - Function runs immediately when file is uploaded  
✅ **Reliable delivery** - Event Grid handles retries and dead lettering  
✅ **Filtered events** - Only processes files from the right container  
✅ **Scalable** - Handles thousands of concurrent file uploads  

### 🔧 **Technical Components**

#### **Event Grid System Topic**
- **What**: Automatically created by Azure Storage
- **Purpose**: Publishes blob lifecycle events (created, deleted, etc.)
- **Events**: `Microsoft.Storage.BlobCreated`, `Microsoft.Storage.BlobDeleted`

#### **Event Grid Subscription** (What we're creating)
- **What**: A rule that defines "when X event happens, call Y endpoint"
- **Filter**: Only `BlobCreated` events from `unprocessed-pdf` container
- **Destination**: Your Function App's webhook endpoint
- **Payload**: Event details including blob name, container, metadata

#### **Function App Webhook**
- **What**: Special HTTP endpoint that receives Event Grid events
- **URL Pattern**: `https://{function-app}.azurewebsites.net/runtime/webhooks/blobs`
- **Authentication**: Requires function system key (`blobs_extension`)
- **Function**: Triggers your `ProcessBlobUpload` function

### 📋 **Real-World Example**

When you upload `invoice.pdf` to `unprocessed-pdf` container:

```json
{
  "eventType": "Microsoft.Storage.BlobCreated",
  "subject": "/blobServices/default/containers/unprocessed-pdf/blobs/invoice.pdf",
  "eventTime": "2025-07-29T16:30:00.000Z",
  "data": {
    "api": "PutBlob",
    "url": "https://storage.blob.core.windows.net/unprocessed-pdf/invoice.pdf",
    "contentType": "application/pdf"
  }
}
```

Event Grid subscription:
1. **Receives** this event from storage system topic
2. **Checks filter** - ✅ Subject starts with `/blobServices/default/containers/unprocessed-pdf/`
3. **Calls webhook** - `POST https://func-xyz.azurewebsites.net/runtime/webhooks/blobs?code=abc123`
4. **Function runs** - `ProcessBlobUpload` function processes `invoice.pdf`

### 🎛️ **Why Not Alternatives?**

#### **Timer Trigger** (Polling)
❌ **Delays** - Check every X minutes, miss immediate processing  
❌ **Inefficient** - Runs even when no files to process  
❌ **Complex logic** - Need to track what's been processed  

#### **Blob Trigger** (Direct binding)
❌ **Storage queues** - Uses hidden storage queues, harder to monitor  
❌ **Poison messages** - Failed processing can block the queue  
❌ **Less control** - Cannot easily customize retry logic  

#### **Event Grid** (Our choice)
✅ **Real-time** - Instant notification when files arrive  
✅ **Reliable** - Built-in retry and dead letter handling  
✅ **Observable** - Full event tracking and monitoring  
✅ **Flexible** - Easy to add filters, routing, multiple subscribers  

## Original Problem

The original implementation required a **two-phase deployment process**:

1. **Phase 1**: Deploy main infrastructure (Function App, Storage, Event Grid system topic) using `azd up`
2. **Phase 2**: Run post-deployment PowerShell script (`scripts/post-up.ps1`) to create Event Grid subscription

### Original PowerShell Approach (`scripts/post-up.ps1`)

```powershell
# Retrieve function app system key using Azure CLI
$blobExtensionKey = az functionapp keys list --name $functionAppName --resource-group $resourceGroupName --query "systemKeys.blobs_extension" -o tsv

# Construct webhook URL manually
$webhookUrl = "https://$functionAppName.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.ProcessBlobUpload&code=$blobExtensionKey"

# Create Event Grid subscription using Azure CLI
az eventgrid system-topic event-subscription create `
    --name $eventSubscriptionName `
    --resource-group $resourceGroupName `
    --system-topic-name $systemTopicName `
    --endpoint $webhookUrl `
    --included-event-types Microsoft.Storage.BlobCreated `
    --subject-begins-with "/blobServices/default/containers/unprocessed-pdf/"
```

### Limitations of Original Approach

❌ **Azure CLI Dependency**: Required Azure CLI for function key retrieval  
❌ **Imperative Process**: Manual steps outside of infrastructure-as-code  
❌ **CI/CD Complexity**: Multiple deployment phases with script dependencies  
❌ **Maintenance Overhead**: PowerShell scripts to maintain and version  
❌ **Platform Dependency**: Required PowerShell/.NET runtime

## Conversion Process

### Step 1: Research and Discovery

**Challenge**: How to access Azure Function system keys directly in Bicep without Azure CLI?

**Attempts Made**:
1. **Direct Function App `listKeys()`** - Failed: No `extensionKeys` property available
2. **Function App Keys Resource** - Failed: ARM template evaluation errors
3. **Microsoft.Web/sites/host Resource** - ✅ **Success!**

### Step 2: Key Technical Breakthrough

**Solution Discovery**: The `Microsoft.Web/sites/host` resource type provides access to function system keys:

```bicep
// Reference to the Function App host for key access
resource functionAppHost 'Microsoft.Web/sites/host@2022-09-01' existing = {
  name: 'default'
  parent: functionApp
}

// Access system keys directly in Bicep
${functionAppHost.listKeys().systemKeys.blobs_extension}
```

**Key Properties Available**:
- `masterKey` - Function app master key
- `functionKeys` - Individual function keys
- `systemKeys.blobs_extension` - ✅ **The key we needed!**

### Step 3: Pure Bicep Implementation

Created new infrastructure under `/infra/eventgrid/`:

#### A. **Core Event Grid Module** (`subscription.bicep`)
```bicep
resource eventSubscription 'Microsoft.EventGrid/systemTopics/ @2024-06-01-preview' = {
  name: eventSubscriptionName
  parent: systemTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${functionAppName}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.ProcessBlobUpload&code=${functionAppHost.listKeys().systemKeys.blobs_extension}'
      }
    }
    filter: {
      subjectBeginsWith: '/blobServices/default/containers/${unprocessedContainerName}'
      includedEventTypes: ['Microsoft.Storage.BlobCreated']
    }
  }
}
```

#### B. **Deployment Wrapper** (`main.bicep`)
```bicep
module eventGridSubscription 'subscription.bicep' = {
  name: 'eventGridSubscription'
  params: {
    systemTopicName: systemTopicName
    functionAppName: functionAppName
    unprocessedContainerName: unprocessedContainerName
    eventSubscriptionName: eventSubscriptionName
  }
}
```

#### C. **Enhanced Deployment Script** (`deploy.bicep.ps1`)
```powershell
$deploymentResult = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "main.bicep" `
    --parameters "@$parameterFile" `
    --output json | ConvertFrom-Json
```

### Step 4: Trial and Error Process

**Error-Driven Development**: ARM template errors provided crucial insights:

1. **First Error**: `'extensionKeys' doesn't exist, available properties are 'masterKey, functionKeys, systemKeys'`
   - **Learning**: Use `systemKeys` instead of `extensionKeys`

2. **Second Error**: `'eventgrid_extension' doesn't exist, available properties are 'blobs_extension'`
   - **Learning**: Use `blobs_extension` for blob trigger webhooks

3. **Final Success**: `systemKeys.blobs_extension` worked perfectly!

### Step 5: Testing and Validation

**End-to-End Testing**:
1. ✅ **Deployment Success**: `provisioningState: "Succeeded"`
2. ✅ **Function Integration**: Uploaded `PerksPlus.pdf` → Event Grid → Function App
3. ✅ **File Processing**: File moved to `processed-pdf` container as `processed-PerksPlus.pdf`

## New Deployment Architecture

### Why Two-Phase Deployment is Required

The Event Grid subscription **cannot** be deployed in the same Bicep template as the Function App due to a **circular dependency problem**:

#### 🔄 **The Dependency Challenge**
1. **Event Grid subscription needs**: Function App to exist + Function App system keys
2. **Function App system keys**: Only available **after** the Function App is fully deployed and running
3. **Bicep limitation**: Cannot reference `listKeys()` on a resource being created in the same template

#### 🚫 **What Doesn't Work (Single-Phase)**
```bicep
// ❌ This FAILS because functionApp is being created in same template
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  // ... function app configuration
}

resource functionAppHost 'Microsoft.Web/sites/host@2022-09-01' existing = {
  name: 'default'
  parent: functionApp  // ❌ Can't use listKeys() on resource being created
}

resource eventSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2024-06-01-preview' = {
  // ❌ This will fail at ARM template evaluation time
  properties: {
    destination: {
      properties: {
        endpointUrl: '...code=${functionAppHost.listKeys().systemKeys.blobs_extension}'  // ❌ FAILS
      }
    }
  }
}
```

#### ✅ **What Works (Two-Phase)**
```bicep
// Phase 1: Deploy Function App (main infrastructure)
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  // ... function app configuration - deployed and running
}

// Phase 2: Deploy Event Grid subscription (separate template)
resource functionApp 'Microsoft.Web/sites@2022-09-01' existing = {  // ✅ References EXISTING resource
  name: functionAppName
}

resource functionAppHost 'Microsoft.Web/sites/host@2022-09-01' existing = {
  name: 'default'
  parent: functionApp  // ✅ Works because function app already exists
}
```

#### 🔑 **ARM Template Evaluation Rules**
- **Creation Time**: ARM cannot evaluate `listKeys()` on resources that don't exist yet
- **Existing Resources**: ARM can evaluate `listKeys()` on resources marked as `existing`
- **Deployment Boundary**: Each ARM deployment must be self-contained with all dependencies available

### Two-Phase Pure Bicep Approach

#### Phase 1: Main Infrastructure
```bash
azd up  # Deploys Function App, Storage, Event Grid system topic
```

#### Phase 2: Event Grid Subscription
```bash
az deployment group create \
  --resource-group "rg-gridnet729b" \
  --template-file "infra/eventgrid/main.bicep" \
  --parameters "@infra/eventgrid/main.parameters.json"
```

### Alternative Approaches Considered

#### ❌ **Option 1: Single Bicep Template with dependsOn**
```bicep
resource eventSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2024-06-01-preview' = {
  dependsOn: [functionApp]  // ❌ Still fails because listKeys() evaluated at template compilation
  // ...
}
```
**Problem**: `dependsOn` only controls deployment order, not ARM template evaluation. `listKeys()` is evaluated during template compilation, before deployment.

#### ❌ **Option 2: Nested Templates with Outputs**
```bicep
// Try to output the key from nested template
output functionKey string = functionApp.listKeys().systemKeys.blobs_extension  // ❌ Same problem
```
**Problem**: Same ARM evaluation issue - can't use `listKeys()` on resources being created.

#### ❌ **Option 3: Deployment Scripts**
```bicep
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  // Run Azure CLI to get keys and create subscription
}
```
**Problem**: Defeats the purpose of pure Bicep; adds complexity and Azure CLI dependency back.

#### ✅ **Option 4: Two-Phase Deployment (Our Solution)**
- **Phase 1**: Deploy and establish all base resources
- **Phase 2**: Reference existing resources with `listKeys()`
- **Result**: Clean, pure Bicep solution without workarounds

### File Structure Created

```
infra/eventgrid/
├── main.bicep               # Deployment wrapper module
├── subscription.bicep       # Core Event Grid subscription with function key access
├── main.parameters.json     # Deployment parameters
├── deploy.bicep.ps1        # Enhanced PowerShell deployment script
└── README.md               # Documentation
```

## Conversion Benefits Achieved

### ✅ **Infrastructure-as-Code Purity**
- **Before**: Hybrid approach (Bicep + PowerShell scripts)
- **After**: Pure Bicep declarative infrastructure

### ✅ **Eliminated Dependencies**
- **Before**: Required Azure CLI for function key retrieval
- **After**: Native Bicep function key access

### ✅ **CI/CD Simplification**
- **Before**: Complex multi-step deployment with script execution
- **After**: Standard Bicep deployment pipeline

### ✅ **Maintainability**
- **Before**: PowerShell scripts to version and maintain
- **After**: Declarative Bicep templates with versioning

### ✅ **Repeatability**
- **Before**: Script execution could vary based on environment
- **After**: Consistent Bicep deployment results

### ✅ **Platform Independence**
- **Before**: Required PowerShell/.NET runtime
- **After**: Standard Azure Resource Manager deployment

## Technical Insights Gained

### 1. **ARM Template Function Discovery**
- `Microsoft.Web/sites/host` resource provides reliable access to function keys
- ARM template errors are invaluable for API discovery
- `listKeys()` behavior varies significantly between resource types

### 2. **Bicep Resource Reference Patterns**
```bicep
// Pattern for accessing existing resources across modules
resource functionApp 'Microsoft.Web/sites@2022-09-01' existing = {
  name: functionAppName
}

resource functionAppHost 'Microsoft.Web/sites/host@2022-09-01' existing = {
  name: 'default'
  parent: functionApp  // Key: parent relationship for nested resources
}
```

### 3. **Event Grid Webhook URL Construction**
```bicep
// Template: https://{function-app}.azurewebsites.net/runtime/webhooks/{trigger-type}?functionName={namespace}.{function}&code={system-key}
endpointUrl: 'https://${functionAppName}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.ProcessBlobUpload&code=${functionAppHost.listKeys().systemKeys.blobs_extension}'
```

## Migration Impact

### Files Replaced
- ❌ `scripts/post-up.ps1` - No longer needed for new deployments
- ❌ `scripts/post-up.sh` - No longer needed for new deployments

### Files Added
- ✅ `infra/eventgrid/main.bicep` - Deployment wrapper
- ✅ `infra/eventgrid/subscription.bicep` - Core Event Grid module
- ✅ `infra/eventgrid/main.parameters.json` - Parameters
- ✅ `infra/eventgrid/deploy.bicep.ps1` - Enhanced deployment script
- ✅ `infra/eventgrid/README.md` - Documentation

### Deployment Process Change
- **Before**: `azd up` → Run `scripts/post-up.ps1` → Manual verification
- **After**: `azd up` → `az deployment group create` → Automatic verification

## Future Recommendations

### 1. **Integration with AZD**
Consider integrating the Event Grid deployment into the main `azd up` process using Bicep modules.

### 2. **Template Generalization**
The Event Grid subscription template could be generalized for other blob containers or event types.

### 3. **CI/CD Pipeline Integration**
The pure Bicep approach enables seamless integration with Azure DevOps, GitHub Actions, or other CI/CD platforms.

### 4. **Monitoring and Alerting**
Add Application Insights integration and monitoring to the Bicep templates for better observability.

## Conclusion

The conversion from imperative PowerShell scripts to declarative Bicep infrastructure represents a significant improvement in:
- **Developer Experience**: Simplified deployment process
- **Operational Excellence**: Consistent, repeatable deployments
- **Maintenance**: Reduced complexity and dependencies
- **CI/CD Integration**: Standard infrastructure-as-code practices

The key breakthrough was discovering the `Microsoft.Web/sites/host` resource type for accessing function system keys directly in Bicep, eliminating the need for Azure CLI-based key retrieval in post-deployment scripts.

---
*This conversion demonstrates the power of declarative infrastructure-as-code and the importance of persistence when working with Azure Resource Manager APIs.*
