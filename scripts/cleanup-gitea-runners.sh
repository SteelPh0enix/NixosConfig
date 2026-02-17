#!/usr/bin/env bash
#
# Gitea Actions Runner Cleanup Script
# Deletes all offline (dead) runners from Gitea instance
#

set -uo pipefail

# Configuration
GITEA_URL="${GITEA_URL:-http://steelph0enix.framework:6969}"
GITEA_TOKEN="${GITEA_TOKEN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_info() {
    echo -e "$1"
}

# Check if token is provided
if [[ -z "$GITEA_TOKEN" ]]; then
    print_error "GITEA_TOKEN environment variable is not set"
    echo "Usage: GITEA_TOKEN=your_token $0"
    echo "Or export GITEA_TOKEN=your_token and then run $0"
    exit 1
fi

# Function to make API calls
gitea_api() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="${3:-}"

    local curl_opts=(
        -s
        -w "\n%{http_code}"
        -H "Authorization: token ${GITEA_TOKEN}"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
    )

    if [[ "$method" != "GET" ]]; then
        curl_opts+=(-X "$method")
    fi

    if [[ -n "$data" ]]; then
        curl_opts+=(-d "$data")
    fi

    local response
    response=$(curl "${curl_opts[@]}" "${GITEA_URL}/api/v1${endpoint}")
    
    # Extract HTTP code (last line) and body (everything else)
    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')
    
    # Check for non-JSON response
    if ! echo "$body" | jq -e . >/dev/null 2>&1; then
        # Not valid JSON, return error object
        echo "{\"error\": \"Invalid response\", \"http_code\": \"$http_code\", \"body\": $(echo "$body" | jq -Rs .)}"
        return 1
    fi
    
    echo "$body"
}

# Function to check if API is accessible
check_api() {
    local response
    response=$(gitea_api "/version" 2>/dev/null || echo '{"error": "connection failed"}')

    if echo "$response" | jq -e '.version' >/dev/null 2>&1; then
        local version
        version=$(echo "$response" | jq -r '.version')
        print_success "Connected to Gitea version: $version"
        return 0
    else
        print_error "Failed to connect to Gitea API at $GITEA_URL"
        print_info "Response: $response"
        return 1
    fi
}

# Function to get all runners
get_runners() {
    local page=1
    local all_runners="[]"
    local response

    while true; do
        if ! response=$(gitea_api "/user/actions/runners?page=${page}&limit=50"); then
            # API call failed, gitea_api already returned an error JSON
            print_error "Failed to fetch runners from API"
            echo "[]"
            return 1
        fi

        # Check if response contains error
        if echo "$response" | jq -e 'has("error")' >/dev/null 2>&1; then
            print_error "API Error: $(echo "$response" | jq -r '.error // "Unknown error"')"
            if echo "$response" | jq -e 'has("body")' >/dev/null 2>&1; then
                print_info "Server response: $(echo "$response" | jq -r '.body' | head -c 200)"
            fi
            echo "[]"
            return 1
        fi

        # Check if response has runners field (it's wrapped in an object)
        if ! echo "$response" | jq -e 'has("runners")' >/dev/null 2>&1; then
            print_error "Unexpected response format from API"
            print_info "Response: $(echo "$response" | head -c 500)"
            echo "[]"
            return 1
        fi

        # Extract runners array from response
        local runners
        runners=$(echo "$response" | jq '.runners')

        # Check if we got any runners
        local count
        count=$(echo "$runners" | jq 'length')

        if [[ "$count" -eq 0 ]]; then
            break
        fi

        # Merge runners into all_runners
        all_runners=$(echo "$all_runners" "$runners" | jq -s 'add')

        ((page++))
    done

    echo "$all_runners"
}

# Function to delete a runner
delete_runner() {
    local runner_id="$1"
    local runner_name="$2"

    local response
    response=$(gitea_api "/user/actions/runners/${runner_id}" "DELETE" 2>&1)

    if [[ -z "$response" ]] || echo "$response" | jq -e 'has("message") | not' >/dev/null 2>&1; then
        print_success "  ✓ Deleted runner: $runner_name (ID: $runner_id)"
        return 0
    else
        print_error "  ✗ Failed to delete runner $runner_name (ID: $runner_id): $(echo "$response" | jq -r '.message // "Unknown error"')"
        return 1
    fi
}

# Main script
main() {
    print_info "=== Gitea Actions Runner Cleanup ==="
    print_info "Gitea URL: $GITEA_URL"
    echo

    # Check dependencies
    if ! command -v curl &>/dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        print_error "jq is required but not installed"
        exit 1
    fi

    # Check API connectivity
    if ! check_api; then
        exit 1
    fi

    echo
    print_info "Fetching runners..."

    local runners
    runners=$(get_runners)

    if [[ -z "$runners" ]] || [[ "$runners" == "[]" ]]; then
        print_warning "No runners found"
        exit 0
    fi

    local total_count
    total_count=$(echo "$runners" | jq 'length')
    print_info "Found $total_count total runner(s)"

    # Get offline runners
    local offline_runners
    offline_runners=$(echo "$runners" | jq '[.[] | select(.status == "offline")]')

    local offline_count
    offline_count=$(echo "$offline_runners" | jq 'length')

    if [[ "$offline_count" -eq 0 ]]; then
        print_success "No offline runners found. Nothing to clean up!"
        exit 0
    fi

    echo
    print_warning "Found $offline_count offline runner(s):"
    echo "$offline_runners" | jq -r '.[] | "  - \(.name) (ID: \(.id), Last Online: \(.last_online // "never"))"'

    echo
    read -rp "Do you want to delete these $offline_count offline runner(s)? [y/N] " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Aborted. No runners were deleted."
        exit 0
    fi

    echo
    print_info "Deleting offline runners..."

    local deleted=0
    local failed=0

    # Process runners one by one
    echo "$offline_runners" | jq -c '.[]' | while IFS= read -r runner; do
        local id name
        id=$(echo "$runner" | jq -r '.id')
        name=$(echo "$runner" | jq -r '.name')
        
        if delete_runner "$id" "$name"; then
            ((deleted++))
        else
            ((failed++))
        fi
    done

    echo
    print_success "Cleanup complete!"
    print_info "Deleted: $deleted runner(s)"
    if [[ "$failed" -gt 0 ]]; then
        print_warning "Failed: $failed runner(s)"
    fi
}

main "$@"
