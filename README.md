# ToscaExecutionClient

## Description
Our Tosca Execution Clients allow you to trigger Tosca TestEvents from CI/CD pipelines or other environments. They're an out-of-the-box solution that comes with a variety of configuration options. What's more, the clients are fully script-based, which allows you to tailor your Tosca CI/CD integration exactly to your needs.
Tosca Execution Clients leverage the Execution API of Tosca Server. If you want to integrate directly with the Execution API, check out our online help.

## Supported functionality
### Tosca 15.2 and higher
Tosca Execution Client supports full functionality for DEX executions. For Elastic Execution Grid executions, Tosca Execution Client supports enqueuing executions through the enqueueOnly option.

Latest version: Tosca 2025.1 LTS

## System requirements
To use Tosca Execution Clients, you need Tosca Server 15.2 LTS or higher. We offer the client in two versions: for Windows systems and Linux systems.

* Windows
  * The client is available as PowerShell script.
  * You need PowerShell 3.1 or newer.
* Linux
  * The client is available as Shell script.
  * You need curl 7.43 or newer.

## Get started
Depending on whether you want to run the Tosca Execution Client on Windows or Linux, you need different system configurations.

### Windows
#### PowerShell Execution Policy
The machine that runs the Tosca Execution Client needs to be allowed to execute the script. Depending on your specific infrastructure setup, you may already have this in place. If you don't, change the PowerShell Execution Policy on the machine. For more information, take a look at this Microsoft [article] (https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.2).

#### Add Tosca Server certificate to Trusted Root certificate store
If you run Tosca Server with https, you need to add the certificate used by Tosca Server to the Trusted Root certificate store on the machine that runs the Tosca Execution Client.

### Linux configurations
#### Make sure that Tosca Execution Client can be executed
Make sure that the machine can execute the Tosca Execution Client, which means that the user who executes the script needs to be allowed to do so. You can achieve this with following command:

```
chmod u+x <path to tosca_execution_client.sh>
```

#### Make sure that Tosca Server certificate is available on the executing machine
If you run Tosca Server with https, the certificate used by Tosca Server needs to be available on the machine that runs Tosca Execution Client. Use the --caCertificate option to make the Tosca Execution Client trust this certificate. 

## Run Tosca Execution Client

### Launch Tosca Execution Client
To launch the Tosca Execution Client on a Windows system, use the following command:
```
.\tosca_execution_client.ps1 -toscaServerUrl <toscaServerUrl> -projectName <projectName> -events <events> [Options]
```
To launch the Tosca Execution Client on a Linux system, use the following command:
```
./tosca_execution_client.sh --toscaServerUrl <toscaServerUrl> --projectName <projectName> --events <events> [Options]
```
### Mandatory parameters

| Name                  | Description   
| :-------------------- | :------------ 
| toscaServerUrl        | URL of Tosca Server, e.g. https://myserver.tricentis.com or http://111.111.111.0:81. 
| projectName           | Project root name of the Tosca project where the event is located.      
| events                | Stringified JSON array containing the names or uniqueIds of the events that you want to execute. If you want to overwrite TCPs or Agent Characteristics for a specific event, use the "eventsConfigFilePath" parameter instead.
| eventsConfigFilePath &nbsp; &nbsp;  | Path to the JSON file that contains the event configuration, including TCPs and Agent Characteristics. If you use this parameter, you don't need to use the "events" parameter.

Check out the [Tosca help](https://support.tricentis.com/community/manuals_detail.do?&url=continuous_integration/tosca_execution_clients.htm) for more information on how to configure events and some practical examples.

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




