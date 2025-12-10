#!/usr/bin/env bash

# eoAPI Container Image Root User Check

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

CHART_PATH="${PROJECT_ROOT}/charts/eoapi"
PROFILE_PATH="${PROJECT_ROOT}/charts/eoapi/profiles/experimental.yaml"

echo "======================================"
echo "Container Image Root User Audit"
echo "======================================"
echo ""

# Extract images from Helm templates
if ! command -v helm &>/dev/null; then
  log_error "helm is required but not installed"
  exit 1
fi

# Extract images, excluding testing-only images
# Filters out: Helm test hooks, mock/sample/test images
if [[ ! -f "$PROFILE_PATH" ]]; then
  log_error "Experimental profile not found: $PROFILE_PATH"
  exit 1
fi

# Update Helm dependencies if needed
log_debug "Updating Helm chart dependencies..."
if ! helm dependency update "$CHART_PATH" &>/dev/null; then
  log_warn "Helm dependency update failed, continuing anyway..."
fi

rendered_yaml=$(helm template test-release "$CHART_PATH" \
  --set gitSha=test \
  -f "$PROFILE_PATH" \
  --set stac-auth-proxy.enabled=false \
  2>&1 || \
helm template test-release "$CHART_PATH" \
  --set gitSha=test \
  -f "$PROFILE_PATH" \
  --set stac-auth-proxy.env.OIDC_DISCOVERY_URL=https://dummy.example.com/.well-known/openid-configuration \
  2>&1)

if [[ -z "$rendered_yaml" ]] || echo "$rendered_yaml" | grep -q "Error:"; then
  log_error "Failed to render Helm templates"
  echo "$rendered_yaml" | head -20
  exit 1
fi

images=()
while IFS= read -r line; do
  [[ -n "$line" ]] && images+=("$line")
done < <(
  # Extract images with context to identify test hooks
  echo "$rendered_yaml" | awk '
    BEGIN { in_test_hook = 0 }
    /^---/ { in_test_hook = 0 }
    /helm\.sh\/hook.*test/ { in_test_hook = 1 }
    /^\s+(- )?image:/ {
      image = $0
      gsub(/.*image:\s*/, "", image)
      gsub(/["'\''"]/, "", image)
      gsub(/^[[:space:]]+/, "", image)
      if (image && image != "") {
        # Skip if in test hook
        if (!in_test_hook) {
          # Skip images with testing patterns (but allow "test-release" in image names)
          if (image !~ /\/mock/ &&
              image !~ /\/sample/ &&
              image !~ /\/bats\// &&
              image !~ /mock-/ &&
              image !~ /-mock/ &&
              image !~ /sample/ &&
              image !~ /bats:/) {
            print image
          }
        }
      }
    }
  ' | sort -u
)

if [[ ${#images[@]} -eq 0 ]]; then
  log_error "No images found in Helm templates"
  log_info "Rendered YAML length: ${#rendered_yaml} characters"
  exit 1
fi

log_debug "Found ${#images[@]} images to check"

total=0
root_count=0
non_root_count=0
error_count=0

check_image() {
  local image=$1
  local user

  echo -n "Checking: $image ... "

  if docker pull "$image" &>/dev/null; then
    if ! user=$(docker inspect "$image" --format='{{.Config.User}}' 2>/dev/null); then
      echo -e "${RED}ERROR${NC} (Failed to inspect)"
      ((error_count++))
      return
    fi

    if [ -z "$user" ] || [ "$user" == "0" ] || [ "$user" == "root" ] || [ "$user" == "0:0" ]; then
      echo -e "${RED}⚠️  RUNS AS ROOT${NC} (User: ${user:-not set})"
      ((root_count++))
    else
      echo -e "${GREEN}✓ Non-root${NC} (User: $user)"
      ((non_root_count++))
    fi
  else
    echo -e "${YELLOW}SKIP${NC} (Failed to pull image)"
    ((error_count++))
  fi
}

for image in "${images[@]}"; do
  check_image "$image" || true
  ((total++)) || true
done

echo ""
echo "======================================"
echo "Summary"
echo "======================================"
echo "Total images checked: $total"
echo -e "${RED}Running as root: $root_count${NC}"
echo -e "${GREEN}Running as non-root: $non_root_count${NC}"
echo -e "${YELLOW}Errors/Skipped: $error_count${NC}"
echo ""

if [ $root_count -gt 0 ]; then
  echo -e "${RED}⚠️  WARNING: $root_count image(s) run as root user${NC}"
  exit 1
else
  echo -e "${GREEN}✓ All images run as non-root user${NC}"
  exit 0
fi
