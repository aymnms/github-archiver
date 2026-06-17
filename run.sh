#!/bin/bash

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ENV_FILE=".env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="$SCRIPT_DIR/$ENV_FILE"

# ── Dependency check ─────────────────────────────────────────────────────────

missing=()
for cmd in git curl ssh; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Dépendances manquantes : ${missing[*]}${NC}"
    echo -e "${DIM}Installe-les puis relance le script.${NC}"
    exit 1
fi

usage() {
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  ${GREEN}./run.sh${NC} ${DIM}[--delete] <repo1> [repo2...]${NC}"
    echo -e "  ${GREEN}./run.sh --setup${NC}"
    echo -e "  ${GREEN}./run.sh --setup${NC} ${DIM}[--delete] <repo1> [...]${NC}"
    echo ""
    echo -e "  ${DIM}--delete   Delete the source repo after a successful mirror${NC}"
    echo -e "  ${DIM}           Requires 'delete_repo' scope (classic) or Administration: write (fine-grained)${NC}"
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
    echo -e "${BOLD}${BLUE}Configuration${NC}"
    echo -e "${DIM}Les paramètres seront sauvegardés dans ${ENV_FILE}.${NC}"
    echo ""

    echo -e "  ${DIM}Token requis — permissions :${NC}"
    echo -e "  ${DIM}  Classic token  → scope 'repo'${NC}"
    echo -e "  ${DIM}  Fine-grained   → Contents: read, Metadata: read, Administration: write${NC}"
    echo -e "  ${DIM}  (+ Members: read si destination = organisation)${NC}"
    echo ""

    while true; do
        gh_token=$(prompt \
            "GitHub Personal Access Token" \
            "" \
            "true")

        echo -e "  ${DIM}Validation du token...${NC}"
        token_status=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer ${gh_token}" \
            "https://api.github.com/user")

        if [[ "$token_status" == "200" ]]; then
            echo -e "  ${GREEN}Token valide.${NC}"
            break
        else
            echo -e "  ${RED}Token invalide ou expiré (HTTP ${token_status}). Réessaie.${NC}"
        fi
    done

    default_user=$(git config --global user.name 2>/dev/null || true)
    source_input=$(prompt \
        "Nom d'utilisateur GitHub source" \
        "laisser vide pour ${default_user:-votre user git local}")
    source_user="${source_input:-$default_user}"

    dest_org=$(prompt \
        "Organisation ou compte GitHub de destination" \
        "où archiver les repos")

    visibility=$(prompt \
        "Visibilité des repos archivés" \
        "public / private / mirror (copie la visibilité du repo source)")
    visibility="${visibility:-mirror}"

    cat > "$ENV_PATH" <<EOF
GH_TOKEN="$gh_token"
SOURCE_GITHUB_USER="$source_user"
DEST_GITHUB_ORG="$dest_org"
REPO_VISIBILITY="$visibility"
EOF

    echo ""
    echo -e "${GREEN}Configuration sauvegardée.${NC}"
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

# ── Setup si nécessaire ──────────────────────────────────────────────────────

if [[ "$FORCE_SETUP" == true || ! -f "$ENV_PATH" ]]; then
    if [[ ! -f "$ENV_PATH" ]]; then
        echo -e "${YELLOW}Aucune configuration trouvée. Lancement du setup initial.${NC}"
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
