#!/usr/bin/env bash
# Examples for the native POST /extract endpoint.
# Requires: curl, jq

BASE="${LOCAL_EXTRACT_BASE_URL:-http://localhost:8090}"

echo "=== Basic markdown + text extraction ==="
curl -s "${BASE}/extract" \
  -H "content-type: application/json" \
  -d '{
    "url": "https://example.com",
    "formats": ["markdown", "text", "metadata"]
  }' | jq

echo ""
echo "=== HTML format ==="
curl -s "${BASE}/extract" \
  -H "content-type: application/json" \
  -d '{
    "url": "https://example.com",
    "formats": ["html"],
    "max_content_chars": 50000
  }' | jq '.html | .[0:500]'

echo ""
echo "=== With timeout override ==="
curl -s "${BASE}/extract" \
  -H "content-type: application/json" \
  -d '{
    "url": "https://example.com",
    "formats": ["markdown"],
    "timeout_seconds": 10
  }' | jq '.success, .metadata.elapsed_ms'
