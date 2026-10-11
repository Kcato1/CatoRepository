#!/bin/bash

#
# Data Science & Data Engineering Environment Setup for Linux
#
# Installs: Python (Miniconda), Jupyter Lab, VS Code, databases,
# data science packages, and sets up workspace
#
# Usage: sudo ./setup-data-science.sh
#

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SKIP_DATABASES=false
SKIP_DOCKER=false
SKIP_VSCODE=false
LOG_FILE="setup-data-science-log-$(date +%Y%m%d-%H%M%S).txt"
WORKSPACE_DIR="$HOME/DataScience"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-databases)
            SKIP_DATABASES=true
            shift
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --skip-vscode)
            SKIP_VSCODE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-databases    Skip PostgreSQL and MongoDB installation"
            echo "  --skip-docker       Skip Docker installation"
            echo "  --skip-vscode       Skip VS Code installation"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)
            echo -e "${NC}[$timestamp] [INFO] $message${NC}" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[$timestamp] [SUCCESS] $message${NC}" | tee -a "$LOG_FILE"
            ;;
        WARNING)
            echo -e "${YELLOW}[$timestamp] [WARNING] $message${NC}" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[$timestamp] [ERROR] $message${NC}" | tee -a "$LOG_FILE"
            ;;
        SECTION)
            echo -e "${CYAN}[$timestamp] [SECTION] $message${NC}" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Progress tracking
TOTAL_STEPS=12
CURRENT_STEP=0

show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local activity="$1"
    log SECTION "Step $CURRENT_STEP/$TOTAL_STEPS: $activity"
}

# Banner
echo -e "\n${CYAN}================================================================${NC}"
echo -e "${CYAN}   Data Science & Data Engineering Environment Setup${NC}"
echo -e "${CYAN}   Linux Edition${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW}This will install a complete data science development environment${NC}"
echo -e "${YELLOW}Log file: $LOG_FILE${NC}"
echo -e "${CYAN}================================================================${NC}\n"

# Check if running as root for system packages
if [ "$EUID" -ne 0 ] && [ "$SKIP_DATABASES" = false ]; then
    log WARNING "Not running as root. System package installations may require sudo."
    log WARNING "Some installations might fail without sudo privileges."
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    log INFO "Detected OS: $OS $VERSION"
else
    log ERROR "Cannot detect OS"
    exit 1
fi

# Step 1: Update package manager
show_progress "Updating Package Manager"
log INFO "Updating package lists..."

case $OS in
    ubuntu|debian)
        if [ "$EUID" -eq 0 ]; then
            apt-get update -y || log WARNING "apt update failed"
        else
            log WARNING "Skipping apt update (not root)"
        fi
        ;;
    fedora|rhel|centos)
        if [ "$EUID" -eq 0 ]; then
            dnf update -y || yum update -y || log WARNING "Package manager update failed"
        else
            log WARNING "Skipping package update (not root)"
        fi
        ;;
esac

log SUCCESS "Package manager updated"

# Step 2: Install system dependencies
show_progress "Installing System Dependencies"
log INFO "Installing build tools and dependencies..."

PACKAGES="wget curl git build-essential ca-certificates gnupg"

case $OS in
    ubuntu|debian)
        if [ "$EUID" -eq 0 ]; then
            apt-get install -y $PACKAGES || log WARNING "Some packages failed to install"
        else
            log WARNING "Skipping system dependencies (not root)"
        fi
        ;;
    fedora|rhel|centos)
        if [ "$EUID" -eq 0 ]; then
            dnf install -y git wget curl || yum install -y git wget curl || log WARNING "Some packages failed"
        else
            log WARNING "Skipping system dependencies (not root)"
        fi
        ;;
esac

log SUCCESS "System dependencies installed"

# Step 3: Install Miniconda
show_progress "Installing Miniconda Python Distribution"

if command -v conda &> /dev/null; then
    log SUCCESS "Conda already installed"
    conda --version | tee -a "$LOG_FILE"
