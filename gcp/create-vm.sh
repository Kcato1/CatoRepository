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

# SSH only via IAP. The default network's default-allow-ssh (priority 65534) opens port 22 to the
# internet, so tagged VMs get an IAP allow (900) and an explicit deny (1000) that both outrank it.
NETWORK_TAG=datasci-iap-ssh
if ! gcloud compute firewall-rules describe datasci-allow-iap-ssh >/dev/null 2>&1; then
    gcloud compute firewall-rules create datasci-allow-iap-ssh \
        --network=default \
        --direction=INGRESS \
        --action=ALLOW \
        --rules=tcp:22 \
        --source-ranges=35.235.240.0/20 \
        --target-tags="$NETWORK_TAG" \
        --priority=900 \
        --description="SSH via Identity-Aware Proxy"
fi
if ! gcloud compute firewall-rules describe datasci-deny-public-ssh >/dev/null 2>&1; then
    gcloud compute firewall-rules create datasci-deny-public-ssh \
        --network=default \
        --direction=INGRESS \
        --action=DENY \
        --rules=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --target-tags="$NETWORK_TAG" \
        --priority=1000 \
        --description="Block SSH from anywhere except IAP"
fi

if gcloud compute instances describe "$VM_NAME" --zone "$ZONE" >/dev/null 2>&1; then
    echo "VM $VM_NAME already exists; making sure it has the IAP-only SSH tag."
    gcloud compute instances add-tags "$VM_NAME" --zone "$ZONE" --tags="$NETWORK_TAG"
else
    gcloud compute instances create "$VM_NAME" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --image-family=ubuntu-2404-lts-amd64 \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size="$DISK_SIZE" \
        --boot-disk-type=pd-balanced \
        --scopes=cloud-platform \
        --tags="$NETWORK_TAG" \
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
