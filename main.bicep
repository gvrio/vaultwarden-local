param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Specify container app name')
param containerAppName string = 'containerapp-${uniqueSuffix}'

@description('Specify container app env name')
param containerAppEnvName string = 'containerapp-env-${uniqueSuffix}'

@description('Specify container app log name')
param containerAppLogName string = 'containerapp-log-${uniqueSuffix}'

@description('Specify storage account name')
param storageAccountName string = 'stacc${uniqueSuffix}'

@description('Specify storage env name')
param storageEnvName string = 'stenv${uniqueSuffix}'

@description('Specify file share name')
param fileShareName string = 'vw-data'

@description('Specify deployment location')
param location string = 'canadaeast'

@description('Specify vaultwarden release version')
param vwVersion string = 'latest'

@description('PLACEHOLDER - Entra ID tenant ID, from the app registration')
param entraTenantId string

@description('PLACEHOLDER - Entra ID application (client) ID, from the app registration')
param ssoClientId string

@description('PLACEHOLDER - Entra ID client secret value, from the app registration')
@secure()
param ssoClientSecret string

@description('PLACEHOLDER - Argon2id PHC hash generated via `vaultwarden hash`, NOT plaintext')
@secure()
param adminTokenHash string

var vaultwardenContainerImage string = 'vaultwarden/server:${vwVersion}'
var ssoAuthority string = '${environment().authentication.loginEndpoint}${entraTenantId}/v2.0'

var minReplica int = 0
var maxReplica int = 1

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: containerAppLogName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

resource containerAppEnv 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: containerAppEnv.id

    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
      }
      secrets: [
        {
          name: 'sso-client-secret'
          value: ssoClientSecret
        }
        {
          name: 'admin-token'
          value: adminTokenHash
        }
      ]
    }

    template: {
      containers: [
        {
          name: 'vaultwarden'
          image: vaultwardenContainerImage
          env: [
            {
              name: 'DOMAIN'
              value: 'https://${containerAppName}.${containerAppEnv.properties.defaultDomain}'
            }
            {
              name: 'SSO_ENABLED'
              value: 'true'
            }
            {
              name: 'SSO_ONLY'
              value: 'true'
            }
            {
              name: 'SSO_CLIENT_ID'
              value: ssoClientId
            }
            {
              name: 'SSO_CLIENT_SECRET'
              secretRef: 'sso-client-secret'
            }
            {
              name: 'SSO_AUTHORITY'
              value: ssoAuthority
            }
            {
              name: 'ADMIN_TOKEN'
              secretRef: 'admin-token'
            }
            {
              name: 'SIGNUPS_ALLOWED'
              value: 'false'
            }
            {
              name: 'SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION'
              value: 'true'
            }
            {
              name: 'ENABLE_DB_WAL' 
              value: 'true'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'vw-data'
              mountPath: '/data'
              
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'vw-data'
          storageName: storageEnv.name
          storageType:'AzureFile'
          mountOptions: 'uid=0,gid=0,dir_mode=0777,file_mode=0777,mfsymlinks,nobrl'
        }
      ]
      
      scale: {
        minReplicas: minReplica
        maxReplicas: maxReplica
      }
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name:'Standard_LRS'
  }
}

resource storageEnv 'Microsoft.App/managedEnvironments/storages@2026-01-01' ={
  parent: containerAppEnv
  name: storageEnvName
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: fileStorage.name
      accessMode: 'ReadWrite'
    }
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2026-04-01' existing = {
  parent: storageAccount
  name: 'default'
}

resource fileStorage 'Microsoft.Storage/storageAccounts/fileServices/shares@2026-04-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    shareQuota: 1
    enabledProtocols: 'SMB'
    accessTier: 'TransactionOptimized'
  }
}


