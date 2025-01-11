# Enable logging
Start-Transcript -Path "C:\Windows\Temp\ZabbixInstall.log"
Write-Host "Script started at $(Get-Date)"
Write-Host "Current user context: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
# Specify Zabbix server/proxy IP here
$ServerIP = "<IP-Address-Of-Zabbix>"
# Target directory for Zabbix installation (updated path)
$InstallPath = "C:\Program Files\Zabbix Agent 2"
# Configuration file path
$ConfigFile = "$InstallPath\conf\zabbix_agent2.conf"
#Log file path
$NewLogFilePath = "C:\Program Files\Zabbix Agent 2\zabbix_agent2.log"
#HostMetadata configuration for auto registration
$HostMetadata = "<HostMetadata String>"

# Function to get available DC path using DNS
function Get-AvailableDCPath {
    try {
        $domain = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName
        if (-not $domain) {
            throw "No domain name detected. Ensure the client is joined to a domain."
        }
        Write-Host "Domain found: $domain"
        
        # Use Resolve-DnsName to query SRV records
        $srvRecords = Resolve-DnsName -Name "_ldap._tcp.$domain" -Type SRV -ErrorAction Stop
        
        if (-not $srvRecords) {
            throw "No domain controllers resolved via DNS."
        }

        Write-Host "Found $(($srvRecords | Measure-Object).Count) domain controllers via SRV records"

        foreach ($record in $srvRecords) {
            $dcHostname = $record.NameTarget
            $dcPath = "\\$dcHostname\NETLOGON\zabbix"
            Write-Host "Trying DC path: $dcPath"
            if (Test-Path $dcPath) {
                Write-Host "Successfully connected to DC: $dcHostname"
                return $dcPath
            } else {
                Write-Host "Path not accessible: $dcPath"
            }
        }

        throw "No accessible domain controllers found"
    } catch {
        throw "Error finding available DC: $_"
    }
}

# Get Zabbix path from available DC
try {
    $ZabbixPath = Get-AvailableDCPath
    Write-Host "Using Zabbix path: $ZabbixPath"
} catch {
    Write-Host "ERROR: Failed to get available DC path: $_"
    Stop-Transcript
    Exit 1
}

# Gets the server hostname(FQDN)
try {
    $HostName = [System.Net.Dns]::GetHostName()
    $DomainName = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName

    if (-not $DomainName) {
        Write-Host "WARNING: Machine is not part of a domain, using hostname only."
        $ServerHostname = $HostName
    } else {
        $ServerHostname = "$HostName.$DomainName"
    }

    Write-Host "Detected hostname: $ServerHostname"
} catch {
    Write-Host "ERROR: Unable to detect FQDN: $_"
    Stop-Transcript
    Exit 1
}

# Check if Zabbix Agent is already installed and running
try {
    $service = Get-Service -Name "Zabbix Agent 2" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Host "Zabbix Agent is already installed and running. Exiting..."
            Stop-Transcript
            Exit 0
        } elseif ($service.Status -eq "Stopped") {
            Write-Host "Zabbix Agent is installed but stopped. Starting the service..."
            Start-Service "Zabbix Agent 2"
            Stop-Transcript
            Exit 0
        }
    }
} catch {
    Write-Host "Error checking service status: $_"
}

# Ensure Zabbix directory exists
try {
    if (!(Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force
        Write-Host "Created installation directory: $InstallPath"
    }
} catch {
    Write-Host "Error creating directory: $_"
    Stop-Transcript
    Exit 1
}

# Copy files from NetLogon to the target directory
try {
    Write-Host "Copying Zabbix files from NetLogon share..."
    Copy-Item -Path "$ZabbixPath\*" -Destination $InstallPath -Recurse -Force -ErrorAction Stop
    Write-Host "Files copied successfully"
} catch {
    Write-Host "Error copying files: $_"
    Stop-Transcript
    Exit 1
}

# Update the configuration file
try {
    if (Test-Path $ConfigFile) {
        Write-Host "Updating configuration file..."
        $config = Get-Content -Path $ConfigFile
        $config = $config -replace '127.0.0.1', $ServerIP
        $config = $config -replace 'Windows host', $ServerHostname
        # Check if a commented LogFile line exists
        if ($config -match '#\s*LogFile=.*') {
            Write-Host "Found commented LogFile directive. Uncommenting and updating..."
            $config = $config -replace '#\s*LogFile=.*', "LogFile=$NewLogFilePath"
        } elseif ($config -match '^LogFile=.*') {
            Write-Host "Found existing LogFile directive. Updating..."
            $config = $config -replace '^LogFile=.*', "LogFile=$NewLogFilePath"
        } else {
            Write-Host "LogFile directive not found. Adding new line..."
            $config += "LogFile=$NewLogFilePath"
        }

        # Check if a commented HostMetadata line exists
        if ($config -match '#\s*HostMetadata=.*') {
            Write-Host "Found commented HostMetadata directive. Uncommenting and updating..."
            $config = $config -replace '#\s*HostMetadata=.*', "HostMetadata=$HostMetadata"
        } elseif ($config -match '^HostMetadata=.*') {
            Write-Host "Found existing HostMetadata directive. Updating..."
            $config = $config -replace '^HostMetadata=.*', "HostMetadata=$HostMetadata"
        } else {
            Write-Host "HostMetadata directive not found. Adding new line..."
            $config += "HostMetadata=$HostMetadata"
        }

        $config | Set-Content -Path $ConfigFile
        Write-Host "Configuration file updated successfully"
    } else {
        Write-Host "ERROR: Configuration file not found at $ConfigFile"
        Stop-Transcript
        Exit 1
    }
} catch {
    Write-Host "Error updating configuration: $_"
    Stop-Transcript
    Exit 1
}

# Install and start service
try {
    Write-Host "Installing Zabbix Agent service..."
    $result = & "$InstallPath\bin\zabbix_agent2.exe" --config $ConfigFile --install
    Write-Host "Installation result: $result"
    
    Write-Host "Starting Zabbix Agent service..."
    $result = & "$InstallPath\bin\zabbix_agent2.exe" --start --config $ConfigFile
    Write-Host "Start result: $result"
} catch {
    Write-Host "Error installing/starting service: $_"
    Stop-Transcript
    Exit 1
}

# Configure firewall
try {
    Write-Host "Configuring Windows Firewall..."
    New-NetFirewallRule -DisplayName "Allow Zabbix Agent communication" -Direction Inbound -Program "$InstallPath\bin\zabbix_agent2.exe" -RemoteAddress LocalSubnet -Action Allow -ErrorAction Stop
    Write-Host "Firewall rule created successfully"
} catch {
    Write-Host "Error creating firewall rule: $_"
    # Don't exit here as the agent might still work
}

Write-Host "Script completed successfully at $(Get-Date)"
Stop-Transcript