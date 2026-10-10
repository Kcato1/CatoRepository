<#
.SYNOPSIS
    Windows Server VM setup script for Catoconsting deployment environment
.DESCRIPTION
    Sets up a Windows Server VM for deploying the Catoconsting Java web application including:
    - Java JDK 17 (Microsoft distribution) for running the application
    - IIS Web Server with URL Rewrite
    - Firewall rules for web traffic
    - Application deployment directory structure
    - Windows Service configuration for Java application
    - Monitoring and logging setup

    Safe to run again: steps that are already done are skipped, generated
    helper files are only rewritten when their content changes (the old copy is
    kept as .bak), and the script exits with code 1 if any step failed.
.PARAMETER ComputerName
    Name identifier for this server
.PARAMETER LogFile
    Path to the log file (defaults to a timestamped file next to this script)
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script')]
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false)]
    [string]$LogFile
)

$ErrorActionPreference = "Continue"

# Import common module
Import-Module "$PSScriptRoot\lib\common.psm1" -Force
if (-not $LogFile) {
    $LogFile = Join-Path $PSScriptRoot "setup-log-$ComputerName-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
}
Set-LogFile -Path $LogFile

# Check if running as Administrator
Assert-Administrator

# Check if running on Windows Server
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$isServer = $osInfo.ProductType -eq 2 -or $osInfo.ProductType -eq 3
if (-not $isServer) {
    Write-Log "Warning: This script is designed for Windows Server. Current OS: $($osInfo.Caption)" "WARNING"
}

Write-Log "=== Windows Server VM Setup Started ===" "INFO"
Write-Log "Server Name: $ComputerName"
Write-Log "OS: $($osInfo.Caption)"

# Configuration variables
$AppName = "Catoconsting"
$DeploymentRoot = "C:\Apps"
$AppDir = Join-Path $DeploymentRoot $AppName
$LogDir = Join-Path $AppDir "logs"
$ConfigDir = Join-Path $AppDir "config"

# Step 1: Install Chocolatey if not present
Install-Chocolatey

# Step 2: Install Java JDK 17 (Microsoft distribution)
Install-JavaJDK17

# Set JAVA_HOME if not set
Set-JavaHome

# Step 3: Install IIS Web Server and components
# Every feature is requested on every run: Install-WindowsFeature skips the
# ones already present, so a partly finished earlier run gets completed.
Write-Log "Checking for IIS..."
$iisInstalled = $false
$iisFeatures = @('Web-Server', 'Web-Asp-Net45', 'Web-Net-Ext45', 'Web-ISAPI-Ext', 'Web-ISAPI-Filter')
if (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue) {
    try {
        $missing = @(Get-WindowsFeature -Name $iisFeatures | Where-Object { -not $_.Installed } | ForEach-Object { $_.Name })
        if ($missing.Count -eq 0) {
            Write-Log "IIS and all required features are already installed" "SUCCESS"
        } else {
            Write-Log "Installing IIS features: $($missing -join ', ')..."
            $result = Install-WindowsFeature -Name $iisFeatures -IncludeManagementTools -ErrorAction Stop
            if (-not $result.Success) {
                throw "Install-WindowsFeature reported failure (exit code $($result.ExitCode))"
            }
            if ($result.RestartNeeded -eq 'Yes') {
                Write-Log "IIS installed but Windows needs a restart to finish" "WARNING"
            }
            Write-Log "IIS installed successfully" "SUCCESS"
        }
        $iisInstalled = $true
    } catch {
        Write-Log "Failed to install IIS: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "IIS features not available on this system (Install-WindowsFeature needs Windows Server)" "WARNING"
}

# Step 4: Install URL Rewrite Module for IIS (useful for reverse proxy)
Write-Log "Checking for IIS URL Rewrite Module..."
if (-not $iisInstalled) {
    Write-Log "Skipping URL Rewrite: IIS is not installed" "WARNING"
} elseif (Test-ChocoPackage -Package urlrewrite) {
    Write-Log "URL Rewrite module is already installed" "SUCCESS"
} else {
    try {
        Invoke-ChocoInstall -Package urlrewrite
        Write-Log "URL Rewrite module installed" "SUCCESS"
    } catch {
        Write-Log "Failed to install URL Rewrite: $($_.Exception.Message)" "WARNING"
    }
}

# Step 5: Create application directory structure
Write-Log "Creating application directory structure..."
try {
    @($DeploymentRoot, $AppDir, $LogDir, $ConfigDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Log "Created directory: $_" "SUCCESS"
        } else {
            Write-Log "Directory already exists: $_" "SUCCESS"
        }
    }

    # Set appropriate permissions (by SID so it works on non-English Windows)
    $networkService = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-20")
    $acl = Get-Acl $AppDir
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $networkService, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.SetAccessRule($accessRule)
    Set-Acl $AppDir $acl
    Write-Log "Set permissions for NETWORK SERVICE on $AppDir" "SUCCESS"

} catch {
    Write-Log "Failed to create directory structure: $($_.Exception.Message)" "ERROR"
}

