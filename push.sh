#!/bin/bash

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
DARK_GRAY='\033[1;30m'
NC='\033[0m'

SOURCE_USER="${SOURCE_GITHUB_USER}"
DEST_ORG="${DEST_GITHUB_ORG}"
API="https://api.github.com"

# Detect whether destination is an org or a personal account (one call, before the loop)
dest_type=$(curl -s \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    "${API}/users/${DEST_ORG}" \
    | grep '"type"' | head -1 | sed 's/.*"type": *"\([^"]*\)".*/\1/')
if [[ "$dest_type" == "Organization" ]]; then
    CREATE_ENDPOINT="${API}/orgs/${DEST_ORG}/repos"
else
    CREATE_ENDPOINT="${API}/user/repos"
fi

for project_name in "$@"
do
    echo -e "${BLUE}push.sh > start $project_name${NC}"

    if (
        echo -e "${DARK_GRAY}Cloning ${SOURCE_USER}/${project_name} (mirror)...${NC}"
        git clone --mirror "https://oauth2:${GH_TOKEN}@github.com/${SOURCE_USER}/${project_name}.git" "${project_name}.git"

        echo -e "${DARK_GRAY}Fetching metadata...${NC}"
        repo_info=$(curl -s \
            -H "Authorization: Bearer ${GH_TOKEN}" \
            "${API}/repos/${SOURCE_USER}/${project_name}")

        # Extract raw JSON values to embed directly in payloads.
        # head -1 guards against duplicate keys in the response.
        desc_raw=$(echo "$repo_info" | grep '"description"' | head -1 | sed 's/.*"description": *//' | sed 's/,$//' | tr -d '\r')
        [ -z "$desc_raw" ] && desc_raw="null"

        # tr -d '\n ' collapses multi-line pretty-printed JSON to one line
        # before grep, ensuring the match works on both macOS and Linux.
        topics_raw=$(curl -s \
            -H "Authorization: Bearer ${GH_TOKEN}" \
            "${API}/repos/${SOURCE_USER}/${project_name}/topics" \
            | tr -d '\n ' | grep -o '"names":\[[^]]*\]' | sed 's/"names"://')
        [ -z "$topics_raw" ] && topics_raw="[]"

        # Determine visibility
        case "${REPO_VISIBILITY:-mirror}" in
            private) private_val="true" ;;
            public)  private_val="false" ;;
            *)       private_val=$(echo "$repo_info" | grep '"private"' | head -1 | sed 's/.*"private": *//' | sed 's/,.*//' | tr -d ' \r') ;;
        esac
        [ -z "$private_val" ] && private_val="false"

        status=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer ${GH_TOKEN}" \
            "${API}/repos/${DEST_ORG}/${project_name}")

        if [[ "$status" == "200" ]]; then
            echo -e "${DARK_GRAY}${DEST_ORG}/${project_name} already exists, updating metadata...${NC}"
            curl -s -X PATCH \
                -H "Authorization: Bearer ${GH_TOKEN}" \
                -H "Content-Type: application/json" \
                "${API}/repos/${DEST_ORG}/${project_name}" \
                -d "{\"description\": ${desc_raw}, \"private\": ${private_val}}" > /dev/null
        else
            echo -e "${DARK_GRAY}Creating ${DEST_ORG}/${project_name}...${NC}"
            curl -s -X POST \
                -H "Authorization: Bearer ${GH_TOKEN}" \
                -H "Content-Type: application/json" \
                "${CREATE_ENDPOINT}" \
                -d "{\"name\": \"${project_name}\", \"private\": ${private_val}, \"description\": ${desc_raw}}" > /dev/null
        fi

        echo -e "${DARK_GRAY}Setting topics...${NC}"
        curl -s -X PUT \
            -H "Authorization: Bearer ${GH_TOKEN}" \
            -H "Content-Type: application/json" \
            "${API}/repos/${DEST_ORG}/${project_name}/topics" \
            -d "{\"names\": ${topics_raw}}" > /dev/null

        echo -e "${DARK_GRAY}Pushing all branches and tags...${NC}"
        cd "${project_name}.git"
        git push --mirror "git@github.com:${DEST_ORG}/${project_name}.git"
    ); then
        echo -e "${GREEN}push.sh > $project_name pushed to ${DEST_ORG}${NC}"
    else
        echo -e "${RED}push.sh > $project_name failed, skipping${NC}"
    fi

    rm -rf "${project_name}.git" 2>/dev/null || true
    echo -e "${BLUE}push.sh > $project_name local folder removed${NC}"
done
