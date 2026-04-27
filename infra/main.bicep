// ============================================================
// PurchaseSample – Azure Integration Services Infrastructure
// Provisions all resources needed to run the purchase-flow
// Logic App Standard workflow.
//
// Resources created:
//   - Storage Account          (Logic App state store)
//   - App Service Plan (WS1)   (Logic App Standard host)
//   - Logic App Standard       (purchase-flow workflow host)
//   - Azure SQL Server + DB    (Customers & Products data)
//   - Service Bus Namespace    (async error notifications)
//   - Service Bus Queue        (purchase-errors)
//   - Key Vault                (secrets store)
//   - Key Vault secrets        (SQL & Service Bus connection strings)
//   - Role assignment          (Logic App MI → Key Vault Secrets User)
// ============================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short prefix used for resource naming (max 8 characters).')
@maxLength(8)
param prefix string = 'purchase'

@description('SQL Server administrator login username.')
param sqlAdminLogin string = 'sqladmin'

@description('SQL Server administrator login password.')
@secure()
param sqlAdminPassword string

@description('Name of the Service Bus queue that receives product-unavailable error notifications.')
param serviceBusQueueName string = 'purchase-errors'

// ============================================================
// Derived names — all globally unique via resourceGroup ID hash
// ============================================================
var suffix             = uniqueString(resourceGroup().id)
var storageAccountName = take('${prefix}st${suffix}', 24)
var appServicePlanName = '${prefix}-asp-${suffix}'
var logicAppName       = '${prefix}-la-${suffix}'
var sqlServerName      = '${prefix}-sql-${suffix}'
var sqlDatabaseName    = 'PurchaseSampleDb'
var serviceBusNsName   = '${prefix}-sb-${suffix}'
var keyVaultName       = take('${prefix}-kv-${suffix}', 24)

// Role definition ID for "Key Vault Secrets User"
var kvSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// ============================================================
// Storage Account — required by Logic App Standard for state
// ============================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

// ============================================================
// App Service Plan — Workflow Standard SKU (WS1)
// ============================================================
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  kind: 'elastic'
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
  properties: {
    maximumElasticWorkerCount: 20
  }
}

// ============================================================
// Logic App Standard
// System-assigned managed identity is used to read Key Vault
// secrets at runtime via @Microsoft.KeyVault() references in
// app settings.
// ============================================================
resource logicApp 'Microsoft.Web/sites@2023-01-01' = {
  name: logicAppName
  location: location
  kind: 'workflowapp,functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      appSettings: [
        { name: 'APP_KIND',                              value: 'workflowApp' }
        { name: 'FUNCTIONS_EXTENSION_VERSION',           value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME',              value: 'node' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION',          value: '~18' }
        {
          name:  'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name:  'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        { name: 'WEBSITE_CONTENTSHARE',                  value: logicAppName }
        {
          // Resolved at runtime via managed identity
          name:  'sql-connection-string'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=sql-connection-string)'
        }
        {
          // Resolved at runtime via managed identity
          name:  'servicebus-connection-string'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=servicebus-connection-string)'
        }
        { name: 'SERVICEBUS_QUEUE_NAME',                  value: serviceBusQueueName }
      ]
    }
  }
  // Note: the Key Vault role assignment (keyVaultRoleAssignment) is deployed
  // in the same template. The @Microsoft.KeyVault() app-setting references are
  // resolved at *runtime*, so the Logic App can read secrets by the time it
  // handles its first request.
}

// ============================================================
// Azure SQL Server
// ============================================================
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    minimalTlsVersion: '1.2'
  }
}

// Allow Azure services (including Logic App) to reach SQL
resource sqlFirewallAllowAzure 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIPs'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Azure SQL Database (Basic tier — suitable for dev/test)
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

// ============================================================
// Service Bus Namespace (Standard — supports queues & topics)
// ============================================================
resource serviceBusNs 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNsName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

// Error notification queue — replaces the BizTalk one-way
// PurchaseProductUnavailableErrorResponsePort send port
resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNs
  name: serviceBusQueueName
  properties: {
    lockDuration: 'PT30S'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P1D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 5
  }
}

// Shared Access Policy for Logic App (Send + Listen)
resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: serviceBusNs
  name: 'LogicAppSendListen'
  properties: {
    rights: [
      'Send'
      'Listen'
    ]
  }
}

// ============================================================
// Key Vault — stores SQL & Service Bus connection strings
// RBAC authorization model (no access policies)
// ============================================================
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name:   'standard'
    }
    tenantId:                 tenant().tenantId
    enableRbacAuthorization:  true
    enableSoftDelete:         true
    softDeleteRetentionInDays: 7
    enabledForDeployment:         false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption:     false
  }
}

// Grant Logic App managed identity the "Key Vault Secrets User" role
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name:  guid(keyVault.id, logicAppName, kvSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
    principalId:      logicApp.identity.principalId
    principalType:    'ServicePrincipal'
  }
}

// SQL connection string secret
resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name:   'sql-connection-string'
  properties: {
    value: 'Server=${sqlServer.properties.fullyQualifiedDomainName};Database=${sqlDatabaseName};User Id=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  }
}

// Service Bus connection string secret
resource serviceBusConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name:   'servicebus-connection-string'
  properties: {
    value: serviceBusAuthRule.listKeys().primaryConnectionString
  }
}

// ============================================================
// Outputs
// ============================================================
output logicAppName       string = logicApp.name
output logicAppHostname   string = logicApp.properties.defaultHostName
output sqlServerFqdn      string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName    string = sqlDatabase.name
output serviceBusNsName   string = serviceBusNs.name
output serviceBusQueueName string = serviceBusQueue.name
output keyVaultName       string = keyVault.name
