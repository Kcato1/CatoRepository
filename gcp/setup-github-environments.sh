#!/bin/bash
#
# Creates the GitHub environments used by .github/workflows/deploy-cloud-run.yml:
#   production - you (the logged-in gh user) must approve each deploy; only main may deploy.
#   preview    - no rules; PR preview deploys show up under it.
# Needs gh logged in as a repo admin. Safe to re-run.
#
# Usage: bash setup-github-environments.sh [OWNER/REPO]
#

set -euo pipefail

REPO=${1:-Kcato1/CatoRepository}
REVIEWER_ID=$(gh api user --jq .id)
REVIEWER=$(gh api user --jq .login)

gh api -X PUT "repos/$REPO/environments/production" --input - >/dev/null <<EOF
{
  "reviewers": [{"type": "User", "id": $REVIEWER_ID}],
  "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}
}
EOF

if ! gh api "repos/$REPO/environments/production/deployment-branch-policies" \
        --jq '.branch_policies[].name' | grep -qx main; then
    gh api -X POST "repos/$REPO/environments/production/deployment-branch-policies" \
        -f name=main -f type=branch >/dev/null
fi

gh api -X PUT "repos/$REPO/environments/preview" >/dev/null

echo "production: deploys from main wait for approval by $REVIEWER."
echo "Add more reviewers under Settings -> Environments -> production."
