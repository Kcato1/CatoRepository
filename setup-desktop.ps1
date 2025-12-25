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
.PARAMETER ComputerName
    Name identifier for this computer
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

# Logging function
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
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "This script requires Administrator privileges" "ERROR"
    throw "Administrator privileges required"
}

Write-Log "=== Desktop PC Setup Started ===" "INFO"
Write-Log "Computer Name: $ComputerName"

# Step 1: Install Chocolatey if not present
Write-Log "Checking for Chocolatey package manager..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Chocolatey package manager..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Log "Chocolatey installed successfully" "SUCCESS"

        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } catch {
        Write-Log "Failed to install Chocolatey: $($_.Exception.Message)" "ERROR"
        throw
    }
} else {
    Write-Log "Chocolatey is already installed" "SUCCESS"
}

# Step 2: Install Java JDK 17 (Microsoft distribution)
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
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } catch {
        Write-Log "Failed to install Java JDK 17: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "Java JDK 17 is already installed: $javaVersion" "SUCCESS"
}

# Set JAVA_HOME if not set
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

# Step 3: Install Apache Maven
Write-Log "Checking for Apache Maven..."
if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Apache Maven..."
    try {
        choco install maven -y
        Write-Log "Maven installed successfully" "SUCCESS"

        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } catch {
        Write-Log "Failed to install Maven: $($_.Exception.Message)" "ERROR"
    }
} else {
    $mavenVersion = & mvn -version 2>&1 | Select-String "Apache Maven" | ForEach-Object { $_.ToString() }
    Write-Log "Maven is already installed: $mavenVersion" "SUCCESS"
}

# Step 4: Install Git for Windows
Write-Log "Checking for Git..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Git for Windows..."
    try {
        choco install git -y
        Write-Log "Git installed successfully" "SUCCESS"

        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } catch {
        Write-Log "Failed to install Git: $($_.Exception.Message)" "ERROR"
    }
} else {
    $gitVersion = & git --version 2>&1
    Write-Log "Git is already installed: $gitVersion" "SUCCESS"
}

# Step 5: Install Visual Studio Code (optional but recommended)
Write-Log "Checking for Visual Studio Code..."
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Visual Studio Code..."
    try {
        choco install vscode -y
        Write-Log "VS Code installed successfully" "SUCCESS"

        # Install useful extensions
        Write-Log "Installing VS Code extensions for Java development..."
        Start-Sleep -Seconds 5  # Wait for VS Code installation to complete

        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        if (Get-Command code -ErrorAction SilentlyContinue) {
            code --install-extension vscjava.vscode-java-pack --force 2>&1 | Out-Null
            code --install-extension vscjava.vscode-maven --force 2>&1 | Out-Null
            Write-Log "VS Code Java extensions installed" "SUCCESS"
        }
    } catch {
        Write-Log "Failed to install VS Code: $($_.Exception.Message)" "WARNING"
    }
} else {
    Write-Log "VS Code is already installed" "SUCCESS"
}

# Step 6: Configure Git
Write-Log "Configuring Git..."
try {
    $gitUserName = git config --global user.name 2>$null
    if (-not $gitUserName) {
        Write-Host "`nGit configuration needed:" -ForegroundColor Yellow
        $userName = Read-Host "Enter your Git user name"
        $userEmail = Read-Host "Enter your Git email"

        git config --global user.name "$userName"
        git config --global user.email "$userEmail"
        Write-Log "Git configured with user: $userName <$userEmail>" "SUCCESS"
    } else {
        Write-Log "Git already configured for user: $gitUserName" "SUCCESS"
    }
} catch {
    Write-Log "Failed to configure Git: $($_.Exception.Message)" "WARNING"
}

# Step 7: Create workspace directory
$workspaceDir = Join-Path $env:USERPROFILE "CatoWorkspace"
Write-Log "Setting up workspace directory: $workspaceDir"
if (-not (Test-Path $workspaceDir)) {
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null
    Write-Log "Workspace directory created" "SUCCESS"
}

# Step 8: Clone repository (optional - requires GitHub access)
$repoDir = Join-Path $workspaceDir "CatoRepository"
if (-not (Test-Path $repoDir)) {
    Write-Host "`nDo you want to clone the Catoconsting repository now? (Y/N): " -ForegroundColor Yellow -NoNewline
    $cloneResponse = Read-Host

    if ($cloneResponse -eq 'Y' -or $cloneResponse -eq 'y') {
        Write-Host "Enter the repository URL (e.g., https://github.com/username/CatoRepository.git): " -NoNewline
        $repoUrl = Read-Host

        try {
            Write-Log "Cloning repository from: $repoUrl"
            Set-Location $workspaceDir
            git clone $repoUrl
            Write-Log "Repository cloned successfully" "SUCCESS"
        } catch {
            Write-Log "Failed to clone repository: $($_.Exception.Message)" "WARNING"
        }
    }
} else {
    Write-Log "Repository already exists at: $repoDir" "SUCCESS"
}

# Step 9: Verify installations
Write-Log "`n=== Verification of Installed Components ===" "INFO"
Write-Log "Verifying Java..."
try {
    $javaCheck = & java -version 2>&1 | Out-String
    Write-Log "Java: OK" "SUCCESS"
} catch {
    Write-Log "Java: FAILED" "ERROR"
}

Write-Log "Verifying Maven..."
try {
    $mvnCheck = & mvn -version 2>&1 | Out-String
    Write-Log "Maven: OK" "SUCCESS"
} catch {
    Write-Log "Maven: FAILED" "ERROR"
}

Write-Log "Verifying Git..."
try {
    $gitCheck = & git --version 2>&1 | Out-String
    Write-Log "Git: OK" "SUCCESS"
} catch {
    Write-Log "Git: FAILED" "ERROR"
}

# Summary
Write-Host "`n================================================" -ForegroundColor Green
Write-Host "   Desktop Setup Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host "Installed Components:" -ForegroundColor Cyan
Write-Host "  - Chocolatey Package Manager" -ForegroundColor White
Write-Host "  - Java JDK 17 (Microsoft OpenJDK)" -ForegroundColor White
Write-Host "  - Apache Maven" -ForegroundColor White
Write-Host "  - Git for Windows" -ForegroundColor White
Write-Host "  - Visual Studio Code (with Java extensions)" -ForegroundColor White
Write-Host "`nWorkspace: $workspaceDir" -ForegroundColor Yellow
Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Restart your terminal to ensure all PATH changes take effect" -ForegroundColor White
Write-Host "  2. Navigate to your workspace: cd $workspaceDir" -ForegroundColor White
Write-Host "  3. Clone the repository if you haven't already" -ForegroundColor White
Write-Host "  4. Build the project: mvn clean install" -ForegroundColor White
Write-Host "================================================`n" -ForegroundColor Green

Write-Log "=== Desktop PC Setup Completed ===" "SUCCESS"
