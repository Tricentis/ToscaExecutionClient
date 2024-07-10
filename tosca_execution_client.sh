#!/bin/bash

#####################################################################################
#
# Tosca Execution Client for Bash
# Triggers Tosca TestEvents via Tosca Server Execution API
#
#####################################################################################

######################################################################
# Global parameters/variables
######################################################################

# Default color values for printed error messages
clear="\033[0m"
red="\033[0;31m"

# Default parameter values for enqueue request
executionEnvironment="Dex"
importResults=true
creator="ToscaExecutionClient"

# Default request parameters
requestRetries=5
requestTimeout=180
requestRetryDelay=30
pollingInterval=60
clientTimeout=36000
caCertificateSwitch=""
insecureSwitch=""

# Default logging parameters
logFolderPath="logs"
resultsFolderPath="results"
tmpFilePath="tosca_execution_client_tmp"
silent=false
debug=false

# Variables for authentication
accessToken=""
tokenExpirationDate=0
authenticationEnabled=false

# Variables for execution
executionId=""
executionStatus=""
executionResults=""

validationFailed=true

######################################################################
# Functions
######################################################################

#######################################
# Extracts string values from JSON strings.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   String value for fetched JSON key
#######################################
function get_string_json_key () {
  echo ${1} | grep -o "\"${2}\":\"[^\",}]*" | grep -o "[^\"]*$"
}

#######################################
# Extracts number values from JSON strings.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Number value for fetched JSON key
#######################################
function get_number_json_key () {
  echo ${1} | grep -o "\"${2}\":[^,}]*" | cut -d ":" -f2
}

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
  echo -e "\n Usage: ${0} --toscaServerUrl <toscaServerUrl> --projectName <projectName> --events <events> [Options]\n"
  echo " Mandatory parameters:"
  echo "  --toscaServerUrl        URL of Tosca Server, e.g. https://myserver.tricentis.com or http://111.111.111.0:81."
  echo "  --projectName           Project root name of the Tosca project where the event is located."
  echo "  --events                Stringified JSON array containing the names or uniqueIds of the events that you want to execute. If you want to overwrite TCPs or Agent Characteristics for a specific event, use the \"eventsConfigFilePath\" parameter instead."
  echo "  --eventsConfigFilePath  Path to the JSON file that contains the event configuration, including TCPs and Agent Characteristics. If you use this parameter, you don't need to use the \"events\" parameter."
  echo -e "\n Options:"
  echo "  --caCertificate         Path to the CA certificate (in PEM format) that the ToscaExecutionClient uses for peer certificate validation. This parameter is mandatory if you use HTTPS and don't use the \"insecure\" parameter."
  echo "  --clientId              Client ID of the Tricentis User Administration access token. This parameter is mandatory if you use HTTPS."
  echo "  --clientSecret          Client secret of the Tricentis User Administration access token. This parameter is mandatory if you use HTTPS."
  echo "  --clientTimeout         Time in seconds that the ToscaExecutionClient waits for the execution to finish before it aborts (default: 36000)."
  echo "  --creator               Name of who triggered the execution. The DEX Monitor UI displays this name (default: ToscaExecutionClient)."
  echo "  -d, --debug             Activate debug mode."
  echo "  --enqueueOnly           Only enqueue the execution. ToscaExecutionClient doesn't fetch results."
  echo "  --executionEnvironment  Environment in which you want to execute the event. Possible values are \"Dex\" or \"ElasticExecutionGrid\" (default: \"Dex\")."
  echo "  --executionId           ID of the execution for which you want to get results. You only need this parameter if you choose \"fetchResultsOnly\"."
  echo "  --fetchPartialResults   Fetch partial execution results."
  echo "  --fetchResultsOnly      Get the results of an currently running or already finished execution."
  echo "  -h, --help              Get usage information for the ToscaExecutionClient."
  echo "  --importResults         Import results into your Tosca project. Possible values are \"true\" and \"false\"."
  echo "  --insecure              Disables peer certificate validation when you use HTTPS."
  echo "  --logFolderPath         Path to the folder where the ToscaExecutionClient saves log files (default: logs)."
  echo "  --pollingInterval       Interval in seconds in which the ToscaExecutionClient requests results from the DEX Server (default: 60)."
  echo "  --requestTimeout        Time in seconds that the ToscaExecutionClient waits for a response from AOS (default: 180)."
  echo "  --requestRetries        Number of times that ToscaExecutionClient retries failed requests (default: 5)."
  echo "  --requestRetryDelay     Time in seconds that ToscaExecutionClient waits until it retries a failed request (default: 30)."
  echo "  --resultsFileName       Name of the file in which ToscaExecutionClient saves execution results (default: \"<executionId>_results.xml\")."
  echo "  --resultsFolderPath     Path to the folder where ToscaExecutionClient saves execution results (default: results)."
  echo "  -s, --silent            Deactivate logging to stdout (terminal)."
  echo -e "\n\n Example: ${0} --toscaServerUrl \"https://myserver.tricentis.com\" --projectName \"Tosca_Project_Root\" --events '[\"Event 1\", \"Event 2\"]'\n"
  exit 1
}

