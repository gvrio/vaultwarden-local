@description('Specify container app name')
param containerAppName string = 'containerapp-${uniqueString(resourceGroup().id)}'

@description('Specify container app env')
param containerAppEnvName string = 'containerapp-env-${uniqueString(resourceGroup().id)}'

@description('Specify container app log space')
param containerAppLogName string = 'containerapp-log-${uniqueString(resourceGroup().id)}'

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
              // computed, not a placeholder — the environment's default domain is
              // known independently of this container app, so the FQDN can be
              // built ahead of the app actually existing
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
          ]
        }
      ]
      scale: {
        minReplicas: minReplica
        maxReplicas: maxReplica
      }
    }
  }
}
