<#
.SYNOPSIS
    Static data server for kevin-Mini, reachable from the home network only.
.DESCRIPTION
    Installs Caddy (pinned version, SHA-512 verified) as an auto-start Windows service that
    serves a folder of data files (CSV, Parquet, JSON, ...) plus a landing page over HTTP.
    - Runs as the low-privilege LocalService account and restarts itself if it crashes.
    - Windows Firewall allows the port only on Private networks and only from the local subnet.
    - Serves correct content types, HTTP range requests (DuckDB, pyarrow, Polars) and CORS,
      and compresses CSV/JSON but not Parquet.
    - Keeps the PC from sleeping on AC power unless -AllowSleep is given.
    Safe to re-run: it updates the existing install in place.
.PARAMETER Port
    TCP port to serve on (default 8080).
.PARAMETER InstallDir
    Where Caddy, its config and logs live (default C:\DataServer).
.PARAMETER DataRoot
    Folder served as the website (default <InstallDir>\public). Put data files in its "data" subfolder.
.PARAMETER BindAddress
    Listen only on this IPv4 address of this PC. Default: all addresses; the firewall rule is
    what keeps it LAN-only. If you set this, reserve the address in your router's DHCP settings.
.PARAMETER BasicAuthUser
    Require a username and password (you'll be prompted for the password). Over plain HTTP this is
    a deterrent only: anyone on the network can read the credentials. Re-running without this
    parameter keeps the existing login; use -RemoveBasicAuth to remove it.
.PARAMETER RemoveBasicAuth
    Remove a previously configured login.
.PARAMETER SetNetworkPrivate
    If the connected network is classified Public, switch it to Private so the firewall rule applies.
.PARAMETER AllowSleep
    Don't change the PC's sleep settings.
.PARAMETER Uninstall
    Stop and remove the service and firewall rule. Files and data are left in place.
.EXAMPLE
    .\setup-data-server.ps1
.EXAMPLE
    .\setup-data-server.ps1 -Port 8090 -DataRoot D:\Datasets -BasicAuthUser kevin
.EXAMPLE
    .\setup-data-server.ps1 -Uninstall
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Setup helpers are not intended for -WhatIf use')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Switches are read inside helper functions')]
[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8080,

    [string]$InstallDir = 'C:\DataServer',

    [string]$DataRoot,

    [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}$')]
    [string]$BindAddress,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$BasicAuthUser,

    [switch]$RemoveBasicAuth,
    [switch]$SetNetworkPrivate,
    [switch]$AllowSleep,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Invoke-WebRequest is very slow with the progress bar in 5.1

Import-Module "$PSScriptRoot\lib\common.psm1" -Force
$LogFile = Join-Path $PSScriptRoot "setup-log-data-server-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
Set-LogFile -Path $LogFile

$CaddyVersion = '2.11.7'
# From https://github.com/caddyserver/caddy/releases/download/v2.11.7/caddy_2.11.7_checksums.txt
$CaddySha512 = @{
    'amd64' = 'c308154504e53755958ffc62d8a2657ab17eefd6dd25c45dbb2c3d93d29519971f77ca652f7d0f2bcb7f980b9ba3822478865e29969d0272d7613550a43152b1'
    'arm64' = '5e232f5fd68968c288034d98f8b4a6b16f246da6d5f1d3a8c7543b83327f1de0bf5d01d627768fbfd1dd254d7d53eb94589a40b126c29def10ac01365a3fe982'
}

$ServiceName = 'DataServer'
$FirewallRuleName = 'DataServer-HTTP-In'
$LocalServiceSid = '*S-1-5-19'

if (-not $DataRoot) { $DataRoot = Join-Path $InstallDir 'public' }
$BinDir = Join-Path $InstallDir 'caddy'
$CaddyExe = Join-Path $BinDir 'caddy.exe'
$ConfigPath = Join-Path $InstallDir 'Caddyfile'
$LogDir = Join-Path $InstallDir 'logs'
$StateDir = Join-Path $InstallDir 'state'
$DataDir = Join-Path $DataRoot 'data'
$TemplateDir = Join-Path $PSScriptRoot 'data-server'
$BinaryPath = "`"$CaddyExe`" run --config `"$ConfigPath`" --adapter caddyfile"

# Windows PowerShell 5.1 turns a native program's stderr into a terminating error when
# $ErrorActionPreference is Stop and stderr is redirected; Caddy logs to stderr.
function Invoke-Native {
    param([string]$FilePath, [string[]]$ArgumentList)
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    } finally {
        $ErrorActionPreference = $saved
    }
}

