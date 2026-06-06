<#
.SYNOPSIS
    Automated SSL Certificate Installation for vCenter using Let's Encrypt (ACME)
.DESCRIPTION
    Request, generate, and install a free 90-day trusted SSL certificate on vCenter Server.
    Uses Let's Encrypt via Posh-ACME for certificate management.
.PARAMETER vCenterURL
    FQDN or IP address of vCenter Server (e.g., vc.example.com)
.PARAMETER CommonName
    Common Name for the certificate (typically the vCenter FQDN)
.PARAMETER EmailContact
    Email address for ACME account and renewal notifications
.PARAMETER vCenterCredential
    PSCredential object for vCenter authentication. If not provided, user will be prompted.
.PARAMETER LogPath
    Directory path for script logs. Defaults to user's Documents folder.
.PARAMETER SkipCertificateValidation
    Switch to skip certificate validation for initial HTTPS connection (useful for self-signed certs)
.PARAMETER MaxRetries
    Maximum number of retry attempts for API calls. Default: 3
.EXAMPLE
    .\Install-vCenterSSL.ps1 -vCenterURL 'vc.example.com' -CommonName 'vc.example.com' -EmailContact 'admin@example.com'
.EXAMPLE
    $cred = Get-Credential
    .\Install-vCenterSSL.ps1 -vCenterURL 'vc.example.com' -CommonName 'vc.example.com' `
        -EmailContact 'admin@example.com' -vCenterCredential $cred -SkipCertificateValidation
.NOTES
    Tested on: vCenter 7.x, vCenter 8.x
    PowerShell: 5.1, 7.x
    Original Author: Nicholas Mangraviti (virtuallywired.io)
    Refactored & Optimized: 2026
    Required Module: Posh-ACME
    License: MIT
.LINK
    https://github.com/rmbolger/Posh-ACME
    https://github.com/alsyundawy/Install-vCenterSSL
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = 'vCenter Server FQDN or IP address')]
    [ValidateNotNullOrEmpty()]
    [string]$vCenterURL,
    
    [Parameter(Mandatory = $true, HelpMessage = 'Certificate Common Name')]
    [ValidateNotNullOrEmpty()]
    [string]$CommonName,
    
    [Parameter(Mandatory = $true, HelpMessage = 'Email address for ACME account')]
    [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
    [string]$EmailContact,
    
    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$vCenterCredential,
    
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$LogPath = [System.IO.Path]::Combine($env:USERPROFILE, 'Documents', 'vCenterSSL_Logs'),
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipCertificateValidation,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3
)

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Script metadata
$ScriptVersion = '2.0'
$ScriptName = Split-Path -Leaf $PSCommandPath
$ScriptPath = Split-Path -Parent $PSCommandPath
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path -Path $LogPath -ChildPath "vCenterSSL_$timestamp.log"

# ACME & Certificate constants
$ACME_SERVER = 'LE_PROD'
$PREFERRED_CHAIN = 'ISRG Root X1'
$ROOT_CA_URL = 'https://letsencrypt.org/certs/isrgrootx1.pem.txt'
$ROOT_CA_HASH = '22B557A27055B33606B6559F37703928D3E4AD79F110B407D04986E1843543D1'
$VCENTER_API_VERSION = '/rest/com/vmware/cis/session'
$VCENTER_CERT_API = '/api/vcenter/certificate-management/vcenter/tls'

# HTTP request defaults
$HTTP_TIMEOUT = 30
$HTTP_RETRY_DELAY = 5

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Initialize-Logging {
    <#
    .SYNOPSIS
        Create log directory and initialize logging
    #>
    try {
        if (-not (Test-Path -Path $LogPath -PathType Container)) {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
        }
        
        # Create log file with header
        Add-Content -Path $LogFile -Value @"
================================================================================
vCenter SSL Certificate Installation Log
Script Version: $ScriptVersion
Execution Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
PowerShell Version: $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)
Target vCenter: $vCenterURL
Target CN: $CommonName
================================================================================
"@ -ErrorAction SilentlyContinue
        
        Write-Information "Logging initialized at: $LogFile"
    }
    catch {
        Write-Warning "Failed to initialize logging: $_"
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Write message to log file and console with timestamp and level
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO',
        
        [Parameter(Mandatory = $false)]
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    }
    catch {
        # Silent fail if log write fails
    }
    
    if (-not $NoConsole) {
        switch ($Level) {
            'INFO'    { Write-Host $logMessage -ForegroundColor Cyan }
            'WARN'    { Write-Host $logMessage -ForegroundColor Yellow }
            'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            'DEBUG'   { Write-Host $logMessage -ForegroundColor Gray }
        }
    }
}

# ============================================================================
# VALIDATION & UTILITY FUNCTIONS
# ============================================================================

function Test-DnsResolution {
    <#
    .SYNOPSIS
        Validate that vCenter URL can be resolved
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname
    )
    
    Write-Log "Validating DNS resolution for: $Hostname" -Level 'INFO'
    
    try {
        $dns = Resolve-DnsName -Name $Hostname -Type A -ErrorAction SilentlyContinue
        if ($dns) {
            Write-Log "DNS resolution successful: $Hostname -> $($dns[0].IPAddress)" -Level 'SUCCESS'
            return $true
        }
        else {
            Write-Log "DNS resolution failed for: $Hostname" -Level 'WARN'
            return $false
        }
    }
    catch {
        Write-Log "DNS resolution error: $_" -Level 'WARN'
        return $false
    }
}

function Test-vCenterConnectivity {
    <#
    .SYNOPSIS
        Test connectivity to vCenter HTTPS endpoint
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$URL
    )
    
    Write-Log "Testing connectivity to: https://$URL" -Level 'INFO'
    
    try {
        $params = @{
            Uri             = "https://$URL"
            Method          = 'Get'
            TimeoutSec      = $HTTP_TIMEOUT
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
        }
        
        if ($SkipCertificateValidation) {
            if ($IsCoreCLR) {
                $params['SkipCertificateCheck'] = $true
            }
            else {
                # For PowerShell 5.1
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            }
        }
        
        $response = Invoke-WebRequest @params
        if ($response.StatusCode -in 200, 400, 401, 403) {
            Write-Log "vCenter connectivity test passed" -Level 'SUCCESS'
            return $true
        }
    }
    catch {
        Write-Log "vCenter connectivity test failed: $_" -Level 'WARN'
        return $false
    }
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Execute command with automatic retry logic
    #>
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = $MaxRetries,
        
        [Parameter(Mandatory = $false)]
        [int]$DelaySeconds = $HTTP_RETRY_DELAY
    )
    
    $attempt = 0
    $lastException = $null
    
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            Write-Log "Attempt $attempt of $MaxAttempts" -Level 'DEBUG'
            return & $ScriptBlock
        }
        catch {
            $lastException = $_
            if ($attempt -lt $MaxAttempts) {
                Write-Log "Attempt $attempt failed: $($_.Exception.Message). Retrying in $DelaySeconds seconds..." -Level 'WARN'
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    
    Write-Log "All retry attempts exhausted. Last error: $($lastException.Exception.Message)" -Level 'ERROR'
    throw $lastException
}

# ============================================================================
# MODULE MANAGEMENT FUNCTIONS
# ============================================================================

function Assert-PoshACMEModule {
    <#
    .SYNOPSIS
        Ensure Posh-ACME module is installed and imported
    #>
    Write-Log "Checking for Posh-ACME module..." -Level 'INFO'
    
    $module = Get-Module -ListAvailable -Name 'Posh-ACME' -ErrorAction SilentlyContinue
    
    if (-not $module) {
        Write-Log "Posh-ACME module not found. Installing..." -Level 'WARN'
        
        try {
            Install-Module -Name 'Posh-ACME' -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
            Write-Log "Posh-ACME installed successfully" -Level 'SUCCESS'
        }
        catch {
            Write-Log "Failed to install Posh-ACME: $_" -Level 'ERROR'
            throw "Posh-ACME installation failed: $_"
        }
    }
    else {
        Write-Log "Posh-ACME module found (Version: $($module.Version))" -Level 'SUCCESS'
    }
    
    # Import module
    try {
        Import-Module -Name 'Posh-ACME' -Force -ErrorAction Stop
        Write-Log "Posh-ACME module imported successfully" -Level 'SUCCESS'
    }
    catch {
        Write-Log "Failed to import Posh-ACME: $_" -Level 'ERROR'
        throw "Posh-ACME import failed: $_"
    }
}

# ============================================================================
# CERTIFICATE FUNCTIONS
# ============================================================================

function Assert-ACMEServer {
    <#
    .SYNOPSIS
        Configure ACME server
    #>
    Write-Log "Configuring ACME server..." -Level 'INFO'
    
    try {
        $server = Get-PAServer -ErrorAction SilentlyContinue
        
        if ($server.name -eq $ACME_SERVER) {
            Write-Log "ACME server already set to: $($server.Name)" -Level 'SUCCESS'
        }
        else {
            Write-Log "Setting ACME server to: $ACME_SERVER" -Level 'INFO'
            Set-PAServer -DirectoryUrl $ACME_SERVER -Force -ErrorAction Stop
            Write-Log "ACME server configured successfully" -Level 'SUCCESS'
        }
    }
    catch {
        Write-Log "Failed to configure ACME server: $_" -Level 'ERROR'
        throw $_
    }
}

function Assert-ACMEAccount {
    <#
    .SYNOPSIS
        Ensure ACME account exists
    #>
    Write-Log "Checking ACME account..." -Level 'INFO'
    
    try {
        $account = Get-PAAccount -ErrorAction SilentlyContinue
        
        if ($account) {
            $contact = $account.Contact -split ':' | Select-Object -Last 1
            Write-Log "ACME account found: $contact" -Level 'SUCCESS'
        }
        else {
            Write-Log "Creating new ACME account with contact: $EmailContact" -Level 'INFO'
            New-PAAccount -Contact $EmailContact -AcceptTOS -Force -Confirm:$false -ErrorAction Stop
            Write-Log "ACME account created successfully" -Level 'SUCCESS'
        }
    }
    catch {
        Write-Log "Failed to manage ACME account: $_" -Level 'ERROR'
        throw $_
    }
}

function Test-ExistingCertificate {
    <#
    .SYNOPSIS
        Check for valid existing certificate
    #>
    Write-Log "Checking for existing certificate for: $CommonName" -Level 'INFO'
    
    try {
        $cert = Get-PACertificate -MainDomain $CommonName -ErrorAction SilentlyContinue
        
        if ($cert -and $cert.AllSANs -contains $CommonName) {
            $now = Get-Date
            if ($now -gt $cert.NotBefore -and $now -lt $cert.NotAfter) {
                Write-Log "Valid certificate found, expires: $($cert.NotAfter)" -Level 'SUCCESS'
                
                $response = Read-Host "Would you like to reuse the existing certificate? (Y/N)"
                if ($response -match '^[Yy]$') {
                    Write-Log "Reusing existing certificate" -Level 'INFO'
                    return $true
                }
            }
        }
        
        return $false
    }
    catch {
        Write-Log "Error checking existing certificate: $_" -Level 'DEBUG'
        return $false
    }
}

function New-ACMECertificate {
    <#
    .SYNOPSIS
        Request new certificate from Let's Encrypt
    #>
    Write-Log "Requesting new certificate for: $CommonName" -Level 'INFO'
    
    try {
        $params = @{
            Domain           = $CommonName
            AcceptTOS        = $true
            PreferredChain   = $PREFERRED_CHAIN
            Force            = $true
            ErrorAction      = 'Stop'
        }
        
        if ($EmailContact) {
            $params['Contact'] = $EmailContact
        }
        
        Invoke-WithRetry {
            New-PACertificate @params
        }
        
        Write-Log "Certificate requested successfully: $CommonName" -Level 'SUCCESS'
    }
    catch {
        Write-Log "Failed to request certificate: $_" -Level 'ERROR'
        throw $_
    }
}

function Get-ValidatedRootCA {
    <#
    .SYNOPSIS
        Download and validate ISRG Root X1 certificate
    #>
    Write-Log "Downloading and validating ROOT CA..." -Level 'INFO'
    
    try {
        $wc = New-Object System.Net.WebClient
        $rootCaContent = Invoke-WithRetry {
            $wc.DownloadString($ROOT_CA_URL)
        }
        
        # Validate hash
        $stream = New-Object System.IO.MemoryStream
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.Write($rootCaContent)
        $writer.Flush()
        $stream.Position = 0
        
        $hash = Get-FileHash -InputStream $stream -Algorithm SHA256
        $stream.Dispose()
        $writer.Dispose()
        
        if ($hash.Hash -eq $ROOT_CA_HASH) {
            Write-Log "ROOT CA signature validated successfully" -Level 'SUCCESS'
            return $rootCaContent
        }
        else {
            throw "ROOT CA hash mismatch. Expected: $ROOT_CA_HASH, Got: $($hash.Hash)"
        }
    }
    catch {
        Write-Log "Failed to validate ROOT CA: $_" -Level 'ERROR'
        throw $_
    }
}

function Format-CertificateContent {
    <#
    .SYNOPSIS
        Format certificate content to PEM standard
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('CERTIFICATE', 'PRIVATE KEY')]
        [string]$Type
    )
    
    Write-Log "Formatting $Type to PEM standard" -Level 'DEBUG'
    
    $cleaned = $Content -replace '\s+', '' `
                        -replace '-----BEGIN[A-Z\s]+-----', "-----BEGIN $Type-----`n" `
                        -replace '-----END[A-Z\s]+-----', "`n-----END $Type-----"
    
    return $cleaned
}