else
    log INFO "Installing Miniconda..."

    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    elif [ "$ARCH" = "aarch64" ]; then
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh"
    else
        log ERROR "Unsupported architecture: $ARCH"
        exit 1
    fi

    log INFO "Downloading Miniconda for $ARCH..."
    wget -q "$MINICONDA_URL" -O /tmp/miniconda.sh || {
        log ERROR "Failed to download Miniconda"
        exit 1
    }

    log INFO "Installing Miniconda to $HOME/miniconda3..."
    bash /tmp/miniconda.sh -b -p "$HOME/miniconda3" || {
        log ERROR "Miniconda installation failed"
        exit 1
    }

    rm /tmp/miniconda.sh

    # Initialize conda
    log INFO "Initializing conda..."
    eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
    $HOME/miniconda3/bin/conda init bash

    log SUCCESS "Miniconda installed successfully"
    log WARNING "Please restart your terminal or run: source ~/.bashrc"
fi

# Make conda available in this script
export PATH="$HOME/miniconda3/bin:$PATH"

# Step 4: Install Git (if not already installed)
show_progress "Verifying Git Installation"

if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version)
    log SUCCESS "Git already installed: $GIT_VERSION"
else
    log INFO "Git not found in PATH, may need system package installation"
fi

# Step 5: Install VS Code (optional)
if [ "$SKIP_VSCODE" = false ]; then
    show_progress "Installing Visual Studio Code"

    if command -v code &> /dev/null; then
        log SUCCESS "VS Code already installed"
    else
        log INFO "Installing VS Code..."

        case $OS in
            ubuntu|debian)
                if [ "$EUID" -eq 0 ]; then
                    # Add Microsoft GPG key
                    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
                    install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /usr/share/keyrings/packages.microsoft.gpg

                    # Add VS Code repository
                    echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list

                    # Install
                    apt-get update -y
                    apt-get install -y code || log WARNING "VS Code installation failed"

                    rm /tmp/packages.microsoft.gpg
                    log SUCCESS "VS Code installed"
                else
                    log WARNING "Cannot install VS Code (not root)"
                fi
                ;;
            fedora|rhel|centos)
                log INFO "VS Code installation for Fedora/RHEL - manual installation recommended"
                log INFO "Visit: https://code.visualstudio.com/docs/setup/linux"
                ;;
        esac
    fi
else
    log WARNING "Skipping VS Code installation"
fi

# Step 6: Install PostgreSQL (optional)
if [ "$SKIP_DATABASES" = false ]; then
    show_progress "Installing PostgreSQL Database"

    if command -v psql &> /dev/null; then
        log SUCCESS "PostgreSQL already installed"
    else
        log INFO "Installing PostgreSQL..."

        case $OS in
            ubuntu|debian)
                if [ "$EUID" -eq 0 ]; then
                    apt-get install -y postgresql postgresql-contrib || log WARNING "PostgreSQL installation failed"
                    systemctl start postgresql || log WARNING "Could not start PostgreSQL"
                    systemctl enable postgresql || log WARNING "Could not enable PostgreSQL"
                    log SUCCESS "PostgreSQL installed"
                else
                    log WARNING "Cannot install PostgreSQL (not root)"
                fi
                ;;
            fedora|rhel|centos)
                if [ "$EUID" -eq 0 ]; then
                    dnf install -y postgresql-server postgresql-contrib || yum install -y postgresql-server postgresql-contrib
                    postgresql-setup --initdb || log WARNING "PostgreSQL init failed"
                    systemctl start postgresql
                    systemctl enable postgresql
                    log SUCCESS "PostgreSQL installed"
                else
                    log WARNING "Cannot install PostgreSQL (not root)"
                fi
                ;;
        esac
    fi
else
    log WARNING "Skipping database installations"
fi

# Step 7: Install Docker (optional)
if [ "$SKIP_DOCKER" = false ]; then
    show_progress "Installing Docker"

    if command -v docker &> /dev/null; then
        log SUCCESS "Docker already installed"
    else
        log INFO "Installing Docker..."

        case $OS in
            ubuntu|debian)
                if [ "$EUID" -eq 0 ]; then
                    # Install Docker
                    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
                    sh /tmp/get-docker.sh || log WARNING "Docker installation failed"
                    rm /tmp/get-docker.sh

                    # Add current user to docker group
                    usermod -aG docker $SUDO_USER || log WARNING "Could not add user to docker group"

                    log SUCCESS "Docker installed"
                    log WARNING "You may need to log out and back in for Docker permissions"
                else
                    log WARNING "Cannot install Docker (not root)"
                fi
                ;;
            fedora|rhel|centos)
                log INFO "Docker installation for Fedora/RHEL - see https://docs.docker.com/engine/install/"
                ;;
        esac
    fi
