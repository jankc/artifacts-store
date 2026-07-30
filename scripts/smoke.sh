#!/bin/sh
#
# smoke.sh — end-to-end test of the lnd-artifacts engine on disposable fixtures.
#
# Builds a throwaway host repository and a bare artifact remote under a temp dir,
# then walks the whole life cycle: init -> edit through a symlink -> sync ->
# git clean -fdx -> heal -> adopt -> worktree -> cure -> heal, asserting after
# every step that the HOST repository stays byte-for-byte clean.
#
# usage: ./scripts/smoke.sh [--keep]
#
set -eu

KEEP=0
if [ "${1:-}" = "--keep" ]; then KEEP=1; fi

HERE=$(cd "$(dirname "$0")" && pwd -P)
ENGINE="$HERE/lnd-artifacts.sh"
HOOKS="$HERE/../hooks"

# physical path: the engine resolves everything with `pwd -P`, and on macOS the
# temp dir is reached through symlinks (/var -> /private/var)
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lnd-artifacts-smoke.XXXXXX")" && pwd -P)
HOST="$WORK/host"
WT="$WORK/host-wt"
REMOTE="$WORK/artifacts.git"
SEED="$WORK/seed"
STORE="$HOST/.git/lundegaard"

PASS=0
FAIL=0

cleanup() {
    if [ "$KEEP" -eq 1 ]; then
        printf '\nfixtures kept in %s\n' "$WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

# --- assertions ------------------------------------------------------------

ok() {
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$1"
}

bad() {
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n' "$1"
}

check() { # check <description> <condition-as-command...>
    ck_desc=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$ck_desc"; else bad "$ck_desc"; fi
}

check_not() {
    ck_desc=$1
    shift
    if "$@" >/dev/null 2>&1; then bad "$ck_desc"; else ok "$ck_desc"; fi
}

eq() { # eq <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1 (expected '$2', got '$3')"
    fi
}

step() { printf '\n== %s\n' "$*"; }

host_clean() { # the host repo must never notice us
    hc_out=$(git -C "$1" status --porcelain)
    if [ -z "$hc_out" ]; then
        ok "host porcelain clean: $2"
    else
        bad "host porcelain dirty: $2"
        printf '%s\n' "$hc_out" | sed 's/^/       /'
    fi
}

is_link_to() { # is_link_to <link> <expected-target-path>
    [ -L "$1" ] || return 1
    il_dir=$(cd "$(dirname "$1")" && pwd -P) || return 1
    il_target=$(readlink "$1")
    case $il_target in
        /*) il_abs=$il_target ;;
        *) il_abs="$il_dir/$il_target" ;;
    esac
    [ -e "$il_abs" ] || return 1
    il_res=$(cd "$(dirname "$il_abs")" && pwd -P)/$(basename "$il_abs")
    il_want=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")
    [ "$il_res" = "$il_want" ]
}

engine() { sh "$ENGINE" "$@"; }

# --- fixtures --------------------------------------------------------------

GIT_AUTHOR_NAME=smoke
GIT_AUTHOR_EMAIL=smoke@example.invalid
GIT_COMMITTER_NAME=smoke
GIT_COMMITTER_EMAIL=smoke@example.invalid
GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_NOSYSTEM

step "fixtures in $WORK"

git init -q --bare -b main "$REMOTE"

git init -q -b main "$SEED"
mkdir -p "$SEED/.claude" "$SEED/openspec"
printf '{}\n' >"$SEED/.claude/settings.json"
printf 'project\n' >"$SEED/openspec/project.md"
printf '# instructions\n' >"$SEED/CLAUDE.md"
git -C "$SEED" add -A
git -C "$SEED" commit -qm "seed artifacts"
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push -q -u origin main

git init -q -b main "$HOST"
mkdir -p "$HOST/src"
printf 'app\n' >"$HOST/src/app.txt"
printf 'readme\n' >"$HOST/README.md"
git -C "$HOST" add -A
git -C "$HOST" commit -qm "host project"
printf '# user rule\n*.log\n' >>"$HOST/.git/info/exclude"
EXCLUDE_BEFORE=$(cat "$HOST/.git/info/exclude")

cd "$HOST"

# --- init ------------------------------------------------------------------

step "init --dry-run changes nothing"
engine init "$REMOTE" --dry-run >/dev/null
check_not "no store created by dry run" test -e "$STORE"
check_not "no link created by dry run" test -L "$HOST/.claude"
eq "exclude untouched by dry run" "$EXCLUDE_BEFORE" "$(cat "$HOST/.git/info/exclude")"

step "init clones and links"
engine init "$REMOTE" >/dev/null
check "store exists" test -d "$STORE/.git"
check "link .claude" is_link_to "$HOST/.claude" "$STORE/.claude"
check "link openspec" is_link_to "$HOST/openspec" "$STORE/openspec"
check "link CLAUDE.md" is_link_to "$HOST/CLAUDE.md" "$STORE/CLAUDE.md"
check_not "store .git is not linked to" test -L "$HOST/.git"
host_clean "$HOST" "after init"
eq "user exclude rules preserved" "$EXCLUDE_BEFORE" \
    "$(sed '/>>> lnd-artifacts managed >>>/,/<<< lnd-artifacts managed <<</d' "$HOST/.git/info/exclude")"
eq "managed block matches the store listing" "$(printf '.claude\nCLAUDE.md\nopenspec\n')" \
    "$(sed -n '/>>> lnd-artifacts managed >>>/,/<<< lnd-artifacts managed <<</p' "$HOST/.git/info/exclude" |
        grep '^/' | sed 's|^/||')"

step "init refuses an existing store"
check_not "second init exits non-zero" engine init "$REMOTE"
check "store survived the refusal" test -d "$STORE/.git"

step "init cleans up after a failed clone"
git init -q -b main "$WORK/other"
git -C "$WORK/other" commit -q --allow-empty -m x
(cd "$WORK/other" && check_not "bad clone exits non-zero" engine init "$WORK/does-not-exist.git")
check_not "no partial store left behind" test -e "$WORK/other/.git/lundegaard"

# --- heal ------------------------------------------------------------------

step "heal is a quiet no-op when healthy"
eq "heal --quiet prints nothing" "" "$(engine heal --quiet 2>&1)"
host_clean "$HOST" "after heal no-op"

step "write through a symlink lands in the store"
printf 'edited\n' >"$HOST/.claude/settings.json"
eq "store sees the edit" "edited" "$(cat "$STORE/.claude/settings.json")"
host_clean "$HOST" "after editing an artifact"

# --- sync ------------------------------------------------------------------

step "sync commits and pushes"
engine sync >/dev/null
eq "store is clean after sync" "" "$(git -C "$STORE" status --porcelain)"
eq "nothing unpushed after sync" "0" "$(git -C "$STORE" rev-list --count '@{u}..HEAD')"
eq "remote has the edit" "edited" "$(git -C "$REMOTE" show main:.claude/settings.json)"
host_clean "$HOST" "after sync"

step "sync is a no-op when already in sync"
case "$(engine sync)" in
    *"already in sync"*) ok "sync reports already in sync" ;;
    *) bad "sync should report already in sync" ;;
esac

step "sync surfaces a rebase conflict without pushing"
git -C "$SEED" pull -q --rebase
printf 'remote side\n' >"$SEED/CLAUDE.md"
git -C "$SEED" commit -qam "remote change"
git -C "$SEED" push -q
printf 'local side\n' >"$HOST/CLAUDE.md"
check_not "conflicting sync exits non-zero" engine sync
check "store left mid-rebase for manual fixing" test -n "$(git -C "$STORE" diff --name-only --diff-filter=U)"
eq "nothing was pushed" "remote side" "$(git -C "$REMOTE" show main:CLAUDE.md)"
git -C "$STORE" rebase --abort
git -C "$STORE" reset -q --hard origin/main
engine heal >/dev/null
host_clean "$HOST" "after aborting the conflicted rebase"

# --- git clean survival ----------------------------------------------------

step "git clean -fdx removes links, heal restores them"
git -C "$HOST" clean -fdxq
check_not ".claude link gone" test -L "$HOST/.claude"
check "store survived git clean" test -d "$STORE/.git"
engine heal >/dev/null
check "link .claude restored" is_link_to "$HOST/.claude" "$STORE/.claude"
check "link openspec restored" is_link_to "$HOST/openspec" "$STORE/openspec"
host_clean "$HOST" "after clean + heal"

# --- quarantine ------------------------------------------------------------

step "pre-existing content is quarantined, never deleted"
rm "$HOST/.claude"
mkdir "$HOST/.claude"
printf 'mine\n' >"$HOST/.claude/local.json"
engine heal >/dev/null
check "link .claude re-created" is_link_to "$HOST/.claude" "$STORE/.claude"
QFOUND=0
for q in "$HOST"/.claude.quarantined-*; do
    if [ -f "$q/local.json" ]; then QFOUND=1; fi
done
eq "quarantined content preserved" "1" "$QFOUND"
rm -rf "$HOST"/.claude.quarantined-*

step "a foreign symlink at a managed name is quarantined"
rm "$HOST/openspec"
ln -s /etc "$HOST/openspec"
engine heal >/dev/null
check "openspec relinked to the store" is_link_to "$HOST/openspec" "$STORE/openspec"
check "foreign link quarantined" sh -c 'ls -d "$1"/openspec.quarantined-* >/dev/null 2>&1' _ "$HOST"
rm -rf "$HOST"/openspec.quarantined-*
host_clean "$HOST" "after quarantines are cleared"

# --- adopt -----------------------------------------------------------------

step "adopt moves an untracked path into the store"
mkdir -p "$HOST/.opencode"
printf 'cfg\n' >"$HOST/.opencode/config.json"
engine adopt .opencode --dry-run >/dev/null
check "dry-run adopt did not move anything" test -d "$HOST/.opencode/"
check_not "dry-run adopt did not populate the store" test -e "$STORE/.opencode"
engine adopt .opencode >/dev/null
check "adopted entry is in the store" test -f "$STORE/.opencode/config.json"
check "adopted entry is linked back" is_link_to "$HOST/.opencode" "$STORE/.opencode"
check "adopted entry is excluded" grep -Fqx "/.opencode" "$HOST/.git/info/exclude"
host_clean "$HOST" "after adopt"

step "adopt refuses what it must refuse"
check_not "tracked path refused" engine adopt src
check_not "nested path refused" engine adopt src/app.txt
check_not "already-managed link refused" engine adopt .claude
check "tracked path untouched" test -f "$HOST/src/app.txt"

step "adopted work syncs"
engine sync >/dev/null
eq "remote has the adopted file" "cfg" "$(git -C "$REMOTE" show main:.opencode/config.json)"

# --- worktrees (6.2) -------------------------------------------------------

step "linked worktree shares the store and gets its own links"
git -C "$HOST" worktree add -q -b feature "$WT"
check_not "fresh worktree has no links yet" test -L "$WT/.claude"
(cd "$WT" && engine heal >/dev/null)
check "worktree link .claude" is_link_to "$WT/.claude" "$STORE/.claude"
check "worktree link .opencode" is_link_to "$WT/.opencode" "$STORE/.opencode"
check "worktree links are relative" sh -c 'case $(readlink "$1") in /*) exit 1 ;; *) exit 0 ;; esac' _ "$WT/.claude"
host_clean "$WT" "worktree after heal"
host_clean "$HOST" "main worktree unaffected by worktree heal"
eq "store resolves identically from the worktree" \
    "$(cd "$HOST" && engine status | sed -n 's/^  store    : //p')" \
    "$(cd "$WT" && engine status | sed -n 's/^  store    : //p')"

step "edits made in the worktree are the same files"
printf 'from-worktree\n' >"$WT/.claude/settings.json"
eq "main worktree sees the edit" "from-worktree" "$(cat "$HOST/.claude/settings.json")"

step "concurrent runs serialize on the store lock"
LOCKDIR="$HOST/.git/lundegaard.lock"
mkdir "$LOCKDIR"
printf 'pid=%s\n' "$$" >"$LOCKDIR/owner"
LOCKOUT=$( (cd "$WT" && engine heal 2>&1) || true)
case $LOCKOUT in
    *"lock"*) ok "second run reports the held lock" ;;
    *) bad "second run should report the held lock (got: $LOCKOUT)" ;;
esac
rm -rf "$LOCKDIR"
check "heal works again once the lock is gone" sh -c 'cd "$1" && sh "$2" heal' _ "$WT" "$ENGINE"

step "stale lock diagnostics"
mkdir "$LOCKDIR"
printf 'pid=%s\n' "999999" >"$LOCKDIR/owner"
STALEOUT=$(engine heal 2>&1 || true)
case $STALEOUT in
    *"no longer running"*"rm -rf"*) ok "stale lock explains how to clear it" ;;
    *) bad "stale lock should explain the fix (got: $STALEOUT)" ;;
esac
rm -rf "$LOCKDIR"

# --- hooks -----------------------------------------------------------------

step "hooks"
eq "SessionStart is silent when healthy" "" "$(sh "$HOOKS/session-start.sh")"
rm "$HOST/.claude"
SSOUT=$(sh "$HOOKS/session-start.sh")
case $SSOUT in
    *SessionStart*link*) ok "SessionStart reports the restored link" ;;
    *) bad "SessionStart should report the restored link (got: $SSOUT)" ;;
esac
check "SessionStart restored the link" is_link_to "$HOST/.claude" "$STORE/.claude"
eq "Stop is silent when the store is clean" "" "$(engine sync >/dev/null; sh "$HOOKS/stop.sh")"
printf 'unsynced\n' >"$HOST/.claude/settings.json"
STOPOUT=$(sh "$HOOKS/stop.sh")
case $STOPOUT in
    *systemMessage*sync*) ok "Stop warns about unsynced artifacts" ;;
    *) bad "Stop should warn about unsynced artifacts (got: $STOPOUT)" ;;
esac
eq "Stop mutated nothing" "1" "$(git -C "$STORE" status --porcelain | grep -c .)"
(cd "$WORK/other" && eq "SessionStart silent without a store" "" "$(sh "$HOOKS/session-start.sh")")
(cd "$WORK/other" && eq "Stop silent without a store" "" "$(sh "$HOOKS/stop.sh")")
(cd "$WORK" && eq "SessionStart silent outside a git repo" "" "$(sh "$HOOKS/session-start.sh")")
engine sync >/dev/null

# --- store hygiene warning -------------------------------------------------

step "status warns about a housekeeping file at the store root"
printf 'nope\n' >"$STORE/README.md"
case "$(engine status)" in
    *"payload-only"*) ok "status warns about README.md at the store root" ;;
    *) bad "status should warn about README.md at the store root" ;;
esac

step "a store entry colliding with tracked host content is refused, not quarantined"
COLLOUT=$(engine heal 2>&1 || true)
case $COLLOUT in
    *"skipped 'README.md'"*) ok "heal refuses to move tracked host content" ;;
    *) bad "heal should refuse to move tracked host content (got: $COLLOUT)" ;;
esac
eq "tracked README.md still holds the host's content" "readme" "$(cat "$HOST/README.md")"
check_not "no quarantine of tracked content" sh -c 'ls -d "$1"/README.md.quarantined-* >/dev/null 2>&1' _ "$HOST"
host_clean "$HOST" "after a tracked-content collision"
case "$(engine status)" in
    *"COLLISION    README.md"*) ok "status reports the collision" ;;
    *) bad "status should report the collision" ;;
esac
rm "$STORE/README.md"
engine heal >/dev/null
check_not "README.md link removed once the store entry is gone" test -L "$HOST/README.md"
check "the host's own README.md is untouched" test -f "$HOST/README.md"
eq "host README.md content intact" "readme" "$(cat "$HOST/README.md")"
host_clean "$HOST" "after removing a store entry"

# --- cure / heal round-trip ------------------------------------------------

step "cure removes links and the exclude block, keeps the store"
engine cure --dry-run >/dev/null
check "dry-run cure kept the links" test -L "$HOST/.claude"
engine cure --all-worktrees >/dev/null
check_not "main worktree link gone" test -L "$HOST/.claude"
check_not "worktree link gone" test -L "$WT/.claude"
check_not "managed block gone" grep -Fq ">>> lnd-artifacts managed >>>" "$HOST/.git/info/exclude"
eq "user exclude rules still intact" "$EXCLUDE_BEFORE" "$(cat "$HOST/.git/info/exclude")"
check "store untouched by cure" test -f "$STORE/.claude/settings.json"
host_clean "$HOST" "after cure"

step "heal restores everything after cure"
engine heal >/dev/null
check "link .claude restored" is_link_to "$HOST/.claude" "$STORE/.claude"
check "link .opencode restored" is_link_to "$HOST/.opencode" "$STORE/.opencode"
check "managed block restored" grep -Fq ">>> lnd-artifacts managed >>>" "$HOST/.git/info/exclude"
host_clean "$HOST" "after cure -> heal round-trip"
(cd "$WT" && engine heal >/dev/null)
host_clean "$WT" "worktree after cure -> heal round-trip"

# --- summary ---------------------------------------------------------------

printf '\n%s\n' "-----------------------------------------"
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
printf 'smoke test OK\n'
