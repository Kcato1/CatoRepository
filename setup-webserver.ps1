<#
.SYNOPSIS
    Simple web server setup script for testing and development
.DESCRIPTION
    Installs Node.js and http-server for quick local web server setup.
    Useful for testing static websites, HTML files, and web applications.

    Administrator rights are only needed when Node.js still has to be
    installed. http-server is installed for the account running the script,
    so run it as the person who will use it.

    Safe to run again: installed tools are skipped, and the script exits with
    code 1 if a step failed.
.PARAMETER Port
    Port number for the web server (default: 8080)
.PARAMETER Directory
    Directory to serve (default: current directory)
.PARAMETER Address
    Address to listen on (default: 127.0.0.1, this computer only). Use 0.0.0.0
    to share the directory with other machines on the network.
.PARAMETER Start
    Automatically start the web server after installation
.EXAMPLE
    .\setup-webserver.ps1
.EXAMPLE
    .\setup-webserver.ps1 -Port 3000 -Start
.EXAMPLE
    .\setup-webserver.ps1 -Directory "C:\Projects\MyApp" -Port 8080 -Start
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script')]
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,

    [Parameter(Mandatory=$false)]
    [string]$Directory = (Get-Location).Path,

    [Parameter(Mandatory=$false)]
    [string]$Address = "127.0.0.1",

    [Parameter(Mandatory=$false)]
    [switch]$Start
)

$ErrorActionPreference = "Stop"

# Import common module
Import-Module "$PSScriptRoot\lib\common.psm1" -Force

if (-not (Test-Path -Path $Directory -PathType Container)) {
    Write-Log "Directory not found: $Directory" "ERROR"
    exit 1
}
$Directory = (Resolve-Path -Path $Directory).Path

# Banner
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "   Simple Web Server Setup" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Port: $Port" -ForegroundColor Yellow
Write-Host "Directory: $Directory" -ForegroundColor Yellow
Write-Host "Address: $Address" -ForegroundColor Yellow
Write-Host "================================================`n" -ForegroundColor Cyan

try {
    # Steps 1-2: Node.js (and Chocolatey to install it). Only this part needs Administrator.
    Write-Log "Checking for Node.js..."
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Log "Node.js is already installed: $(& node --version)" "SUCCESS"
    } else {
        if (-not (Test-Administrator)) {
            Write-Log "Node.js is not installed. Run this script as Administrator once to install it, then again as your normal user." "ERROR"
            Write-Host "Or install Node.js yourself, then run: npm install -g http-server" -ForegroundColor Yellow
            exit 1
        }
        Install-Chocolatey
        Write-Log "Installing Node.js LTS..."
        Invoke-ChocoInstall -Package nodejs-lts
        Update-EnvironmentPath
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
            throw "node was not found on PATH after installing Node.js"
        }
        Write-Log "Node.js installed: $(& node --version)" "SUCCESS"
    }

    # Step 3: Check npm
    Write-Log "Verifying npm..."
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "npm is required but was not found. Please reinstall Node.js"
    }
    Write-Log "npm version: $(& npm --version)" "SUCCESS"

    # Step 4: Install http-server for this user (npm -g installs into the user's profile)
    Write-Log "Checking for http-server..."
    if (Get-Command http-server -ErrorAction SilentlyContinue) {
        Write-Log "http-server is already installed" "SUCCESS"
    } else {
        if ((Test-Administrator)) {
            Write-Log "Installing http-server for $([Security.Principal.WindowsIdentity]::GetCurrent().Name); other accounts need to run this script themselves" "WARNING"
        }
        Write-Log "Installing http-server globally..."
        & npm install -g http-server
        if ($LASTEXITCODE -ne 0) {
            throw "npm install -g http-server failed with exit code $LASTEXITCODE"
        }
        Update-EnvironmentPath
        Write-Log "http-server installed successfully" "SUCCESS"
    }

    # Step 5: Verify http-server installation
    if (-not (Get-Command http-server -ErrorAction SilentlyContinue)) {
        throw "http-server is not on PATH; open a new terminal and run this script again"
    }
    $httpServerVersion = & http-server --version
    if ($LASTEXITCODE -ne 0) {
        throw "http-server --version failed with exit code $LASTEXITCODE"
    }
    Write-Log "http-server version: $httpServerVersion" "SUCCESS"
} catch {
    Write-Log "Setup failed: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Summary
Write-Host "`n================================================" -ForegroundColor Green
Write-Host "   Web Server Setup Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host "`nInstalled Components:" -ForegroundColor Cyan
Write-Host "  - Node.js (LTS)" -ForegroundColor White
Write-Host "  - npm" -ForegroundColor White
Write-Host "  - http-server" -ForegroundColor White
Write-Host "`nUsage Options:" -ForegroundColor Cyan
Write-Host "`n  Option 1: Use the wrapper script" -ForegroundColor Yellow
Write-Host "    .\start-webserver.ps1" -ForegroundColor White
Write-Host "    .\start-webserver.ps1 -Port 3000" -ForegroundColor White
Write-Host "    .\start-webserver.ps1 -Port 8080 -Open" -ForegroundColor White
Write-Host "    .\start-webserver.ps1 -Address 0.0.0.0   (share on the network)" -ForegroundColor White
Write-Host "`n  Option 2: Use http-server directly" -ForegroundColor Yellow
Write-Host "    http-server -a 127.0.0.1 -p 8080" -ForegroundColor White
Write-Host "    http-server -a 127.0.0.1 -p 8080 -o" -ForegroundColor White
Write-Host "    http-server ./public -a 127.0.0.1 -p 3000" -ForegroundColor White
Write-Host "`n  Common Options:" -ForegroundColor Yellow
Write-Host "    -p <port>    Port number (default: 8080)" -ForegroundColor White
Write-Host "    -a <address> Address to listen on (http-server's own default is 0.0.0.0, every network)" -ForegroundColor White
Write-Host "    -o           Open browser automatically" -ForegroundColor White
Write-Host "    -c-1         Disable caching" -ForegroundColor White
Write-Host "    --cors       Enable CORS" -ForegroundColor White
Write-Host "    -g or --gzip Enable gzip compression" -ForegroundColor White
Write-Host "`n================================================`n" -ForegroundColor Green

# Step 6: Optionally start the server
$startScript = Join-Path $PSScriptRoot "start-webserver.ps1"
if ($Start) {
    & $startScript -Port $Port -Directory $Directory -Address $Address
} else {
    Write-Host "To start the server, run:" -ForegroundColor Yellow
    Write-Host "  .\start-webserver.ps1 -Port $Port -Directory `"$Directory`"" -ForegroundColor Cyan
    Write-Host "Or:" -ForegroundColor Yellow
    Write-Host "  http-server `"$Directory`" -a $Address -p $Port`n" -ForegroundColor Cyan
}
exit 0
