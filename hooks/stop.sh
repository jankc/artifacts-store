#!/bin/sh
#
# Stop hook — warn (only warn) when artifact work is unsynced.
#
# Reads the store's git state and prints a systemMessage. It never commits,
# pushes, fetches or touches the host repository, and stays silent when the
# store is clean, absent, or this is not a git repository. Always exits 0.
#
set -u

unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
case $COMMON in
    /*) ;;
    *) COMMON="$PWD/$COMMON" ;;
esac
STORE="$COMMON/lundegaard"
[ -d "$STORE" ] || exit 0

DIRTY=$(git -C "$STORE" status --porcelain --untracked-files=all 2>/dev/null | grep -c . || true)
BRANCH=$(git -C "$STORE" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
UPSTREAM=""
if [ -n "$BRANCH" ]; then
    UP_REMOTE=$(git -C "$STORE" config --get "branch.$BRANCH.remote" 2>/dev/null || true)
    UP_MERGE=$(git -C "$STORE" config --get "branch.$BRANCH.merge" 2>/dev/null || true)
    if [ -n "$UP_REMOTE" ] && [ -n "$UP_MERGE" ]; then
        UP_NAME=${UP_MERGE#refs/heads/}
        if [ "$UP_REMOTE" = "." ]; then
            UPSTREAM=$UP_NAME
        else
            UPSTREAM="$UP_REMOTE/$UP_NAME"
        fi
    fi
fi
COMPARE=""
if [ -n "$UPSTREAM" ] && git -C "$STORE" rev-parse --verify --quiet '@{u}^{commit}' >/dev/null 2>&1; then
    COMPARE='@{u}'
elif [ -z "$UPSTREAM" ] && [ -n "$BRANCH" ]; then
    if git -C "$STORE" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        COMPARE="origin/$BRANCH"
    else
        CANDIDATES=""
        for REMOTE in $(git -C "$STORE" remote 2>/dev/null || true); do
            if git -C "$STORE" show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH"; then
                CANDIDATES="${CANDIDATES}${CANDIDATES:+
}$REMOTE/$BRANCH"
            fi
        done
        if [ "$(printf '%s\n' "$CANDIDATES" | grep -c . || true)" -eq 1 ]; then
            COMPARE=$CANDIDATES
        fi
    fi
fi

AHEAD=unknown
if [ -n "$COMPARE" ]; then
    AHEAD=$(git -C "$STORE" rev-list --count "$COMPARE..HEAD" 2>/dev/null || printf 'unknown')
fi

if [ "$DIRTY" = "0" ] && { [ "$AHEAD" = "0" ] || [ "$AHEAD" = "unknown" ]; }; then
    exit 0
fi

MSG="lnd-artifacts: unsynced artifacts — ${DIRTY} uncommitted file(s), ${AHEAD} unpushed commit(s) in ${STORE}. Run the lnd-artifacts sync verb to publish them (nothing is pushed automatically)."
MSG=$(printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

printf '{"systemMessage":"%s"}\n' "$MSG"
exit 0
