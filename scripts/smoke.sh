#!/bin/sh
#
# smoke.sh — end-to-end test of the lnd-artifacts engine on disposable fixtures.
#
# Builds a throwaway host repository and a bare artifact remote under a temp dir,
# then walks the whole life cycle: init -> edit through a symlink -> sync ->
# git clean -fdx -> heal -> adopt -> worktree -> detach -> heal, asserting after
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
VENDORED="$HOST/.git/lundegaard.engine.sh"
VERSION=$(sh "$ENGINE" --version | awk '{print $NF}')

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

# The exact worktree-init invocation the README documents — plugin-free, guarded
# so it is a silent no-op wherever there is no vendored engine.
WORKTREE_INIT='E="$(git rev-parse --git-common-dir 2>/dev/null)/lundegaard.engine.sh"; [ -x "$E" ] && "$E" heal --quiet || true'

worktree_init() { # worktree_init <cwd>
    (cd "$1" && sh -c "$WORKTREE_INIT")
}

vendored_version() { # vendored_version <path>
    sed -n 's/^VERSION=//p' "$1" | sed -n '1p'
}

wait_for_lock_waiters() { # wait_for_lock_waiters <log> <count>
    wf_log=$1
    wf_want=$2
    wf_i=0
    while [ "$wf_i" -lt 7 ]; do
        wf_have=0
        if [ -f "$wf_log" ]; then
            wf_have=$(LC_ALL=C sort -u "$wf_log" | grep -c . || true)
        fi
        if [ "$wf_have" -ge "$wf_want" ]; then return 0; fi
        wf_i=$((wf_i + 1))
        sleep 1
    done
    return 1
}

# The engine's lock retry calls sleep only after a failed mkdir. Logging those
# calls gives concurrent tests a deterministic "both are waiting" handshake.
WAIT_BIN="$WORK/wait-bin"
REAL_SLEEP=$(command -v sleep)
REAL_GIT=$(command -v git)
mkdir "$WAIT_BIN"
cat >"$WAIT_BIN/sleep" <<'EOF'
#!/bin/sh
printf '%s\n' "$PPID" >>"$LND_WAIT_LOG"
exec "$LND_REAL_SLEEP" "$@"
EOF
chmod +x "$WAIT_BIN/sleep"
cat >"$WAIT_BIN/git" <<'EOF'
#!/bin/sh
if [ "${LND_INTERRUPT_CLONE:-0}" -eq 1 ] && [ "${1:-}" = clone ]; then
    for LND_ARG in "$@"; do LND_DEST=$LND_ARG; done
    mkdir -p "$LND_DEST"
    printf 'partial\n' >"$LND_DEST/partial"
    kill -TERM "$PPID"
    exec "$LND_REAL_SLEEP" 5
fi
exec "$LND_REAL_GIT" "$@"
EOF
chmod +x "$WAIT_BIN/git"

# --- fixtures --------------------------------------------------------------

GIT_AUTHOR_NAME=smoke
GIT_AUTHOR_EMAIL=smoke@example.invalid
GIT_COMMITTER_NAME=smoke
GIT_COMMITTER_EMAIL=smoke@example.invalid
GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL

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
printf '# user rule\n*.log' >>"$HOST/.git/info/exclude"
cp "$HOST/.git/info/exclude" "$WORK/exclude.before"
EXCLUDE_BEFORE=$(cat "$HOST/.git/info/exclude")

cd "$HOST"

# --- init ------------------------------------------------------------------

step "init --dry-run changes nothing"
INIT_DRY=$(engine init "$REMOTE" --dry-run)
case $INIT_DRY in
    *"clone $REMOTE -> $STORE"*"post-clone first-level store entry"*"generate the managed block"*"vendor the engine $VERSION to $VENDORED"*)
        ok "dry-run init prints the no-network post-clone plan, vendoring included"
        ;;
    *) bad "dry-run init plan is incomplete (got: $INIT_DRY)" ;;
esac
check_not "no store created by dry run" test -e "$STORE"
check_not "no link created by dry run" test -L "$HOST/.claude"
check_not "no engine vendored by dry run" test -e "$VENDORED"
check "exclude bytes untouched by dry run" cmp -s "$WORK/exclude.before" "$HOST/.git/info/exclude"

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

step "init vendors a runnable engine beside the store"
check "vendored engine exists and is executable" test -x "$VENDORED"
eq "vendored engine reports the running version" "$VERSION" "$(sh "$VENDORED" --version | awk '{print $NF}')"
eq "vendored engine is byte-identical to the plugin's" "same" \
    "$(cmp -s "$ENGINE" "$VENDORED" && echo same || echo different)"
case "$(engine status)" in
    *"engine   : vendored $VERSION at $VENDORED"*) ok "status reports the vendored engine" ;;
    *) bad "status should report the vendored engine" ;;
esac