function ConvertTo-CaddyPath {
    param([string]$Path)
    # Caddyfile wants forward slashes; quote so paths with spaces work.
    return '"' + ($Path -replace '\\', '/') + '"'
}

function Get-CaddyArch {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { return 'amd64' }
        'ARM64' { return 'arm64' }
        default { throw "Unsupported processor architecture: $arch" }
    }
}

function Test-CaddyInstalled {
    if (-not (Test-Path $CaddyExe)) { return $false }
    $result = Invoke-Native $CaddyExe @('version')
    return ($result.ExitCode -eq 0 -and $result.Output -like "v$CaddyVersion*")
}

function Install-Caddy {
    $arch = Get-CaddyArch
    $zipName = "caddy_${CaddyVersion}_windows_$arch.zip"
    $url = "https://github.com/caddyserver/caddy/releases/download/v$CaddyVersion/$zipName"
    $work = Join-Path ([IO.Path]::GetTempPath()) "caddy-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $zip = Join-Path $work $zipName
        Write-Log "Downloading Caddy $CaddyVersion ($arch)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

        $actual = (Get-FileHash -Path $zip -Algorithm SHA512).Hash
        if ($actual -ne $CaddySha512[$arch]) {
            throw "Checksum mismatch for $zipName (got $actual). Not installing."
        }
        Write-Log "Checksum verified (SHA-512)" "SUCCESS"

        Expand-Archive -Path $zip -DestinationPath $work -Force
        Stop-DataServerService
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
        Copy-Item -Path (Join-Path $work 'caddy.exe') -Destination $CaddyExe -Force
        Write-Log "Installed $CaddyExe" "SUCCESS"
    } finally {
        Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Stop-DataServerService {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        Write-Log "Stopping $ServiceName service..."
        Stop-Service -Name $ServiceName -Force
        (Get-Service -Name $ServiceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }
}

function Get-PasswordHash {
    param([securestring]$Password)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $CaddyExe
    $psi.Arguments = 'hash-password'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    # Sent on stdin so the password never appears on a command line. Caddy keeps a
    # trailing CR as part of the password, so end the line with LF only.
    $proc.StandardInput.Write((ConvertFrom-SecureStringPlain $Password) + "`n")
    $proc.StandardInput.Close()
    $hash = $proc.StandardOutput.ReadToEnd().Trim()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0 -or $hash -notmatch '^\$2[aby]\$') {
        throw "caddy hash-password failed: $stderr"
    }
    return $hash
}

