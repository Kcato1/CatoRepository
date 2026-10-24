<#
.SYNOPSIS
    Data Engineering and Data Science environment setup for Windows
.DESCRIPTION
    Complete development environment setup including:
    - Python (Anaconda distribution with data science packages)
    - R and RStudio
    - Jupyter Lab
    - Databases (PostgreSQL, MongoDB)
    - Big Data tools (Apache Spark)
    - Development tools (VS Code, Git, Docker)
    - Database clients (DBeaver)
    - Cloud CLIs (Azure, AWS)
    - Visualization tools (Power BI Desktop)

    Machine-wide tools are installed here (this part needs Administrator).
    Per-user steps (VS Code extensions, conda for PowerShell, the DataScience
    workspace) run through setup-data-science-user.ps1, automatically when the
    elevated account is the signed-in user.

    Safe to run again: tools that are already installed are skipped, and the
    script exits with code 1 if any step failed.
.PARAMETER SkipR
    Skip R and RStudio installation
.PARAMETER SkipDatabases
    Skip database installations
.PARAMETER SkipDocker
    Skip Docker Desktop installation
.PARAMETER SkipPowerBI
    Skip Power BI Desktop installation
.PARAMETER PostgresPassword
    Password for the PostgreSQL 'postgres' user. If omitted, the PostgreSQL
    package generates a random one and prints it in the install output.
.PARAMETER LogFile
    Path to the log file (defaults to a timestamped file next to this script)
.EXAMPLE
    .\setup-data-science.ps1
.EXAMPLE
    .\setup-data-science.ps1 -SkipR -SkipPowerBI
.EXAMPLE
    .\setup-data-science.ps1 -PostgresPassword (Read-Host -AsSecureString "postgres password")
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script')]
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$SkipR,

    [Parameter(Mandatory=$false)]
    [switch]$SkipDatabases,

    [Parameter(Mandatory=$false)]
    [switch]$SkipDocker,

    [Parameter(Mandatory=$false)]
    [switch]$SkipPowerBI,

    [Parameter(Mandatory=$false)]
    [securestring]$PostgresPassword,

    [Parameter(Mandatory=$false)]
    [string]$LogFile
)

$ErrorActionPreference = "Continue"

# Import common module
Import-Module "$PSScriptRoot\lib\common.psm1" -Force
if (-not $LogFile) {
    $LogFile = Join-Path $PSScriptRoot "setup-data-science-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
}
Set-LogFile -Path $LogFile

# Require Administrator
Assert-Administrator

# Banner
Write-Host "`n" -NoNewline
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   Data Engineering & Data Science Environment Setup" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "This will install a complete data science development environment" -ForegroundColor Yellow
Write-Host "Log file: $LogFile" -ForegroundColor Yellow
Write-Host "================================================================`n" -ForegroundColor Cyan

# Progress tracking: count only the steps that will actually run
$TotalSteps = 8 + $(if (-not $SkipR) { 1 } else { 0 }) + $(if (-not $SkipDatabases) { 2 } else { 0 }) +
    $(if (-not $SkipDocker) { 1 } else { 0 }) + $(if (-not $SkipPowerBI) { 1 } else { 0 })
$CurrentStep = 0

function Show-Progress {
    param([string]$Activity)
    $script:CurrentStep++
    $percent = [math]::Min(100, [math]::Round(($script:CurrentStep / $TotalSteps) * 100))
    Write-Progress -Activity "Data Science Environment Setup" -Status $Activity -PercentComplete $percent
    Write-Log "=== Step $script:CurrentStep/${TotalSteps}: $Activity ==="
}

# Components that are present at the end, for the summary
$installed = [System.Collections.Generic.List[string]]::new()

