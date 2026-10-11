#!/bin/bash
#
# Data science environment for a GCP Compute Engine VM (Ubuntu 22.04/24.04).
# Run ON the VM as your normal user (not root); it uses sudo for system packages.
#
# Usage: bash setup-gcp-datasci.sh [--skip-ml]
#

# shellcheck disable=SC2024,SC1091  # log file is user-owned, so redirecting as the user is intended
set -euo pipefail

SKIP_ML=false
for arg in "$@"; do
    case $arg in
        --skip-ml) SKIP_ML=true ;;
        -h|--help)
            echo "Usage: $0 [--skip-ml]"
            echo "  --skip-ml   Skip TensorFlow and PyTorch (saves ~3 GB and 10+ minutes)"
            exit 0 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

if [[ "$EUID" -eq 0 ]]; then
    echo "Run this as your normal user, not root. It will call sudo when needed."
    exit 1
fi

VENV_DIR="$HOME/datasci-venv"
WORKSPACE_DIR="$HOME/DataScience"
LOG_DIR="$HOME/setup-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/gcp-setup-$(date +%Y%m%d-%H%M%S).log"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

log() {
    local level=$1; shift
    local color=$NC
    case $level in
        SUCCESS) color=$GREEN ;;
        WARNING) color=$YELLOW ;;
        ERROR)   color=$RED ;;
        STEP)    color=$CYAN ;;
        *)       color=$NC ;;
    esac
    echo -e "${color}[$(date '+%H:%M:%S')] [$level] $*${NC}" | tee -a "$LOG_FILE"
}

trap 'log ERROR "Failed at line $LINENO. See $LOG_FILE"' ERR

METADATA="http://metadata.google.internal/computeMetadata/v1"
METADATA_HEADER="Metadata-Flavor: Google"
if curl -sf -H "$METADATA_HEADER" "$METADATA/instance/zone" >/dev/null 2>&1; then
    ZONE=$(curl -s -H "$METADATA_HEADER" "$METADATA/instance/zone" | cut -d/ -f4)
    INSTANCE=$(curl -s -H "$METADATA_HEADER" "$METADATA/instance/name")
    PROJECT=$(curl -s -H "$METADATA_HEADER" "$METADATA/project/project-id")
    log SUCCESS "GCP VM detected: $INSTANCE ($ZONE) in project $PROJECT"
else
    ZONE="<zone>"; INSTANCE="<instance>"; PROJECT="<project>"
    log WARNING "Not running on a GCP VM; continuing anyway"
fi

. /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    log ERROR "This script supports Ubuntu/Debian only (found $ID)"
    exit 1
fi

log STEP "1/7 System packages"
sudo apt-get update -y >>"$LOG_FILE" 2>&1
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-dev build-essential git curl wget \
    ca-certificates gnupg postgresql-client >>"$LOG_FILE" 2>&1
log SUCCESS "System packages installed ($(python3 --version))"

log STEP "2/7 Google Cloud CLI"
if command -v gcloud >/dev/null 2>&1; then
    log SUCCESS "gcloud already installed"
else
    curl -fsSL --proto '=https' --tlsv1.2 https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | sudo gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
    sudo apt-get update -y >>"$LOG_FILE" 2>&1
    sudo apt-get install -y google-cloud-cli >>"$LOG_FILE" 2>&1
    log SUCCESS "gcloud installed"
fi

# A venv keeps packages out of Ubuntu's system Python (PEP 668 blocks global pip on 24.04).
log STEP "3/7 Python virtual environment at $VENV_DIR"
[[ -d "$VENV_DIR" ]] || python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --quiet --only-binary :all: --upgrade pip setuptools wheel
log SUCCESS "Virtual environment ready"

log STEP "4/7 Data science + GCP packages"
pip install --quiet --only-binary :all: --upgrade \
    numpy pandas scipy matplotlib seaborn plotly scikit-learn statsmodels \
    jupyterlab ipykernel \
    polars "dask[dataframe]" pyarrow \
    sqlalchemy psycopg2-binary pg8000 \
    google-cloud-bigquery google-cloud-bigquery-storage db-dtypes \
    google-cloud-storage google-cloud-secret-manager google-cloud-aiplatform \
    "cloud-sql-python-connector[pg8000]" \
    pandas-gbq gcsfs \
    dbt-bigquery >>"$LOG_FILE" 2>&1
log SUCCESS "Core packages installed"

if [[ "$SKIP_ML" = false ]]; then
    log STEP "5/7 ML frameworks (TensorFlow, PyTorch CPU)"
    pip install --quiet --only-binary :all: tensorflow >>"$LOG_FILE" 2>&1
    pip install --quiet --only-binary :all: torch torchvision --index-url https://download.pytorch.org/whl/cpu >>"$LOG_FILE" 2>&1
    log SUCCESS "TensorFlow and PyTorch installed"
else
    log WARNING "5/7 Skipping ML frameworks (--skip-ml)"
fi

log STEP "6/7 Jupyter kernel and workspace"
python -m ipykernel install --user --name datasci --display-name "Python (datasci)" >>"$LOG_FILE" 2>&1
mkdir -p "$WORKSPACE_DIR"/{projects,datasets,notebooks,scripts,models,outputs}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/examples" ]]; then
    cp -r "$SCRIPT_DIR/examples" "$WORKSPACE_DIR/scripts/gcp-examples"
fi
log SUCCESS "Workspace ready at $WORKSPACE_DIR"

log STEP "7/7 Helper scripts"
# Jupyter binds to localhost only; reach it through an SSH tunnel, never an open firewall port.
cat > "$HOME/start-jupyter.sh" <<EOF
#!/bin/bash
source "$VENV_DIR/bin/activate"
cd "$WORKSPACE_DIR/notebooks"
echo "On your local machine, open a tunnel:"
echo "  gcloud compute ssh $INSTANCE --zone $ZONE --tunnel-through-iap -- -L 8888:localhost:8888"
echo "Then browse to the http://localhost:8888/?token=... URL printed below."
exec jupyter lab --ip=127.0.0.1 --port=8888 --no-browser
EOF
chmod +x "$HOME/start-jupyter.sh"

if ! grep -q "datasci-venv/bin/activate" "$HOME/.bashrc"; then
    echo "source \"$VENV_DIR/bin/activate\"" >> "$HOME/.bashrc"
fi
log SUCCESS "Created ~/start-jupyter.sh and auto-activated venv in ~/.bashrc"

cat <<EOF

================================================================
  GCP data science environment ready
================================================================
  Python venv : $VENV_DIR
  Workspace   : $WORKSPACE_DIR
  Log         : $LOG_FILE

Next steps
  1. Verify GCP access (uses the VM's service account automatically):
       bq ls
       gcloud storage ls
  2. Start Jupyter on the VM:
       ~/start-jupyter.sh
  3. From your laptop, tunnel in:
       gcloud compute ssh $INSTANCE --zone $ZONE --tunnel-through-iap -- -L 8888:localhost:8888
  4. Try the examples:
       python $WORKSPACE_DIR/scripts/gcp-examples/bigquery_example.py --project $PROJECT
EOF
