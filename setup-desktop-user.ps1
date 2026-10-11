<#
.SYNOPSIS
    Per-user part of the Catoconsting desktop setup
.DESCRIPTION
    Sets up the things that belong to one Windows account rather than the
    whole machine:
    - VS Code Java extensions
    - Git user.name and user.email
    - The CatoWorkspace folder in the user profile
    - Cloning the project repository

    Run it as the developer who will use the machine, in a normal (not
    elevated) PowerShell window. setup-desktop.ps1 runs it automatically
    when the elevated account is the signed-in user.

    Safe to run again: steps that are already done are skipped, and the script
    exits with code 1 if any step failed.
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
.EXAMPLE
    .\setup-desktop-user.ps1 -GitUserName "Jane Doe" -GitUserEmail "jane@example.com"
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script')]
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogFile,

    [string]$GitUserName,
    [string]$GitUserEmail,
    [string]$RepoUrl,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Continue"

# Import common module. When setup-desktop.ps1 runs this script the module is
# already loaded, and importing without -Force keeps its log file and failure
# list so both scripts report into one summary.
Import-Module "$PSScriptRoot\lib\common.psm1"
if (-not $LogFile) {
    $LogFile = Join-Path $PSScriptRoot "setup-log-$env:COMPUTERNAME-user-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
}
Set-LogFile -Path $LogFile

Write-Log "=== Desktop Per-User Setup Started ===" "INFO"
Write-Log "User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

# Ask for a value unless it was passed in or prompting is disabled
function Get-InputValue {
    param([string]$Value, [string]$Prompt)
    if ($Value) { return $Value }
    if ($NonInteractive) { return $null }
    return (Read-Host $Prompt).Trim()
}

# Install VS Code Java extensions on every run (already-installed ones are skipped)
if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Log "Installing VS Code extensions for Java development..."
    $installed = & code --list-extensions 2>$null
    foreach ($extension in 'vscjava.vscode-java-pack', 'vscjava.vscode-maven') {
        if ($installed -contains $extension) {
            Write-Log "VS Code extension already installed: $extension" "SUCCESS"
            continue
        }
        & code --install-extension $extension 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "VS Code extension installed: $extension" "SUCCESS"
        } else {
            Write-Log "Failed to install VS Code extension $extension (exit code $LASTEXITCODE)" "WARNING"
        }
    }
}

# Step 1: Configure Git
Write-Log "Configuring Git..."
if (Get-Command git -ErrorAction SilentlyContinue) {
    foreach ($setting in @(
        @{ Key = 'user.name';  Value = $GitUserName;  Prompt = 'Enter your Git user name' },
        @{ Key = 'user.email'; Value = $GitUserEmail; Prompt = 'Enter your Git email' }
    )) {
        $current = & git config --global $setting.Key 2>$null
        if ($current -and -not $setting.Value) {
            Write-Log "Git $($setting.Key) already configured: $current" "SUCCESS"
            continue
        }
        $newValue = Get-InputValue -Value $setting.Value -Prompt $setting.Prompt
        if (-not $newValue) {
            Write-Log "Git $($setting.Key) not set (no value given)" "WARNING"
            continue
        }
        & git config --global $setting.Key $newValue
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Git $($setting.Key) set to: $newValue" "SUCCESS"
        } else {
            Write-Log "Failed to set Git $($setting.Key) (exit code $LASTEXITCODE)" "ERROR"
        }
    }
} else {
    Write-Log "Skipping Git configuration: git is not on PATH" "WARNING"
}

# Step 2: Create workspace directory
$workspaceDir = Join-Path $env:USERPROFILE "CatoWorkspace"
Write-Log "Setting up workspace directory: $workspaceDir"
if (-not (Test-Path $workspaceDir)) {
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null
    Write-Log "Workspace directory created" "SUCCESS"
} else {
    Write-Log "Workspace directory already exists" "SUCCESS"
}

# Step 3: Clone repository (optional - requires GitHub access)
if (-not $RepoUrl -and -not $NonInteractive) {
    Write-Host "`nDo you want to clone the Catoconsting repository now? (Y/N): " -ForegroundColor Yellow -NoNewline
    if ((Read-Host) -match '^[Yy]') {
        $RepoUrl = Get-InputValue -Prompt "Enter the repository URL (e.g., https://github.com/username/CatoRepository.git)"
    }
}

if ($RepoUrl) {
    # git clones into a folder named after the last part of the URL
    $repoName = ($RepoUrl.TrimEnd('/') -split '[/:]')[-1] -replace '\.git$', ''
    $repoDir = Join-Path $workspaceDir $repoName
    if (Test-Path $repoDir) {
        Write-Log "Repository already exists at: $repoDir" "SUCCESS"
    } elseif (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log "Cannot clone repository: git is not on PATH" "ERROR"
    } else {
        Write-Log "Cloning repository from: $RepoUrl"
        & git -C $workspaceDir clone $RepoUrl
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Repository cloned to: $repoDir" "SUCCESS"
        } else {
            Write-Log "Failed to clone repository (exit code $LASTEXITCODE)" "ERROR"
        }
    }
} else {
    Write-Log "Skipping repository clone"
}

if (Get-SetupFailure) {
    Write-Log "=== Desktop Per-User Setup Finished With Errors ===" "WARNING"
    exit 1
}
Write-Log "=== Desktop Per-User Setup Completed ===" "SUCCESS"
exit 0