#######################################
# Checks if folder exists.
# Globals:
#   None
# Arguments:
#   Path to directory
# Returns:
#   Folder exists / Folder does not exist
#######################################
folderExists() {
  test -d "${1}" && echo "true" || echo "false"
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
log() {
  local logLevel=${1}
  local logMessage=${2}
  local currentDate=`date "+%Y-%m-%d %H:%M:%S %z"`

  local message="${currentDate} [${logLevel}] ${logMessage}"

  # Create log folder if it does not exist  
  if ( [ ! -d "${logFolderPath}" ] ) then 
    echo "${currentDate} [ERR] Directory \"${logFolderPath}\" does not exist. Try to create directory \"${logFolderPath}\"..."
    mkdir -p "${logFolderPath}"
    if ( [ ! -d "${logFolderPath}" ] ) then 
      echo "${currentDate} [ERR] Failed to create directory \"${logFolderPath}\"."
      echo "${currentDate} [INF] Stopping ToscaExecutionClient..."
      exit 1
    else
      log "INF" "Successfully created directory \"${logFolderPath}\"."
    fi
  fi

  if ( [ "${silent}" == "false" ] ) then
    # Write log message to stdout (terminal)
    if ( [ "${logLevel}" == "ERR" ] ) then
      echo -e "${red}$message${clear}";
    else
      echo "${message}"
    fi
  fi

  logFilePath="${logFolderPath}/`date "+%Y%m%d"`_ToscaExecutionClient.txt"
  echo "${message}" >> ${logFilePath}
}

#######################################
# Logs errors from stdin.
# Globals:
#   None
# Arguments:
#   Log message
# Returns:
#   Nothing
#######################################
logErrorsFromStdIn() {
  # pass stdin as error to logger function
  local line="$(cat -)"
  
  if ( [ ! -z "${line}" ] ) then
    log "ERR" "${line}"
  fi
}

#######################################
# Logs collected curl request errors.
# Globals:
#   None
# Arguments:
#   Log message
# Returns:
#   Nothing
#######################################
logCurlRequesErrors() {
  while IFS= read -r line
  do
    if ( [ ! -z "${line}" ] ) then
      log "ERR" "${line}"
    fi
  done < "${tmpFilePath}"
}

#######################################
# Fetches access token from Tosca Server
# Globals:
#   toscaServerUrl
#   requestTimeout
#   requestRetries
#   requestRetryDelay
#   clientId
#   clientSecret
# Arguments:
# Returns:
#   Nothing
#######################################
function fetchOrRefreshAccessToken() {
  
  # Only fetch token if credentials are provided, no token exists or expiration is close
  if ( [ "${authenticationEnabled}" == "true" ] && [ $(date +%s) -ge ${tokenExpirationDate} ] ) then
    log "INF" "Fetching access token with provided credentials..."

    local response=$(
      curl \
        --location \
        --header "X-Tricentis: OK" \
        --write-out "HTTPSTATUS:%{http_code}" \
        --connect-timeout ${requestTimeout} \
        --retry ${requestRetries} \
        --retry-delay ${requestRetryDelay} \
        --silent \
        --show-error \
        --request POST "${toscaServerUrl}/tua/connect/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=${clientId}" \
        --data-urlencode "client_secret=${clientSecret}" \
        ${caCertificateSwitch} \
        ${insecureSwitch} \
        2> ${tmpFilePath}
    )

    # Log collected request errors and remove temp file
    logCurlRequesErrors

    if ( [ -f "${tmpFilePath}" ] ) then 
      rm "${tmpFilePath}" 2> >(logErrorsFromStdIn)
    fi

    local responseStatus=$(echo ${response} | tr -d "\n" | sed -E "s/.*HTTPSTATUS:([0-9]{3})$/\1/")
    local responseBody=$(echo ${response} | sed -E "s/HTTPSTATUS\:[0-9]{3}$//")

    if ( [ "${debug}" == "true" ] ) then
      log "DBG" "Status code of the response = HTTP code ${responseStatus}."
      log "DBG" "Body of the response = ${responseBody}"
    fi

    # Request successful
    if ( [[ "${responseStatus}" =~ ^2 ]] ) then
      log "INF" "Sucessfully fetched access token"
      local expiresIn=$(get_number_json_key "${responseBody}" "expires_in")
      accessToken=$(get_string_json_key "${responseBody}" "access_token")

      # Trigger the token refresh when 80% of the tokens lifetime have expired
      tokenExpirationDate=$(($(date +%s)+${expiresIn}*80/100))

    # Handle errors
    else
      log "ERR" "ToscaExecutionClient failed to fetch the access token."
      log "ERR" "Status code of the response = HTTP code ${responseStatus}."
      log "ERR" "Body of the response = ${responseBody}"
    fi
  fi
}

#######################################
# Enqueues execution request
# Globals:
#   toscaServerUrl
#   requestTimeout
#   requestRetries
#   requestRetryDelay
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
  local enqueueParameters="{\"ExecutionEnvironment\": \"${executionEnvironment}\", \"ProjectName\": \"${projectName}\", \"Events\": ${events}, \"ImportResult\": ${importResults}, \"Creator\": \"${creator}\"}"
  
  log "INF" "Enqueue execution with provided parameters..."

  if ( [ "${debug}" == "true" ] ) then
    log "DBG" "Enqueue parameters:"
    log "DBG" "${enqueueParameters}"
  fi

  fetchOrRefreshAccessToken

  local response=$(
    curl \
      --location \
      --header "X-Tricentis: OK" \
      --write-out "HTTPSTATUS:%{http_code}" \
      --connect-timeout ${requestTimeout} \
      --retry ${requestRetries} \
      --retry-delay ${requestRetryDelay} \
      --silent \
      --show-error \
      --request POST "${toscaServerUrl}/automationobjectservice/api/execution/enqueue" \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer ${accessToken}" \
      --data-raw "${enqueueParameters}" \
      ${caCertificateSwitch} \
      ${insecureSwitch} \
      2> ${tmpFilePath}
  )

  # Log collected request errors and remove temp file
  logCurlRequesErrors

  if ( [ -f "${tmpFilePath}" ] ) then 
    rm "${tmpFilePath}" 2> >(logErrorsFromStdIn)
  fi

  local responseStatus=$(echo ${response} | tr -d "\n" | sed -E "s/.*HTTPSTATUS:([0-9]{3})$/\1/")
  local responseBody=$(echo ${response} | sed -E "s/HTTPSTATUS\:[0-9]{3}$//")

  if ( [ "${debug}" == "true" ] ) then
    log "DBG" "Status code of the response = HTTP code ${responseStatus}."
    log "DBG" "Body of the response = ${responseBody}"
  fi

  # Request successful
  if ( [[ "${responseStatus}" =~ ^2 ]] ) then
    executionId=$(get_string_json_key "${responseBody}" "ExecutionId")

    if ( [ -z "${executionId}" ] ) then
      log "ERR" "Enqueue response does not include executionId property."
      log "ERR" "Status code of the response = HTTP code ${responseStatus}."
      log "ERR" "Body of the response = ${responseBody}"
      exit 1
    else
      log "INF" "Successfully enqueued execution with id \"${executionId}\"."
    fi
  # Handle unauthorized response
  elif ( [ "${responseStatus}" == 401 ] ) then
    log "ERR" "ToscaExecutionClient is not authorized to enqueue the execution. Check the credentials configuration..."
    exit 1
  # Handle other errors
  else
    log "ERR" "ToscaExecutionClient failed to enqueue the execution."
    log "ERR" "Status code of the response = HTTP code ${responseStatus}."
    log "ERR" "Body of the response = ${responseBody}"
    exit 1
  fi
}