# Install a Chocolatey package unless it is already present.
# IsInstalled detects tools that were installed some other way.
function Install-Tool {
    param(
        [string]$DisplayName,
        [string]$Package,
        [scriptblock]$IsInstalled = { $false },
        [string]$SensitiveParameters,
        [string]$Note
    )
    if ((Test-ChocoPackage -Package $Package) -or (& $IsInstalled)) {
        Write-Log "$DisplayName already installed" "SUCCESS"
        $installed.Add($DisplayName)
        return
    }
    Write-Log "Installing $DisplayName..."
    try {
        Invoke-ChocoInstall -Package $Package -SensitiveParameters $SensitiveParameters
        Update-EnvironmentPath
        Write-Log "$DisplayName installed successfully" "SUCCESS"
        if ($Note) { Write-Log $Note "WARNING" }
        $installed.Add($DisplayName)
    } catch {
        Write-Log "Failed to install ${DisplayName}: $($_.Exception.Message)" "ERROR"
    }
}

# Step 1: Install Chocolatey
Show-Progress "Installing Chocolatey Package Manager"
Install-Chocolatey

# Step 2: Install Python (Anaconda Distribution)
# The Anaconda package does not add conda to PATH; Get-CondaPath also checks its install folders.
Show-Progress "Installing Anaconda Python Distribution"
Install-Tool -DisplayName "Anaconda Python" -Package anaconda3 -IsInstalled { Get-CondaPath }

# Step 3: Install Git
Show-Progress "Installing Git for Version Control"
Install-Tool -DisplayName "Git" -Package git -IsInstalled { Get-Command git -ErrorAction SilentlyContinue }

# Step 4: Install Visual Studio Code
Show-Progress "Installing Visual Studio Code"
Install-Tool -DisplayName "Visual Studio Code" -Package vscode -IsInstalled { Get-Command code -ErrorAction SilentlyContinue }

# Step 5: Install R and RStudio
# R is not added to PATH by its installer, and "R" alone resolves to the
# built-in alias for Invoke-History, so detect it by its install folder.
if (-not $SkipR) {
    Show-Progress "Installing R and RStudio"
    Install-Tool -DisplayName "R" -Package r.project -IsInstalled {
        Test-Path "$env:ProgramFiles\R\R-*\bin\R.exe"
    }
    Install-Tool -DisplayName "RStudio" -Package r.studio -IsInstalled {
        (Test-Path "$env:ProgramFiles\RStudio\rstudio.exe") -or (Test-Path "$env:ProgramFiles\RStudio\bin\rstudio.exe")
    }
} else {
    Write-Log "Skipping R and RStudio installation" "WARNING"
}

# Steps 6-7: Install PostgreSQL and MongoDB
if (-not $SkipDatabases) {
    Show-Progress "Installing PostgreSQL Database"
    $postgresParams = $null
    $postgresNote = "PostgreSQL generated a random password for the 'postgres' user; it is shown in the install output above. Rerun with -PostgresPassword to choose one on a fresh install."
    if ($PostgresPassword) {
        $plain = [System.Net.NetworkCredential]::new('', $PostgresPassword).Password
        $postgresParams = "/Password:$plain"
        $postgresNote = $null
    }
    Install-Tool -DisplayName "PostgreSQL" -Package postgresql -SensitiveParameters $postgresParams -Note $postgresNote -IsInstalled {
        Test-Path "$env:ProgramFiles\PostgreSQL\*\bin\psql.exe"
    }

    Show-Progress "Installing MongoDB"
    Install-Tool -DisplayName "MongoDB" -Package mongodb -IsInstalled {
        Test-Path "$env:ProgramFiles\MongoDB\Server\*\bin\mongod.exe"
    }
} else {
    Write-Log "Skipping database installations" "WARNING"
}

# Step 8: Install DBeaver (Universal Database Client)
Show-Progress "Installing DBeaver Database Client"
Install-Tool -DisplayName "DBeaver" -Package dbeaver -IsInstalled { Test-Path "$env:ProgramFiles\DBeaver\dbeaver.exe" }