step "the vendored engine is not payload"
PAYLOAD_BEFORE=$(ls -A "$STORE" | LC_ALL=C sort)
engine heal >/dev/null
engine sync >/dev/null
eq "store root listing unchanged by vendoring" "$PAYLOAD_BEFORE" "$(ls -A "$STORE" | LC_ALL=C sort)"
eq "store porcelain empty after vendoring" "" "$(git -C "$STORE" status --porcelain)"
check_not "engine is not inside the store" test -e "$STORE/lundegaard.engine.sh"
check_not "engine is not linked into the worktree root" test -e "$HOST/lundegaard.engine.sh"
check_not "engine is not linked into the worktree root (broken link)" test -L "$HOST/lundegaard.engine.sh"
check_not "sync did not commit the engine" git -C "$STORE" cat-file -e "HEAD:lundegaard.engine.sh"
check_not "engine is not in the managed exclude block" grep -Fq "lundegaard.engine.sh" "$HOST/.git/info/exclude"
host_clean "$HOST" "after vendoring"

step "init refuses an existing store"
check_not "second init exits non-zero" engine init "$REMOTE"
check "store survived the refusal" test -d "$STORE/.git"

step "init cleans up after a failed clone"
git init -q -b main "$WORK/other"
git -C "$WORK/other" commit -q --allow-empty -m x
(cd "$WORK/other" && check_not "bad clone exits non-zero" engine init "$WORK/does-not-exist.git")
check_not "no partial store left behind" test -e "$WORK/other/.git/lundegaard"
check_not "no engine vendored by a failed init" test -e "$WORK/other/.git/lundegaard.engine.sh"

step "interrupted clone cleans up its partial store"
INT_HOST="$WORK/interrupted-init"
git init -q -b main "$INT_HOST"
git -C "$INT_HOST" commit -q --allow-empty -m host
if (
    cd "$INT_HOST"
    LND_INTERRUPT_CLONE=1
    LND_REAL_GIT=$REAL_GIT
    LND_REAL_SLEEP=$REAL_SLEEP
    PATH="$WAIT_BIN:$PATH"
    export LND_INTERRUPT_CLONE LND_REAL_GIT LND_REAL_SLEEP PATH
    engine init "$REMOTE"
) >"$WORK/interrupted-init.out" 2>&1; then
    bad "interrupted init should exit non-zero"
else
    ok "interrupted init exits non-zero"
fi
check_not "interrupted init removes the partial store" test -e "$INT_HOST/.git/lundegaard"
check_not "interrupted init vendors no engine" test -e "$INT_HOST/.git/lundegaard.engine.sh"
check_not "interrupted init releases the lock" test -e "$INT_HOST/.git/lundegaard.lock"

step "concurrent init checks store absence under the lock"
CI_HOST="$WORK/concurrent-init"
git init -q -b main "$CI_HOST"
git -C "$CI_HOST" commit -q --allow-empty -m host
CI_LOCK="$CI_HOST/.git/lundegaard.lock"
mkdir "$CI_LOCK"
printf 'pid=%s\n' "$$" >"$CI_LOCK/owner"
CI_WAIT="$WORK/init.wait"
(
    cd "$CI_HOST"
    LND_WAIT_LOG=$CI_WAIT
    LND_REAL_SLEEP=$REAL_SLEEP
    LND_REAL_GIT=$REAL_GIT
    PATH="$WAIT_BIN:$PATH"
    export LND_WAIT_LOG LND_REAL_SLEEP LND_REAL_GIT PATH
    engine init "$REMOTE"
) >"$WORK/init-1.out" 2>&1 &
CI_PID1=$!
(
    cd "$CI_HOST"
    LND_WAIT_LOG=$CI_WAIT
    LND_REAL_SLEEP=$REAL_SLEEP
    LND_REAL_GIT=$REAL_GIT
    PATH="$WAIT_BIN:$PATH"
    export LND_WAIT_LOG LND_REAL_SLEEP LND_REAL_GIT PATH
    engine init "$REMOTE"
) >"$WORK/init-2.out" 2>&1 &
CI_PID2=$!
if wait_for_lock_waiters "$CI_WAIT" 2; then
    ok "both concurrent init processes reached the held lock"
else
    bad "concurrent init processes did not both reach the held lock"
fi
rm -rf "$CI_LOCK"
if wait "$CI_PID1"; then CI_RC1=0; else CI_RC1=$?; fi
if wait "$CI_PID2"; then CI_RC2=0; else CI_RC2=$?; fi
if { [ "$CI_RC1" -eq 0 ] && [ "$CI_RC2" -ne 0 ]; } ||
   { [ "$CI_RC2" -eq 0 ] && [ "$CI_RC1" -ne 0 ]; }; then
    ok "exactly one concurrent init succeeds"
else
    bad "concurrent init results should be one success and one refusal (got $CI_RC1/$CI_RC2)"
fi
check "winning concurrent store survives" test -d "$CI_HOST/.git/lundegaard/.git"
check "winning concurrent init linked artifacts" is_link_to "$CI_HOST/.claude" "$CI_HOST/.git/lundegaard/.claude"
case "$(cat "$WORK/init-1.out")$(cat "$WORK/init-2.out")" in
    *"already exists"*) ok "losing concurrent init sees the completed store" ;;
    *) bad "losing concurrent init should report the existing store" ;;
