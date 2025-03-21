@description('The name seed for your application. Check outputs for the actual name and url')
param appName string = 'bottleneck'

@description('Version of node')
param appNodeVersion string = '14.15.1'

@description('Version of php')
param phpVersion string = '7.1'

@description('Name of the CosmosDb Account')
param databaseAccountId string = 'db-${appName}'

@description('Name of the web app host plan')
param hostingPlanName string = 'plan-${appName}'


//Making the name unique - if this fails, it's because the name is already taken (and you're really unlucky!)
var webAppName = 'app-${appName}-${uniqueString(resourceGroup().id, appName)}'

resource webApp 'Microsoft.Web/sites@2021-01-15' = {
  name: webAppName
  location: resourceGroup().location
  tags: {
    //This looks nasty, but see here: https://github.com/Azure/bicep/issues/555
    'hidden-related:${hostingPlan.id}': 'empty'
  }
  properties: {
    siteConfig: {
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: AppInsights.properties.InstrumentationKey
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'default'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: appNodeVersion
        }
        {
          name: 'CONNECTION_STRING'
          value: cosmos.outputs.connstr
        }
        {
          name: 'MSDEPLOY_RENAME_LOCKED_FILES'
          value: '1'
        }
        {
          name:'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        } //For use if you're doing a zip deploy and need build
      ]
      phpVersion: phpVersion
    }
    serverFarmId: hostingPlan.id
  }
}
output appUrl string = webApp.properties.defaultHostName
output appName string = webApp.name


resource webAppConfig 'Microsoft.Web/sites/config@2019-08-01' = { 
  parent: webApp
  name: 'web'
  properties: {
    scmType: 'ExternalGit'
  }
}

resource webAppLogging 'Microsoft.Web/sites/config@2021-02-01' = {
  parent: webApp
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Warning'
      }
    }
    httpLogs: {
      fileSystem: {
        enabled: true
        retentionInDays: 1
        retentionInMb: 25
      }
    }
  }
}




resource hostingPlan 'Microsoft.Web/serverfarms@2021-01-15' = {
  name: hostingPlanName
  location: resourceGroup().location
  sku: {
    name: 'P2v3'
    tier: 'PremiumV3'
    size: 'P2v3'
    family: 'Pv3'
    capacity: 1
  }
  kind: 'app'
  properties: {
    perSiteScaling: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
  }
}

resource AppInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: webAppName
  location: resourceGroup().location
  kind: 'web'
  tags: {
    //This looks nasty, but see here: https://github.com/Azure/bicep/issues/555
    'hidden-link:${resourceGroup().id}/providers/Microsoft.Web/sites/${webAppName}': 'Resource'
  }
  properties: {
    Application_Type: 'web'
    Request_Source: 'AzureTfsExtensionAzureProject'
  }
}

resource codeDeploy 'Microsoft.Web/sites/sourcecontrols@2021-01-15' = {
  parent: webApp
  name: 'web'
  properties: {
    repoUrl:'https://github.com/Azure-Samples/nodejs-appsvc-cosmosdb-bottleneck.git'
    branch: 'main'
    isManualIntegration: true
  }
}

//Using the latest api versions to deploy Cosmos actually stops the app code from working. So at least for the time being, it's going to just use the old API versions to create the MongoDb in CosmosDb.
//module costos 'cosmos2021.bicep' = { 
module cosmos 'cosmosRustic.bicep' = {
  name: 'cosmosDb'
  params: {
    databaseAccountId: databaseAccountId
  }
}