function ConvertFrom-SecureStringPlain {
    param([securestring]$Value)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-AuthBlock {
    if ($BasicAuthUser) {
        $first = Read-Host -AsSecureString "Password for $BasicAuthUser"
        $second = Read-Host -AsSecureString "Repeat password"
        if ((ConvertFrom-SecureStringPlain $first) -cne (ConvertFrom-SecureStringPlain $second)) {
            throw "Passwords didn't match."
        }
        if ((ConvertFrom-SecureStringPlain $first).Length -lt 8) { throw "Use a password of at least 8 characters." }
        $hash = Get-PasswordHash -Password $first
        Write-Log "Login enabled for user '$BasicAuthUser'" "SUCCESS"
        return "@authed not method OPTIONS`n`tbasic_auth @authed {`n`t`t$BasicAuthUser $hash`n`t}"
    }
    if ($RemoveBasicAuth -or -not (Test-Path $ConfigPath)) { return '' }

    # Keep the login from the previous run, so a plain re-run doesn't silently open the server up.
    $existing = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
    $m = [regex]::Match($existing, '(?m)^\s*basic_auth @authed \{\r?\n\s*(\S+ \S+)\r?\n\s*\}')
    if ($m.Success) {
        Write-Log "Keeping the existing login (use -RemoveBasicAuth to remove it)"
        return "@authed not method OPTIONS`n`tbasic_auth @authed {`n`t`t$($m.Groups[1].Value)`n`t}"
    }
    return ''
}

function Write-CaddyConfig {
    param([string]$AuthBlock)
    $template = Get-Content -Path (Join-Path $TemplateDir 'Caddyfile.template') -Raw -Encoding UTF8
    $bind = if ($BindAddress) { "bind $BindAddress" } else { '' }
    $values = @{
        '__PORT__'      = "$Port"
        '__DATA_ROOT__' = ConvertTo-CaddyPath $DataRoot
        '__LOG_FILE__'  = ConvertTo-CaddyPath (Join-Path $LogDir 'access.log')
        '__CADDY_LOG__' = ConvertTo-CaddyPath (Join-Path $LogDir 'caddy.log')
        '__STATE_DIR__' = ConvertTo-CaddyPath $StateDir
        '__BIND__'      = $bind
        '__AUTH__'      = $AuthBlock
    }
    $config = $template
    foreach ($key in $values.Keys) { $config = $config.Replace($key, $values[$key]) }

    $current = if (Test-Path $ConfigPath) { Get-Content -Path $ConfigPath -Raw -Encoding UTF8 } else { $null }
    if ($current -eq $config) {
        Write-Log "Config unchanged: $ConfigPath" "SUCCESS"
        return $false
    }
    # Validate a candidate first: a rejected config left in place would break the next
    # restart or reboot, and a re-run would then see it as unchanged.
    $candidate = "$ConfigPath.new"
    [IO.File]::WriteAllText($candidate, $config, (New-Object Text.UTF8Encoding $false))
    $result = Invoke-Native $CaddyExe @('validate', '--config', $candidate, '--adapter', 'caddyfile')
    if ($result.ExitCode -ne 0) {
        Remove-Item -Path $candidate -Force -ErrorAction SilentlyContinue
        throw "Caddy rejected the generated config (the current one is unchanged):`n$($result.Output)"
    }
    Move-Item -Path $candidate -Destination $ConfigPath -Force
    Write-Log "Wrote and validated $ConfigPath" "SUCCESS"
    return $true
}

function Initialize-Folder {
    foreach ($dir in @($InstallDir, $BinDir, $LogDir, $StateDir, $DataRoot, $DataDir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $index = Join-Path $DataRoot 'index.html'
    if (-not (Test-Path $index)) {
        Copy-Item -Path (Join-Path $TemplateDir 'index.html') -Destination $index
        Write-Log "Added landing page: $index" "SUCCESS"
    }
    # LocalService reads the program, config and data, and writes only logs and state. Inherited
    # permissions are left alone so your own access is unchanged.
    foreach ($grant in @(
            @{ Path = $InstallDir; Rights = '(OI)(CI)RX' },
            @{ Path = $DataRoot; Rights = '(OI)(CI)RX' },
            @{ Path = $LogDir; Rights = '(OI)(CI)M' },
            @{ Path = $StateDir; Rights = '(OI)(CI)M' })) {
        $result = Invoke-Native 'icacls.exe' @($grant.Path, '/grant', "${LocalServiceSid}:$($grant.Rights)", '/Q')
        if ($result.ExitCode -ne 0) { throw "icacls failed on $($grant.Path): $($result.Output)" }
    }
    Write-Log "Folder permissions set for the LocalService account" "SUCCESS"
}

# Returns $true if the service's command line or account changed (needs a restart).
function Install-DataServerService {
    if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
        New-Service -Name $ServiceName -BinaryPathName $BinaryPath -DisplayName 'Data Server (Caddy)' `
            -Description "Static data files for the home network on port $Port." -StartupType Automatic | Out-Null
        Write-Log "Created service $ServiceName" "SUCCESS"
    }
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'"
    $changed = ($svc.PathName -ne $BinaryPath) -or ($svc.StartName -ne 'NT AUTHORITY\LocalService')
    if ($changed) {
        # CIM rather than sc.exe: Windows PowerShell 5.1 drops the empty password argument sc.exe needs.
        $result = Invoke-CimMethod -InputObject $svc -MethodName Change -Arguments @{
            PathName      = $BinaryPath
            StartName     = 'NT AUTHORITY\LocalService'
            StartPassword = ''
        }
        if ($result.ReturnValue -ne 0) { throw "Updating service $ServiceName failed (Win32_Service.Change returned $($result.ReturnValue))" }
        Write-Log "Service runs as LocalService: $BinaryPath" "SUCCESS"
    }
    foreach ($arguments in @(
            @('config', $ServiceName, 'start=', 'delayed-auto'),
            @('failure', $ServiceName, 'reset=', '86400', 'actions=', 'restart/5000/restart/5000/restart/60000'))) {
        $result = Invoke-Native 'sc.exe' $arguments
        if ($result.ExitCode -ne 0) { throw "sc.exe $($arguments -join ' ') failed: $($result.Output)" }
    }
    Write-Log "Service starts at boot (delayed start) and restarts if it crashes" "SUCCESS"
    return $changed
}

function Start-DataServerService {
    param([bool]$Restart)
    $svc = Get-Service -Name $ServiceName
    if ($Restart -and $svc.Status -eq 'Running') {
        Restart-Service -Name $ServiceName -Force
    } elseif ($svc.Status -ne 'Running') {
        Start-Service -Name $ServiceName
    }
    (Get-Service -Name $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))

    $probeHost = if ($BindAddress) { $BindAddress } else { 'localhost' }
    $url = "http://${probeHost}:$Port/"
    for ($i = 0; $i -lt 10; $i++) {
        try {
            $code = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5).StatusCode
        } catch {
            $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        }
        if ($code -eq 200 -or $code -eq 401) {
            Write-Log "Server is answering at $url (HTTP $code)" "SUCCESS"
            return
        }
        Start-Sleep -Seconds 1
    }
    throw "Service is running but $url doesn't answer. See $(Join-Path $LogDir 'caddy.log') and the System event log."
}

function Set-FirewallRule {
    Remove-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name $FirewallRuleName -DisplayName "Data Server (TCP $Port)" `
        -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow `
        -Profile Private -RemoteAddress LocalSubnet -Program $CaddyExe | Out-Null
    Write-Log "Firewall: TCP $Port allowed on Private networks from the local subnet only" "SUCCESS"

    # Only the home network matters. Switching other Public networks (VPNs, virtual or
    # second adapters) to Private would open this and other Private-profile rules on them.
    $lanIndex = Get-LanInterfaceIndex
    if ($SetNetworkPrivate -and -not $lanIndex) {
        Write-Log "Couldn't tell which network is your home network, so none was switched. Re-run with -BindAddress <this PC's LAN IP>." "WARNING"
    }
    $public = @(Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' })
    foreach ($net in $public) {
        if (-not $lanIndex) {
            Write-Log "Network '$($net.Name)' is classified Public, so other devices can't connect through it." "WARNING"
        } elseif ($net.InterfaceIndex -ne $lanIndex) {
            Write-Log "Leaving network '$($net.Name)' as Public: it isn't the one this PC uses to reach your router"
        } elseif ($SetNetworkPrivate) {
            Set-NetConnectionProfile -InterfaceIndex $net.InterfaceIndex -NetworkCategory Private
            Write-Log "Network '$($net.Name)' switched from Public to Private" "SUCCESS"
        } else {
            Write-Log ("Network '$($net.Name)' is classified Public, so other devices can't connect. " +
                "If this is your home network, re-run with -SetNetworkPrivate.") "WARNING"
        }
    }
}

# The interface of -BindAddress; otherwise the one physical adapter with a default route
# through a real gateway. Full-tunnel VPNs add their own default route (often with a
# lower metric), so virtual adapters and on-link routes don't count. If that still leaves
# more than one candidate, return nothing rather than guess.
function Get-LanInterfaceIndex {
    if ($BindAddress) {
        return (Get-NetIPAddress -IPAddress $BindAddress).InterfaceIndex
    }
    $physical = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ifIndex)
    $candidates = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $physical -contains $_.InterfaceIndex -and $_.NextHop -ne '0.0.0.0' } |
        Select-Object -ExpandProperty InterfaceIndex -Unique)
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) {
        Write-Log "More than one network adapter has a route to the internet; use -BindAddress to pick your home network." "WARNING"
    }
    return $null
}

function Set-SleepPolicy {
    if ($AllowSleep) {
        Write-Log "Leaving sleep settings unchanged (-AllowSleep)"
        return
    }
    foreach ($setting in 'standby-timeout-ac', 'hibernate-timeout-ac') {
        $result = Invoke-Native 'powercfg.exe' @('/change', $setting, '0')
        if ($result.ExitCode -ne 0) { throw "powercfg /change $setting 0 failed: $($result.Output)" }
    }
    Write-Log "Sleep and hibernate disabled while on AC power, so the server stays reachable" "SUCCESS"
}

function Show-Summary {
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -ExpandProperty IPAddress)
    if ($BindAddress) { $ips = @($BindAddress) }
    $name = $env:COMPUTERNAME
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "  Data server is running" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "From other devices on your network, try:"
    Write-Host "  http://${name}:$Port/          (Windows PCs)"
    Write-Host "  http://$($name.ToLower()).local:$Port/    (Mac, iPhone, Linux)"
    foreach ($ip in $ips) { Write-Host "  http://${ip}:$Port/" }
    Write-Host ""
    Write-Host "If the name doesn't resolve, use the IP address. Reserve it in your router's DHCP"
    Write-Host "settings so it doesn't change."
    Write-Host ""
    Write-Host "Publish files by copying them into: $DataDir"
    Write-Host "Landing page:  $(Join-Path $DataRoot 'index.html')"
    Write-Host "Logs:          $LogDir"
    Write-Host "Manage:        Restart-Service $ServiceName  |  Get-Service $ServiceName"
    Write-Host "Remove:        .\setup-data-server.ps1 -Uninstall"
    Write-Host ""
}

function Uninstall-DataServer {
    Stop-DataServerService
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        $result = Invoke-Native 'sc.exe' @('delete', $ServiceName)
        if ($result.ExitCode -ne 0) { throw "sc.exe delete $ServiceName failed: $($result.Output)" }
        Write-Log "Removed service $ServiceName" "SUCCESS"
    }
    Remove-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue
    Write-Log "Removed firewall rule $FirewallRuleName" "SUCCESS"
    Write-Log "Left files in place: $InstallDir and $DataRoot. Sleep settings were not changed back."
}

try {
    Assert-Administrator

    if ($Uninstall) {
        Uninstall-DataServer
        exit 0
    }
    if ($BasicAuthUser -and $RemoveBasicAuth) { throw "Use either -BasicAuthUser or -RemoveBasicAuth, not both." }
    if ($BindAddress -and -not (Get-NetIPAddress -IPAddress $BindAddress -ErrorAction SilentlyContinue)) {
        throw "-BindAddress $BindAddress is not an address of this PC."
    }

    Write-Log "Setting up the data server on $env:COMPUTERNAME (port $Port)"
    Initialize-Folder
    $binaryChanged = $false
    if (Test-CaddyInstalled) {
        Write-Log "Caddy $CaddyVersion already installed" "SUCCESS"
    } else {
        Install-Caddy
        $binaryChanged = $true
    }
    $configChanged = Write-CaddyConfig -AuthBlock (Get-AuthBlock)
    $serviceChanged = Install-DataServerService
    Start-DataServerService -Restart ($binaryChanged -or $configChanged -or $serviceChanged)
    Set-FirewallRule
    Set-SleepPolicy
    Show-Summary
    Write-Log "Log saved to $LogFile"
} catch {
    Write-Log "Setup failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