#######################################
# Fetches execution status
# Globals:
#   toscaServerUrl
#   requestTimeout
#   requestRetries
#   requestRetryDelay
#   accessToken
#   executionId
# Arguments:
#   None
# Returns:
#   Nothing
#######################################
function fetchExecutionStatus() {
  log "INF" "Fetch status for execution with id \"${executionId}\"..."

  fetchOrRefreshAccessToken

  local response=$(
    curl \
      --location \
      --header "X-Tricentis: OK" \
      --write-out "HTTPSTATUS:%{http_code}" \
      --connect-timeout ${requestTimeout} \
      --retry ${requestRetries} \
      --retry-delay ${requestRetryDelay} \
      --silent \
      --show-error \
      --request GET "${toscaServerUrl}/automationobjectservice/api/execution/${executionId}/status" \
      --header "Authorization: Bearer ${accessToken}" \
      ${caCertificateSwitch} \
      ${insecureSwitch} \
      2> ${tmpFilePath}
  )

  # Log collected request errors and remove temp file
  logCurlRequesErrors

  if ( [ -f "${tmpFilePath}" ] ) then 
    rm "${tmpFilePath}" 2> >(logErrorsFromStdIn)
 fi

  local responseStatus=$(echo ${response} | tr -d "\n" | sed -E "s/.*HTTPSTATUS:([0-9]{3})$/\1/")
  local responseBody=$(echo ${response} | sed -E "s/HTTPSTATUS\:[0-9]{3}$//")

  if ( [ "${debug}" == "true" ] ) then
    log "DBG" "Status code of the response = HTTP code ${responseStatus}."
    log "DBG" "Body of the response = ${responseBody}"
  fi

  # Request successful
  if ( [[ "${responseStatus}" =~ ^2 ]] ) then
    executionStatus=$(get_string_json_key "${responseBody}" "status")

    if ( [ -z "${executionStatus}" ] ) then
      log "ERR" "Status response does not include status property."
      log "ERR" "Status code of the response = HTTP code ${responseStatus}."
      log "ERR" "Body of the response = ${responseBody}"
    fi
  # Handle unauthorized response
  elif ( [ "${responseStatus}" == 401 ] ) then
    log "ERR" "ToscaExecutionClient is not authorized to fetch the status for execution with id \"${executionId}\". Check the credentials configuration..."
  # Handle other errors
  else
    log "ERR" "ToscaExecutionClient failed to fetch the status for execution with id \"${executionId}\"."
    log "ERR" "Status code of the response = HTTP code ${responseStatus}."
    log "ERR" "Body of the response = ${responseBody}"
  fi
}

