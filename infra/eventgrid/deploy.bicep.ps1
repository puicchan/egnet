#!/usr/bin/env pwsh

<#
.SYNOPSIS
Pure Bicep deployment script for Event Grid subscription

.DESCRIPTION
This script deploys an Event Grid subscription using pure Bicep infrastructure-as-code.
It replaces the original PowerShell script that used Azure CLI commands for key retrieval.

.PARAMETER ResourceGroupName
The name of the resource group containing the Function App and Event Grid system topic

.PARAMETER FunctionAppName
The name of the Function App to connect to

.PARAMETER SystemTopicName
The name of the Event Grid system topic

.PARAMETER EventSubscriptionName
The name of the Event Grid subscription to create

.EXAMPLE
.\deploy.bicep.ps1 -ResourceGroupName "rg-gridnet729b" -FunctionAppName "func-t4omtjkvxmhtg" -SystemTopicName "eventgridpdftopic"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$FunctionAppName,
    
    [Parameter(Mandatory = $true)]
    [string]$SystemTopicName,
    
    [Parameter(Mandatory = $false)]
    [string]$EventSubscriptionName = "unprocessed-pdf-topic-subscription",
    
    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "unprocessed-pdf"
)

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Event Grid subscription deployment..." -ForegroundColor Green
Write-Host "   Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host "   Function App: $FunctionAppName" -ForegroundColor Cyan
Write-Host "   System Topic: $SystemTopicName" -ForegroundColor Cyan
Write-Host "   Event Subscription: $EventSubscriptionName" -ForegroundColor Cyan

try {
    # Create parameter file content
    $parameterContent = @{
        "`$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
        "contentVersion" = "1.0.0.0"
        "parameters" = @{
            "resourceGroupName" = @{ "value" = $ResourceGroupName }
            "functionAppName" = @{ "value" = $FunctionAppName }
            "systemTopicName" = @{ "value" = $SystemTopicName }
            "eventSubscriptionName" = @{ "value" = $EventSubscriptionName }
            "unprocessedContainerName" = @{ "value" = $ContainerName }
        }
    } | ConvertTo-Json -Depth 10

    # Write parameter file
    $parameterFile = Join-Path $PSScriptRoot "main.parameters.deploy.json"
    $parameterContent | Out-File -FilePath $parameterFile -Encoding UTF8

    Write-Host "📄 Created parameter file: $parameterFile" -ForegroundColor Yellow

    # Deploy using Azure CLI at subscription scope
    Write-Host "🔧 Deploying Bicep template at subscription scope..." -ForegroundColor Yellow
    
    $deploymentResult = az deployment sub create `
        --location "East US" `
        --template-file (Join-Path $PSScriptRoot "main.bicep") `
        --parameters "@$parameterFile" `
        --output json | ConvertFrom-Json

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Event Grid subscription deployed successfully!" -ForegroundColor Green
        
        # Output deployment summary
        if ($deploymentResult.properties.outputs.summary) {
            $summary = $deploymentResult.properties.outputs.summary.value
            Write-Host ""
            Write-Host "📋 Deployment Summary:" -ForegroundColor Magenta
            Write-Host "   Status: $($summary.status)" -ForegroundColor Green
            Write-Host "   Event Subscription: $($summary.eventSubscriptionName)" -ForegroundColor Cyan
            Write-Host "   Function App: $($summary.functionAppName)" -ForegroundColor Cyan
            Write-Host "   System Topic: $($summary.systemTopicName)" -ForegroundColor Cyan
            Write-Host "   Container: $($summary.containerName)" -ForegroundColor Cyan
        }

        # Test the connection
        Write-Host ""
        Write-Host "🧪 Testing Event Grid subscription..." -ForegroundColor Yellow
        $subscription = az eventgrid system-topic event-subscription show `
            --name $EventSubscriptionName `
            --resource-group $ResourceGroupName `
            --system-topic-name $SystemTopicName `
            --output json | ConvertFrom-Json

        if ($subscription.provisioningState -eq "Succeeded") {
            Write-Host "✅ Event Grid subscription is active and ready!" -ForegroundColor Green
            Write-Host "   Endpoint: $($subscription.destination.endpointBaseUrl)" -ForegroundColor Cyan
            Write-Host "   Filter: $($subscription.filter.subjectBeginsWith)" -ForegroundColor Cyan
        }
        else {
            Write-Warning "⚠️ Event Grid subscription state: $($subscription.provisioningState)"
        }
    }
    else {
        Write-Error "❌ Deployment failed. Check the error details above."
        exit 1
    }
}
catch {
    Write-Error "❌ Deployment failed with error: $($_.Exception.Message)"
    exit 1
}
finally {
    # Clean up temporary parameter file
    if (Test-Path $parameterFile) {
        Remove-Item $parameterFile -Force
        Write-Host "🧹 Cleaned up temporary parameter file" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "🎉 Event Grid setup complete! Your Function App will now receive blob upload events." -ForegroundColor Green
Write-Host ""
Write-Host "💡 To test the setup:" -ForegroundColor Blue
Write-Host "   1. Upload a PDF file to the '$ContainerName' container in your storage account" -ForegroundColor White
Write-Host "   2. Check the 'processed-pdf' container for the processed file" -ForegroundColor White
Write-Host "   3. Review Application Insights logs for function execution details" -ForegroundColor White
