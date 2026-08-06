<#
.SYNOPSIS
    Windows Server VM setup script for Catoconsting deployment environment
.DESCRIPTION
    Sets up a Windows Server VM for deploying the Catoconsting Java web application including:
    - Java JDK 17 (Microsoft distribution) for running the application
    - IIS Web Server with URL Rewrite and ARR (Application Request Routing)
    - Firewall rules for web traffic
    - Application deployment directory structure
    - Windows Service configuration for Java application
    - Monitoring and logging setup
.PARAMETER ComputerName
    Name identifier for this server
.PARAMETER LogFile
    Path to the log file
#>

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

# Check if running as Administrator
Require-Administrator

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
Write-Log "Checking for IIS..."
$iisFeature = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
if ($iisFeature) {
    if ($iisFeature.Installed) {
        Write-Log "IIS is already installed" "SUCCESS"
    } else {
        Write-Log "Installing IIS Web Server..."
        try {
            Install-WindowsFeature -Name Web-Server -IncludeManagementTools
            Install-WindowsFeature -Name Web-Asp-Net45
            Install-WindowsFeature -Name Web-Net-Ext45
            Install-WindowsFeature -Name Web-ISAPI-Ext
            Install-WindowsFeature -Name Web-ISAPI-Filter
            Write-Log "IIS installed successfully" "SUCCESS"
        } catch {
            Write-Log "Failed to install IIS: $($_.Exception.Message)" "ERROR"
        }
    }
} else {
    Write-Log "IIS features not available on this system (may not be Windows Server)" "WARNING"
}

# Step 4: Install URL Rewrite Module for IIS (useful for reverse proxy)
Write-Log "Installing IIS URL Rewrite Module..."
try {
    choco install urlrewrite -y
    Write-Log "URL Rewrite module installed" "SUCCESS"
} catch {
    Write-Log "Failed to install URL Rewrite: $($_.Exception.Message)" "WARNING"
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

    # Set appropriate permissions
    $acl = Get-Acl $AppDir
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NETWORK SERVICE", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
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
        choco install nssm -y
        Write-Log "NSSM installed successfully" "SUCCESS"

        # Refresh environment
        Update-EnvironmentPath
    } else {
        Write-Log "NSSM is already installed" "SUCCESS"
    }
} catch {
    Write-Log "Failed to install NSSM: $($_.Exception.Message)" "WARNING"
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

Set-Content -Path $deployScriptPath -Value $deployScript
Write-Log "Deployment script created" "SUCCESS"

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

# Check if Java is available
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Error "Java is not installed or not in PATH"
    exit 1
}

# Remove existing service if it exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Removing existing service..."
    nssm remove $ServiceName confirm
}

# Create new service
Write-Host "Creating Windows Service: $ServiceName..."
nssm install $ServiceName java "-jar `"$JarFile`""
nssm set $ServiceName AppDirectory $AppDir
nssm set $ServiceName DisplayName "Catoconsting Web Application"
nssm set $ServiceName Description "Java web application for Catoconsting project"
nssm set $ServiceName Start SERVICE_AUTO_START
nssm set $ServiceName AppStdout (Join-Path $LogDir "service-stdout.log")
nssm set $ServiceName AppStderr (Join-Path $LogDir "service-stderr.log")
nssm set $ServiceName AppRotateFiles 1
nssm set $ServiceName AppRotateBytes 10485760  # 10 MB

Write-Host "Service created successfully!"
Write-Host "Starting service..."
Start-Service -Name $ServiceName

Write-Host "`nService Status:"
Get-Service -Name $ServiceName | Format-Table -AutoSize

Write-Host "`nService configured successfully!"
Write-Host "Logs location: $LogDir"
'@

Set-Content -Path $serviceScriptPath -Value $serviceScript
Write-Log "Service setup script created" "SUCCESS"

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

Set-Content -Path $configTemplatePath -Value $configTemplate
Write-Log "Configuration template created" "SUCCESS"

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

Set-Content -Path $readmePath -Value $readmeContent
Write-Log "Operations README created" "SUCCESS"

# Step 12: Verify installations
Write-Log "`n=== Verification of Installed Components ===" "INFO"
Write-Log "Verifying Java..."
try {
    $javaCheck = & java -version 2>&1 | Out-String
    Write-Log "Java: OK" "SUCCESS"
} catch {
    Write-Log "Java: FAILED" "ERROR"
}

Write-Log "Verifying IIS..."
try {
    $iisCheck = Get-Service W3SVC -ErrorAction Stop
    Write-Log "IIS: $($iisCheck.Status)" "SUCCESS"
} catch {
    Write-Log "IIS: Not available" "WARNING"
}

Write-Log "Verifying NSSM..."
try {
    $nssmCheck = Get-Command nssm -ErrorAction Stop
    Write-Log "NSSM: OK" "SUCCESS"
} catch {
    Write-Log "NSSM: FAILED" "WARNING"
}

# Summary
Write-Host "`n================================================" -ForegroundColor Green
Write-Host "   Windows Server Setup Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host "Server Configuration:" -ForegroundColor Cyan
Write-Host "  - Java JDK 17 (Microsoft OpenJDK)" -ForegroundColor White
Write-Host "  - IIS Web Server" -ForegroundColor White
Write-Host "  - URL Rewrite Module" -ForegroundColor White
Write-Host "  - NSSM Service Manager" -ForegroundColor White
Write-Host "  - Firewall rules configured" -ForegroundColor White
Write-Host "`nApplication Directory: $AppDir" -ForegroundColor Yellow
Write-Host "`nDeployment Scripts Created:" -ForegroundColor Cyan
Write-Host "  - $deployScriptPath" -ForegroundColor White
Write-Host "  - $serviceScriptPath" -ForegroundColor White
Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Deploy your JAR file using: .\deploy.ps1 -JarPath <path-to-jar>" -ForegroundColor White
Write-Host "  2. Set up Windows Service: .\setup-service.ps1" -ForegroundColor White
Write-Host "  3. Configure application properties in: $ConfigDir" -ForegroundColor White
Write-Host "  4. Monitor logs in: $LogDir" -ForegroundColor White
Write-Host "  5. Access application at: http://$ComputerName:8080" -ForegroundColor White
Write-Host "`nRefer to: $readmePath for operational guide" -ForegroundColor Yellow
Write-Host "================================================`n" -ForegroundColor Green

Write-Log "=== Windows Server VM Setup Completed ===" "SUCCESS"
