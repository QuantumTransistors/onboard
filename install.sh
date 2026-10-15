#!/usr/bin/env bash
# Usage: install.sh [--dry-run]   (piped: `| bash -s -- --dry-run`)
# Bash 3.2 and a BSD userland.

set -u

REPO=QuantumTransistors/wsctl
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'

DRY=0
CHANGED=0

say() { printf '%s\n' "$*"; }
ok() { say "  ok      $1"; }
did() { say "  done    $1"; CHANGED=1; }
would() { say "  would   $1"; CHANGED=1; }
stop() {
    say "$*" >&2
    exit 1
}
dry_end() {
    say ""
    say "Dry run: nothing was changed. The steps after this one need $1."
    exit 0
}

usage() {
    say "usage: install.sh [--dry-run]" >&2
    exit 2
}

newest_tag() {
    gh api "repos/$REPO/tags?per_page=100" --paginate --jq '.[].name' </dev/null 2>/dev/null |
        grep -E "$TAG_RE" | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -n 1
}

mac_step() {
    if [ "$(uname -s)" != Darwin ]; then
        stop "install.sh sets up a Mac, and this is $(uname -s)."
    fi
}

gh_step() {
    local d
    for d in /opt/homebrew/bin /usr/local/bin; do
        command -v brew >/dev/null 2>&1 || { [ -x "$d/brew" ] && PATH="$d:$PATH"; }
    done
    if command -v gh >/dev/null 2>&1; then
        ok "gh: $(command -v gh)"
        return 0
    fi
    if ! command -v brew >/dev/null 2>&1; then
        say "install.sh installs gh with Homebrew, which this Mac does not have. Run these two, then run this again:" >&2
        say "" >&2
        say "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" >&2
        say "  brew install gh" >&2
        exit 1
    fi
    if [ "$DRY" = 1 ]; then
        would "gh: brew install gh"
        dry_end "gh"
    fi
    brew install gh </dev/null || stop "\`brew install gh\` failed; fix what it says and run this again."
    did "gh: installed with Homebrew"
}

login_step() {
    if gh auth status --hostname github.com >/dev/null 2>&1 </dev/null; then
        ok "gh: logged in to github.com"
        return 0
    fi
    if [ "$DRY" = 1 ]; then
        would "gh: gh auth login --hostname github.com --git-protocol https --web"
        dry_end "that login"
    fi
    say "Logging gh in to GitHub: open the address gh prints in a browser, enter its code and approve."
    gh auth login --hostname github.com --git-protocol https --web </dev/null ||
        stop "\`gh auth login\` did not finish; run this again to retry."
    did "gh: logged in to github.com"
}

clearance_step() {
    local why login
    if why=$(gh api "repos/$REPO" --jq .full_name 2>&1 </dev/null); then
        ok "GitHub: this account can read $REPO"
        return 0
    fi
    login=$(gh api user --jq .login </dev/null 2>/dev/null)
    stop "The GitHub account gh is logged in with, ${login:-(unknown)}, cannot read $REPO (gh said: $(say "$why" | head -n 1)). Ask whoever invited you to give ${login:-that account} access, then run this again."
}

handoff() {
    local tag
    tag=$(newest_tag)
    [ -n "$tag" ] || stop "Could not list $REPO's release tags with gh; run this again."
    ok "wsctl: newest release $tag"
    [ "$CHANGED" = 0 ] && say "  Nothing to do here: every step was already done."
    say ""
    say "Handing over to onboard.sh at $tag."
    set -- "$tag"
    [ "$DRY" = 1 ] && set -- --dry-run "$tag"
    gh api -H 'Accept: application/vnd.github.raw' "repos/$REPO/contents/onboard.sh?ref=$tag" </dev/null |
        "${BASH:-bash}" -s -- "$@"
    local got=("${PIPESTATUS[@]}")
    [ "${got[0]}" = 0 ] || stop "Could not fetch onboard.sh at $tag with gh; run this again."
    exit "${got[1]}"
}

main() {
    while [ $# -gt 0 ]; do
        case $1 in
            --dry-run) DRY=1 ;;
            *) usage ;;
        esac
        shift
    done
    mac_step
    gh_step
    login_step
    clearance_step
    handoff
}

main "$@"