#######################################
# Fetches execution results
# Globals:
#   toscaServerUrl
#   requestTimeout
#   requestRetries
#   requestRetryDelay
#   accessToken
#   executionId
# Arguments:
#   fetchPartialResults
# Returns:
#   Nothing
#######################################
function fetchExecutionResults() {
  local fetchPartialResults="${1}"
  local queryParameters=""

  if ( [ "${fetchPartialResults}" == "true" ] ) then
    queryParameters="?partial=true"
  fi

  log "INF" "Fetching results for execution with id \"${executionId}\"..."

  fetchOrRefreshAccessToken
  
  local response=$(
    curl \
      --location \
      --header "X-Tricentis: OK" \
      --write-out "HTTPSTATUS:%{http_code}" \
      --connect-timeout ${requestTimeout} \
      --retry ${requestRetries} \
      --retry-delay ${requestRetryDelay} \
      --silent \
      --show-error \
      --request GET "${toscaServerUrl}/automationobjectservice/api/execution/${executionId}/results${queryParameters}" \
      --header "Authorization: Bearer ${accessToken}" \
      ${caCertificateSwitch} \
      ${insecureSwitch} \
      2> ${tmpFilePath}
  )

  # Log collected request errors and remove temp file
  logCurlRequesErrors

  if ( [ -f "${tmpFilePath}" ] ) then 
    rm "${tmpFilePath}" 2> >(logErrorsFromStdIn)
 fi

  local responseStatus=$(echo ${response} | tr -d "\n" | sed -E "s/.*HTTPSTATUS:([0-9]{3})$/\1/")
  local responseBody=$(echo ${response} | sed -E "s/HTTPSTATUS\:[0-9]{3}$//")

  if ( [ "${debug}" == "true" ] ) then
    log "DBG" "Status code of the response = HTTP code ${responseStatus}."
    log "DBG" "Body of the response = ${responseBody}"
  fi

  # Request successful
  if ( [[ "${responseStatus}" =~ ^2 ]] ) then
    # Reset execution results variable
    executionResults=""

    # All results available
    if ( [ "${responseStatus}" == 200 ] ) then
      log "INF" "Sucessfully fetched results for execution with id \"${executionId}\"."
      executionResults="${responseBody}"
    # Not all results are available (E.g. cancelled events, configuration errors) 
    elif ( [ "${responseStatus}" == 206 ] ) then
      log "WRN" "Not all execution results have been returned for execution with id \"${executionId}\". Check AOS, DEX Server and DEX agent logs."
      executionResults="${responseBody}"
    # Handle non existing results when fetchPartialResults option is activated
    elif ( [ "${fetchPartialResults}" == "true" ] ) then
      log "INF" "No results available yet for execution with id \"${executionId}\"."
    else
      log "ERR" "No results available for execution with id \"${executionId}\". Check AOS, DEX Server and DEX agent logs."
    fi
  # Handle unauthorized response
  elif ( [ "${responseStatus}" == 401 ] ) then
    log "ERR" "ToscaExecutionClient is not authorized to fetch the results for execution with id \"${executionId}\". Check the credentials configuration..."
    exit 1
  # Handle other errors
  else
    log "ERR" "ToscaExecutionClient failed to fetch the results for execution with id \"${executionId}\"."
    log "ERR" "Status code of the response = HTTP code ${responseStatus}."
    log "ERR" "Body of the response = ${responseBody}"
    exit 1
  fi
}

