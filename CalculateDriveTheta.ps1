<#
    This powershell script uses the Google Maps
    Directions API to find the current drive times
    from my home to my workplace and from my
    my workplace to my house.

    Secrets:
    1. My account's Google Maps API Key
    2. My home address
    3. My work address

    Workflow:
    1. Authenticate to Azure.
    2. Retrieve my Google Maps API key, home address,
    and work address from an Azure Key Vault.
    3. Convert my addresses of interest into PlaceIds
    for use with the API.
    4. Query the API for the drive duration from
    home to work and from work to home.
    5. Prettify and print the results.
#>

<#
    Authenticating to Azure
    1. Create an Azure Active Directory App Registration
    2. Create an Azure Key Vault
    3. Create a Certificate in the Key Vault
    4. Download the .cer file and upload it to the App Registration
    5. Download the .pfx private key and install it on your machine.
    6. Create a JSON object in SPInfo.json as follows:
    {
        "Name": "SampleApp",
        "TenantId": "<Sample AAD Tenant Guid>",
        "ApplicationId": "<Service Principal App Id>",
        "ObjectId": "<Sample Service Principal Object Id>",
        "AzureKeyVaultName": "<Name of the Azure Key Vault>"
        "CertificateThumbprint": "<Thumbprint from the Certificate you created>",
    }
#>

# Use SPInfo.json to connect to Azure.
$SP = Get-Content -Path ".\SPInfo.json" | ConvertFrom-Json
Connect-AzAccount `
    -ServicePrincipal `
    -Tenant $SP.TenantId `
    -CertificateThumbprint $SP.CertificateThumbprint `
    -ApplicationId $SP.ApplicationId `
    | Out-Null

# Retrieve each secret from Azure Key Vault
$MapsApiKey     = Get-AzKeyVaultSecret -VaultName $SP.AzureKeyVaultName -AsPlainText -Name "DirectionsApiKey"
$HomeAddress    = Get-AzKeyVaultSecret -VaultName $SP.AzureKeyVaultName -AsPlainText -Name "HomeAddress"
$WorkAddress    = Get-AzKeyVaultSecret -VaultName $SP.AzureKeyVaultName -AsPlainText -Name "WorkAddress"

<#
    This function uses a human-readable
    address to query the Places API and
    return a Place Id.
#>
function Get-PlaceId {
    param (
        $Location,
        $Key
    )
    $FormattedLocation = $Location.Replace(' ', '%20')
    $Query = "https://maps.googleapis.com/maps/api/place/textsearch/json?query=${FormattedLocation}&key=${Key}"
    $Result = Invoke-WebRequest -Uri $Query | ConvertFrom-Json
    return $Result.results.place_id
}


<#
    This function performs the
    actual action of querying the
    Directions API.
#>
function Get-DirectionsApiResult {
    param (
        $Origin,
        $Destination,
        $Key
    )
    $Query = "https://maps.googleapis.com/maps/api/directions/json?origin=place_id%3A${Origin}&destination=place_id%3A${Destination}&key=${Key}"
    return Invoke-WebRequest -Uri $Query | ConvertFrom-Json
}

# Convert human-readable addresses into PlaceIds
$HomePlaceId = Get-PlaceId -Location $HomeAddress -Key $MapsApiKey
$WorkPlaceId = Get-PlaceId -Location $WorkAddress -Key $MapsApiKey

# Use the PlaceIds to get the JSON result for each trip
$HomeToWorkResult = Get-DirectionsApiResult -Origin $HomePlaceId -Destination $WorkPlaceId -Key $MapsApiKey
$WorkToHomeResult = Get-DirectionsApiResult -Origin $WorkPlaceId -Destination $HomePlaceId -Key $MapsApiKey

# Extract the time in seconds each trip takes
$HomeToWorkInSeconds = $HomeToWorkResult.routes.legs.duration.value
$WorkToHomeInSeconds = $WorkToHomeResult.routes.legs.duration.value

# Prettify and print the result.
$FormattedHomeToWork = New-TimeSpan -Seconds $HomeToWorkInSeconds
$FormattedWorkToHome = New-TimeSpan -Seconds $WorkToHomeInSeconds

Write-Output "`nThe drive from home to work is currently taking $($FormattedHomeToWork.Minutes) minutes and $($FormattedHomeToWork.Seconds) seconds."

Write-Output "`nThe drive from work to home is currently taking $($FormattedWorkToHome.Minutes) minutes and $($FormattedWorkToHome.Seconds) seconds."

Write-Output "`n"