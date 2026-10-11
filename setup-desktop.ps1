<#
.SYNOPSIS
    Desktop PC setup script for Catoconsting development environment
.DESCRIPTION
    Sets up a development environment on Windows desktop PCs including:
    - Chocolatey package manager
    - Java JDK 17 (Microsoft distribution)
    - Apache Maven
    - Git for Windows
    - Visual Studio Code (optional)
    - Project repository clone and configuration

    Safe to run again: steps that are already done are skipped, and the script
    exits with code 1 if any step failed.
.PARAMETER ComputerName
    Name identifier for this computer
.PARAMETER LogFile
    Path to the log file (defaults to a timestamped file next to this script)
.PARAMETER GitUserName
    Git user.name to configure instead of prompting
.PARAMETER GitUserEmail
    Git user.email to configure instead of prompting
.PARAMETER RepoUrl
    Repository to clone into the workspace instead of prompting
.PARAMETER NonInteractive
    Never prompt; steps with missing values are skipped
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script')]
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false)]
    [string]$LogFile,

    [string]$GitUserName,
    [string]$GitUserEmail,
    [string]$RepoUrl,
    [switch]$NonInteractive
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

Write-Log "=== Desktop PC Setup Started ===" "INFO"
Write-Log "Computer Name: $ComputerName"

# Per-user settings (Git config, VS Code extensions, workspace) belong to the
# account that runs them, so note who this window runs as and who is signed in.
$runningAs = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$consoleUser = $null
Write-Log "Running as: $runningAs"
try {
    $consoleUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
} catch {
    Write-Log "Could not determine the signed-in user: $($_.Exception.Message)" "WARNING"
}

# Install a Chocolatey package if its command is not on PATH
function Install-ChocoTool {
    param([string]$Command, [string]$Package, [string]$DisplayName)
    Write-Log "Checking for $DisplayName..."
    if (Get-Command $Command -ErrorAction SilentlyContinue) {
        Write-Log "$DisplayName is already installed" "SUCCESS"
        return
    }
    Write-Log "Installing $DisplayName..."
    try {
        Invoke-ChocoInstall -Package $Package
        Update-EnvironmentPath
        Write-Log "$DisplayName installed successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to install ${DisplayName}: $($_.Exception.Message)" "ERROR"
    }
}

# Step 1: Install Chocolatey if not present
Install-Chocolatey

# Step 2: Install Java JDK 17 (Microsoft distribution)
Install-JavaJDK17

# Set JAVA_HOME if not set
Set-JavaHome

# Step 3: Install Apache Maven
Install-ChocoTool -Command mvn -Package maven -DisplayName "Apache Maven"

# Step 4: Install Git for Windows
Install-ChocoTool -Command git -Package git -DisplayName "Git for Windows"

# Step 5: Install Visual Studio Code (optional but recommended)
Write-Log "Checking for Visual Studio Code..."
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Visual Studio Code..."
    try {
        Invoke-ChocoInstall -Package vscode
        Update-EnvironmentPath
        Write-Log "VS Code installed successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to install VS Code: $($_.Exception.Message)" "WARNING"
    }
} else {
    Write-Log "VS Code is already installed" "SUCCESS"
}

# Step 6: per-user setup (VS Code extensions, Git config, workspace, clone).
# These belong to whoever runs them, so they only run here when the elevated
# account is the signed-in user; otherwise that user runs the script themselves.
$userScript = Join-Path $PSScriptRoot "setup-desktop-user.ps1"
$userSetupSkipped = $consoleUser -and $consoleUser -ne $runningAs
if ($userSetupSkipped) {
    Write-Log "Skipping per-user setup: this window is elevated as $runningAs, not the signed-in user $consoleUser" "WARNING"
    Write-Log "As $consoleUser, run in a normal PowerShell window: .\setup-desktop-user.ps1" "WARNING"
} else {
    $userArgs = @{ LogFile = $LogFile }
    foreach ($name in 'GitUserName', 'GitUserEmail', 'RepoUrl', 'NonInteractive') {
        if ($PSBoundParameters.ContainsKey($name)) { $userArgs[$name] = $PSBoundParameters[$name] }
    }
    # Failures are recorded in the shared module, so the summary below includes
    # them; the script's own exit code is not needed here.
    & $userScript @userArgs
}

# Step 7: Verify installations
Write-Log "`n=== Verification of Installed Components ===" "INFO"
foreach ($check in @(
    @{ Name = 'Java';  Command = 'java'; Arguments = @('-version') },
    @{ Name = 'Maven'; Command = 'mvn';  Arguments = @('-version') },
    @{ Name = 'Git';   Command = 'git';  Arguments = @('--version') }
)) {
    Write-Log "Verifying $($check.Name)..."
    if (-not (Get-Command $check.Command -ErrorAction SilentlyContinue)) {
        Write-Log "$($check.Name): not found on PATH" "ERROR"
        continue
    }
    & $check.Command @($check.Arguments) 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "$($check.Name): OK" "SUCCESS"
    } else {
        Write-Log "$($check.Name): FAILED (exit code $LASTEXITCODE)" "ERROR"
    }
}

# Summary
$failures = Get-SetupFailure
$color = if ($failures) { "Yellow" } else { "Green" }
Write-Host "`n================================================" -ForegroundColor $color
if ($failures) {
    Write-Host "   Desktop Setup Finished With Errors" -ForegroundColor $color
} else {
    Write-Host "   Desktop Setup Complete!" -ForegroundColor $color
}
Write-Host "================================================" -ForegroundColor $color
Write-Host "Installed Components:" -ForegroundColor Cyan
Write-Host "  - Chocolatey Package Manager" -ForegroundColor White
Write-Host "  - Java JDK 17 (Microsoft OpenJDK)" -ForegroundColor White
Write-Host "  - Apache Maven" -ForegroundColor White
Write-Host "  - Git for Windows" -ForegroundColor White
Write-Host "  - Visual Studio Code (with Java extensions)" -ForegroundColor White
if ($failures) {
    Write-Host "`nFailed steps:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Fix the problems above and run the script again; finished steps are skipped." -ForegroundColor Yellow
}
Write-Host "Log File: $LogFile" -ForegroundColor Yellow
Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Restart your terminal to ensure all PATH changes take effect" -ForegroundColor White
if ($userSetupSkipped) {
    Write-Host "  2. As $consoleUser, in a normal PowerShell window: .\setup-desktop-user.ps1" -ForegroundColor White
} else {
    Write-Host "  2. Navigate to your workspace: cd $(Join-Path $env:USERPROFILE 'CatoWorkspace')" -ForegroundColor White
}
Write-Host "  3. Clone the repository if you haven't already" -ForegroundColor White
Write-Host "  4. Build the project: mvn clean install" -ForegroundColor White
Write-Host "================================================`n" -ForegroundColor $color

if ($failures) {
    Write-Log "=== Desktop PC Setup Finished With $($failures.Count) Failed Step(s) ===" "WARNING"
    exit 1
}
Write-Log "=== Desktop PC Setup Completed ===" "SUCCESS"
exit 0
