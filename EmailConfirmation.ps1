# Accept the user details as parameters
param (
    [Parameter(Mandatory = $true)]
    [string]$RequestorEmail,

    [Parameter(Mandatory = $true)]
    [string]$DisplayName,

    [Parameter(Mandatory = $true)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $true)]
    [string]$Password
)

# Script Configuration
# Define the script name placeholder and log directory for all logging operations
$Script:ScriptName = 'EmailConfirmation'
$Script:LogDirectory = 'C:\WestSpring IT\LogFiles'

function New-LogMessage {
    param(
        # The severity level for the log entry (START, INFO, WARN, ERROR, SUCCESS, END)
        # START/END are used for script initialization and completion; ERROR for failures;
        # SUCCESS for completed operations; WARN for warnings; INFO for general information
        [ValidateSet('START', 'INFO', 'WARN', 'ERROR', 'SUCCESS', 'END')]
        [string]$Level = 'INFO',

        # The message text to log and display
        [Parameter(Mandatory)]
        [string]$Message
    )

    # Maximum log file size before rotation is triggered (10 MB)
    $MaxLogSize = 10MB

    # Map each log level to a numeric severity for log parsing and filtering
    # START/END = 0 (informational), INFO = 1, WARN = 2, ERROR = 3 (highest priority)
    $LevelMap = @{
        'START'   = 0
        'INFO'    = 1
        'WARN'    = 2
        'ERROR'   = 3
        'SUCCESS' = 0
        'END'     = 0
    }

    try {
        # Initialize log infrastructure on first function call
        if (-not [bool]($PSBoundParameters.Keys -contains 'CalledInternally')) {
            # Ensure log directory is configured (use default if not already set)
            if (-not $Script:LogDirectory) {
                $Script:LogDirectory = 'C:\WestSpring IT\LogFiles'
            }
            
            # Ensure script name is configured (derive from actual script path if not already set)
            if (-not $Script:ScriptName) {
                $Script:ScriptName = (Get-Item $PSCommandPath).BaseName
            }
            
            # Initialize the log file path on first call
            if (-not $Script:LogFile) {
                New-Item -Path $Script:LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
                $SafeScriptName = $Script:ScriptName -replace '[<>:"/\\|?*]', '_'
                $Script:LogFile = Join-Path $Script:LogDirectory "$SafeScriptName.log"
            }

            # Implement log rotation when file size exceeds threshold
            if ((Test-Path $Script:LogFile) -and (Get-Item $Script:LogFile).Length -gt $MaxLogSize) {
                Move-Item $Script:LogFile "$($Script:LogFile).1" -Force
            }
        }

        # Format the log entry with timestamp, severity level number, level name, and message
        $LogTimeDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $LevelNum = $LevelMap[$Level]
        $PaddedLevel = $Level.PadRight(7)
        $Entry = "[$LogTimeDate][$LevelNum][$PaddedLevel] $Message"

        # Write the formatted entry to the log file with UTF-8 encoding
        Add-Content -Path $Script:LogFile -Value $Entry -Encoding utf8 -ErrorAction Stop

        # Output to console with color-coding for visual emphasis
        switch ($Level) {
            'START' { Write-Host $Entry -ForegroundColor Cyan }
            'END' { Write-Host $Entry -ForegroundColor Cyan }
            'ERROR' { Write-Host $Entry -ForegroundColor Red }
            'SUCCESS' { Write-Host $Entry -ForegroundColor Green }
            'WARN' { Write-Warning $Entry }
            default { Write-Host $Entry }
        }
    }
    catch {
        # If any error occurs during logging, report it and exit gracefully
        Write-Error $($_.Exception.Message)
    }
}

New-LogMessage -Level 'START' -Message "Starting $Script:ScriptName execution."

# Specify OneTimeSecret API credentials
$OneTimeSecretUsername = 'thomassamuel@westspring-it.co.uk'
$OneTimeSecretApiToken = '526l7to6fe4zqqktn05bhnt9t8n6of5eg0kl5e8zibyw6dwgc7'

# Create OneTimeSecret credential object
$SecureToken = ConvertTo-SecureString -String $OneTimeSecretApiToken -AsPlainText -Force
$OneTimeSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $OneTimeSecretUsername, $SecureToken

# Build OneTimeSecret payload
$SecretContent = @"
Username: $UserPrincipalName
Password: $Password
"@

$OneTimeSecretBody = @{
    secret = @{
        kind         = "conceal"
        share_domain = "eu.onetimesecret.com"
        ttl          = 604800
        secret       = $SecretContent
    }
} | ConvertTo-Json -Depth 3

# Send the request to OneTimeSecret API to create a secret
try {
    $OneTimeSecretResponse = Invoke-RestMethod `
        -Uri 'https://eu.onetimesecret.com/api/v2/secret/conceal' `
        -Method Post `
        -Credential $OneTimeSecretCredential `
        -ContentType 'application/json' `
        -Body $OneTimeSecretBody
    New-LogMessage -Level 'SUCCESS' -Message 'Successfully created OneTimeSecret'
}
catch {
    New-LogMessage -Level 'ERROR' -Message "Failed to create OneTimeSecret: $($_.Exception.Message)"
    exit 1
}

# Construct OneTimeSecret URL
$OneTimeSecretIdentifier = $OneTimeSecretResponse.record.secret.identifier
$OneTimeSecretUrl = "https://eu.onetimesecret.com/secret/$OneTimeSecretIdentifier"

# Download email confirmation template from blob storage and prepare
try {
    $EmailBody = Invoke-WebRequest "https://raw.githubusercontent.com/WestSpring-IT/User-Processing/refs/heads/main/EmailConfirmation.html" -UseBasicParsing
    New-LogMessage -Level "SUCCESS" -Message "Downloaded email template successfully"

    $EmailBody = $EmailBody.Content

    $Replacements = @{
        "{{RequestorEmail}}"    = $RequestorEmail
        "{{DisplayName}}"       = $DisplayName
        "{{UserPrincipalName}}" = $UserPrincipalName
        "{{OneTimeSecretURL}}"  = $OneTimeSecretUrl
    }

    foreach ($Placeholder in $Replacements.Keys) {
        $EmailBody = $EmailBody.Replace($Placeholder, $Replacements[$Placeholder])
    }
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to download email template: $($_.Exception.Message)"
    exit 1
}

# Store SMTP credentials securely in Azure Automation variables and retrieve them for email sending
$SmtpCredentials = New-Object System.Management.Automation.PSCredential ($(Get-AutomationVariable -Name "AmazonSESUsername"), $(Get-AutomationVariable -Name "AmazonSESPassword" | ConvertTo-SecureString -AsPlainText))

# Compose the email body with HTML formatting
try {
    $EmailParams = @{
        Subject    = "New User Created: $($DisplayName)"
        Body       = $EmailBody
        To         = $RequestorEmail
        From       = "automations@westspring-it.co.uk"
        BodyAsHtml = $true
        SmtpServer = "email-smtp.eu-west-1.amazonaws.com"
        UseSsl     = $true
        Port       = 587
        Credential = $SmtpCredentials
    }
    New-LogMessage -Level "SUCCESS" -Message "Email parameters configured successfully"
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to configure email parameters: $($_.Exception.Message)"
    exit 1
}

# Send the email notification to the requestor using Amazon SES SMTP
try {
    Send-MailMessage @EmailParams
    New-LogMessage -Level "SUCCESS" -Message "Email sent successfully to $($requestorEmail)"
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to send email: $($_.Exception.Message)"
    exit 1
}

New-LogMessage -Level 'END' -Message "Completed $Script:ScriptName execution."
exit 0