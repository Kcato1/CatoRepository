<#
.SYNOPSIS
    Per-user part of the data science setup
.DESCRIPTION
    Sets up the things that belong to one Windows account rather than the
    whole machine:
    - VS Code extensions for Python, Jupyter, Git and Docker
    - conda for PowerShell (conda init)
    - The DataScience workspace folders and README in the user profile

    Run it as the person who will use the machine, in a normal (not elevated)
    PowerShell window. setup-data-science.ps1 runs it automatically when the
    elevated account is the signed-in user.

    Safe to run again: steps that are already done are skipped, and the script
    exits with code 1 if any step failed.
.PARAMETER LogFile
    Path to the log file (defaults to a timestamped file next to this script)
.EXAMPLE
    .\setup-data-science-user.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script')]
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogFile
)

$ErrorActionPreference = "Continue"

# Import common module. When setup-data-science.ps1 runs this script the
# module is already loaded, and importing without -Force keeps its log file
# and failure list so both scripts report into one summary.
Import-Module "$PSScriptRoot\lib\common.psm1"
if (-not $LogFile) {
    $LogFile = Join-Path $PSScriptRoot "setup-data-science-log-user-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
}
Set-LogFile -Path $LogFile

Write-Log "=== Data Science Per-User Setup Started ===" "INFO"
Write-Log "User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

# Step 1: VS Code extensions (already-installed ones are skipped)
if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Log "Installing VS Code extensions..."
    $extensions = @(
        "ms-python.python",
        "ms-python.vscode-pylance",
        "ms-toolsai.jupyter",
        "ms-toolsai.jupyter-keymap",
        "ms-toolsai.jupyter-renderers",
        "ms-toolsai.vscode-jupyter-cell-tags",
        "ms-toolsai.vscode-jupyter-slideshow",
        "donjayamanne.githistory",
        "eamodio.gitlens",
        "ms-vscode.powershell",
        "redhat.vscode-yaml",
        "ms-azuretools.vscode-docker"
    )
    $existing = & code --list-extensions 2>$null
    foreach ($extension in $extensions) {
        if ($existing -contains $extension) {
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
} else {
    Write-Log "Skipping VS Code extensions: code is not on PATH (open a new terminal after installing VS Code)" "WARNING"
}

# Step 2: Set up conda for PowerShell (conda init leaves an already set up profile unchanged)
$conda = Get-CondaPath
if ($conda) {
    Write-Log "Initializing conda for PowerShell ($conda)..."
    & $conda init powershell | Out-Host
    if ($LASTEXITCODE -eq 0) {
        Write-Log "conda is set up for PowerShell; restart your terminal to use it" "SUCCESS"
    } else {
        Write-Log "conda init powershell failed (exit code $LASTEXITCODE)" "ERROR"
    }
} else {
    Write-Log "Skipping conda setup: Anaconda is not installed" "WARNING"
}

# Step 3: Create workspace directory structure
$workspaceRoot = Join-Path $env:USERPROFILE "DataScience"
$directories = @(
    $workspaceRoot,
    (Join-Path $workspaceRoot "projects"),
    (Join-Path $workspaceRoot "datasets"),
    (Join-Path $workspaceRoot "notebooks"),
    (Join-Path $workspaceRoot "scripts"),
    (Join-Path $workspaceRoot "models"),
    (Join-Path $workspaceRoot "outputs")
)

Write-Log "Creating workspace structure at: $workspaceRoot"
foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Log "Created: $dir" "SUCCESS"
    } else {
        Write-Log "Exists: $dir" "SUCCESS"
    }
}

# Workspace README. Only rewritten when its content changes; an edited copy
# is kept as README.txt.bak.
$envScript = Join-Path $PSScriptRoot "create-datasci-env.ps1"
$readmePath = Join-Path $workspaceRoot "README.txt"
$readmeContent = @"
====================================================================
  Data Science & Data Engineering Workspace
====================================================================

Welcome to your data science workspace!

DIRECTORY STRUCTURE:
--------------------
projects/   - Your data science and engineering projects
datasets/   - Raw and processed datasets
notebooks/  - Jupyter notebooks
scripts/    - Python/R scripts and utilities
models/     - Trained ML models and serialized objects
outputs/    - Visualizations, reports, and results

INSTALLED TOOLS:
----------------
Core:
  - Anaconda Python (with data science packages)
  - Git for version control
  - Visual Studio Code with extensions

Data Science:
  - Jupyter Lab
  - Python libraries (pandas, numpy, scikit-learn, etc.)
  - TensorFlow and PyTorch (CPU)
  - R and RStudio (unless skipped)

Data Engineering:
  - Apache Spark (PySpark)
  - PostgreSQL
  - MongoDB
  - DBeaver (database client)

Cloud & DevOps:
  - Azure CLI
  - AWS CLI
  - Docker Desktop

Visualization:
  - Power BI Desktop
  - Plotly, Matplotlib, Seaborn

GETTING STARTED:
----------------
1. Restart your terminal to activate conda

2. Create the data science environment (normal, non-admin window):
   & "$envScript"

3. Activate the environment:
   conda activate datasci

4. Start Jupyter Lab:
   jupyter lab

5. Configure Git (if not already):
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"

CONDA ENVIRONMENTS:
-------------------
- base: Default Anaconda environment
- datasci: Your data science environment with all packages

Useful conda commands:
  conda env list              # List all environments
  conda activate datasci      # Activate environment
  conda deactivate            # Deactivate environment
  conda list                  # List installed packages
  conda install <package>     # Install new package

JUPYTER LAB:
------------
Start Jupyter Lab:
  jupyter lab

Access at: http://localhost:8888

Create a new notebook:
  - Click "+" in the file browser
  - Select "Python (DataSci)" kernel

DATABASES:
----------
PostgreSQL:
  - Service: postgresql-x64-<version>
  - Port: 5432
  - User: postgres
  - Connect via: DBeaver or psql

MongoDB:
  - Service: MongoDB
  - Port: 27017
  - Connect via: DBeaver or mongo shell

HELPFUL RESOURCES:
------------------
- Anaconda Docs: https://docs.anaconda.com
- Jupyter Docs: https://jupyter.org/documentation
- Pandas Docs: https://pandas.pydata.org/docs
- Scikit-learn: https://scikit-learn.org
- TensorFlow: https://www.tensorflow.org
- PyTorch: https://pytorch.org
- PySpark: https://spark.apache.org/docs/latest/api/python

NEXT STEPS:
-----------
1. Restart your terminal
2. Run: & "$envScript"
3. Activate: conda activate datasci
4. Start Jupyter: jupyter lab
5. Begin your first project!

====================================================================
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
====================================================================
"@

Set-FileIfChanged -Path $readmePath -Value $readmeContent -IgnorePattern '^Created: '

if (Get-SetupFailure) {
    Write-Log "=== Data Science Per-User Setup Finished With Errors ===" "WARNING"
    exit 1
}
Write-Log "=== Data Science Per-User Setup Completed ===" "SUCCESS"
exit 0
