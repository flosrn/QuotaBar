#!/bin/bash
# FORK(flosrn): bring the fork up to an upstream QuotaBar release, then build,
# test, package (signed with a local certificate) and install it.
#
#   Scripts/fork/sync.sh            newest stable release (vX.Y.Z)
#   Scripts/fork/sync.sh --beta     newest release, pre-releases included
#   Scripts/fork/sync.sh --tag v0.5.32
#   Scripts/fork/sync.sh --check    say whether a newer release exists (exit 10 if so)
#   Scripts/fork/sync.sh --rebuild  no rebase: build, test, package, install HEAD
#   Scripts/fork/sync.sh --push     also push the branch to origin afterwards
#   --no-install / --no-test        skip those steps
#
# The fork's commits are rebased onto the release tag, so they stay a short
# stack on top of upstream. Before rebasing, the branch is saved as
# fork-before-<tag>; to undo: git reset --hard fork-before-<tag>.
#
# Environment: SIGN_ID (default "Orca Dev"), APP_DEST (default
# /Applications/QuotaBar.app).
set -euo pipefail
cd "$(dirname "$0")/../.."

BRANCH=fork
UPSTREAM=upstream
SIGN_ID="${SIGN_ID:-Orca Dev}"
APP_DEST="${APP_DEST:-/Applications/QuotaBar.app}"
BACKUP_DIR="$HOME/Library/Caches/quotabar-fork"

beta=0 check=0 rebuild=0 push=0 install=1 test=1 tag=""
while [ $# -gt 0 ]; do
  case "$1" in
    --beta) beta=1 ;;
    --check) check=1 ;;
    --rebuild) rebuild=1 ;;
    --push) push=1 ;;
    --no-install) install=0 ;;
    --no-test) test=0 ;;
    --tag) tag="${2:?--tag needs a tag}"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] && die "a rebase is in progress: resolve it (git status, then git rebase --continue) or undo it (git rebase --abort), then run this again."
[ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || die "check out the '$BRANCH' branch first."
git diff --quiet && git diff --cached --quiet || die "commit or stash your changes first."

say "Fetching $UPSTREAM"
git fetch "$UPSTREAM" --tags --prune --quiet

if [ -z "$tag" ]; then
  if [ "$beta" = 1 ]; then pattern='^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$'; else pattern='^v[0-9]+\.[0-9]+\.[0-9]+$'; fi
  # versionsort.suffix: v0.5.30-beta.3 sorts below v0.5.30, not above it.
  tag="$(git -c versionsort.suffix=-beta tag --list 'v*' --sort=-v:refname | grep -E "$pattern" | head -1)"
fi
[ -n "$tag" ] || die "no upstream release tag found."
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "no such tag: $tag"

current="$(git describe --tags --abbrev=0 --match 'v*' HEAD 2>/dev/null || echo '?')"
if git merge-base --is-ancestor "$tag" HEAD; then uptodate=1; else uptodate=0; fi

if [ "$check" = 1 ]; then
  if [ "$uptodate" = 1 ]; then echo "up to date: fork is on $current (newest: $tag)"; exit 0; fi
  echo "update available: fork is on $current, upstream released $tag"; exit 10
fi

if [ "$rebuild" = 0 ]; then
  if [ "$uptodate" = 1 ]; then
    say "Already on $tag ($current); nothing to rebase. Use --rebuild to reinstall."
    [ "$push" = 1 ] && git push --force-with-lease origin "$BRANCH"
    exit 0
  fi
  say "Rebasing $BRANCH from $current onto $tag"
  git branch -f "$BRANCH-before-$tag" HEAD
  if ! git rebase "$tag"; then
    cat >&2 <<EOF

Rebase stopped on a conflict. Fork changes are marked FORK(flosrn) — see FORK.md.
  git status                     what conflicts
  git add <file> && git rebase --continue
  git rebase --abort             give up; $BRANCH is back where it was
Then run this script again.
EOF
    exit 1
  fi
fi

say "Building"
swift build

if [ "$test" = 1 ]; then
  say "Testing"
  swift test
fi

say "Packaging (signed as \"$SIGN_ID\")"
security find-identity -v -p codesigning | grep -qF "\"$SIGN_ID\"" || die "no code-signing identity named \"$SIGN_ID\" (set SIGN_ID)."
UNIVERSAL=0 SIGN_ID="$SIGN_ID" ./Scripts/package_app.sh

if [ "$install" = 1 ]; then
  say "Installing to $APP_DEST"
  if pgrep -xq QuotaBar; then
    osascript -e 'tell application id "bar.quota.QuotaBar" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do pgrep -xq QuotaBar || break; sleep 0.5; done
    pgrep -xq QuotaBar && pkill -x QuotaBar || true
  fi
  mkdir -p "$BACKUP_DIR"
  if [ -d "$APP_DEST" ]; then
    rm -rf "$BACKUP_DIR/QuotaBar.app"
    mv "$APP_DEST" "$BACKUP_DIR/QuotaBar.app"
    echo "Previous app kept at $BACKUP_DIR/QuotaBar.app"
  fi
  ditto QuotaBar.app "$APP_DEST"
  open "$APP_DEST"
fi

if [ "$push" = 1 ]; then
  say "Pushing $BRANCH"
  git push --force-with-lease origin "$BRANCH"
fi

say "Done: fork on $(git describe --tags --abbrev=0 --match 'v*' HEAD)"