esac
host_clean "$CI_HOST" "after concurrent init"

step "inherited git environment cannot redirect the store"
ENV_STATUS=$(cd "$HOST" && GIT_COMMON_DIR="$CI_HOST/.git" engine status)
case $ENV_STATUS in
    *"store    : $STORE"*) ok "engine ignores inherited GIT_COMMON_DIR" ;;
    *) bad "engine store resolution was redirected (got: $ENV_STATUS)" ;;
esac
rm "$HOST/.claude"
(cd "$HOST" && GIT_COMMON_DIR="$CI_HOST/.git" sh "$HOOKS/session-start.sh") >/dev/null
check "SessionStart ignores inherited GIT_COMMON_DIR" is_link_to "$HOST/.claude" "$STORE/.claude"

step "an unborn store receives the remote's first commit"
EMPTY_REMOTE="$WORK/empty-artifacts.git"
EMPTY_HOST="$WORK/empty-host"
FIRST_SEED="$WORK/first-seed"
git init -q --bare -b main "$EMPTY_REMOTE"
git init -q -b main "$EMPTY_HOST"
git -C "$EMPTY_HOST" commit -q --allow-empty -m host
(cd "$EMPTY_HOST" && engine init "$EMPTY_REMOTE") >/dev/null
check_not "empty artifact store starts without HEAD" git -C "$EMPTY_HOST/.git/lundegaard" rev-parse --verify HEAD
git init -q -b main "$FIRST_SEED"
printf 'first\n' >"$FIRST_SEED/FIRST.md"
git -C "$FIRST_SEED" add -A
git -C "$FIRST_SEED" commit -qm "first artifact commit"
git -C "$FIRST_SEED" remote add origin "$EMPTY_REMOTE"
git -C "$FIRST_SEED" push -q -u origin main:published
git -C "$EMPTY_HOST/.git/lundegaard" config branch.main.merge refs/heads/published
FIRST_SYNC=$(cd "$EMPTY_HOST" && engine sync)
eq "unborn sync receives the first remote artifact" "first" "$(cat "$EMPTY_HOST/.git/lundegaard/FIRST.md")"
eq "unborn sync preserves the configured remote branch" "origin/published" \
    "$(git -C "$EMPTY_HOST/.git/lundegaard" rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
case $FIRST_SYNC in
    *"initialized from origin/published"*) ok "unborn sync reports the configured remote initialization" ;;
    *) bad "unborn sync should report configured initialization (got: $FIRST_SYNC)" ;;
esac
(cd "$EMPTY_HOST" && engine heal >/dev/null)
check "heal links the first remote artifact" is_link_to "$EMPTY_HOST/FIRST.md" "$EMPTY_HOST/.git/lundegaard/FIRST.md"
host_clean "$EMPTY_HOST" "after first remote commit"

# --- heal ------------------------------------------------------------------

step "heal is a quiet no-op when healthy"
eq "heal --quiet prints nothing" "" "$(engine heal --quiet 2>&1)"
host_clean "$HOST" "after heal no-op"
eq "matching versions leave the vendored engine untouched" "$VERSION" "$(vendored_version "$VENDORED")"

step "heal refreshes a drifted vendored engine"
sed 's/^VERSION=.*/VERSION=0.0.1-old/' "$VENDORED" >"$WORK/drifted.sh"
cp "$WORK/drifted.sh" "$VENDORED"
chmod +x "$VENDORED"
case "$(engine status)" in
    *"vendored 0.0.1-old"*"differs from the running $VERSION"*)
        ok "status names both versions on drift"
        ;;
    *) bad "status should name both versions on drift (got: $(engine status))" ;;
esac
DRIFT_HEAL=$(engine heal)
case $DRIFT_HEAL in
    *"refresh the vendored engine"*"0.0.1-old -> $VERSION"*) ok "heal reports the refresh" ;;
    *) bad "heal should report the refresh (got: $DRIFT_HEAL)" ;;
esac
eq "drifted engine was rewritten" "$VERSION" "$(vendored_version "$VENDORED")"
check "refreshed engine stays executable" test -x "$VENDORED"
eq "heal is quiet again once versions match" "" "$(engine heal --quiet 2>&1)"
host_clean "$HOST" "after refreshing the vendored engine"

step "heal restores a deleted vendored engine"
rm "$VENDORED"
case "$(engine status)" in
    *"engine   : not vendored at $VENDORED"*) ok "status reports the missing engine" ;;
    *) bad "status should report the missing engine" ;;
esac
engine heal >/dev/null
check "heal recreated the vendored engine" test -x "$VENDORED"
eq "recreated engine has the running version" "$VERSION" "$(vendored_version "$VENDORED")"

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
SYNC_HEAD_BEFORE=$(git -C "$STORE" rev-parse HEAD)
SYNC_DRY=$(engine sync --dry-run)
case $SYNC_DRY in
    *"fetch origin"*"rebase onto origin/main"*"push if commits remain ahead"*)
        ok "dry-run sync includes remote integration"
        ;;
    *) bad "dry-run sync should include remote integration (got: $SYNC_DRY)" ;;
