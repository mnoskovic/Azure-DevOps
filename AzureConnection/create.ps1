# 
#  Need to be run as subscription owner/admin with abilitiy to manage azure ad 
#  - creates app registration
#  - assigns permissions to it on subscription level (contributor, user access administrator)
#  - creates ednpoint in azure devops (binding to the account)


param
(

    [Parameter(Mandatory=$false)]	
    $Subscription = $null, # subscription id or name 

    [Parameter(Mandatory=$false)]	
    $ApplicationName = "devops",

    [Parameter(Mandatory=$true)]	
    $ApplicationPassword,  # app registration password

    [Parameter(Mandatory=$true)]	
    $AzureDevOpsProjectUrl,  # e.g. "https://dev.azure.com/mnoskovic-trainings/devops",

    [Parameter(Mandatory=$false)]	
    $AzureDevOpsServiceConnectionName = "azure",

    [Parameter(Mandatory=$true)]	
    $AzureDevOpsPatToken, # "pat token value", 

    [switch] $local #= $true
)

#cls

function Add-RoleDefinition
{
    param
    (
        
        $servicePrincipalName,
        $servicePrincipalId,
        $roleDefinitionName,
        $scope
    )

    $ra = Get-AzureRmRoleAssignment -RoleDefinitionName $roleDefinitionName -ServicePrincipalName $servicePrincipalName  -Scope $scope -ErrorAction SilentlyContinue
    if ($ra -eq $null)
    {
        Write-Output "Assigning $roleDefinitionName role for '$ApplicationName' to subscription"
    
        $NewRole = $null
        $Retries = 0;
        While ($NewRole -eq $null -and $Retries -le 6)
        {
            # Sleep here for a few seconds to allow the service principal application to become active (should only take a couple of seconds normally)
            Sleep 15
            New-AzureRMRoleAssignment -RoleDefinitionName $roleDefinitionName -ServicePrincipalName $servicePrincipalName -Scope $scope | Write-Verbose -ErrorAction SilentlyContinue
            $NewRole = Get-AzureRMRoleAssignment -RoleDefinitionName $roleDefinitionName -ServicePrincipalName $servicePrincipalName -Scope $scope -ErrorAction SilentlyContinue
            $Retries++;
        }
    }
    else
    {
        Write-Output "$roleDefinitionName role for '$ApplicationName' to subscription already exists"
    }
}


if ($local.IsPresent)
{
    if($Subscription -ne $null)
    {
        Login-AzureRmAccount -Subscription $Subscription
    }
    else
    {
        Login-AzureRmAccount
    }    
}


if ([System.String]::IsNullOrEmpty($ApplicationPassword))
{
    Write-Error "Application password missing"
    Exit
}


$appPwd = ConvertTo-SecureString $ApplicationPassword -AsPlainText -Force

$app = Get-AzureRmADApplication | Where-Object { $_.DisplayName -eq $ApplicationName } | Select-Object -First 1
if ($app -eq $null)
{
    Write-Output "Creating AD App Registration '$ApplicationName'"

     #set permission to "Read and Write All Applications"
    $app = New-AzureRmADApplication -DisplayName $ApplicationName -IdentifierUris $AzureDevOpsProjectUrl -Password $appPwd 
}
else
{
    Write-Output "AD App Registration '$ApplicationName' already exists"
}

$sp = Get-AzureRmADServicePrincipal | Where-Object { $_.DisplayName -eq $ApplicationName } | Select-Object -First 1
if ($sp -eq $null)
{
    Write-Output "Creating AD ServicePrincipal for '$ApplicationName'"
   
    $sp = New-AzureRmADServicePrincipal -ApplicationId $app.ApplicationId -Password $appPwd
    Write-Output "Waiting for AD ServicePrincipal '$ApplicationName' to be ready..."
    Sleep -Seconds 20
}
else
{
    Write-Output "AD ServicePrincipal for '$ApplicationName' already exists"
}



$c = Get-AzureRmContext
$subscriptionId = $c.Subscription.Id

Add-RoleDefinition -servicePrincipalName $sp.ApplicationId -roleDefinitionName "Contributor" -scope "/subscriptions/$subscriptionId"
#Add-RoleDefinition -servicePrincipalName $sp.ApplicationId -roleDefinitionName "User Access Administrator" -scope "/subscriptions/$subscriptionId"


$subscriptionName = $c.Subscription.Name
$tenantId = $c.Tenant.Id
$id = [System.Guid]::NewGuid().ToString("N")
$servicePrincipalId = $sp.ApplicationId

$encodedAzureDevOpsPatToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$AzureDevOpsPatToken"))

$requestHeaders = @{
    Authorization = "Basic $encodedAzureDevOpsPatToken"
}

#$requestBody = "{`"id`":`"$id`",`"description`":`"`",`"administratorsGroup`":null,`"authorization`":{`"parameters`":{`"tenantid`":`"$tenantId`",`"serviceprincipalid`":`"$id`",`"authenticationType`":`"spnKey`",`"serviceprincipalkey`":`"$ApplicationPassword`"},`"scheme`":`"ServicePrincipal`"},`"createdBy`":null,`"data`":{`"subscriptionId`":`"$subscriptionId`",`"subscriptionName`":`"$subscriptionName`",`"environment`":`"AzureCloud`",`"scopeLevel`":`"Subscription`",`"creationMode`":`"Manual`",`"azureSpnRoleAssignmentId`":`"`",`"azureSpnPermissions`":`"`",`"spnObjectId`":`"`",`"appObjectId`":`"`"},`"name`":`"$AzureDevOpsServiceConnectionName`",`"type`":`"azurerm`",`"url`":`"https://management.azure.com/`",`"readersGroup`":null,`"groupScopeId`":null,`"isReady`":false,`"operationStatus`":null}"
#$requestBody = "{`"id`":`"$id`",`"authorization`":{`"parameters`":{`"tenantid`":`"$tenantId`",`"serviceprincipalid`":`"$servicePrincipalId`",`"authenticationType`":`"spnKey`",`"serviceprincipalkey`":`"$ApplicationPassword`"},`"scheme`":`"ServicePrincipal`"},`"data`":{`"subscriptionId`":`"$subscriptionId`",`"subscriptionName`":`"$subscriptionName`",`"environment`":`"AzureCloud`",`"scopeLevel`":`"Subscription`",`"creationMode`":`"Manual`"},`"name`":`"$AzureDevOpsServiceConnectionName`",`"type`":`"azurerm`",`"url`":`"https://management.azure.com/`"}"

$requestBody = "{`"authorization`":{`"parameters`":{`"tenantid`":`"$tenantId`",`"serviceprincipalid`":`"$servicePrincipalId`",`"authenticationType`":`"spnKey`",`"serviceprincipalkey`":`"$ApplicationPassword`"},`"scheme`":`"ServicePrincipal`"},`"data`":{`"subscriptionId`":`"$subscriptionId`",`"subscriptionName`":`"$subscriptionName`",`"environment`":`"AzureCloud`",`"scopeLevel`":`"Subscription`",`"creationMode`":`"Manual`"},`"name`":`"$AzureDevOpsServiceConnectionName`",`"type`":`"azurerm`",`"url`":`"https://management.azure.com/`"}"


#$requestBody

$requestUrl = "$AzureDevOpsProjectUrl/_apis/serviceendpoint/endpoints?api-version=5.0-preview.2"
#$requestUrl


$response = Invoke-RestMethod -Uri $requestUrl -Method Get -Headers @{Authorization=("Basic {0}" -f $encodedAzureDevOpsPatToken)} -UseBasicParsing
#$response

$endpoint = $response.value | ?{$_.name -eq $AzureDevOpsServiceConnectionName } | Select-Object -First 1
if ($endpoint -eq $null)
{
    Write-Output "Creating service endpoint '$AzureDevOpsServiceConnectionName' in azure devops '$AzureDevOpsProjectUrl'"


    $response = Invoke-RestMethod -Uri $requestUrl -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $encodedAzureDevOpsPatToken)} -Body $requestBody -UseBasicParsing
    #$response

    $response = Invoke-RestMethod -Uri $requestUrl -Method Get -Headers @{Authorization=("Basic {0}" -f $encodedAzureDevOpsPatToken)} -UseBasicParsing
    $endpoint = $response.value | ?{$_.name -eq $AzureDevOpsServiceConnectionName } | Select-Object -First 1
    if ($endpoint -eq $null)
    {
        Write-Error "Creation of service endpoint '$AzureDevOpsServiceConnectionName' in azure devops '$AzureDevOpsProjectUrl' not successful"
    }
}
else
{
    Write-Output "Service endpoint '$AzureDevOpsServiceConnectionName' already exists in azure devops '$AzureDevOpsProjectUrl'"
}


Add-RoleDefinition -servicePrincipalName $sp.ApplicationId -servicePrincipalId $sp.Id -roleDefinitionName Contributor -scope "/subscriptions/$subscriptionId"




