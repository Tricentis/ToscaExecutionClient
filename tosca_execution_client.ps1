#Requires -Version 3.0

#####################################################################################
#
# Tosca Execution Client for PowerShell
# Triggers Tosca TestEvents via Tosca Server Execution API
#
#####################################################################################

######################################################################
# Global parameters/variables
######################################################################

param(
    # Mandatory parameters
    [string]$toscaServerUrl,
    [string]$executionEnvironment = "Dex",
    [string]$projectName,
    [string]$events,
    [string]$eventsConfigFilePath,
    
    #Optional parameters
    [string]$clientId,
    [string]$clientSecret,
    [int]$clientTimeout = 36000,
    [string]$creator = "ToscaExecutionClient",
    [Alias("d")]
    [switch]$debug,
    [Alias("h")]
    [switch]$help,
    [switch]$enqueueOnly,
    [string]$executionId = "",
    [string]$importResults = "true",
    [switch]$fetchPartialResults,
    [switch]$fetchResultsOnly,
    [string]$logFolderPath = "logs",
    [int]$pollingInterval = 60,
    [int]$requestTimeout = 180,
    [string]$resultsFileName = "",
    [string]$resultsFolderPath = "results",
    [Alias("s")]
    [switch]$silent
)

[bool]$validationFailed = $true

# Variables for authentication
[string]$accessToken=""
[int]$tokenExpirationDate = 0
[bool]$authenticationEnabled = $false

# Variables for execution
[string]$executionStatus=""
[string]$executionResults=""

# Define logFileName
$logFileName = "$(Get-Date -Format "yyyyMMddssfff")_ToscaExecutionClient.txt"

######################################################################
# Functions
######################################################################

#######################################
# Prints usage information for this script.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Nothing
#######################################
function displayHelp() {
    Write-Output "`nUsage: $($PSCommandPath) -toscaServerUrl <toscaServerUrl> -projectName <projectName> -events <events> [Options]`n"

    Write-Output "Mandatory parameters:"
    Write-Output " toscaServerUrl            URL of Tosca Server, e.g. https://myserver.tricentis.com or http://111.111.111.0:81."
    Write-Output " projectName               Project root name of the Tosca project where the event is located."
    Write-Output " events                    Stringified JSON array containing the names or uniqueIds of the events that you want to execute. If you want to overwrite TCPs or Agent Characteristics for a specific event, use the ""eventsConfigFilePath"" parameter instead."
    Write-Output " eventsConfigFilePath      Path to the JSON file that contains the event configuration, including TCPs and Agent Characteristics. If you use this parameter, you don't need to use the ""events"" parameter."

    Write-Output "`nOptions:"
    Write-Output " clientId                  Client ID of the Tricentis User Administration access token. This parameter is mandatory if you use HTTPS."
    Write-Output " clientSecret              Client secret of the Tricentis User Administration access token. This parameter is mandatory if you use HTTPS."
    Write-Output " clientTimeout             Time in seconds that the ToscaExecutionClient waits for the execution to finish before it aborts (default: 36000)."
    Write-Output " creator                   Name of who triggered the execution. The DEX Monitor UI displays this name (default: ToscaExecutionClient)."
    Write-Output " debug                     Activates debug mode."
    Write-Output " enqueueOnly               Only enqueue the execution. ToscaExecutionClient doesn't fetch results."
    Write-Output " executionEnvironment      Environment in which you want to execute the event. Possible values are ""Dex"" or ""ElasticExecutionGrid"" (default: ""Dex"")."
    Write-Output " executionId               ID of the execution for which you want to get results. You only need this parameter if you choose ""fetchResultsOnly""."
    Write-Output " fetchPartialResults       Fetch partial execution results."
    Write-Output " fetchResultsOnly          Get the results of an currently running or already finished execution."
    Write-Output " help                      Get usage information for the ToscaExecutionClient."
    Write-Output " importResults             Import results into your Tosca project. Possible values are ""true"" and ""false""."
    Write-Output " logFolderPath             Path to the folder where the ToscaExecutionClient saves log files (default: logs)."
    Write-Output " pollingInterval           Interval in seconds in which the ToscaExecutionClient requests results from the DEX Server (default: 60)."
    Write-Output " resultsFileName           Name of the file in which ToscaExecutionClient saves execution results (default: ""<executionId>_results.xml"")."
    Write-Output " requestTimeout            Time in seconds that the ToscaExecutionClient waits for a response from AOS (default: 180)."
    Write-Output " resultsFolderPath         Path to the folder where ToscaExecutionClient saves execution results (default: results)."
    Write-Output " silent                    Deactivate logging to stdout (terminal)."
}