#######################################
# Writes execution results
# Globals:
#   executionId
#   executionResults
#   resultsFilePath
# Arguments:
#   writePartialResults
# Returns:
#   Nothing
#######################################
function writeResults() {
  local writePartialResults="${1}"
  local currentDate=`date "+%Y%m%d_%H%M%S"`
  local folderPath=${resultsFolderPath}

  if ( [ ! -z "${executionResults}" ] ) then

    if ( [ "${writePartialResults}" == "true" ] ) then
      folderPath="${folderPath}/${executionId}_partial"
      resultsFilePath="${folderPath}/${currentDate}_results.xml"
      log "INF" "Writing partial results for execution with id \"${executionId}\" to file \"${resultsFilePath}\"..."
    else
        if ( [ ! -z "${resultsFileName}" ] ) then
          resultsFilePath="${folderPath}/${resultsFileName}"
        else
          resultsFilePath="${folderPath}/${executionId}_results.xml"
        fi

      log "INF" "Writing results for execution with id \"${executionId}\" to file \"${resultsFilePath}\"..."
    fi

    # Create results folder if it does not exist  
    if ( [ ! -d "${folderPath}" ] ) then 
      log "INF" "Directory \"${folderPath}\" does not exist. Try to create directory \"${folderPath}\"..."
      mkdir -p "${folderPath}"
      if ( [ ! -d "${folderPath}" ] ) then 
        log "ERR" "Failed to create directory \"${folderPath}\"."
        log "INF" "Stopping ToscaExecutionClient..."
        exit 1
      else
        log "INF" "Successfully created directory \"${folderPath}\"."
      fi
    fi

    echo ${executionResults} > ${resultsFilePath} 2> >(logErrorsFromStdIn)
    log "INF" "Finished writing execution results to file \"${resultsFilePath}\""
  fi
}