else
    log WARNING "Skipping Docker installation"
fi

# Step 8: Create Data Science Conda Environment
show_progress "Creating Data Science Conda Environment"

log INFO "This will create a 'datasci' conda environment with all packages..."
log INFO "This step will be done via a separate script: create-datasci-env.sh"

# Create the conda environment setup script
cat > "$HOME/create-datasci-env.sh" << 'EOF'
#!/bin/bash

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

echo "Creating datasci conda environment..."

# Create environment
conda create -n datasci python=3.11 -y

# Activate environment
conda activate datasci

echo "Installing core data science packages..."
conda install -y numpy pandas scipy matplotlib seaborn scikit-learn

echo "Installing Jupyter..."
conda install -y jupyter jupyterlab notebook ipykernel

echo "Installing machine learning frameworks..."
conda install -y pytorch torchvision torchaudio cpuonly -c pytorch
pip install tensorflow

echo "Installing big data tools..."
conda install -y pyspark

echo "Installing database connectors..."
conda install -y sqlalchemy psycopg2 pymongo

echo "Installing data processing tools..."
conda install -y dask polars

echo "Installing visualization libraries..."
conda install -y plotly bokeh altair

echo "Installing statistical libraries..."
conda install -y statsmodels

echo "Installing additional tools..."
pip install streamlit great-expectations dbt-core dbt-postgres apache-airflow

echo "Registering Jupyter kernel..."
python -m ipykernel install --user --name datasci --display-name "Python (DataSci)"

echo ""
echo "✓ Data science environment 'datasci' created successfully!"
echo ""
echo "To use it:"
echo "  conda activate datasci"
echo "  jupyter lab"
EOF

chmod +x "$HOME/create-datasci-env.sh"
log SUCCESS "Created environment setup script: $HOME/create-datasci-env.sh"

# Step 9: Create Workspace Structure
show_progress "Creating Workspace Directory Structure"

log INFO "Creating workspace at: $WORKSPACE_DIR"

mkdir -p "$WORKSPACE_DIR"/{projects,datasets,notebooks,scripts,models,outputs}

log SUCCESS "Created workspace structure:"
log INFO "  $WORKSPACE_DIR/projects     - Your data science projects"
log INFO "  $WORKSPACE_DIR/datasets     - Raw and processed data"
log INFO "  $WORKSPACE_DIR/notebooks    - Jupyter notebooks"
log INFO "  $WORKSPACE_DIR/scripts      - Python scripts"
log INFO "  $WORKSPACE_DIR/models       - Trained ML models"
log INFO "  $WORKSPACE_DIR/outputs      - Results and visualizations"

# Step 10: Create Workspace README
show_progress "Creating Workspace Documentation"

cat > "$WORKSPACE_DIR/README.txt" << EOF
====================================================================
  Data Science & Data Engineering Workspace (Linux)
====================================================================

Welcome to your data science workspace!

DIRECTORY STRUCTURE:
--------------------
projects/   - Your data science and engineering projects
datasets/   - Raw and processed datasets
notebooks/  - Jupyter notebooks
scripts/    - Python scripts and utilities
models/     - Trained ML models and serialized objects
outputs/    - Visualizations, reports, and results

INSTALLED TOOLS:
----------------
Core:
  - Miniconda Python distribution
  - Git for version control
  - Visual Studio Code (if installed)

Data Science:
  - Jupyter Lab (via conda environment)
  - Python libraries (pandas, numpy, scikit-learn, etc.)
  - TensorFlow and PyTorch
  - PySpark

Databases:
  - PostgreSQL (if installed)

GETTING STARTED:
----------------
1. Restart your terminal or run:
   source ~/.bashrc

2. Create the data science environment:
   bash ~/create-datasci-env.sh

3. Activate the environment:
   conda activate datasci

4. Start Jupyter Lab:
   cd $WORKSPACE_DIR/notebooks
   jupyter lab

