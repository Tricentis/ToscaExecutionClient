# ToscaExecutionClient

## Description
Our Tosca Execution Clients allow you to trigger Tosca TestEvents from CI/CD pipelines or other environments. Coming with lots of configuration options, Tosca Execution Clients are an out-of-the box solution to leverage the Execution API of Tosca Server. If you want to integrate directly with Tosca Server Execution API, please take a look at Tricentis Tosca documentation. On top of that, Tosca Execution Clients are fully script-based, enabling easy customization to tailor your Tosca CI/CD integration exactly to your business needs.

## System requirements
Tosca Execution Clients require at least Tosca Server 15.2 LTS or newer. To support both Windows and Linux operating systems, we provide 2 versions of Tosca Execution Client. For Windows systems we provide Tosca Execution Client as PowerShell script. For Linux systems we provide Tosca Execution Client as Shell script.

### Windows
To run Tosca Execution Client on Windows, at least PowerShell 3.1 or newer is required.

### Linux
To run Tosca Execution Client on Linux, at least curl 7.12.3 or newer is required.

## Getting started
Depending on whether you run Tosca Execution Client on Windows or Linux, different configuration is needed in advance. To get you started as quickly as possible, we have summarized all required steps in this chapter. 

### Windows
#### PowerShell Execution Policy
The machine that launches Tosca Execution Client needs to be allowed to execute the script. Depending on your specific infrastructure setup, this can already be in place. If not, you need to change the PowerShell Execution Policy for your machine. More information can be found in this [article](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.2) from Microsoft. 

#### Add Tosca Server Certificate to Trusted Root certificate store
If you run Tosca Server with https, you need to add the certificate used by Tosca Server to the Trusted Root certificate store on the machine that runs Tosca Execution Client. 

### Linux
#### Make sure that Tosca Execution Client can be executed
In order to use Tosca Execution Client on a Linux machine, the user that executes the script needs to be allowed to do so. You can achieve this with following command:

```
chmod u+x <path to tosca_execution_client.sh>
```

#### Make sure that Tosca Server certificate is available on executing machine
If you run Tosca Server with https, the certificate used by Tosca Server needs to be available on the machine that runs Tosca Execution Client. You can then use the --caCert option to make Tosca Execution Client trust this certificate.   

## Usage

### Launch Tosca Execution Client
Tosca Execution Client for Windows can be launched with following command:
```
.\tosca_execution_client.ps1 -toscaServerUrl <toscaServerUrl> -projectName <projectName> -events <events> [Options]
```
Tosca Execution Client for Linux can be launched with following command:
```
./tosca_execution_client.sh --toscaServerUrl <toscaServerUrl> --projectName <projectName> --events <events> [Options]
```
### Mandatory parameters

| Name                  | Description   
| :-------------------- | :------------ 
| toscaServerUrl        | URL of Tosca Server, e.g. https://myserver.tricentis.com or http://111.111.111.0:81. 
| projectName           | Project root name of the Tosca project where the event is located.      
| events                | Names or uniqueIds of the events that you want to execute, separated by comma. If you want to overwrite TCPs or Agent Characteristics for a specific event, use the "eventsConfigFilePath" parameter instead.      
| eventsConfigFilePath &nbsp; &nbsp;  | Path to the JSON file that contains the event configuration, including TCPs and Agent Characteristics. If you use this parameter, you don't need to use the "events" parameter.

### Options
| Name                  | Description   
| :-------------------- | :------------ 
| caCertificate         | Path to the CA certificate (in PEM format) that the Tosca Execution Client uses for peer certificate validation. This parameter is mandatory if you use HTTPS and don't use the "insecure" parameter. You can use this parameter only with Tosca Execution Client for Linux.
| clientId              | Client ID of the Tricentis User Administration access token. This parameter is mandatory if you use HTTPS.
| clientSecret          | Client secret of the Tricentis User Administration access token. This parameter is mandatory if you use HTTPS.
| clientTimeout         | Time in seconds that the Tosca Execution Client waits for the execution to finish before it aborts (default: 36000).
| creator               | Name of who triggered the execution. The DEX Monitor UI displays this name (default: ToscaExecutionClient).
| d, debug              | Activate debug mode.
| enqueueOnly           | Only enqueue the execution. Tosca Execution Client doesn't fetch results.
| executionEnvironment  | Environment in which you want to execute the event. Possible values are "Dex" or "ElasticExecutionGrid" (default: "Dex").
| executionId           | ID of the execution for which you want to get results. You only need this parameter if you choose "fetchResultsOnly".
| fetchPartialResults   | Fetch partial execution results.
| fetchResultsOnly      | Get the results of an currently running or already finished execution.
| h, help               | Get usage information for the Tosca Execution Client.
| importResults         | Import results into your Tosca project. Possible values are "true" and "false".
| insecure              | Disables peer certificate validation when you use HTTPS. You can use this parameter only with Tosca Execution Client for Linux.
| logFolderPath         | Path to the folder where the Tosca Execution Client saves log files (default: logs).
| pollingInterval       | Interval in seconds in which the Tosca Execution Client requests results from the DEX Server (default: 60).
| requestTimeout        | Time in seconds that the Tosca Execution Client waits for a response from AOS (default: 180).
| requestRetries        | Number of times that Tosca Execution Client retries failed requests (default: 5). You can use this parameter only with Tosca Execution Client for Linux.
| requestRetryDelay     | Time in seconds that Tosca Execution Client waits until it retries a failed request (default: 30). You can use this parameter only with Tosca Execution Client for Linux.
| resultsFileName       | Name of the file in which Tosca Execution Client saves execution results (default: "\<executionId\>_results.xml").
| resultsFolderPath     | Path to the folder where Tosca Execution Client saves execution results (default: results).
| s, silent             | Deactivate logging to stdout (terminal).




