# CLAUDE.md

Context for AI assistants working on this project.

## What it is

`github-archiver` is a bash CLI tool that mirrors GitHub repositories to another account or organization. It copies all branches, tags, description, topics, and visibility. Zero dependencies beyond `git`, `curl`, and `ssh`.

Current version: **1.0.5**

## Repos

- `github.com/aymnms/github-archiver` — this repo (the tool)
- `github.com/aymnms/homebrew-tap` — Homebrew tap (`Formula/github-archiver.rb`)
- `github.com/aymnms-archives/.github` — org profile, mirrors `github-archiver.sh` as `run.sh`
- Local paths:
  - `/Users/aymnms/Documents/dev/github-archiver/`
  - `/Users/aymnms/Documents/dev/homebrew-tap/`
  - `/Users/aymnms/Documents/dev/.github/`

## Architecture

Two scripts:

- `github-archiver.sh` — entry point: dependency check, setup wizard, loads `.env`, calls `push.sh`
- `push.sh` — core logic: mirror clone, GitHub API calls, push, optional source deletion, run summary

Config stored at `~/.config/github-archiver/.env` (XDG standard).

## .env variables

```
GH_TOKEN            # GitHub PAT (scopes: repo + delete_repo if using --delete)
SOURCE_GITHUB_USER  # GitHub account to clone FROM
DEST_GITHUB_ORG     # GitHub account or org to archive TO
REPO_VISIBILITY     # public | private | mirror (default: mirror)
```

## CLI

```bash
github-archiver --setup                      # first-time configuration
github-archiver <repo1> [repo2...]           # mirror repos
github-archiver --delete <repo1> [...]       # mirror then delete source
github-archiver --version                    # print current version
```

## Installation

```bash
brew install aymnms/tap/github-archiver
brew upgrade github-archiver
brew uninstall github-archiver
```

## Key design decisions

- **`git clone --mirror` + `git push --mirror`** — copies all branches, tags, and refs, not just the current branch
- **Strip `refs/pull/*` before push** — GitHub rejects these internal refs; git may exit 0 despite errors, causing false success and unwanted source deletion
- **Subshell per project** — isolates `cd` and `set -e` so a failure on one repo doesn't cascade to the next
- **`curl` + `grep`/`sed` only** — no `gh` CLI, no `python3`, no external dependencies
- **`tr -d '\n '` before grep on topics** — GitHub API returns pretty-printed JSON; grep is line-by-line and would miss multi-line arrays without this
- **Org vs user endpoint detection** — `GET /users/:dest` checks `"type"` field to choose between `POST /orgs/:org/repos` and `POST /user/repos`
- **`~/.config/github-archiver/`** — XDG Base Directory standard, consistent with `gh` CLI; works correctly whether run locally or installed via Homebrew
- **GitHub login from API** — `GET /user` is called during token validation; `"login"` field is extracted and used as default source username (not `git config user.name` which is a display name, not an identifier)
- **Run summary** — tracked in parent shell via `SUCCEEDED` / `FAILED` arrays (not inside subshells); printed after the loop

## Open issues

- **#1** `bug: no validation of required fields in setup` — empty `dest_org` or `source_user` saves silently and fails at run time
- **#2** `bug: REPO_VISIBILITY not validated in setup` — invalid value silently falls through to `mirror` behavior
- **#3** `feat: add --dry-run flag` — show what would happen without executing write operations

## Release process

Every release requires bumping the version, tagging, and updating the Formula:

```bash
# 1. Bump VERSION in github-archiver.sh, commit and push
git tag vX.Y.Z && git push origin vX.Y.Z

# 2. Create GitHub release via API
curl -s -X POST -H "Authorization: Bearer $GH_TOKEN" \
  https://api.github.com/repos/aymnms/github-archiver/releases \
  -d '{"tag_name":"vX.Y.Z","name":"vX.Y.Z","body":"...","draft":false,"prerelease":false}'

# 3. Compute SHA256 of the tarball
curl -sL https://github.com/aymnms/github-archiver/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256

# 4. Update url + sha256 in homebrew-tap/Formula/github-archiver.rb
# 5. Commit and push homebrew-tap
# 6. Sync github-archiver.sh → run.sh in aymnms-archives/.github
```

## What to keep in sync

After any change to `github-archiver.sh` or `push.sh`, sync to `aymnms-archives/.github`:
- `github-archiver.sh` → copied as `run.sh`
- `push.sh` → copied as `push.sh`