5. Configure Git (if not already):
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"

CONDA ENVIRONMENTS:
-------------------
- base: Default Miniconda environment
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
  conda activate datasci
  jupyter lab

Access at: http://localhost:8888

DATABASE:
---------
PostgreSQL (if installed):
  - Port: 5432
  - User: postgres
  - Connect: psql -U postgres

HELPFUL RESOURCES:
------------------
- Miniconda Docs: https://docs.conda.io/
- Jupyter Docs: https://jupyter.org/documentation
- Pandas Docs: https://pandas.pydata.org/docs
- Scikit-learn: https://scikit-learn.org

NEXT STEPS:
-----------
1. Run: bash ~/create-datasci-env.sh
2. Activate: conda activate datasci
3. Start Jupyter: jupyter lab
4. Begin your first project!

====================================================================
Created: $(date '+%Y-%m-%d %H:%M:%S')
====================================================================
EOF

log SUCCESS "Created workspace README: $WORKSPACE_DIR/README.txt"

# Step 11: Create quick start script
show_progress "Creating Quick Start Script"

cat > "$HOME/start-jupyter.sh" << EOF
#!/bin/bash

# Quick start script for Jupyter Lab

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# Activate data science environment
conda activate datasci

# Navigate to notebooks
cd $WORKSPACE_DIR/notebooks

# Start Jupyter Lab
echo "Starting Jupyter Lab..."
echo "Access at: http://localhost:8888"
echo "Press Ctrl+C to stop"
echo ""

jupyter lab
EOF

chmod +x "$HOME/start-jupyter.sh"
log SUCCESS "Created quick start script: $HOME/start-jupyter.sh"

# Step 12: Summary
show_progress "Installation Complete"

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}   Data Science Environment Setup Complete!${NC}"
echo -e "${GREEN}================================================================${NC}"

echo -e "\n${CYAN}Installed Components:${NC}"
echo -e "  ${GREEN}✓${NC} Miniconda Python Distribution"
echo -e "  ${GREEN}✓${NC} Git for Version Control"

if [ "$SKIP_VSCODE" = false ]; then
    echo -e "  ${GREEN}✓${NC} Visual Studio Code"
fi

if [ "$SKIP_DATABASES" = false ]; then
    echo -e "  ${GREEN}✓${NC} PostgreSQL Database"
fi

if [ "$SKIP_DOCKER" = false ]; then
    echo -e "  ${GREEN}✓${NC} Docker"
fi

echo -e "\n${CYAN}Workspace Location:${NC}"
echo -e "  ${YELLOW}$WORKSPACE_DIR${NC}"

echo -e "\n${CYAN}Created Scripts:${NC}"
echo -e "  ${YELLOW}$HOME/create-datasci-env.sh${NC}  - Create conda environment"
echo -e "  ${YELLOW}$HOME/start-jupyter.sh${NC}       - Quick start Jupyter Lab"

echo -e "\n${YELLOW}IMPORTANT - Next Steps:${NC}"
echo -e "  ${WHITE}1. Restart your terminal or run:${NC}"
echo -e "     ${CYAN}source ~/.bashrc${NC}"
echo -e ""
echo -e "  ${WHITE}2. Create the data science environment:${NC}"
echo -e "     ${CYAN}bash ~/create-datasci-env.sh${NC}"
echo -e ""
echo -e "  ${WHITE}3. Activate the environment:${NC}"
echo -e "     ${CYAN}conda activate datasci${NC}"
echo -e ""
echo -e "  ${WHITE}4. Start Jupyter Lab:${NC}"
echo -e "     ${CYAN}bash ~/start-jupyter.sh${NC}"
echo -e "     ${WHITE}or${NC}"
echo -e "     ${CYAN}jupyter lab${NC}"
echo -e ""
echo -e "  ${WHITE}5. Read the workspace guide:${NC}"
echo -e "     ${CYAN}cat $WORKSPACE_DIR/README.txt${NC}"

echo -e "\n${YELLOW}Log file saved to: $LOG_FILE${NC}"
echo -e "${GREEN}================================================================${NC}\n"

log SUCCESS "=== Data Science Environment Setup Completed ==="
