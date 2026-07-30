#!/bin/sh
#
# Stop hook — warn (only warn) when artifact work is unsynced.
#
# Reads the store's git state and prints a systemMessage. It never commits,
# pushes, fetches or touches the host repository, and stays silent when the
# store is clean, absent, or this is not a git repository. Always exits 0.
#
set -u

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
case $COMMON in
    /*) ;;
    *) COMMON="$PWD/$COMMON" ;;
esac
STORE="$COMMON/lundegaard"
[ -d "$STORE" ] || exit 0

DIRTY=$(git -C "$STORE" status --porcelain 2>/dev/null | grep -c . || true)
AHEAD=0
if git -C "$STORE" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    AHEAD=$(git -C "$STORE" rev-list --count '@{u}..HEAD' 2>/dev/null || printf '0')
elif git -C "$STORE" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    # commits exist but no upstream is configured — those are unpushed too
    AHEAD=$(git -C "$STORE" rev-list --count HEAD 2>/dev/null || printf '0')
fi

[ "$DIRTY" = "0" ] && [ "$AHEAD" = "0" ] && exit 0

MSG="lnd-artifacts: unsynced artifacts — ${DIRTY} uncommitted file(s), ${AHEAD} unpushed commit(s) in ${STORE}. Run the lnd-artifacts sync verb to publish them (nothing is pushed automatically)."
MSG=$(printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

printf '{"systemMessage":"%s"}\n' "$MSG"
exit 0
