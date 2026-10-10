#!/bin/bash
#
# Create a Compute Engine VM for data science work.
# Run from your LOCAL machine (Windows: Git Bash or Cloud Shell) with gcloud installed and logged in.
#
# Usage: bash create-vm.sh PROJECT_ID [VM_NAME] [ZONE] [MACHINE_TYPE]
#   bash create-vm.sh my-project
#   bash create-vm.sh my-project datasci-vm us-central1-a e2-standard-8
#

set -euo pipefail

PROJECT_ID=${1:?Usage: $0 PROJECT_ID [VM_NAME] [ZONE] [MACHINE_TYPE]}
VM_NAME=${2:-datasci-vm}
ZONE=${3:-us-central1-a}
MACHINE_TYPE=${4:-e2-standard-4}
DISK_SIZE=100GB
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Project: $PROJECT_ID | VM: $VM_NAME | Zone: $ZONE | Type: $MACHINE_TYPE"
gcloud config set project "$PROJECT_ID"

echo "Enabling required APIs..."
gcloud services enable \
    compute.googleapis.com \
    bigquery.googleapis.com \
    storage.googleapis.com \
    sqladmin.googleapis.com \
    secretmanager.googleapis.com \
    aiplatform.googleapis.com \
    iap.googleapis.com

# Allow SSH only from Google's IAP range, so the VM needs no public SSH exposure.
if ! gcloud compute firewall-rules describe allow-iap-ssh >/dev/null 2>&1; then
    gcloud compute firewall-rules create allow-iap-ssh \
        --network=default \
        --allow=tcp:22 \
        --source-ranges=35.235.240.0/20 \
        --description="SSH via Identity-Aware Proxy"
fi

if gcloud compute instances describe "$VM_NAME" --zone "$ZONE" >/dev/null 2>&1; then
    echo "VM $VM_NAME already exists; skipping creation."
else
    gcloud compute instances create "$VM_NAME" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --image-family=ubuntu-2404-lts-amd64 \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size="$DISK_SIZE" \
        --boot-disk-type=pd-balanced \
        --scopes=cloud-platform \
        --shielded-secure-boot
fi

echo "Waiting for SSH to come up..."
for _ in $(seq 1 20); do
    if gcloud compute ssh "$VM_NAME" --zone "$ZONE" --tunnel-through-iap --command "true" >/dev/null 2>&1; then
        break
    fi
    sleep 10
done

echo "Copying setup files to the VM..."
gcloud compute scp --recurse --zone "$ZONE" --tunnel-through-iap \
    "$SCRIPT_DIR/setup-gcp-datasci.sh" "$SCRIPT_DIR/examples" "$VM_NAME":~/gcp-setup/

cat <<EOF

VM is ready. Finish setup on the VM:

  gcloud compute ssh $VM_NAME --zone $ZONE --tunnel-through-iap
  bash ~/gcp-setup/setup-gcp-datasci.sh

Stop the VM when you're not using it (you only pay for disk while stopped):

  gcloud compute instances stop $VM_NAME --zone $ZONE
  gcloud compute instances start $VM_NAME --zone $ZONE
EOF