# Step 9: Install Docker Desktop
if (-not $SkipDocker) {
    Show-Progress "Installing Docker Desktop"
    Install-Tool -DisplayName "Docker Desktop" -Package docker-desktop -IsInstalled { Get-Command docker -ErrorAction SilentlyContinue } `
        -Note "Restart your computer to complete the Docker installation"
} else {
    Write-Log "Skipping Docker Desktop installation" "WARNING"
}

# Step 10: Install Azure CLI
Show-Progress "Installing Azure CLI"
Install-Tool -DisplayName "Azure CLI" -Package azure-cli -IsInstalled { Get-Command az -ErrorAction SilentlyContinue }

# Step 11: Install AWS CLI
Show-Progress "Installing AWS CLI"
Install-Tool -DisplayName "AWS CLI" -Package awscli -IsInstalled { Get-Command aws -ErrorAction SilentlyContinue }

# Step 12: Install Power BI Desktop
if (-not $SkipPowerBI) {
    Show-Progress "Installing Power BI Desktop"
    Install-Tool -DisplayName "Power BI Desktop" -Package powerbi -IsInstalled {
        Test-Path "$env:ProgramFiles\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
    }
} else {
    Write-Log "Skipping Power BI Desktop installation" "WARNING"
}

# Step 13: Per-user setup (VS Code extensions, conda for PowerShell, workspace).
# These belong to whoever runs them, so they only run here when the elevated
# account is the signed-in user; otherwise that user runs the script themselves.
Show-Progress "Setting Up Per-User Workspace"
$runningAs = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$consoleUser = $null
try {
    $consoleUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
} catch {
    Write-Log "Could not determine the signed-in user: $($_.Exception.Message)" "WARNING"
}
$userSetupSkipped = $consoleUser -and $consoleUser -ne $runningAs
if ($userSetupSkipped) {
    Write-Log "Skipping per-user setup: this window is elevated as $runningAs, not the signed-in user $consoleUser" "WARNING"
    Write-Log "As $consoleUser, run in a normal PowerShell window: .\setup-data-science-user.ps1" "WARNING"
} else {
    # Failures are recorded in the shared module, so the summary below includes them
    & (Join-Path $PSScriptRoot "setup-data-science-user.ps1") -LogFile $LogFile
}

# Complete!
Write-Progress -Activity "Data Science Environment Setup" -Completed

$failures = Get-SetupFailure
$color = if ($failures) { "Yellow" } else { "Green" }
Write-Host "`n" -NoNewline
Write-Host "================================================================" -ForegroundColor $color
if ($failures) {
    Write-Host "   Data Science Environment Setup Finished With Errors" -ForegroundColor $color
} else {
    Write-Host "   Data Science Environment Setup Complete!" -ForegroundColor $color
}
Write-Host "================================================================" -ForegroundColor $color

Write-Host "`nInstalled Components:" -ForegroundColor Cyan
$installed | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }

if ($failures) {
    Write-Host "`nFailed steps:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Fix the problems above and run the script again; finished steps are skipped." -ForegroundColor Yellow
}

$envScript = Join-Path $PSScriptRoot "create-datasci-env.ps1"
Write-Host "`nIMPORTANT - Next Steps:" -ForegroundColor Yellow
Write-Host "  1. RESTART YOUR TERMINAL to activate conda" -ForegroundColor White
if ($userSetupSkipped) {
    Write-Host "  2. As $consoleUser, in a normal PowerShell window:" -ForegroundColor White
    Write-Host "     .\setup-data-science-user.ps1" -ForegroundColor Cyan
} else {
    Write-Host "  2. Read the workspace guide:" -ForegroundColor White
    Write-Host "     $(Join-Path $env:USERPROFILE 'DataScience\README.txt')" -ForegroundColor Cyan
}
Write-Host "  3. Create the data science environment (not as Administrator):" -ForegroundColor White
Write-Host "     $envScript" -ForegroundColor Cyan
Write-Host "  4. Activate it and start Jupyter Lab:" -ForegroundColor White
Write-Host "     conda activate datasci; jupyter lab" -ForegroundColor Cyan

if (-not $SkipDocker) {
    Write-Host "`n  Note: Restart your computer to complete Docker installation" -ForegroundColor Yellow
}

Write-Host "`nLog file saved to: $LogFile" -ForegroundColor Yellow
Write-Host "================================================================`n" -ForegroundColor $color

if ($failures) {
    Write-Log "=== Data Science Environment Setup Finished With $($failures.Count) Failed Step(s) ===" "WARNING"
    exit 1
}
Write-Log "=== Data Science Environment Setup Completed Successfully ===" "SUCCESS"
exit 0