# Step 6: Configure Windows Firewall rules
Write-Log "Configuring firewall rules..."
try {
    # Allow HTTP traffic (port 80)
    $httpRule = Get-NetFirewallRule -DisplayName "Catoconsting HTTP" -ErrorAction SilentlyContinue
    if (-not $httpRule) {
        New-NetFirewallRule -DisplayName "Catoconsting HTTP" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 80 `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Log "Created firewall rule for HTTP (port 80)" "SUCCESS"
    } else {
        Write-Log "Firewall rule for HTTP already exists" "SUCCESS"
    }

    # Allow HTTPS traffic (port 443)
    $httpsRule = Get-NetFirewallRule -DisplayName "Catoconsting HTTPS" -ErrorAction SilentlyContinue
    if (-not $httpsRule) {
        New-NetFirewallRule -DisplayName "Catoconsting HTTPS" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 443 `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Log "Created firewall rule for HTTPS (port 443)" "SUCCESS"
    } else {
        Write-Log "Firewall rule for HTTPS already exists" "SUCCESS"
    }

    # Allow Java application port (8080) - typical for Spring Boot apps
    $javaRule = Get-NetFirewallRule -DisplayName "Catoconsting Java App" -ErrorAction SilentlyContinue
    if (-not $javaRule) {
        New-NetFirewallRule -DisplayName "Catoconsting Java App" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 8080 `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Log "Created firewall rule for Java App (port 8080)" "SUCCESS"
    } else {
        Write-Log "Firewall rule for Java App already exists" "SUCCESS"
    }

} catch {
    Write-Log "Failed to configure firewall rules: $($_.Exception.Message)" "ERROR"
}

# Step 7: Install NSSM (Non-Sucking Service Manager) for running Java app as Windows Service
Write-Log "Installing NSSM (Service Manager)..."
try {
    if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
        Invoke-ChocoInstall -Package nssm
        Write-Log "NSSM installed successfully" "SUCCESS"

        # Refresh environment
        Update-EnvironmentPath
    } else {
        Write-Log "NSSM is already installed" "SUCCESS"
    }
} catch {
    Write-Log "Failed to install NSSM: $($_.Exception.Message)" "ERROR"
}

# Step 8: Create deployment script
$deployScriptPath = Join-Path $AppDir "deploy.ps1"
Write-Log "Creating deployment script: $deployScriptPath"
$deployScript = @'
# Catoconsting Deployment Script
# This script deploys the JAR file and restarts the application service

param(
    [Parameter(Mandatory=$true)]
    [string]$JarPath
)

$AppName = "Catoconsting"
$AppDir = "C:\Apps\Catoconsting"
$ServiceName = "CatoconstingService"

Write-Host "Deploying $AppName..."

# Verify JAR file exists
if (-not (Test-Path $JarPath)) {
    Write-Error "JAR file not found: $JarPath"
    exit 1
}

# Stop service if it exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "Stopping $ServiceName..."
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 5
}

# Copy JAR file
$targetJar = Join-Path $AppDir "app.jar"
Write-Host "Copying JAR to $targetJar..."
Copy-Item -Path $JarPath -Destination $targetJar -Force

# Start service if it exists
if ($service) {
    Write-Host "Starting $ServiceName..."
    Start-Service -Name $ServiceName
    Write-Host "Deployment completed successfully!"
} else {
    Write-Host "Service not configured. JAR deployed to: $targetJar"
    Write-Host "Run setup-service.ps1 to configure the Windows Service"
}
'@

Set-FileIfChanged -Path $deployScriptPath -Value $deployScript

# Step 9: Create service setup script
$serviceScriptPath = Join-Path $AppDir "setup-service.ps1"
Write-Log "Creating service setup script: $serviceScriptPath"
$serviceScript = @'
# Catoconsting Windows Service Setup Script
# Creates a Windows Service to run the Java application

$AppName = "Catoconsting"
$ServiceName = "CatoconstingService"
$AppDir = "C:\Apps\Catoconsting"
$JarFile = Join-Path $AppDir "app.jar"
$LogDir = Join-Path $AppDir "logs"

# Check if JAR exists
if (-not (Test-Path $JarFile)) {
    Write-Error "Application JAR not found: $JarFile"
    Write-Host "Please deploy your application first using deploy.ps1"
    exit 1
}

# Find java.exe: the service does not inherit this console's PATH
$javaHome = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
$JavaExe = if ($javaHome) { Join-Path $javaHome "bin\java.exe" } else { $null }
if (-not $JavaExe -or -not (Test-Path $JavaExe)) {
    $JavaExe = (Get-Command java -ErrorAction SilentlyContinue).Source
}
if (-not $JavaExe) {
    Write-Error "Java is not installed (set JAVA_HOME or add java to PATH)"
    exit 1
}

# Run an nssm command and stop if it fails
function Invoke-Nssm {
    & nssm @args
    if ($LASTEXITCODE -ne 0) {
        Write-Error "nssm $($args -join ' ') failed with exit code $LASTEXITCODE"
        exit 1
    }
}

# Remove existing service if it exists. Stop it first: removing a running
# service only marks it for deletion and the install below would then fail.
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Removing existing service..."
    if ($existingService.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
    }
    Invoke-Nssm remove $ServiceName confirm
    for ($i = 0; $i -lt 30 -and (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue); $i++) {
        Start-Sleep -Seconds 1
    }
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Error "Service $ServiceName is still being removed; close any Services windows and run this script again"
        exit 1
    }
}

# Create new service
Write-Host "Creating Windows Service: $ServiceName..."
Invoke-Nssm install $ServiceName $JavaExe "-jar `"$JarFile`""
Invoke-Nssm set $ServiceName AppDirectory $AppDir
Invoke-Nssm set $ServiceName DisplayName "Catoconsting Web Application"
Invoke-Nssm set $ServiceName Description "Java web application for Catoconsting project"
Invoke-Nssm set $ServiceName Start SERVICE_AUTO_START
Invoke-Nssm set $ServiceName AppStdout (Join-Path $LogDir "service-stdout.log")
Invoke-Nssm set $ServiceName AppStderr (Join-Path $LogDir "service-stderr.log")
Invoke-Nssm set $ServiceName AppRotateFiles 1
Invoke-Nssm set $ServiceName AppRotateBytes 10485760  # 10 MB

Write-Host "Service created successfully!"
Write-Host "Starting service..."
Start-Service -Name $ServiceName

Write-Host "`nService Status:"
Get-Service -Name $ServiceName | Format-Table -AutoSize

Write-Host "`nService configured successfully!"
Write-Host "Logs location: $LogDir"
'@

Set-FileIfChanged -Path $serviceScriptPath -Value $serviceScript

# Step 10: Create application configuration template
$configTemplatePath = Join-Path $ConfigDir "application.properties.template"
Write-Log "Creating configuration template: $configTemplatePath"
$configTemplate = @'
# Catoconsting Application Configuration Template
# Copy this file to application.properties and customize for your environment

# Server Configuration
server.port=8080
server.address=0.0.0.0

# Logging Configuration
logging.level.root=INFO
logging.level.com.catoconsting=DEBUG
logging.file.name=C:/Apps/Catoconsting/logs/application.log
logging.pattern.console=%d{yyyy-MM-dd HH:mm:ss} - %msg%n
logging.pattern.file=%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n

# Application Name
spring.application.name=Catoconsting

# Add your application-specific configuration below
'@

Set-FileIfChanged -Path $configTemplatePath -Value $configTemplate

# Step 11: Create README for server operations
$readmePath = Join-Path $AppDir "README.txt"
$readmeContent = @"
====================================================
  Catoconsting Server - Operational Guide
====================================================

Application Directory: $AppDir
Logs Directory: $LogDir
Configuration Directory: $ConfigDir

DEPLOYMENT STEPS:
-----------------
1. Copy your JAR file to this server
2. Run deployment script:
   .\deploy.ps1 -JarPath "path\to\your\app.jar"

WINDOWS SERVICE SETUP:
----------------------
1. Ensure JAR is deployed (see above)
2. Run service setup script:
   .\setup-service.ps1

SERVICE MANAGEMENT:
-------------------
Start:   Start-Service CatoconstingService
Stop:    Stop-Service CatoconstingService
Restart: Restart-Service CatoconstingService
Status:  Get-Service CatoconstingService

LOGS LOCATION:
--------------
Application Logs: $LogDir\application.log
Service StdOut:   $LogDir\service-stdout.log
Service StdErr:   $LogDir\service-stderr.log

FIREWALL RULES:
---------------
HTTP (80):      Enabled
HTTPS (443):    Enabled
Java App (8080): Enabled

TROUBLESHOOTING:
----------------
1. Check service status: Get-Service CatoconstingService
2. Check logs in: $LogDir
3. Verify Java: java -version
4. Test JAR manually: java -jar $AppDir\app.jar

IMPORTANT NOTES:
----------------
- Always test deployments in a non-production environment first
- Keep backups of your JAR files
- Monitor logs regularly
- Ensure sufficient disk space for logs

====================================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
====================================================
"@

Set-FileIfChanged -Path $readmePath -Value $readmeContent -IgnorePattern '^Generated: '

# Step 12: Verify installations
Write-Log "`n=== Verification of Installed Components ===" "INFO"
Write-Log "Verifying Java..."
if (Get-Command java -ErrorAction SilentlyContinue) {
    & java -version 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Java: OK" "SUCCESS"
    } else {
        Write-Log "Java: FAILED (exit code $LASTEXITCODE)" "ERROR"
    }
} else {
    Write-Log "Java: not found on PATH" "ERROR"
}

Write-Log "Verifying IIS..."
try {
    $iisCheck = Get-Service W3SVC -ErrorAction Stop
    Write-Log "IIS: $($iisCheck.Status)" "SUCCESS"
} catch {
    Write-Log "IIS: Not available" "WARNING"
}

Write-Log "Verifying NSSM..."
if (Get-Command nssm -ErrorAction SilentlyContinue) {
    Write-Log "NSSM: OK" "SUCCESS"
} else {
    Write-Log "NSSM: not found on PATH" "WARNING"
}

# Summary
$failures = Get-SetupFailure
$color = if ($failures) { "Yellow" } else { "Green" }
Write-Host "`n================================================" -ForegroundColor $color
if ($failures) {
    Write-Host "   Windows Server Setup Finished With Errors" -ForegroundColor $color
} else {
    Write-Host "   Windows Server Setup Complete!" -ForegroundColor $color
}
Write-Host "================================================" -ForegroundColor $color
Write-Host "Server Configuration:" -ForegroundColor Cyan
Write-Host "  - Java JDK 17 (Microsoft OpenJDK)" -ForegroundColor White
Write-Host "  - IIS Web Server" -ForegroundColor White
Write-Host "  - URL Rewrite Module" -ForegroundColor White
Write-Host "  - NSSM Service Manager" -ForegroundColor White
Write-Host "  - Firewall rules configured" -ForegroundColor White
if ($failures) {
    Write-Host "`nFailed steps:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Fix the problems above and run the script again; finished steps are skipped." -ForegroundColor Yellow
}
Write-Host "`nApplication Directory: $AppDir" -ForegroundColor Yellow
Write-Host "`nDeployment Scripts Created:" -ForegroundColor Cyan
Write-Host "  - $deployScriptPath" -ForegroundColor White
Write-Host "  - $serviceScriptPath" -ForegroundColor White
Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Deploy your JAR file using: .\deploy.ps1 -JarPath <path-to-jar>" -ForegroundColor White
Write-Host "  2. Set up Windows Service: .\setup-service.ps1" -ForegroundColor White
Write-Host "  3. Configure application properties in: $ConfigDir" -ForegroundColor White
Write-Host "  4. Monitor logs in: $LogDir" -ForegroundColor White
Write-Host "  5. Access application at: http://${ComputerName}:8080" -ForegroundColor White
Write-Host "`nRefer to: $readmePath for operational guide" -ForegroundColor Yellow
Write-Host "Log File: $LogFile" -ForegroundColor Yellow
Write-Host "================================================`n" -ForegroundColor $color

if ($failures) {
    Write-Log "=== Windows Server VM Setup Finished With $($failures.Count) Failed Step(s) ===" "WARNING"
    exit 1
}
Write-Log "=== Windows Server VM Setup Completed ===" "SUCCESS"
exit 0
