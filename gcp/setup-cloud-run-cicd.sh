#!/bin/bash
#
# One-time GCP setup for .github/workflows/deploy-cloud-run.yml. Safe to re-run.
#
# Production: Artifact Registry repo, deployer + runtime service accounts, a public
#   catoconsting service, and a Workload Identity Federation provider that only trusts
#   jobs on main running in the "production" GitHub environment.
# Previews: the same set again, fully separate (catoconsting-preview service, private),
#   trusting pull_request runs. Nothing preview-side can touch production.
#
# Usage: bash setup-cloud-run-cicd.sh PROJECT_ID [REGION]
#

set -euo pipefail

PROJECT_ID=${1:?Usage: $0 PROJECT_ID [REGION]}
REGION=${2:-us-central1}

GITHUB_REPO="Kcato1/CatoRepository"
# Numeric IDs are immutable, unlike names, so a renamed or re-created repo can't inherit access.
GITHUB_REPO_ID="920805771"

gcloud config set project "$PROJECT_ID" >/dev/null
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

sa_email() {
    local name=$1
    echo "$name@$PROJECT_ID.iam.gserviceaccount.com"
}

ensure_ar_repo() {
    local repo=$1
    if ! gcloud artifacts repositories describe "$repo" --location="$REGION" >/dev/null 2>&1; then
        gcloud artifacts repositories create "$repo" \
            --repository-format=docker --location="$REGION" --description="$repo container images"
    fi
}

ensure_sa() {
    local name=$1
    if ! gcloud iam service-accounts describe "$(sa_email "$name")" >/dev/null 2>&1; then
        gcloud iam service-accounts create "$name" --display-name="$name"
    fi
}

# Created from Google's placeholder image so deploy roles can be scoped to the service itself.
ensure_service() {
    local service=$1 runtime_sa=$2
    if ! gcloud run services describe "$service" --region="$REGION" >/dev/null 2>&1; then
        gcloud run deploy "$service" \
            --region="$REGION" \
            --image=us-docker.pkg.dev/cloudrun/container/hello \
            --service-account="$runtime_sa" \
            --no-allow-unauthenticated \
            --quiet
    fi
}

# run.developer on one service: deploy revisions and move tags/traffic, but no IAM changes
# and no access to other services.
grant_deployer() {
    local service=$1 repo=$2 deploy_sa=$3 runtime_sa=$4
    gcloud run services add-iam-policy-binding "$service" --region="$REGION" \
        --member="serviceAccount:$deploy_sa" --role="roles/run.developer" >/dev/null
    gcloud artifacts repositories add-iam-policy-binding "$repo" --location="$REGION" \
        --member="serviceAccount:$deploy_sa" --role="roles/artifactregistry.writer" >/dev/null
    gcloud iam service-accounts add-iam-policy-binding "$runtime_sa" \
        --member="serviceAccount:$deploy_sa" --role="roles/iam.serviceAccountUser" >/dev/null
}

# One pool per trust level: a principalSet binding matches identities from every provider
# in its pool, so production and preview must not share one.
ensure_wif() {
    local pool=$1 provider=$2 condition=$3 deploy_sa=$4
    local mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id"
    if ! gcloud iam workload-identity-pools describe "$pool" --location=global >/dev/null 2>&1; then
        gcloud iam workload-identity-pools create "$pool" --location=global --display-name="$pool"
    fi
    # Always (re)apply the mapping and condition, so an existing provider can't keep a looser one.
    if gcloud iam workload-identity-pools providers describe "$provider" \
            --location=global --workload-identity-pool="$pool" >/dev/null 2>&1; then
        gcloud iam workload-identity-pools providers update-oidc "$provider" \
            --location=global --workload-identity-pool="$pool" \
            --attribute-mapping="$mapping" --attribute-condition="$condition"
    else
        gcloud iam workload-identity-pools providers create-oidc "$provider" \
            --location=global --workload-identity-pool="$pool" \
            --display-name="$provider" \
            --issuer-uri="https://token.actions.githubusercontent.com" \
            --attribute-mapping="$mapping" --attribute-condition="$condition"
    fi
    gcloud iam service-accounts add-iam-policy-binding "$deploy_sa" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$pool/attribute.repository_id/$GITHUB_REPO_ID" \
        >/dev/null
}

echo "Enabling APIs..."
gcloud services enable \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    sts.googleapis.com \
    secretmanager.googleapis.com

