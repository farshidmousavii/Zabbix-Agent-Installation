# Zabbix agent Installation

## Install Zabbix Agent With GPO 

1. Download the Zabbix agent archive file from [Zabbix site](https://www.zabbix.com/download_agents?version=7.2&release=7.2.1&os=Windows&os_version=Any&hardware=amd64&encryption=No+encryption&packaging=Archive&show_legacy=0) , prefer agent 2
2. Put downloaded file in DC NETLOGON folder
3. Copy zabbix.ps1 file to NETLOGON and change $ServerIP to IP of Zabbix server inside of script
4. Open Group Policy Management on DC and crate new policy and link to OU
5. Right click on created policy and click on edit
6. go to following path and double click on startup
```
Computer Configuration > Windows Settings > Scripts > startup
```
7. in PowerShell Scripts tab click on Add , click on brows and select script on NETLOGON folder and then select ok and close Policy Management
8. Open command Prompt on DC and enter following command

```
gpupdate /force
```

10.  Now restart one of the servers of the domain and Zabbix agent will automatically install on server with GPO