# ============================================================================
# VCENTER AUTHENTICATION & API FUNCTIONS
# ============================================================================

function Get-vCenterSessionToken {
    <#
    .SYNOPSIS
        Authenticate with vCenter and obtain API session token
    #>
    Write-Log "Authenticating with vCenter: $vCenterURL" -Level 'INFO'
    
    if (-not $vCenterCredential) {
        $vCenterCredential = Get-Credential -Message "Enter vCenter credentials" -ErrorAction Stop
    }
    
    try {
        $auth = [System.Convert]::ToBase64String(
            [System.Text.Encoding]::UTF8.GetBytes(
                "$($vCenterCredential.UserName):$($vCenterCredential.GetNetworkCredential().Password)"
            )
        )
        
        $params = @{
            Method          = 'POST'
            Uri             = "https://$vCenterURL$VCENTER_API_VERSION"
            Headers         = @{ 'Authorization' = "Basic $auth" }
            ContentType     = 'application/json'
            TimeoutSec      = $HTTP_TIMEOUT
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
        }
        
        if ($IsCoreCLR -or $SkipCertificateValidation) {
            $params['SkipCertificateCheck'] = $true
        }
        else {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }
        
        $response = Invoke-WithRetry {
            Invoke-WebRequest @params
        }
        
        $token = (ConvertFrom-Json $response.Content).value
        Write-Log "vCenter authentication successful" -Level 'SUCCESS'
        
        return @{ 'vmware-api-session-id' = $token }
    }
    catch {
        Write-Log "vCenter authentication failed: $_" -Level 'ERROR'
        throw "Failed to authenticate with vCenter: $_"
    }
}

