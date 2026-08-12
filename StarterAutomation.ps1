# Accept the webhook data as a parameter
param (
    [Parameter(Mandatory = $true)]
    [object]$WebhookData
)

# Script Configuration
# Define the script name placeholder and log directory for all logging operations
$Script:ScriptName = 'StarterAutomation'
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

# Parse the JSON request body to extract user details
$RequestBody = $WebhookData.RequestBody | ConvertFrom-Json

# Output the received webhook data for debugging purposes
New-LogMessage -Level 'INFO' -Message "Requestor Email: $($RequestBody.RequestorEmail)"
New-LogMessage -Level 'INFO' -Message "First Name: $($RequestBody.FirstName)"
New-LogMessage -Level 'INFO' -Message "Last Name: $($RequestBody.LastName)"
New-LogMessage -Level 'INFO' -Message "Job Title: $($RequestBody.JobTitle)"
New-LogMessage -Level 'INFO' -Message "Department: $($RequestBody.Department)"
if ($RequestBody.ManagerEmail) {
    New-LogMessage -Level 'INFO' -Message "Manager Email: $($RequestBody.ManagerEmail)"
}
else {
    New-LogMessage -Level 'INFO' -Message "Manager Email: N/A"
}

# Generate and store UserPrincipalName and MailNickname for later use
$MailNickname = ($RequestBody.FirstName + "." + $RequestBody.LastName).ToLower()
$UserPrincipalName = ($MailNickname + '#@CLIENTDOMAIN.COM#').ToLower()
New-LogMessage -Level 'INFO' -Message "UserPrincipalName: $UserPrincipalName"
New-LogMessage -Level 'INFO' -Message "MailNickname: $MailNickname"

# Generate a random password using the external API
try {
    $RandomPassword = Invoke-RestMethod "https://wsprodautouksouth.azurewebsites.net/api/PasswordGenerator?code=LDy-XQyLufG6JVlZltAqngJ87MUUZym6YejJb4BNSAZ3AzFuND4o7g=="
    if (-not $RandomPassword) {
        throw 'Received empty password from the API.'
    }
}
catch {
    New-LogMessage -Level 'ERROR' -Message $_.Exception.Message
    exit 1
}

# Connect to Microsoft Graph using the identity of the Azure Function
try {
    $Connection = Connect-MgGraph -Identity
    New-LogMessage -Level 'SUCCESS' -Message "Successfully connected to Microsoft Graph"
    if (-not $Connection) {
        throw 'Failed to establish a connection to Microsoft Graph.'
    }
}
catch {
    New-LogMessage -Level 'ERROR' -Message $_.Exception.Message
    exit 1
}

# Stage the new user with the specified properties and password profile
$UserParams = @{
    AccountEnabled    = $true
    GivenName         = $RequestBody.FirstName
    Surname           = $RequestBody.LastName
    DisplayName       = ($RequestBody.FirstName + ' ' + $RequestBody.LastName)
    MailNickname      = $MailNickname
    UserPrincipalName = $UserPrincipalName
    CompanyName       = '#COMPANY_NAME#'
    PasswordProfile   = @{
        ForceChangePasswordNextSignIn = $true
        Password                      = $RandomPassword
    }
}

# Create the new user in Microsoft Graph
try {
    $NewUser = New-MgUser @UserParams
    New-LogMessage -Level 'SUCCESS' -Message "Successfully created user: $($NewUser.DisplayName)"
}
catch {
    New-LogMessage -Level 'ERROR' -Message "Failed to create user: $($_.Exception.Message)"
    exit 1
}

# Add the new user to the specified licensing group
try {
    New-MgGroupMember -GroupId '#LICENSE_GROUP_ID#' -DirectoryObjectId $NewUser.Id
    New-LogMessage -Level 'SUCCESS' -Message 'Added user to licensing group successfully'
}
catch {
    New-LogMessage -Level 'ERROR' -Message "Failed to add user to licensing group: $($_.Exception.Message)"
}

# Set the users manager if the manager email was provided in the request
if ($RequestBody.managerEmail) {
    try {
        $Manager = Get-MgUser -Filter "mail eq '$($RequestBody.managerEmail)'"
        if ($Manager) {
            Set-MgUserManagerByRef -UserId $NewUser.Id -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($Manager.Id)" }
            New-LogMessage -Level 'SUCCESS' -Message "Assigned manager successfully: $($RequestBody.managerEmail)"
        }
        else {
            New-LogMessage -Level 'WARN' -Message "Manager not found with email: $($RequestBody.managerEmail)"
        }
    }
    catch {
        New-LogMessage -Level 'ERROR' -Message "Failed to assign manager: $($_.Exception.Message)"
    }
}
else {
    New-LogMessage -Level 'INFO' -Message 'No manager email provided, skipping manager assignment'
}

.\EmailConfirmation.ps1 -UserPrincipalName $UserPrincipalName -Password $RandomPassword -RequestorEmail $RequestBody.RequestorEmail -DisplayName ($RequestBody.FirstName + ' ' + $RequestBody.LastName)

New-LogMessage -Level 'END' -Message "Completed $Script:ScriptName execution."
exit 0