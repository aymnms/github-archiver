#!/bin/bash

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

VERSION="1.0.4"

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
    echo -e "  ${GREEN}github-archiver --version${NC}"
    echo ""
    echo -e "  ${DIM}--delete   Delete the source repo after a successful mirror${NC}"
    echo -e "  ${DIM}           Requires 'delete_repo' scope (classic) or Administration: write (fine-grained)${NC}"
    echo -e "  ${DIM}--version  Print the current version${NC}"
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

    github_login=""
    while true; do
        gh_token=$(prompt \
            "GitHub Personal Access Token" \
            "" \
            "true")

        echo -e "  ${DIM}Validating token...${NC}"
        user_info=$(curl -s \
            -H "Authorization: Bearer ${gh_token}" \
            "https://api.github.com/user")
        github_login=$(echo "$user_info" | grep '"login"' | head -1 | sed 's/.*"login": *"\([^"]*\)".*/\1/')

        if [[ -n "$github_login" ]]; then
            echo -e "  ${GREEN}Token valid. Signed in as ${github_login}.${NC}"
            break
        else
            echo -e "  ${RED}Invalid or expired token. Try again.${NC}"
        fi
    done

    source_input=$(prompt \
        "Source GitHub username" \
        "leave empty to use ${github_login}")
    source_user="${source_input:-$github_login}"

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
        --setup)   FORCE_SETUP=true ;;
        --delete)  DELETE_SOURCE=true ;;
        --version) echo "github-archiver $VERSION"; exit 0 ;;
        *)         PROJECTS+=("$arg") ;;
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