esac
eq "dry-run sync leaves HEAD unchanged" "$SYNC_HEAD_BEFORE" "$(git -C "$STORE" rev-parse HEAD)"

step "clean sync integrates remote-only work before reporting success"
git -C "$SEED" pull -q --rebase
printf 'remote-only\n' >"$SEED/openspec/remote-only.txt"
git -C "$SEED" add -A
git -C "$SEED" commit -qm "remote-only change"
git -C "$SEED" push -q
CLEAN_BEHIND_OUT=$(engine sync)
eq "clean-behind sync receives the remote file" "remote-only" "$(cat "$STORE/openspec/remote-only.txt")"
eq "clean-behind sync reaches remote HEAD" "$(git -C "$REMOTE" rev-parse main)" "$(git -C "$STORE" rev-parse HEAD)"
case $CLEAN_BEHIND_OUT in
    *"updated the local store"*) ok "clean-behind sync reports the remote update" ;;
    *) bad "clean-behind sync should report an update (got: $CLEAN_BEHIND_OUT)" ;;
esac
host_clean "$HOST" "after clean-behind sync"

step "configured upstream wins even before its tracking ref exists"
BACKUP_REMOTE="$WORK/backup-artifacts.git"
git clone -q --bare "$REMOTE" "$BACKUP_REMOTE"
git -C "$BACKUP_REMOTE" update-ref refs/heads/published refs/heads/main
git -C "$STORE" remote add backup "$BACKUP_REMOTE"
git -C "$STORE" config branch.main.remote backup
git -C "$STORE" config branch.main.merge refs/heads/published
check_not "backup tracking ref is initially absent" git -C "$STORE" show-ref --verify --quiet refs/remotes/backup/published
printf 'backup-only\n' >"$HOST/.claude/backup-only.txt"
BACKUP_SYNC=$(engine sync)
eq "configured backup branch receives the artifact" "backup-only" "$(git -C "$BACKUP_REMOTE" show published:.claude/backup-only.txt)"
check_not "origin is not selected over the configured backup" git -C "$REMOTE" cat-file -e main:.claude/backup-only.txt
case $BACKUP_SYNC in
    *"fetch backup"*"rebase onto backup/published"*"pushed"*"backup/published"*) ok "sync honors the configured backup upstream branch" ;;
    *) bad "sync should use the configured backup upstream (got: $BACKUP_SYNC)" ;;
esac
git -C "$STORE" push -q origin main
git -C "$STORE" config branch.main.remote origin
git -C "$STORE" config branch.main.merge refs/heads/main
git -C "$STORE" remote remove backup

step "sync and status recover a missing upstream"
git -C "$STORE" branch --unset-upstream
eq "Stop stays silent when origin/main proves a no-upstream branch is pushed" "" "$(sh "$HOOKS/stop.sh")"
printf 'no-upstream\n' >"$HOST/.claude/no-upstream.txt"
mkdir "$HOST/.claude/untracked-files"
printf 'one\n' >"$HOST/.claude/untracked-files/one"
printf 'two\n' >"$HOST/.claude/untracked-files/two"
printf 'three\n' >"$HOST/.claude/untracked-files/three"
case "$(engine status)" in
    *"dirty    : 4 file(s) uncommitted"*) ok "status counts files inside untracked directories" ;;
    *) bad "status should count every untracked file" ;;
esac
git -C "$STORE" add -A
git -C "$STORE" commit -qm "local commit without upstream"
NOUP_STATUS=$(engine status)
case $NOUP_STATUS in
    *"unpushed : 1 commit(s) relative to origin/main"*) ok "status compares an untracked branch to origin/main" ;;
    *) bad "status should report the unpushed commit without an upstream (got: $NOUP_STATUS)" ;;
esac
NOUP_SYNC=$(engine sync)
eq "sync restores the upstream" "origin/main" "$(git -C "$STORE" rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
eq "remote receives no-upstream work" "no-upstream" "$(git -C "$REMOTE" show main:.claude/no-upstream.txt)"
case $NOUP_SYNC in
    *"configured the upstream"*) ok "sync reports upstream configuration" ;;
    *) bad "sync should report upstream configuration (got: $NOUP_SYNC)" ;;
esac

step "status is honest when no remote or tracking ref exists"
ORIGIN_URL=$(git -C "$STORE" remote get-url origin)
git -C "$STORE" remote remove origin
LOCAL_ONLY_STATUS=$(engine status)
case $LOCAL_ONLY_STATUS in
    *"unpushed : unknown (no usable upstream/tracking ref)"*"behind   : unknown"*)
        ok "status reports unknown publication state without a comparison ref"
        ;;
    *) bad "status should report unknown local-only state (got: $LOCAL_ONLY_STATUS)" ;;
esac
git -C "$STORE" remote add origin "$ORIGIN_URL"
git -C "$STORE" fetch -q origin
git -C "$STORE" branch --set-upstream-to=origin/main main >/dev/null