function Install-vCenterCertificate {
    <#
    .SYNOPSIS
        Upload and install certificate on vCenter
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SessionHeaders,
        
        [Parameter(Mandatory = $true)]
        [string]$Certificate,
        
        [Parameter(Mandatory = $true)]
        [string]$PrivateKey,
        
        [Parameter(Mandatory = $true)]
        [string]$RootCertificate
    )
    
    Write-Log "Preparing certificate installation on vCenter" -Level 'INFO'
    
    try {
        # Create JSON payload
        $payload = @{
            cert      = $Certificate
            key       = $PrivateKey
            root_cert = $RootCertificate
        } | ConvertTo-Json -Depth 10
        
        Write-Log "Sending certificate to vCenter API" -Level 'DEBUG'
        
        $params = @{
            Method          = 'PUT'
            Uri             = "https://$vCenterURL$VCENTER_CERT_API"
            Headers         = $SessionHeaders
            Body            = $payload
            ContentType     = 'application/json'
            TimeoutSec      = $HTTP_TIMEOUT
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
        }
        
        if ($IsCoreCLR -or $SkipCertificateValidation) {
            $params['SkipCertificateCheck'] = $true
        }
        else {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }
        
        $response = Invoke-WithRetry {
            Invoke-WebRequest @params
        }
        
        if ($response.StatusCode -eq 204) {
            Write-Log "Certificate installed successfully (HTTP 204)" -Level 'SUCCESS'
            Write-Log "vCenter services will restart to apply new certificate" -Level 'INFO'
            return $true
        }
        else {
            throw "Unexpected response code: $($response.StatusCode)"
        }
    }
    catch {
        Write-Log "Failed to install certificate on vCenter: $_" -Level 'ERROR'
        throw $_
    }
}

