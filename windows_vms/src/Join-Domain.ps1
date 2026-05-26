#ps1_sysnative

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [securestring]$ActiveDirectoryCredential,
    
    [Parameter(Mandatory=$false)]
    [string[]]$DnsServers,

    [Parameter(Mandatory=$false)]
    [string]$ServerName
)

$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1

# Function to test connectivity to DNS servers
function Test-DNSServerConnectivity {
    param(
        [string[]]$DNSServers
    )
    
    Write-Log "Testing connectivity to DNS servers: $DNSServers"
    
    foreach ($server in $DNSServers) {
        if (-not ([System.Net.IPAddress]::TryParse($server, [ref]$null))) {
            Write-Log "Error: Invalid IP address format: $server" -EntryType "Error"
            exit 1
        }

        try {
            $result = Test-NetConnection -ComputerName $server -Port 53 -InformationLevel Quiet
            if ($result) {
                Write-Log "$server is reachable on port 53"
            }
            else {
                Write-Log "$server is not reachable on port 53" -EntryType "Error"
                exit 1
            }
        }
        catch {
            Write-Log "Failed to test $server : $($_.Exception.Message)" -EntryType "Error"
            exit 1
        }
    }
}

# Function to get the primary network adapter (with default route)
function Get-PrimaryNetworkAdapter {
    try {
        # Get the default route
        $defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
        
        if ($defaultRoute) {
            $adapter = Get-NetAdapter -InterfaceIndex $defaultRoute.InterfaceIndex
            Write-Log "Primary adapter detected: $($adapter.Name) (InterfaceIndex: $($adapter.InterfaceIndex))"
            return $adapter
        }
        else {
            Write-Log "No default route found. Falling back to first active adapter."
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Loopback" } | Select-Object -First 1
            if ($adapter) {
                Write-Log "Using adapter: $($adapter.Name)"
                return $adapter
            }
        }
    }
    catch {
        Write-Log "Error detecting primary adapter: $($_.Exception.Message)" -EntryType "Error"
        exit 1
    }
    
    return $null
}

# Function to set DNS servers on the primary adapter
function Set-DNSServers {
    param(
        [string[]]$DNSServers
    )
    
    $adapter = Get-PrimaryNetworkAdapter
    
    if (-not $adapter) {
        Write-Log "No suitable network adapter found!" -EntryType "Error"
        exit 1
    }
    
    try {
        Write-Log "Setting DNS servers on primary adapter: $($adapter.Name)"
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $DNSServers
        Write-Log "DNS servers set successfully on $($adapter.Name)"
    }
    catch {
        Write-Log "Failed to set DNS on $($adapter.Name): $($_.Exception.Message)" -EntryType "Error"
        exit 1
    }
}

# Function to verify DNS resolution
function Test-DomainResolution {
    param(
        [string]$Domain
    )
    
    Write-Log "Testing domain resolution for: $Domain"
    
    try {
        # Test basic DNS resolution
        $result = Resolve-DnsName -Name $Domain
        
        if ($result) {
            Write-Log "Domain '$Domain' resolved successfully!"
            
            # Display resolution results
            Write-Log "Resolution Results:"
            foreach ($record in $result) {
                Write-Log "  Type: $($record.Type), Name: $($record.Name), IP: $($record.IPAddress)"
            }
        }
        else {
            Write-Log "Domain '$Domain' could not be resolved" -EntryType "Error"
            exit 1
        }
    }
    catch {
        Write-Log "DNS resolution failed: $($_.Exception.Message)" -EntryType "Error"
        exit 1
    }
}

# Function to join compture to domain
function Join-Computer {
    param(
        [string]$Domain,
        [securestring]$ActiveDirectoryCredential,
        [Parameter(Mandatory=$false)][string]$ServerName
    )

    $joinCred = New-Object pscredential -ArgumentList ([pscustomobject]@{ 
        UserName = $null; 
        Password = $ActiveDirectoryCredential
    })
    
    try {
        Write-Log "Attempting to join domain $Domain"

        $currentName = $env:COMPUTERNAME

        if ([string]::IsNullOrWhiteSpace($ServerName) -or ($currentName -ieq $ServerName)) {
            Add-Computer -DomainName $Domain -Options UnsecuredJoin,PasswordPass -Credential $joinCred -Force
        } else {
            Write-Log "Renaming computer from $currentName to $ServerName"
            Rename-Computer -NewName $ServerName -Force

            Write-Log "Joining domain using computer credential $ServerName"
            Add-Computer -DomainName $Domain -Options UnsecuredJoin,PasswordPass,JoinWithNewName -NewName $ServerName -Credential $joinCred -Force
        }

        Write-Log "Successfully initiated domain join for $Domain"

        Write-Log "Rebooting system"
        Restart-Computer -Force
    } catch {
        Write-Log "Failed to join domain: $($_.Exception.Message)" -EntryType "Error"
        exit 1
    }
}


### Main script execution ###
Write-Log "Initiating domain join" 

if ($DnsServers) {
    Test-DNSServerConnectivity -DNSServers $DnsServers
    Set-DNSServers -DNSServers $DnsServers
} else {
    Write-Log "DnsServers not configured. Skipping DNS setup."
}

Start-Sleep -Seconds 3
Test-DomainResolution -Domain $DomainName

# Join computer to domain
Join-Computer -Domain $DomainName -ActiveDirectoryCredential $ActiveDirectoryCredential -ServerName $ServerName