step "sync surfaces a rebase conflict without pushing"
git -C "$SEED" pull -q --rebase
printf 'remote side\n' >"$SEED/CLAUDE.md"
git -C "$SEED" commit -qam "remote change"
git -C "$SEED" push -q
printf 'local side\n' >"$HOST/CLAUDE.md"
check_not "conflicting sync exits non-zero" engine sync
check "store left mid-rebase for manual fixing" test -n "$(git -C "$STORE" diff --name-only --diff-filter=U)"
eq "nothing was pushed" "remote side" "$(git -C "$REMOTE" show main:CLAUDE.md)"
REBASE_HEAD=$(git -C "$STORE" rev-parse HEAD)
if engine sync >"$WORK/rebase-retry.out" 2>&1; then
    bad "sync should refuse while a rebase is active"
else
    ok "sync refuses while a rebase is active"
fi
eq "active-rebase refusal leaves HEAD unchanged" "$REBASE_HEAD" "$(git -C "$STORE" rev-parse HEAD)"
check "active-rebase refusal preserves conflicts" test -n "$(git -C "$STORE" diff --name-only --diff-filter=U)"
case "$(cat "$WORK/rebase-retry.out")" in
    *"rebase --continue"*"rebase --abort"*) ok "active-rebase refusal prints recovery commands" ;;
    *) bad "active-rebase refusal should print continue and abort guidance" ;;
esac
git -C "$STORE" rebase --abort
git -C "$STORE" reset -q --hard origin/main
engine heal >/dev/null
host_clean "$HOST" "after aborting the conflicted rebase"

# --- git clean survival ----------------------------------------------------

step "git clean -fdx removes links, heal restores them"
git -C "$HOST" clean -fdxq
check_not ".claude link gone" test -L "$HOST/.claude"
check "store survived git clean" test -d "$STORE/.git"
check "vendored engine survived git clean" test -x "$VENDORED"
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

step "a removed store entry is unlinked in every worktree"
printf 'probe\n' >"$STORE/probe.md"
(cd "$HOST" && engine heal >/dev/null)
(cd "$WT" && engine heal >/dev/null)
check "worktree link probe.md" is_link_to "$WT/probe.md" "$STORE/probe.md"
ln -s ../elsewhere/probe-foreign.md "$WT/probe-foreign.md"
rm "$STORE/probe.md"
(cd "$HOST" && engine heal >/dev/null) # rewrites the shared block first
(cd "$WT" && engine heal >/dev/null)
check_not "main worktree link probe.md removed" test -L "$HOST/probe.md"
check_not "worktree link probe.md removed after the block was rewritten" test -L "$WT/probe.md"
check "foreign symlink outside the store left alone" test -L "$WT/probe-foreign.md"
rm "$WT/probe-foreign.md"

# --- agentless bootstrap (artifact-bootstrap) ------------------------------

step "the vendored engine bootstraps a worktree after the plugin disappears"
FAKE_PLUGIN="$WORK/fake-plugin"
VHOST="$WORK/vendor-host"
VSTORE="$VHOST/.git/lundegaard"
VWT="$WORK/vendor-host-wt"
mkdir -p "$FAKE_PLUGIN/scripts"
cp "$ENGINE" "$FAKE_PLUGIN/scripts/lnd-artifacts.sh"
chmod +x "$FAKE_PLUGIN/scripts/lnd-artifacts.sh"
git init -q -b main "$VHOST"
git -C "$VHOST" commit -q --allow-empty -m host
(cd "$VHOST" && sh "$FAKE_PLUGIN/scripts/lnd-artifacts.sh" init "$REMOTE") >/dev/null
check "a plugin copy elsewhere vendors the engine too" test -x "$VHOST/.git/lundegaard.engine.sh"
rm -rf "$FAKE_PLUGIN"
check_not "the plugin is really gone" test -e "$FAKE_PLUGIN/scripts/lnd-artifacts.sh"
git -C "$VHOST" worktree add -q -b vendor-feature "$VWT"
check_not "fresh worktree starts without links" test -L "$VWT/.claude"
if WT_INIT_OUT=$(worktree_init "$VWT" 2>&1); then WT_INIT_RC=0; else WT_INIT_RC=$?; fi
eq "worktree-init line exits zero" "0" "$WT_INIT_RC"
case $WT_INIT_OUT in
    *"link .claude"*) ok "worktree-init line reports the links it created" ;;
    *) bad "worktree-init line should report created links (got: $WT_INIT_OUT)" ;;
esac
check "worktree-init created .claude" is_link_to "$VWT/.claude" "$VSTORE/.claude"
check "worktree-init created openspec" is_link_to "$VWT/openspec" "$VSTORE/openspec"
check "worktree-init created CLAUDE.md" is_link_to "$VWT/CLAUDE.md" "$VSTORE/CLAUDE.md"
host_clean "$VWT" "worktree after agentless bootstrap"
host_clean "$VHOST" "main worktree after agentless bootstrap"

