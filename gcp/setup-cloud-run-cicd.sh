#!/bin/bash
#
# One-time GCP setup for .github/workflows/deploy-cloud-run.yml.
# Creates the Artifact Registry repo, deploy/runtime service accounts, and a
# Workload Identity Federation provider so GitHub Actions can deploy without
# a stored key. Safe to re-run.
#
# Usage: bash setup-cloud-run-cicd.sh PROJECT_ID [REGION]
#

set -euo pipefail

PROJECT_ID=${1:?Usage: $0 PROJECT_ID [REGION]}
REGION=${2:-us-central1}

GITHUB_REPO="Kcato1/CatoRepository"
# Numeric IDs are immutable, unlike names, so a renamed or re-created repo can't inherit access.
GITHUB_REPO_ID="920805771"

AR_REPO="catoconsting"
POOL="github"
PROVIDER="github-actions"
DEPLOY_SA_NAME="catoconsting-deployer"
RUNTIME_SA_NAME="catoconsting-runtime"
DEPLOY_SA="$DEPLOY_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
RUNTIME_SA="$RUNTIME_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

gcloud config set project "$PROJECT_ID" >/dev/null
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

echo "Enabling APIs..."
gcloud services enable \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    sts.googleapis.com

echo "Artifact Registry repository..."
if ! gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" >/dev/null 2>&1; then
    gcloud artifacts repositories create "$AR_REPO" \
        --repository-format=docker \
        --location="$REGION" \
        --description="Catoconsting container images"
fi

echo "Service accounts..."
for name in "$DEPLOY_SA_NAME" "$RUNTIME_SA_NAME"; do
    if ! gcloud iam service-accounts describe "$name@$PROJECT_ID.iam.gserviceaccount.com" >/dev/null 2>&1; then
        gcloud iam service-accounts create "$name" --display-name="$name"
    fi
done

echo "Granting deploy permissions..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$DEPLOY_SA" --role="roles/run.admin" --condition=None >/dev/null
gcloud artifacts repositories add-iam-policy-binding "$AR_REPO" --location="$REGION" \
    --member="serviceAccount:$DEPLOY_SA" --role="roles/artifactregistry.writer" >/dev/null
# Lets the deployer run the service as the runtime account (which has no roles by default).
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA" \
    --member="serviceAccount:$DEPLOY_SA" --role="roles/iam.serviceAccountUser" >/dev/null

echo "Workload Identity Federation..."
if ! gcloud iam workload-identity-pools describe "$POOL" --location=global >/dev/null 2>&1; then
    gcloud iam workload-identity-pools create "$POOL" \
        --location=global --display-name="GitHub Actions"
fi
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER" \
        --location=global --workload-identity-pool="$POOL" >/dev/null 2>&1; then
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
        --location=global \
        --workload-identity-pool="$POOL" \
        --display-name="GitHub Actions" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.ref=assertion.ref" \
        --attribute-condition="assertion.repository_id=='$GITHUB_REPO_ID' && assertion.ref=='refs/heads/main'"
fi
gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/attribute.repository_id/$GITHUB_REPO_ID" \
    >/dev/null

WIF_PROVIDER="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/providers/$PROVIDER"

cat <<EOF

GCP side is ready. Set these GitHub repository variables (Settings -> Secrets and
variables -> Actions -> Variables), or run:

  gh variable set GCP_PROJECT_ID                 --repo $GITHUB_REPO --body "$PROJECT_ID"
  gh variable set GCP_REGION                     --repo $GITHUB_REPO --body "$REGION"
  gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --repo $GITHUB_REPO --body "$WIF_PROVIDER"
  gh variable set GCP_DEPLOY_SERVICE_ACCOUNT     --repo $GITHUB_REPO --body "$DEPLOY_SA"
  gh variable set GCP_RUNTIME_SERVICE_ACCOUNT    --repo $GITHUB_REPO --body "$RUNTIME_SA"

Only workflow runs on the main branch of $GITHUB_REPO can authenticate.

If the app needs other GCP services at runtime, grant roles to $RUNTIME_SA, e.g.:
  gcloud projects add-iam-policy-binding $PROJECT_ID \\
      --member=serviceAccount:$RUNTIME_SA --role=roles/cloudsql.client
EOF
