<#
.SYNOPSIS
    Common module for Catoconsting PowerShell setup scripts
.DESCRIPTION
    Contains shared functions and utilities used across PowerShell setup scripts
.NOTES
    Usage: Import this module from other scripts
    Import-Module "$PSScriptRoot\lib\common.psm1" -Force
#>

# Logging function
# Usage: Write-Log "message" ["level"]
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logMessage
    }
}

# Check if running as Administrator
# Returns $true if running as admin, $false otherwise
function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Require Administrator privileges
# Throws an error if not running as Administrator
function Require-Administrator {
    if (-NOT (Test-Administrator)) {
        Write-Log "This script requires Administrator privileges" "ERROR"
        throw "Administrator privileges required"
    }
}

# Install Chocolatey package manager if not present
function Install-Chocolatey {
    Write-Log "Checking for Chocolatey package manager..."
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Chocolatey package manager..."
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            Write-Log "Chocolatey installed successfully" "SUCCESS"

            # Refresh environment variables
            Update-EnvironmentPath
        } catch {
            Write-Log "Failed to install Chocolatey: $($_.Exception.Message)" "ERROR"
            throw
        }
    } else {
        Write-Log "Chocolatey is already installed" "SUCCESS"
    }
}

# Refresh environment PATH variable
function Update-EnvironmentPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Install Java JDK 17 (Microsoft distribution)
function Install-JavaJDK17 {
    Write-Log "Checking for Java JDK 17..."
    $javaVersion = $null
    try {
        $javaVersion = & java -version 2>&1 | Select-String "version" | ForEach-Object { $_.ToString() }
    } catch {
        Write-Log "Java not found"
    }

    if (-not $javaVersion -or $javaVersion -notmatch "17\.") {
        Write-Log "Installing Microsoft OpenJDK 17..."
        try {
            choco install microsoft-openjdk17 -y
            Write-Log "Java JDK 17 installed successfully" "SUCCESS"

            # Refresh environment
            Update-EnvironmentPath
        } catch {
            Write-Log "Failed to install Java JDK 17: $($_.Exception.Message)" "ERROR"
        }
    } else {
        Write-Log "Java JDK 17 is already installed: $javaVersion" "SUCCESS"
    }
}

# Set JAVA_HOME environment variable if not set
function Set-JavaHome {
    if (-not $env:JAVA_HOME) {
        Write-Log "Setting JAVA_HOME environment variable..."
        $javaPath = (Get-Command java -ErrorAction SilentlyContinue).Source
        if ($javaPath) {
            $javaHome = Split-Path (Split-Path $javaPath -Parent) -Parent
            [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "Machine")
            $env:JAVA_HOME = $javaHome
            Write-Log "JAVA_HOME set to: $javaHome" "SUCCESS"
        }
    }
}

# Export module members
Export-ModuleMember -Function Write-Log
Export-ModuleMember -Function Test-Administrator
Export-ModuleMember -Function Require-Administrator
Export-ModuleMember -Function Install-Chocolatey
Export-ModuleMember -Function Update-EnvironmentPath
Export-ModuleMember -Function Install-JavaJDK17
Export-ModuleMember -Function Set-JavaHome