######################################################################
# Main
######################################################################

# Parse parameters
while [[ "$#" > 0 ]]; do case ${1} in
  # Mandatory parameters 
  --toscaServerUrl) toscaServerUrl="${2}"; shift;shift;;
  --executionEnvironment) executionEnvironment="${2}"; shift;shift;;
  --projectName) projectName="${2}"; shift;shift;;
  --events) events="${2}"; shift;shift;;
  --eventsConfigFilePath) eventsConfigFilePath="${2}"; shift;shift;;

  # Optional parameters
  --caCertificate) caCertificateSwitch="--cacert ${2}"; shift;shift;;
  --clientId) clientId="${2}";shift;shift;;
  --clientSecret) clientSecret="${2}";shift;shift;;
  --clientTimeout) clientTimeout="${2}";shift;shift;;
  --creator) creator="${2}"; shift;shift;;
  -d|--debug) debug=true; shift;;
  -h|--help) displayHelp; exit 0; shift;;
  --enqueueOnly) enqueueOnly=true;shift;;
  --executionId) executionId="${2}"; shift;shift;;
  --insecure) insecureSwitch="--insecure"; shift;;
  --importResults) importResults="${2}"; shift;shift;;
  --fetchPartialResults) fetchPartialResults=true;shift;;
  --fetchResultsOnly) fetchResultsOnly=true;shift;;
  --logFolderPath) logFolderPath="${2}"; shift;shift;;
  --pollingInterval) pollingInterval="${2}";shift;shift;;
  --requestTimeout) requestTimeout="${2}";shift;shift;;
  --requestRetries) requestRetries="${2}";shift;shift;;
  --requestRetryDelay) requestRetryDelay="${2}";shift;shift;;
  --resultsFileName) resultsFileName="${2}";shift;shift;;
  --resultsFolderPath) resultsFolderPath="${2}";shift;shift;;
  -s|--silent) silent=true;shift;;
  *) log "ERR" "Unknown parameter passed: ${1}";displayHelp;exit 1;shift;;
esac; done

# Verify mandatory parameters
if ( [ -z "${toscaServerUrl}" ] ) then 
  log "ERR" "Mandatory parameter \"toscaServerUrl\" is not set."
elif ( [ -z "${projectName}" ] && [ -z "${fetchResultsOnly}" ] ) then 
  log "ERR" "Mandatory parameter \"projectName\" is not set."
elif ( [ -z "${events}" ] && [ -z "${eventsConfigFilePath}" ] && [ -z "${fetchResultsOnly}" ] ) then
  log "ERR" "Event configuration is missing. Define either \"events\" or \"eventsConfigFilePath\"."
else
  validationFailed=false
fi

