#!/usr/bin/env bash
# =============================================================================
# deploy_aoai_model.sh
# Deploys (creates or updates) a model on an Azure OpenAI resource.
#
# Environment variables (injected by the GitHub Actions workflow):
#   RESOURCE_GROUP      – Azure Resource Group name
#   AOAI_RESOURCE_NAME  – Azure OpenAI account name
#   MODEL_NAME          – Model ID  (e.g. gpt-4o)
#   MODEL_VERSION       – Model version (e.g. 2024-11-20)
#   DEPLOYMENT_NAME     – Deployment slug used in API calls
#   CAPACITY_TPM        – Capacity in TPM × 1000 (e.g. "10" = 10 000 TPM)
#   SCALE_TYPE          – Standard | GlobalStandard | ProvisionedManaged
# =============================================================================
set -euo pipefail

# ── Validate required env vars ───────────────────────────────────────────────
REQUIRED_VARS=(
  RESOURCE_GROUP AOAI_RESOURCE_NAME MODEL_NAME
  MODEL_VERSION DEPLOYMENT_NAME CAPACITY_TPM SCALE_TYPE
)
for VAR in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!VAR:-}" ]]; then
    echo "::error::Required environment variable '$VAR' is not set."
    exit 1
  fi
done

echo ""
echo "════════════════════════════════════════════════════"
echo "  Azure OpenAI — Model Deployment"
echo "════════════════════════════════════════════════════"
echo "  Resource Group : $RESOURCE_GROUP"
echo "  AOAI Resource  : $AOAI_RESOURCE_NAME"
echo "  Model          : $MODEL_NAME  (v$MODEL_VERSION)"
echo "  Deployment     : $DEPLOYMENT_NAME"
echo "  Capacity       : ${CAPACITY_TPM}k TPM"
echo "  Scale type     : $SCALE_TYPE"
echo "════════════════════════════════════════════════════"
echo ""

# ── Verify the AOAI resource exists ──────────────────────────────────────────
echo "▶ Verifying Azure OpenAI resource..."
RESOURCE_STATE=$(az cognitiveservices account show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AOAI_RESOURCE_NAME" \
  --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NotFound")

if [[ "$RESOURCE_STATE" != "Succeeded" ]]; then
  echo "::error::Azure OpenAI resource '$AOAI_RESOURCE_NAME' not found or not ready (state: $RESOURCE_STATE)."
  exit 1
fi
echo "  ✔ Resource is ready (state: $RESOURCE_STATE)"

# ── Confirm model availability in the region ──────────────────────────────────
echo ""
echo "▶ Confirming model '$MODEL_NAME@$MODEL_VERSION' is available..."
AVAILABLE=$(az cognitiveservices account list-skus \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AOAI_RESOURCE_NAME" \
  --query "[?name=='$MODEL_NAME'].name" -o tsv 2>/dev/null | head -n1 || echo "")

# NOTE: list-skus doesn't always reliably filter by model name across all CLI versions.
# The deployment step below will fail with a clear error if the model is unavailable.
if [[ -z "$AVAILABLE" ]]; then
  echo "  ⚠ Could not confirm model availability via list-skus — proceeding anyway."
  echo "    (The deployment step will surface any quota/availability errors.)"
else
  echo "  ✔ Model '$MODEL_NAME' found in available SKUs."
fi

# ── Build the deployment JSON body ────────────────────────────────────────────
# We write it to a temp file to avoid shell-quoting issues with az CLI.
DEPLOY_JSON=$(mktemp /tmp/aoai_deploy_XXXXXX.json)
cat > "$DEPLOY_JSON" <<EOF
{
  "sku": {
    "name": "${SCALE_TYPE}",
    "capacity": ${CAPACITY_TPM}
  },
  "properties": {
    "model": {
      "format": "OpenAI",
      "name": "${MODEL_NAME}",
      "version": "${MODEL_VERSION}"
    }
  }
}
EOF

echo ""
echo "▶ Applying deployment..."
cat "$DEPLOY_JSON"
echo ""

# ── Create or update the deployment ──────────────────────────────────────────
az cognitiveservices account deployment create \
  --resource-group "$RESOURCE_GROUP" \
  --name           "$AOAI_RESOURCE_NAME" \
  --deployment-name "$DEPLOYMENT_NAME" \
  --properties     @"$DEPLOY_JSON"

# ── Cleanup temp file ─────────────────────────────────────────────────────────
rm -f "$DEPLOY_JSON"

echo ""
echo "  ✔ Deployment command accepted. Workflow will now poll for completion."