# ============================================================================
# EXECUTION POLICY & SETUP
# ============================================================================

function Set-ExecutionPolicy {
    <#
    .SYNOPSIS
        Set execution policy for current user
    #>
    Write-Log "Setting execution policy..." -Level 'DEBUG'
    
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
        Write-Log "Execution policy set successfully" -Level 'DEBUG'
    }
    catch {
        Write-Log "Warning: Could not set execution policy: $_" -Level 'WARN'
    }
}

# ============================================================================
# MAIN WORKFLOW
# ============================================================================

function Start-vCenterSSLInstallation {
    <#
    .SYNOPSIS
        Main workflow orchestration
    #>
    
    Write-Log "Starting vCenter SSL Installation Workflow" -Level 'INFO'
    Write-Log "======================================" -Level 'INFO'
    
    try {
        # Pre-flight checks
        Write-Log "=== Phase 1: Pre-Flight Checks ===" -Level 'INFO'
        
        if (-not (Test-DnsResolution -Hostname $vCenterURL)) {
            throw "DNS resolution failed for $vCenterURL"
        }
        
        if (-not (Test-vCenterConnectivity -URL $vCenterURL)) {
            Write-Log "Warning: Could not verify connectivity to vCenter. Proceeding anyway..." -Level 'WARN'
        }
        
        # Module setup
        Write-Log "=== Phase 2: Module Setup ===" -Level 'INFO'
        Set-ExecutionPolicy
        Assert-PoshACMEModule
        
        # ACME configuration
        Write-Log "=== Phase 3: ACME Configuration ===" -Level 'INFO'
        Assert-ACMEServer
        Assert-ACMEAccount
        
        # Certificate management
        Write-Log "=== Phase 4: Certificate Management ===" -Level 'INFO'
        $reuseExisting = Test-ExistingCertificate
        
        if (-not $reuseExisting) {
            New-ACMECertificate
        }
        
        # Root CA validation
        Write-Log "=== Phase 5: Root CA Validation ===" -Level 'INFO'
        $rootCA = Get-ValidatedRootCA
        
        # Load certificate files
        Write-Log "=== Phase 6: Loading Certificate Files ===" -Level 'INFO'
        Write-Log "Reading certificate files from Posh-ACME..." -Level 'INFO'
        
        $certInfo = Get-PACertificate -MainDomain $CommonName -ErrorAction Stop
        
        $fullChain = (Get-Content $certInfo.FullChainFile -Raw) + $rootCA
        $privateKeyContent = Get-Content $certInfo.KeyFile -Raw
        $chainContent = (Get-Content $certInfo.ChainFile -Raw) + $rootCA
        
        # Format certificates
        Write-Log "=== Phase 7: Certificate Formatting ===" -Level 'INFO'
        $cert = Format-CertificateContent -Content $fullChain -Type 'CERTIFICATE'
        $key = Format-CertificateContent -Content $privateKeyContent -Type 'PRIVATE KEY'
        $chain = Format-CertificateContent -Content $chainContent -Type 'CERTIFICATE'
        
        # vCenter authentication and installation
        Write-Log "=== Phase 8: vCenter Certificate Installation ===" -Level 'INFO'
        $sessionHeaders = Get-vCenterSessionToken
        $installResult = Install-vCenterCertificate -SessionHeaders $sessionHeaders `
                                                    -Certificate $cert `
                                                    -PrivateKey $key `
                                                    -RootCertificate $chain
        
        # Summary
        Write-Log "=== Installation Complete ===" -Level 'SUCCESS'
        Write-Log "Certificate for '$CommonName' successfully installed on vCenter" -Level 'SUCCESS'
        Write-Log "Log file saved to: $LogFile" -Level 'INFO'
        
        return @{
            Success   = $true
            Message   = "Certificate installation completed successfully"
            LogFile   = $LogFile
            Timestamp = Get-Date
        }
    }
    catch {
        Write-Log "Fatal error during installation: $_" -Level 'ERROR'
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level 'DEBUG'
        
        return @{
            Success   = $false
            Message   = $_.Exception.Message
            LogFile   = $LogFile
            Timestamp = Get-Date
        }
    }
}

# ============================================================================
# EXECUTION
# ============================================================================

Initialize-Logging
$result = Start-vCenterSSLInstallation

# Return result as object for scriptblock usage
[PSCustomObject]$result
