#!/bin/sh
#
# SessionStart hook — self-repair the artifact links for this worktree.
#
# Fast, silent no-op outside git repositories and in projects without an
# artifact store. Never clones, commits or pushes. Always exits 0: a broken
# artifact setup must never block a session.
#
set -u

HOOK_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || exit 0
ENGINE="$HOOK_DIR/../scripts/lnd-artifacts.sh"
[ -f "$ENGINE" ] || exit 0

# not a git working tree -> nothing to do
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
case $COMMON in
    /*) ;;
    *) COMMON="$PWD/$COMMON" ;;
esac
# no store for this repository -> nothing to do
[ -d "$COMMON/lundegaard" ] || exit 0

OUT=$(sh "$ENGINE" heal --quiet 2>&1) || true
[ -n "$OUT" ] || exit 0

CONTEXT=$(
    printf '%s\n' "lnd-artifacts (SessionStart heal):" "$OUT" |
        sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
        awk 'BEGIN { ORS = "" } { if (NR > 1) printf "\\n"; print }'
)

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$CONTEXT"
exit 0
