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

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot
$LogFile = Join-Path $ScriptRoot "setup-log-$ComputerName-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

# Import common module
Import-Module "$PSScriptRoot\lib\common.psm1" -Force

# Require Administrator
Require-Administrator

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
