#!/usr/bin/env bash
# pi-discover — query an OpenAI-compatible provider for its model list
#
# Usage:
#   pi-discover https://api.neuralwatt.ai/v1
#   pi-discover http://localhost:11434/v1
#
# Outputs a JSON snippet you can add to your models.json providers section.
# Pipe through `jq` for pretty-printing if desired.

set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: pi-discover <base-url> [provider-name]" >&2
	echo "" >&2
	echo "Examples:" >&2
	echo "  pi-discover https://api.neuralwatt.ai/v1 neuralwatt" >&2
	echo "  pi-discover http://localhost:11434/v1 ollama" >&2
	exit 1
fi

BASE_URL="${1%/}"
PROVIDER_NAME="${2:-$(echo "$BASE_URL" | sed 's|https\?://||' | sed 's|/.*||' | tr '.' '_')}"

echo "Querying $BASE_URL/v1/models ..." >&2

# Fetch model list
RESPONSE=$(curl -sf "$BASE_URL/v1/models" 2>/dev/null || curl -sf -H "Authorization: Bearer $API_KEY" "$BASE_URL/v1/models" 2>/dev/null) || {
	echo "Error: Could not fetch models from $BASE_URL/v1/models" >&2
	echo "Set API_KEY environment variable if authentication is required." >&2
	exit 1
}

# Extract model IDs and build JSON
echo "$RESPONSE" | jq -r '
.data[] | .id
' | sort | while read -r id; do
	echo "  • $id" >&2
done

echo ""
echo "Add this to your models.json:"
echo ""

echo "$RESPONSE" | jq --arg name "$PROVIDER_NAME" '
{
  "providers": {
    ($name): {
      "baseUrl": $name,
      "api": "openai-completions",
      "apiKey": "$" + ($name | ascii_upcase) + "_API_KEY",
      "models": [.data[] | { id: .id }]
    }
  }
}
' | sed "s|\"baseUrl\": \"$PROVIDER_NAME\"|\"baseUrl\": \"$BASE_URL\"|"

echo ""
echo "Set your API key: export ${PROVIDER_NAME^^}_API_KEY=your-key-here" >&2