#######################################
# Prints log message
# Globals:
#   logFolderPath
# Arguments:
#   logLevel
#   logMessage
# Returns:
#   Nothing
#######################################
function log([string]$logLevel, [string]$logMessage) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss z"
    $message = [string]::Format("{0} [{1}] {2}", $ts, $logLevel, $logMessage)

    if( -not $silent ) {

        if( $logLevel -eq "ERR" ) {
            Write-Output $message | highlightInRed
        } else {
            Write-Output $message
        }
    }

    $logFilePath = "$logFolderPath\$logFileName"

    try {        
        $message | Out-File $logFilePath -Append       

    } catch {
        Write-Output "$ts [ERR] ToscaExecutionClient failed to write the log message in ""$path""."
        Write-Output "$ts [ERR] $_"
        Write-Output "$ts [INF] Stopping ToscaExecutionClient..."
        exit 1
    }
}

#######################################
# Creates directory if it does not exist
# Globals:
#   None
# Arguments:
#   path
#   suppressLog
# Returns:
#   Nothing
#######################################
function createDirectory([string]$path, [bool]$suppressLog=$false) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss z"

    try {
        if ( -not (Test-Path $path) ) {

            if ( $suppressLog -eq $true ) {
                Write-Output "$ts [INF] Directory ""$path"" does not exist. Try to create directory ""$path""..."
            } else {
                log "INF" "Directory ""$path"" does not exist. Try to create directory ""$path""..."
            }

            New-Item -Path "$path" -ItemType Directory | out-null
            log "INF" "Successfully created directory ""$path""."
        }
    } catch {
        if ( $suppressLog -eq $true ) {
            Write-Output "$ts [ERR] ToscaExecutionClient failed to create directory ""$path""."
            Write-Output "$ts [ERR] $_"
            Write-Output "$ts [INF] Stopping ToscaExecutionClient..."
        } else {
            log "ERR" "ToscaExecutionClient failed to create directory ""$path""."
            log "ERR" "$_"
            log "INF" "Stopping ToscaExecutionClient..."
        }

        exit 1
    }
}

#######################################
# Returns absolute path
# Globals:
#   None
# Arguments:
#   path
#   suppressLog
# Returns:
#   Resolved path to directory
#######################################
function getAbsolutePath([string]$path, [bool]$suppressLog=$false) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss z"

    try {
        $isAbsolutePath = [System.IO.Path]::IsPathRooted($path)

        if ( $isAbsolutePath -eq $false ) {
            $path = [System.IO.Path]::Combine($PSScriptRoot, $path);
        }
        
    } catch {
        if ( $suppressLog -eq $true ) {
            Write-Output "$ts [ERR] ToscaExecutionClient failed to resolve path ""$path""."
            Write-Output "$ts [ERR] $_"
            Write-Output "$ts [INF] Stopping ToscaExecutionClient..."
        } else {
            log "ERR" "ToscaExecutionClient failed to resolve path ""$path""."
            log "ERR" "$_"
            log "INF" "Stopping ToscaExecutionClient..."
        }

        exit 1
    }

    return $path
}

#######################################
# Changes font color of terminal output to red
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Nothing
#######################################
function highlightInRed {
    process { Write-Host $_ -ForegroundColor Red }
}

#######################################
# Writes execution results
# Globals:
#   executionId
#   executionResults
#   resultsFolderPath
# Arguments:
#   writePartialResults
# Returns:
#   Nothing
#######################################
function writeResults([bool]$writePartialResults = $false) {
    $folderPath = $resultsFolderPath
    $currentDate = Get-Date -Format "yyyyMMdd_HHmmss"

    if( -not ([String]::IsNullOrEmpty($executionResults)) ) {

        if ( $writePartialResults -eq $true ) {
            $folderPath = "$folderPath\${executionId}_partial"
            createDirectory $folderPath

            $resultsFilePath= "$folderPath\${currentDate}_results.xml"

            log "INF" "Writing partial results for execution with id ""$executionId"" to file ""$resultsFilePath""..."
        } else {
            if ( -not ([String]::IsNullOrEmpty($resultsFileName)) ) {
                $resultsFilePath="$folderPath\${resultsFileName}"
            } else {
                $resultsFilePath="${folderPath}\${executionId}_results.xml"
            }

            log "INF" "Writing results for execution with id ""$executionId"" to file ""$resultsFilePath""..."
        }

        try {
            $Utf8Encoding = New-Object System.Text.UTF8Encoding $False
            [System.IO.File]::WriteAllLines($resultsFilePath, $executionResults, $Utf8Encoding)
            log "INF" "Finished writing execution results to file ""$resultsFilePath""."

        } catch {
            log "ERR" "ToscaExecutionClient failed to write results in directory ""$folderPath""."
            log "ERR" "$_"
            log "INF" "Stopping ToscaExecutionClient..."
            exit 1
        }
    }
}

