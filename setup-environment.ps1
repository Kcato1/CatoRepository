<#
.SYNOPSIS
    Main setup script for Catoconsting project environments
.DESCRIPTION
    Orchestrates the setup of Windows environments for the Catoconsting Java web application.
    Supports both Desktop PCs (development) and Windows Server VMs (deployment).
.PARAMETER Environment
    The environment type: 'Desktop' or 'Server'
.PARAMETER ComputerName
    Optional name to identify this computer (e.g., 'Desktop-1', 'Desktop-2', 'Server-VM')
.EXAMPLE
    .\setup-environment.ps1 -Environment Desktop -ComputerName "Desktop-1"
.EXAMPLE
    .\setup-environment.ps1 -Environment Server -ComputerName "Server-VM"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Desktop', 'Server')]
    [string]$Environment,

    [Parameter(Mandatory=$false)]
    [string]$ComputerName = $env:COMPUTERNAME
)

# Require Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot
$LogFile = Join-Path $ScriptRoot "setup-log-$ComputerName-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

# Banner
function Show-Banner {
    Write-Host "`n================================================" -ForegroundColor Cyan
    Write-Host "   Catoconsting Environment Setup" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Environment: $Environment" -ForegroundColor Yellow
    Write-Host "Computer: $ComputerName" -ForegroundColor Yellow
    Write-Host "Log File: $LogFile" -ForegroundColor Yellow
    Write-Host "================================================`n" -ForegroundColor Cyan
}

# Main execution
try {
    Show-Banner
    Write-Log "Starting setup for $Environment environment on $ComputerName"

    # Determine which setup script to run
    $setupScript = switch ($Environment) {
        'Desktop' { Join-Path $ScriptRoot "setup-desktop.ps1" }
        'Server'  { Join-Path $ScriptRoot "setup-server.ps1" }
    }

    # Verify setup script exists
    if (-not (Test-Path $setupScript)) {
        throw "Setup script not found: $setupScript"
    }

    Write-Log "Executing setup script: $setupScript"

    # Execute the appropriate setup script
    & $setupScript -ComputerName $ComputerName -LogFile $LogFile

    Write-Log "Setup completed successfully!" "SUCCESS"
    Write-Host "`n================================================" -ForegroundColor Green
    Write-Host "   Setup Completed Successfully!" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "Review the log file for details: $LogFile`n" -ForegroundColor Yellow

} catch {
    Write-Log "Setup failed: $($_.Exception.Message)" "ERROR"
    Write-Host "`n================================================" -ForegroundColor Red
    Write-Host "   Setup Failed!" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check log file: $LogFile`n" -ForegroundColor Yellow
    exit 1
}