step "the worktree-init line works from a nested subdirectory"
rm "$VWT/.claude"
mkdir -p "$VWT/deep/nested"
if worktree_init "$VWT/deep/nested" >/dev/null 2>&1; then NEST_RC=0; else NEST_RC=$?; fi
eq "nested worktree-init exits zero" "0" "$NEST_RC"
check "nested worktree-init links at the worktree root" is_link_to "$VWT/.claude" "$VSTORE/.claude"
check_not "nested worktree-init links nothing in the subdirectory" test -e "$VWT/deep/nested/.claude"
rm -rf "$VWT/deep"
host_clean "$VWT" "worktree after nested bootstrap"

step "the worktree-init line is a silent no-op where it does not apply"
if NOSTORE_OUT=$(worktree_init "$WORK/other" 2>&1); then NOSTORE_RC=0; else NOSTORE_RC=$?; fi
eq "storeless repo exits zero" "0" "$NOSTORE_RC"
eq "storeless repo stays silent" "" "$NOSTORE_OUT"
if NOGIT_OUT=$(worktree_init "$WORK" 2>&1); then NOGIT_RC=0; else NOGIT_RC=$?; fi
eq "outside a git repo exits zero" "0" "$NOGIT_RC"
eq "outside a git repo stays silent" "" "$NOGIT_OUT"
host_clean "$WORK/other" "storeless repo after the worktree-init line"

step "detach clears the bootstrap, heal restores it"
(cd "$VHOST" && engine detach --dry-run >/dev/null)
check "dry-run detach keeps the vendored engine" test -x "$VHOST/.git/lundegaard.engine.sh"
(cd "$VHOST" && engine detach --all-worktrees >/dev/null)
check_not "detach removed the vendored engine" test -e "$VHOST/.git/lundegaard.engine.sh"
check "detach kept the store" test -f "$VSTORE/.claude/settings.json"
check_not "detach removed the worktree link" test -L "$VWT/.claude"
if DETACHED_OUT=$(worktree_init "$VWT" 2>&1); then DETACHED_RC=0; else DETACHED_RC=$?; fi
eq "the one-liner is a no-op once detached" "0" "$DETACHED_RC"
eq "the one-liner stays silent once detached" "" "$DETACHED_OUT"
(cd "$VHOST" && engine heal >/dev/null)
check "heal restored the vendored engine" test -x "$VHOST/.git/lundegaard.engine.sh"
check "heal restored the main worktree link" is_link_to "$VHOST/.claude" "$VSTORE/.claude"
(cd "$VWT" && engine heal >/dev/null)
check "heal restored the linked worktree" is_link_to "$VWT/.claude" "$VSTORE/.claude"
eq "the store was untouched throughout" "" "$(git -C "$VSTORE" status --porcelain)"
host_clean "$VHOST" "after detach -> heal round-trip"
host_clean "$VWT" "linked worktree after detach -> heal round-trip"

step "concurrent sync recomputes state after acquiring the lock"
LOCKDIR="$HOST/.git/lundegaard.lock"
SYNC_COMMITS_BEFORE=$(git -C "$STORE" rev-list --count HEAD)
mkdir "$LOCKDIR"
printf 'pid=%s\n' "$$" >"$LOCKDIR/owner"
SYNC_WAIT="$WORK/sync.wait"
(
    cd "$HOST"
    LND_WAIT_LOG=$SYNC_WAIT
    LND_REAL_SLEEP=$REAL_SLEEP
    LND_REAL_GIT=$REAL_GIT
    PATH="$WAIT_BIN:$PATH"
    export LND_WAIT_LOG LND_REAL_SLEEP LND_REAL_GIT PATH
    engine sync
) >"$WORK/sync-1.out" 2>&1 &
SYNC_PID1=$!
(
    cd "$WT"
    LND_WAIT_LOG=$SYNC_WAIT
    LND_REAL_SLEEP=$REAL_SLEEP
    LND_REAL_GIT=$REAL_GIT
    PATH="$WAIT_BIN:$PATH"
    export LND_WAIT_LOG LND_REAL_SLEEP LND_REAL_GIT PATH
    engine sync
) >"$WORK/sync-2.out" 2>&1 &
SYNC_PID2=$!
if wait_for_lock_waiters "$SYNC_WAIT" 2; then
    ok "both concurrent sync processes reached the held lock"
else
    bad "concurrent sync processes did not both reach the held lock"
fi
rm -rf "$LOCKDIR"
if wait "$SYNC_PID1"; then SYNC_RC1=0; else SYNC_RC1=$?; fi
if wait "$SYNC_PID2"; then SYNC_RC2=0; else SYNC_RC2=$?; fi
eq "first concurrent sync succeeds" "0" "$SYNC_RC1"
eq "second concurrent sync succeeds after rechecking state" "0" "$SYNC_RC2"
eq "concurrent sync creates one commit" "$((SYNC_COMMITS_BEFORE + 1))" "$(git -C "$STORE" rev-list --count HEAD)"
eq "concurrent sync publishes the edit" "from-worktree" "$(git -C "$REMOTE" show main:.claude/settings.json)"
case "$(cat "$WORK/sync-1.out")$(cat "$WORK/sync-2.out")" in
    *"nothing to commit, working tree clean"*) bad "concurrent sync must not use stale dirty state" ;;
    *) ok "concurrent sync avoids stale empty commits" ;;
