<#
.SYNOPSIS
    Create or update the 'datasci' conda environment
.DESCRIPTION
    Creates a conda environment named 'datasci' with Python 3.11 and the data
    science, machine learning, big data and database packages, then registers
    it as a Jupyter kernel.

    Run it after setup-data-science.ps1, in a normal (not elevated) PowerShell
    window, as the user who will use the environment.

    Safe to run again: an existing 'datasci' environment is kept and only
    missing packages are added. The script stops at the first failed step.
.PARAMETER Name
    Environment name (default: datasci)
.EXAMPLE
    .\create-datasci-env.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script')]
[CmdletBinding()]
param(
    [string]$Name = "datasci"
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\lib\common.psm1"

# Run one native step and stop if it fails
function Invoke-Step {
    param([string]$Description, [scriptblock]$Command)
    Write-Host "`n==> $Description" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed (exit code $LASTEXITCODE)"
    }
}

$conda = Get-CondaPath
if (-not $conda) {
    throw "conda was not found. Run setup-data-science.ps1 first, then open a new terminal."
}
Write-Host "Using conda: $conda" -ForegroundColor Yellow

# Create the environment only if it does not exist yet: 'conda create -y' on
# an existing environment deletes and rebuilds it.
$envList = (& $conda env list --json | Out-String) | ConvertFrom-Json
$exists = $envList.envs | Where-Object { (Split-Path $_ -Leaf) -eq $Name }
if ($exists) {
    Write-Host "Environment '$Name' already exists; adding any missing packages" -ForegroundColor Yellow
} else {
    Invoke-Step "Creating environment '$Name' (Python 3.11)" { & $conda create -n $Name python=3.11 -y }
}

Invoke-Step "Installing data science, Jupyter, big data and database packages" {
    & $conda install -n $Name -y `
        numpy pandas scipy matplotlib seaborn scikit-learn statsmodels `
        jupyter jupyterlab notebook ipykernel `
        pyspark sqlalchemy psycopg2 pymongo dask `
        plotly bokeh altair
}

# PyTorch no longer publishes conda packages, so TensorFlow and PyTorch come from pip
Invoke-Step "Installing TensorFlow" {
    & $conda run -n $Name --no-capture-output python -m pip install tensorflow
}
Invoke-Step "Installing PyTorch (CPU)" {
    & $conda run -n $Name --no-capture-output python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
}
Invoke-Step "Installing Polars, Streamlit, Great Expectations and dbt" {
    & $conda run -n $Name --no-capture-output python -m pip install polars streamlit great-expectations dbt-core dbt-postgres
}

Invoke-Step "Registering the Jupyter kernel" {
    & $conda run -n $Name --no-capture-output python -m ipykernel install --user --name $Name --display-name "Python (DataSci)"
}

Write-Host "`nData science environment '$Name' is ready." -ForegroundColor Green
Write-Host "Activate it with: conda activate $Name" -ForegroundColor Yellow
Write-Host "Apache Airflow does not run natively on Windows; use it through WSL or Docker." -ForegroundColor Yellow