#######################################
# Generates header for API requests
# Globals:
#   accessToken
# Arguments:
#   None
# Returns:
#   Nothing
#######################################
function generateHeader() {
    $header = @{"X-Tricentis" = "OK" }

    if( $accessToken ) {
        $header.Authorization = "Bearer $accessToken"
    }

    return $header
}

#######################################
# Returns unix timestamp
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Timestamp
#######################################
function getTimestamp() {
    return [DateTimeOffset]::Now.ToUnixTimeSeconds()
}

#######################################
# Fetches access token from Tosca Server
# Globals:
#   toscaServerUrl
#   requestTimeout
#   clientId
#   clientSecret
# Arguments:
#   None
# Returns:
#   Nothing
#######################################
function fetchOrRefreshAccessToken() {
    $now = getTimestamp

    if ( $authenticationEnabled -eq $true -and $now -ge $script:tokenExpirationDate) {
        log "INF" "Fetching access token with provided credentials..."

        $accessTokenRequest = @{
            grant_type = "client_credentials"
            client_id = $clientId
            client_secret = $clientSecret
        }

        $contentType = "application/x-www-form-urlencoded"
    
        try {
            $accessTokenResponse = Invoke-WebRequest     `
                -Uri "$toscaServerUrl/tua/connect/token" `
                -body $accessTokenRequest                `
                -ContentType $contentType                `
                -Method Post                             `
                -TimeoutSec $requestTimeout              `
                -UseBasicParsing                         `

            log "INF" "Sucessfully fetched access token"

            $accessTokenResponseAsJson = ConvertFrom-Json($accessTokenResponse.Content)
            $expiresIn = $accessTokenResponseAsJson.expires_in
            
            $script:accessToken = $accessTokenResponseAsJson.access_token
            $script:tokenExpirationDate = $now + ($expiresIn * 0.8)
        }
        catch {
            log "ERR" "ToscaExecutionClient failed to fetch the access token."
            log "ERR" $_
        }
    }
}

#######################################
# Enqueues execution request
# Globals:
#   toscaServerUrl
#   requestTimeout
#   accessToken
#   executionEnvironment
#   projectName
#   events
#   importResults
#   creator
# Arguments:
#   None
# Returns:
#   Nothing
#######################################
function enqueueExecution() {
    $header = generateHeader
    $body = "{""ProjectName"":""$projectName"",""ExecutionEnvironment"":""$executionEnvironment"",""Events"":$events,""ImportResult"":$($importResults.ToLower()),""Creator"":""$creator""}"
    $contentType = "application/json"

    log "INF" "Enqueue execution with provided parameters..."

    if ( $debug -eq $true ) {
        log "DBG" "Enqueue parameters:"
        log "DBG" "$body"
        log "DBG" "$header"
    }

    fetchOrRefreshAccessToken

    try {
        $enqueueResponse = Invoke-WebRequest                                      `
            -Uri "$toscaServerUrl/automationobjectservice/api/execution/enqueue"  `
            -body $body                                                           `
            -Headers $header                                                      `
            -ContentType $contentType                                             `
            -Method Post                                                          `
            -TimeoutSec $requestTimeout                                           `
            -UseBasicParsing                                                      `

        $status = $enqueueResponse.StatusCode
        $content = $enqueueResponse.Content

        if ( $debug -eq $true ) {
            log "DBG" "Status code of the response = HTTP code $status."
            log "DBG" "Body of the response = $content"
        }
        
        $executionResponseAsJson = ConvertFrom-Json($content)
        $script:executionId = $executionResponseAsJson.ExecutionId

        if ( [string]::IsNullOrEmpty($executionId) ) {
            log "ERR" "Enqueue response does not include executionId property."
            log "ERR" "Status code of the response = HTTP code $status."
            log "ERR" "Body of the response = $content"
            exit 1
        } else {
            log "INF" "Successfully enqueued execution with id ""$executionId""."
        }
        
    }
    catch {
        log "ERR" "ToscaExecutionClient failed to enqueue the execution."
        log "ERR" $_
        exit 1
    }
}

#######################################
# Fetches execution status
# Globals:
#   toscaServerUrl
#   requestTimeout
#   accessToken
#   executionId
# Arguments:
#   None
# Returns:
#   Nothing
#######################################
function fetchExecutionStatus () {
    $header = generateHeader

    log "INF" "Fetching status for execution with id ""$executionId""..."

    fetchOrRefreshAccessToken

    try {
        $statusResponse = Invoke-WebRequest                                                   `
            -Uri "$toscaServerUrl/automationobjectservice/api/execution/$executionId/status"  `
            -Headers $header                                                                  `
            -Method Get                                                                       `
            -TimeoutSec $requestTimeout                                                       `
            -UseBasicParsing                                                                  `

        $status = $statusResponse.StatusCode
        $content = $statusResponse.Content

        if ( $debug -eq $true ) {
            log "DBG" "Status code of the response = HTTP code $status."
            log "DBG" "Body of the response = $content"
        }
 
        $statusResponseAsJson = ConvertFrom-Json($content)
        $script:executionStatus = $statusResponseAsJson.status

        if ( [string]::IsNullOrEmpty($executionStatus) ) {
            log "ERR" "Status response does not include status property."
            log "ERR" "Status code of the response = HTTP code $status."
            log "ERR" "Body of the response = $content"
        }
    }
    catch {
        log "ERR" "ToscaExecutionClient failed to fetch the status of execution with id ""$executionId""."
        log "ERR" $_
    }
}

#######################################
# Fetches execution results
# Globals:
#   toscaServerUrl
#   requestTimeout
#   accessToken
#   executionId
# Arguments:
#   fetchPartialResults
# Returns:
#   Nothing
#######################################
function fetchExecutionResults ([bool]$fetchPartialResults = $false) {
    $queryParameters = ""
    $header = generateHeader

    log "INF" "Fetching results for execution with id ""$executionId""..."

    if ( $fetchPartialResults -eq $true) {
        $queryParameters="?partial=true"
    }

    try {
        $resultsResponse = Invoke-WebRequest                                                                   `
            -Uri "$toscaServerUrl/automationobjectservice/api/execution/$executionId/results$queryParameters"  `
            -Headers $header                                                                                   `
            -Method Get                                                                                        `
            -TimeoutSec $requestTimeout                                                                        `
            -UseBasicParsing                                                                                   `

        $status = $resultsResponse.StatusCode
        $content = $resultsResponse.Content

        if ( $debug -eq $true ) {
            log "DBG" "Status code of the response = HTTP code $status."
            log "DBG" "Body of the response = $content"
        }
        
        # Reset execution results variable
        $script:executionResults = ""

        # All results available
        if ( $status -eq 200 ) {
            log "INF" "Sucessfully fetched results for execution with id ""$executionId""."
            $script:executionResults=$content
        }
        # Not all results are available (E.g. cancelled events, configuration errors) 
        elseif ( $status -eq 206 ) {
            log "WRN" "Not all execution results have been returned for execution with id ""$executionId"". Check AOS, DEX Server and DEX agent logs."
            $script:executionResults="$responseBody"
        }
        # Handle non existing results when fetchPartialResults option is activated
        elseif ( $fetchPartialResults -eq $true ) {
            log "INF" "No results available yet for execution with id ""$executionId""."
        }
        else {
            log "ERR" "No results available for execution with id ""$executionId"". Check AOS, DEX Server and DEX agent logs."
        }
    }
    catch {
        log "ERR" "ToscaExecutionClient failed to fetch the status of execution with id ""$executionId""."
        log "ERR" $_
        exit 1
    }
}

######################################################################
# Main
######################################################################

# Print help and exit if help switch is enabled
if ( $help -eq $true ) {
    displayHelp
    exit 0 
}

# Create directories for log and results folders 
$logFolderPath = getAbsolutePath $logFolderPath $true
createDirectory $logFolderPath $true

$resultsFolderPath = getAbsolutePath $resultsFolderPath
createDirectory $resultsFolderPath

if ( [String]::IsNullOrEmpty($toscaServerUrl) ) {
    log "ERR" "Mandatory parameter ""toscaServerUrl"" is not set"
} elseif ( [String]::IsNullOrEmpty($projectName) -and $fetchResultsOnly -eq $false ) {
    log "ERR" "Mandatory parameter ""projectName"" is not set"
} elseif ( [String]::IsNullOrEmpty($events) -and [String]::IsNullOrEmpty($eventsConfigFilePath) -and $fetchResultsOnly -eq $false ) {
    log "ERR" "Event configuration is missing. Define either ""events"" or ""eventsConfigFilePath""."
} elseif ( [String]::IsNullOrEmpty($projectName) ) {
    log "ERR" "Mandatory parameter ""projectName"" is not set"
} else {
    $validationFailed = $false
}

# Print help and exit if validation failed
if ( $validationFailed -eq $true ) {
    displayHelp
    exit 1
}

log "INF" "Starting ToscaExecutionClient..."

# Use value from events config file
if( -not ([String]::IsNullOrEmpty($eventsConfigFilePath)) ) {
    log "INF" "Parameter ""eventsConfigFilePath"" defined. Using configuration from file."
    $script:events = Get-Content -Path $eventsConfigFilePath -Raw
}

#Get access token if credentials are provided
if ( -not ([String]::IsNullOrEmpty($clientId)) -and -not ([String]::IsNullOrEmpty($clientSecret)) ) {
    log "INF" "ClientId and clientSecret are provided. Authentication will be enabled. Fetch access token with provided credentials..."    
    $authenticationEnabled = $true
    fetchOrRefreshAccessToken
} else {
    log "WRN" "ClientId or clientSecret is not provided. Continue without authentication..."
}

# Skip enqueue call if fetchResultsOnlyOption is given
if ( $fetchResultsOnly -eq $true ) {
    log "INF" "Option fetchResultsOnly is activated."
} else {
    # Enqueue execution
    enqueueExecution

    # Skip fetching of execution results when enqueueOnlyOption is given 
    if ( $enqueueOnly -eq $true ) {
        log "INF" "Option enqueueOnly is activated."
        log "INF" "Enqueing execution has sucessfully finished" 
        log "INF" "Stopping ToscaExecutionClient..."
        exit 0
    }
}

# Handle missing execution id
if ( ([String]::IsNullOrEmpty($executionId)) ) {
    log "ERR" "ExecutionId is missing or empty." 
    log "INF" "Stopping ToscaExecutionClient..."
    exit 1
}

# Start status polling
log "INF" "Starting execution status polling with an interval of $pollingInterval seconds..."
$executionTimeout = $(getTimestamp) + $clientTimeout
$keepPolling = $true;
while($keepPolling -eq $true) {
    fetchExecutionStatus
    log "INF" "Status of execution with id ""${executionId}"": ""${executionStatus}"""

    $keepPolling = ($(getTimestamp) -le $executionTimeout) -and -not ($executionStatus -like "*Completed*") -and -not ($executionStatus -eq "Error") -and -not ($executionStatus -eq "Cancelled");

    if($keepPolling -eq $false){
        break;
    }

    if ( $fetchPartialResults -eq $true ) {
        # Fetch partial results for the execution
        log "INF" "Fetching partial results ..."
        
        # Fetch partial results
        fetchExecutionResults $true
        
        # Write partial results
        writeResults $true
    }
    
    log "INF" "Starting next polling cycle in $pollingInterval seconds..."
    Start-Sleep -Seconds $pollingInterval
}

# Check for execution status after results polling

if ( ($executionStatus -like "*Completed*") )  
{
    log "INF" "Execution with id ""${executionId}"" finished."

    # Fetch results when execution is finished
    fetchExecutionResults $false
    
    # Write execution results
    writeResults $false
    log "INF" "Stopping ToscaExecutionClient..."
    exit 0
}
elseif ( ($executionStatus -eq "Error") -or ($executionStatus -eq "Cancelled")) {
    log "ERR" "Execution with id ""${executionId}"" Error or Cancelled!"

    # Fetch results when execution is finished
    fetchExecutionResults $false
    
    # Write execution results
    writeResults $false
    log "INF" "Stopping ToscaExecutionClient..."
    exit 1


} else {
    log "ERR" "Execution exceeded clientTimeout of $clientTimeout seconds. Stopping ToscaExecutionClient..."
    exit 1
}