esac
host_clean "$HOST" "main worktree after concurrent sync"
host_clean "$WT" "linked worktree after concurrent sync"

step "concurrent runs serialize on the store lock"
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

# --- local-only entries (add-local-only-artifacts) ---------------------------

STORE_EXCL="$STORE/.git/info/exclude"
drop_store_excl() { # drop_store_excl <line>
    grep -Fvx "$1" "$STORE_EXCL" >"$WORK/store-exclude.tmp" || true
    cat "$WORK/store-exclude.tmp" >"$STORE_EXCL"
}

step "adopt --local keeps an entry out of the store's history"
mkdir -p "$HOST/.private"
printf 'mine\n' >"$HOST/.private/notes.md"
LOCAL_DRY=$(engine adopt .private --local --dry-run)
case $LOCAL_DRY in
    *"add /.private to $STORE_EXCL (local-only)"*) ok "dry-run adopt --local plans the store exclude line" ;;
    *) bad "dry-run adopt --local should plan the store exclude line (got: $LOCAL_DRY)" ;;
esac
check_not "dry-run adopt --local did not populate the store" test -e "$STORE/.private"
check_not "dry-run adopt --local wrote no store exclude line" grep -Fqx "/.private" "$STORE_EXCL"
engine adopt .private --local >/dev/null
check "local-only entry is linked back" is_link_to "$HOST/.private" "$STORE/.private"
check "local-only entry is in the host exclude block" grep -Fqx "/.private" "$HOST/.git/info/exclude"
check "local-only entry is in the store's info/exclude" grep -Fqx "/.private" "$STORE_EXCL"
eq "store git does not see the local-only entry" "" "$(git -C "$STORE" status --porcelain --untracked-files=all -- .private)"
host_clean "$HOST" "after adopt --local"
check_not "--local is refused outside adopt" engine status --local

step "local-only edits never sync; shared edits beside them do"
printf 'shared\n' >"$HOST/openspec/shared.md"
engine sync >/dev/null
eq "remote has the shared edit" "shared" "$(git -C "$REMOTE" show main:openspec/shared.md)"
eq "remote has nothing under .private" "" "$(git -C "$REMOTE" ls-tree main -- .private)"
printf 'mine-2\n' >>"$HOST/.private/notes.md"
case "$(engine sync)" in
    *"already in sync"*) ok "a local-only edit alone leaves nothing to sync" ;;
    *) bad "a local-only edit alone should leave nothing to sync" ;;
esac
git -C "$SEED" pull -q --rebase
printf 'unrelated\n' >"$SEED/openspec/unrelated.md"
git -C "$SEED" add -A
git -C "$SEED" commit -qm "unrelated remote change"
git -C "$SEED" push -q
engine sync >/dev/null
eq "unrelated remote changes integrate beside a local-only entry" "unrelated" "$(cat "$STORE/openspec/unrelated.md")"

step "local-only entries reach every worktree and show in status"
(cd "$WT" && engine heal >/dev/null)
check "worktree link .private" is_link_to "$WT/.private" "$STORE/.private"
host_clean "$WT" "worktree after heal with a local-only entry"
case "$(engine status)" in
    *"local    : .private — never pushed"*) ok "status lists the local-only entry" ;;
    *) bad "status should list .private as local-only" ;;
esac

step "names with gitignore metacharacters stay local and invisible"
mkdir -p "$HOST/[draft]"
printf 'd\n' >"$HOST/[draft]/f"
engine adopt '[draft]' --local >/dev/null
check "store exclude line is escaped" grep -Fqx '/\[draft\]' "$STORE_EXCL"
eq "store git does not see [draft]" "" "$(git -C "$STORE" status --porcelain --untracked-files=all)"
host_clean "$HOST" "after adopting [draft]"
case "$(engine status)" in
    *"local    : .private [draft] — never pushed"*) ok "status lists [draft] as local-only" ;;
    *) bad "status should list [draft] as local-only" ;;
esac
git -C "$SEED" pull -q --rebase
mkdir -p "$SEED/[draft]"
printf 'theirs\n' >"$SEED/[draft]/f"
git -C "$SEED" add -A
git -C "$SEED" commit -qm "a teammate shares [draft]"
git -C "$SEED" push -q
DRAFT_RC=0
DRAFT_OUT=$(engine sync 2>&1) || DRAFT_RC=$?
check "sync stops on a pushed [draft]/f" test "$DRAFT_RC" -ne 0
case $DRAFT_OUT in
    *"[draft]/f"*) ok "the guard names [draft]/f literally" ;;
    *) bad "the guard should name [draft]/f (got: $DRAFT_OUT)" ;;
esac
eq "local [draft]/f untouched" "d" "$(cat "$HOST/[draft]/f")"
git -C "$SEED" rm -rq '[draft]'
git -C "$SEED" commit -qm "drop [draft]"
git -C "$SEED" push -q
rm -rf "$STORE/[draft]"
drop_store_excl '/\[draft\]'
engine heal >/dev/null
check_not "[draft] link removed after its store entry went" test -L "$HOST/[draft]"

