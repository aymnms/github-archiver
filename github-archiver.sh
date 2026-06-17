#!/bin/bash

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/github-archiver"
ENV_PATH="$CONFIG_DIR/.env"
mkdir -p "$CONFIG_DIR"

# ── Dependency check ─────────────────────────────────────────────────────────

missing=()
for cmd in git curl ssh; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Missing dependencies: ${missing[*]}${NC}"
    echo -e "${DIM}Install them and run the script again.${NC}"
    exit 1
fi

usage() {
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  ${GREEN}github-archiver${NC} ${DIM}[--delete] <repo1> [repo2...]${NC}"
    echo -e "  ${GREEN}github-archiver --setup${NC}"
    echo -e "  ${GREEN}github-archiver --setup${NC} ${DIM}[--delete] <repo1> [...]${NC}"
    echo ""
    echo -e "  ${DIM}--delete  Delete the source repo after a successful mirror${NC}"
    echo -e "  ${DIM}          Requires 'delete_repo' scope (classic) or Administration: write (fine-grained)${NC}"
    echo ""
}

prompt() {
    local label="$1"
    local hint="${2:-}"
    local secret="${3:-false}"
    local value

    if [[ -n "$hint" ]]; then
        echo -e "  ${YELLOW}${label}${NC} ${DIM}(${hint})${NC}" >&2
    else
        echo -e "  ${YELLOW}${label}${NC}" >&2
    fi

    if [[ "$secret" == "true" ]]; then
        read -rsp "  > " value
        echo "" >&2
    else
        read -rp "  > " value
    fi

    value="${value#\'}" ; value="${value%\'}"
    value="${value#\"}" ; value="${value%\"}"

    echo "$value"
}

setup() {
    echo ""
    echo -e "${BOLD}${BLUE}Setup${NC}"
    echo -e "${DIM}Settings will be saved to ${ENV_PATH}.${NC}"
    echo ""

    echo -e "  ${DIM}Token permissions required:${NC}"
    echo -e "  ${DIM}  Classic token  → scope 'repo' (+ 'delete_repo' if using --delete)${NC}"
    echo -e "  ${DIM}  Fine-grained   → Contents: read, Metadata: read, Administration: write${NC}"
    echo -e "  ${DIM}  (+ Members: read if destination is an organization)${NC}"
    echo ""

    while true; do
        gh_token=$(prompt \
            "GitHub Personal Access Token" \
            "" \
            "true")

        echo -e "  ${DIM}Validating token...${NC}"
        token_status=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer ${gh_token}" \
            "https://api.github.com/user")

        if [[ "$token_status" == "200" ]]; then
            echo -e "  ${GREEN}Token valid.${NC}"
            break
        else
            echo -e "  ${RED}Invalid or expired token (HTTP ${token_status}). Try again.${NC}"
        fi
    done

    default_user=$(git config --global user.name 2>/dev/null || true)
    source_input=$(prompt \
        "Source GitHub username" \
        "leave empty to use ${default_user:-your local git username}")
    source_user="${source_input:-$default_user}"

    dest_org=$(prompt \
        "Destination GitHub org or user" \
        "where to archive repos")

    visibility=$(prompt \
        "Visibility of archived repos" \
        "public / private / mirror (copies source visibility)")
    visibility="${visibility:-mirror}"

    cat > "$ENV_PATH" <<EOF
GH_TOKEN="$gh_token"
SOURCE_GITHUB_USER="$source_user"
DEST_GITHUB_ORG="$dest_org"
REPO_VISIBILITY="$visibility"
EOF

    echo ""
    echo -e "${GREEN}Configuration saved.${NC}"
    echo ""
}

# ── Parse args ───────────────────────────────────────────────────────────────

FORCE_SETUP=false
DELETE_SOURCE=false
PROJECTS=()

for arg in "$@"; do
    case "$arg" in
        --setup)  FORCE_SETUP=true ;;
        --delete) DELETE_SOURCE=true ;;
        *)        PROJECTS+=("$arg") ;;
    esac
done

if [[ "$FORCE_SETUP" == false && ${#PROJECTS[@]} -eq 0 ]]; then
    usage
    exit 1
fi

# ── Setup if needed ──────────────────────────────────────────────────────────

if [[ "$FORCE_SETUP" == true || ! -f "$ENV_PATH" ]]; then
    if [[ ! -f "$ENV_PATH" ]]; then
        echo -e "${YELLOW}No configuration found. Running initial setup.${NC}"
    fi
    setup
fi

# ── Run ──────────────────────────────────────────────────────────────────────

if [[ ${#PROJECTS[@]} -gt 0 ]]; then
    set -o allexport
    source "$ENV_PATH"
    set +o allexport

    export DELETE_SOURCE
    "$SCRIPT_DIR/push.sh" "${PROJECTS[@]}"
fi
