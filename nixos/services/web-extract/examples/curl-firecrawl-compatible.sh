#!/usr/bin/env bash
# Examples for the Firecrawl-compatible POST /v1/scrape endpoint.
# Requires: curl, jq

BASE="${LOCAL_EXTRACT_BASE_URL:-http://localhost:8090}"

echo "=== Basic Firecrawl-compatible scrape ==="
curl -s "${BASE}/v1/scrape" \
  -H "content-type: application/json" \
  -d '{
    "url": "https://example.com",
    "formats": ["markdown"]
  }' | jq

echo ""
echo "=== With camelCase Firecrawl-style fields ==="
curl -s "${BASE}/v1/scrape" \
  -H "content-type: application/json" \
  -d '{
    "url": "https://example.com",
    "formats": ["markdown", "html"],
    "onlyMainContent": true,
    "timeout": 15000
  }' | jq '.data.metadata'

echo ""
echo "=== Health check ==="
curl -s "${BASE}/v1/health" | jq