echo "== Production =="
DEPLOY_SA=$(sa_email catoconsting-deployer)
RUNTIME_SA=$(sa_email catoconsting-runtime)
ensure_ar_repo catoconsting
ensure_sa catoconsting-deployer
ensure_sa catoconsting-runtime
ensure_service catoconsting "$RUNTIME_SA"
grant_deployer catoconsting catoconsting "$DEPLOY_SA" "$RUNTIME_SA"
if ! gcloud run services add-iam-policy-binding catoconsting --region="$REGION" \
        --member="allUsers" --role="roles/run.invoker" >/dev/null 2>&1; then
    echo "WARNING: could not make the service public (an org policy may restrict allUsers)."
    echo "         It will require authenticated requests."
fi
ensure_wif catoconsting-github github-actions \
    "assertion.repository_id=='$GITHUB_REPO_ID' && assertion.ref=='refs/heads/main' && assertion.environment=='production'" \
    "$DEPLOY_SA"

echo "== Previews =="
PREVIEW_DEPLOY_SA=$(sa_email catoconsting-preview-deployer)
PREVIEW_RUNTIME_SA=$(sa_email catoconsting-preview-runtime)
ensure_ar_repo catoconsting-preview
POLICY_FILE=$(mktemp)
trap 'rm -f "$POLICY_FILE"' EXIT
cat > "$POLICY_FILE" <<'EOF'
[{"name": "delete-old-previews", "action": {"type": "Delete"}, "condition": {"tagState": "any", "olderThan": "30d"}}]
EOF
gcloud artifacts repositories set-cleanup-policies catoconsting-preview \
    --location="$REGION" --policy="$POLICY_FILE" --no-dry-run >/dev/null
ensure_sa catoconsting-preview-deployer
ensure_sa catoconsting-preview-runtime
ensure_service catoconsting-preview "$PREVIEW_RUNTIME_SA"
grant_deployer catoconsting-preview catoconsting-preview "$PREVIEW_DEPLOY_SA" "$PREVIEW_RUNTIME_SA"
ensure_wif catoconsting-github-preview github-pull-requests \
    "assertion.repository_id=='$GITHUB_REPO_ID' && assertion.event_name=='pull_request'" \
    "$PREVIEW_DEPLOY_SA"

WIF_PROVIDER="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/catoconsting-github/providers/github-actions"
PREVIEW_WIF_PROVIDER="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/catoconsting-github-preview/providers/github-pull-requests"

cat <<EOF

GCP side is ready. Next:

1. Set the GitHub repository variables:

  gh variable set GCP_PROJECT_ID                         --repo $GITHUB_REPO --body "$PROJECT_ID"
  gh variable set GCP_REGION                             --repo $GITHUB_REPO --body "$REGION"
  gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER         --repo $GITHUB_REPO --body "$WIF_PROVIDER"
  gh variable set GCP_DEPLOY_SERVICE_ACCOUNT             --repo $GITHUB_REPO --body "$DEPLOY_SA"
  gh variable set GCP_RUNTIME_SERVICE_ACCOUNT            --repo $GITHUB_REPO --body "$RUNTIME_SA"
  gh variable set GCP_PREVIEW_WORKLOAD_IDENTITY_PROVIDER --repo $GITHUB_REPO --body "$PREVIEW_WIF_PROVIDER"
  gh variable set GCP_PREVIEW_DEPLOY_SERVICE_ACCOUNT     --repo $GITHUB_REPO --body "$PREVIEW_DEPLOY_SA"
  gh variable set GCP_PREVIEW_RUNTIME_SERVICE_ACCOUNT    --repo $GITHUB_REPO --body "$PREVIEW_RUNTIME_SA"

2. Require your approval for production deploys:

  bash gcp/setup-github-environments.sh

3. Give the app secrets (optional). Store each value in Secret Manager, let the right
   runtime account read it, then reference it from CLOUD_RUN_SECRETS / PREVIEW_SECRETS:

  printf '%s' "\$VALUE" | gcloud secrets create db-password --data-file=-
  gcloud secrets add-iam-policy-binding db-password \\
      --member=serviceAccount:$RUNTIME_SA --role=roles/secretmanager.secretAccessor
  gh variable set CLOUD_RUN_SECRETS --repo $GITHUB_REPO --body "DB_PASSWORD=db-password:latest"

Production deploys only authenticate from main inside the "production" environment.
Previews authenticate from pull_request runs and can only reach catoconsting-preview.
EOF
