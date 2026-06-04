#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  RESOURCE_GROUP
  AOAI_RESOURCE_NAME
  MODEL_NAME
  MODEL_VERSION
  DEPLOYMENT_NAME
  CAPACITY_TPM
  SCALE_TYPE
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::Missing required variable: $var"
    exit 1
  fi
done

state=$(az cognitiveservices account show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AOAI_RESOURCE_NAME" \
  --query properties.provisioningState \
  -o tsv 2>/dev/null || echo "NotFound")

if [[ "$state" != "Succeeded" ]]; then
  echo "::error::Azure OpenAI resource '$AOAI_RESOURCE_NAME' is not ready (state: $state)."
  exit 1
fi

payload_file=$(mktemp)
trap 'rm -f "$payload_file"' EXIT

cat > "$payload_file" <<EOF
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

echo "Deploying $MODEL_NAME:$MODEL_VERSION to $AOAI_RESOURCE_NAME as $DEPLOYMENT_NAME"

az cognitiveservices account deployment create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AOAI_RESOURCE_NAME" \
  --deployment-name "$DEPLOYMENT_NAME" \
  --properties @"$payload_file"