# Skip enqueue call if fetchResultsOnlyOption is given
if ( [ "${validationFailed}" == "true" ] ) then
  displayHelp
  exit 1    
fi

log "INF" "Starting ToscaExecutionClient..."

# Remove temp file
if ( [ -f "${tmpFilePath}" ] ) then 
  rm "${tmpFilePath}" 2> >(logErrorsFromStdIn)
fi

# Remove path information from provided Tosca Server URL
toscaServerUrl="$(echo ${toscaServerUrl} | cut -d '/' -f1)//$(echo ${toscaServerUrl} | cut -d '/' -f3)"

# Use value from events config file
if ( [ -n "${eventsConfigFilePath}" ] ) then
  log "INF" "Parameter \"eventsConfigFilePath\" defined. Using configuration from file."
  events="$(cat ${eventsConfigFilePath})" 2> >(logErrorsFromStdIn)
fi

# Get access token if credentials are provided
if ( [ -z "${clientId}" ] || [ -z "${clientSecret}" ] ) then
  log "WRN" "ClientId or clientSecret is not provided. Continue without authentication..."
else
  log "INF" "ClientId and clientSecret are provided. Authentication will be enabled. Fetch access token with provided credentials..."
  authenticationEnabled=true
  fetchOrRefreshAccessToken
fi

# Skip enqueue call if fetchResultsOnlyOption is given
if ( [ "${fetchResultsOnly}" == "true" ] ) then
  log "INF" "Option fetchResultsOnly is activated."    
else
  # Enqueue execution
  enqueueExecution

  # Skip fetching of execution results when enqueueOnlyOption is given 
  if ( [ "${enqueueOnly}" == "true" ] ) then
    log "INF" "Option enqueueOnly is activated."
    log "INF" "Enqueing execution has sucessfully finished" 
    log "INF" "Stopping ToscaExecutionClient..."
    exit 0
  fi
fi

# Handle missing execution id
if ( [ -z "${executionId}" ] ) then
  log "ERR" "ExecutionId is missing or empty." 
  log "INF" "Stopping ToscaExecutionClient..."
  exit 1
fi

# Start status polling
log "INF" "Starting execution status polling with an interval of ${pollingInterval} seconds..."
executionTimeout=$(($(date +%s)+${clientTimeout}))
keepPolling=true;
while ( [ "$keepPolling" == true ] )
do
  fetchExecutionStatus
  log "INF" "Status of execution with id \"${executionId}\": \"${executionStatus}\""

  if ( [ $(date +%s) -le ${executionTimeout} ] && [[ ! "${executionStatus}" == *"Completed"* ]] && [[ ! "${executionStatus}" == "Error" ]] && [[ ! "${executionStatus}" == "Cancelled" ]] ) 
  then
    keepPolling=true;
  else
    keepPolling=false;
    break
  fi
  
  # Fetch partial results for the execution
  if ( [ "${fetchPartialResults}" == "true" ] ) then
    log "INF" "Fetching partial results ..."

    # Fetch partial results
    fetchExecutionResults "true"

    # Write partial results
    writeResults "true"
  fi

  log "INF" "Starting next polling cycle in ${pollingInterval} seconds..."
  sleep ${pollingInterval}
done

# Check for execution status after results polling
if ( [[ "${executionStatus}" == *"Completed"* ]] )
then
  log "INF" "Execution with id \"${executionId}\" finished."
  
  # Fetch results when execution is finished
  fetchExecutionResults "false"
  
  # Write execution results
  writeResults "false"
  log "INF" "Stopping ToscaExecutionClient..."
  exit 0
elif ( [[ "${executionStatus}" == "Error" ]] || [[ "${executionStatus}" == "Cancelled" ]] ) then
  log "ERR" "Execution Error or Cancelled!"
  exit 1
else
  log "ERR" "Execution exceeded clientTimeout of ${clientTimeout} seconds. Stopping ToscaExecutionClient..."
  exit 1
fi