step "adopt --local refuses a name already shared on the remote"
git -C "$SEED" pull -q --rebase
mkdir -p "$SEED/.teamdir"
printf 'team\n' >"$SEED/.teamdir/x.md"
git -C "$SEED" add -A
git -C "$SEED" commit -qm "team dir"
git -C "$SEED" push -q
git -C "$STORE" fetch -q origin
mkdir -p "$HOST/.teamdir"
printf 'mine\n' >"$HOST/.teamdir/x.md"
check_not "shared name refused" engine adopt .teamdir --local
check "refused entry left in place" test -d "$HOST/.teamdir/"
check_not "refused entry not moved into the store" test -e "$STORE/.teamdir"
rm -rf "$HOST/.teamdir"
git -C "$SEED" rm -rq .teamdir
git -C "$SEED" commit -qm "drop team dir"
git -C "$SEED" push -q

step "sync stops before the remote overwrites local-only content"
mkdir -p "$SEED/.private"
printf 'theirs\n' >"$SEED/.private/notes.md"
git -C "$SEED" add -A
git -C "$SEED" commit -qm "a teammate shares .private"
git -C "$SEED" push -q
LOCAL_BEFORE=$(cat "$HOST/.private/notes.md")
REMOTE_HEAD=$(git -C "$REMOTE" rev-parse main)
printf 'shared-2\n' >"$HOST/openspec/shared.md"
GUARD_RC=0
GUARD_OUT=$(engine sync 2>&1) || GUARD_RC=$?
check "guarded sync exits non-zero" test "$GUARD_RC" -ne 0
case $GUARD_OUT in
    *"local-only"*".private/notes.md"*) ok "guarded sync names the local-only path" ;;
    *) bad "guarded sync should name .private/notes.md (got: $GUARD_OUT)" ;;
esac
eq "local-only file untouched" "$LOCAL_BEFORE" "$(cat "$HOST/.private/notes.md")"
eq "nothing pushed" "$REMOTE_HEAD" "$(git -C "$REMOTE" rev-parse main)"
eq "the run's local commit stays, unpushed" "1" "$(git -C "$STORE" rev-list --count '@{u}..HEAD')"
check_not "no rebase left behind" test -d "$STORE/.git/rebase-merge"
check_not "lock released" test -d "$HOST/.git/lundegaard.lock"
host_clean "$HOST" "after a guarded sync"

step "dropping the local-only content lets sync through"
rm -rf "$STORE/.private"
drop_store_excl "/.private"
engine sync >/dev/null
eq "the teammate's file arrived" "theirs" "$(cat "$STORE/.private/notes.md")"
eq "remote has the held-back commit" "shared-2" "$(git -C "$REMOTE" show main:openspec/shared.md)"
git -C "$SEED" pull -q --rebase
git -C "$SEED" rm -rq .private
git -C "$SEED" commit -qm "drop .private"
git -C "$SEED" push -q
engine sync >/dev/null
engine heal >/dev/null
(cd "$WT" && engine heal >/dev/null)
check_not "fixture restored: no .private link" test -L "$HOST/.private"
check_not "fixture restored: no worktree .private link" test -L "$WT/.private"
host_clean "$HOST" "after restoring the local-only fixture"

# --- detach / heal round-trip ------------------------------------------------

step "detach removes links and the exclude block, keeps the store"
engine detach --dry-run >/dev/null
check "dry-run detach kept the links" test -L "$HOST/.claude"
check "dry-run detach kept the vendored engine" test -x "$VENDORED"
engine detach --all-worktrees >/dev/null
check_not "main worktree link gone" test -L "$HOST/.claude"
check_not "vendored engine gone" test -e "$VENDORED"
check_not "worktree link gone" test -L "$WT/.claude"
check_not "managed block gone" grep -Fq ">>> lnd-artifacts managed >>>" "$HOST/.git/info/exclude"
eq "user exclude rules still intact" "$EXCLUDE_BEFORE" "$(cat "$HOST/.git/info/exclude")"
check "user exclude bytes restored exactly" cmp -s "$WORK/exclude.before" "$HOST/.git/info/exclude"
check "store untouched by detach" test -f "$STORE/.claude/settings.json"
host_clean "$HOST" "after detach"

step "heal restores everything after detach"
engine heal >/dev/null
check "link .claude restored" is_link_to "$HOST/.claude" "$STORE/.claude"
check "link .opencode restored" is_link_to "$HOST/.opencode" "$STORE/.opencode"
check "vendored engine restored" test -x "$VENDORED"
check "managed block restored" grep -Fq ">>> lnd-artifacts managed >>>" "$HOST/.git/info/exclude"
host_clean "$HOST" "after detach -> heal round-trip"
(cd "$WT" && engine heal >/dev/null)
host_clean "$WT" "worktree after detach -> heal round-trip"

# --- summary ---------------------------------------------------------------

printf '\n%s\n' "-----------------------------------------"
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
printf 'smoke test OK\n'
