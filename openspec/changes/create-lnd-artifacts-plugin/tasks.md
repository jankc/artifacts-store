# Tasks — create-lnd-artifacts-plugin

## 1. Plugin scaffold

- [x] 1.1 Create `.claude-plugin/plugin.json` (name `lnd-artifacts`, description, version 0.1.0)
- [x] 1.2 Create repo `README.md`: what it is, `--plugin-dir` dev loop, store payload-only convention (D2), risks (backup/`rm -rf .git`), quick start
- [x] 1.3 Verify the empty plugin loads: `claude --plugin-dir <repo>` starts a session without errors

## 2. Engine core (scripts/lnd-artifacts.sh)

- [x] 2.1 Script skeleton: verb dispatch (`init|heal|adopt|sync|status|detach`), `--dry-run` plumbing, usage/help, strict-mode POSIX shell
- [x] 2.2 Store resolution helper: absolute `<git-common-dir>/lundegaard` from any worktree; clean error outside a git repo (artifact-store)
- [x] 2.3 `mkdir`-based store lock with bounded retry, PID/timestamp file, stale-lock diagnostics; wrap all mutating verbs (D5) — lock lives at `<common-dir>/lundegaard.lock` (sibling of the store), see note below
- [x] 2.4 Exclude-block helper: regenerate marker-delimited block in `<common-dir>/info/exclude` from store listing, preserving outside content byte-for-byte (D4)
- [x] 2.5 Link helpers: enumerate first-level store entries (skip `.git`), compute per-worktree relative symlink, validate by resolved target, quarantine (`<name>.quarantined-<timestamp>`) anything foreign (D2, D3)

## 3. Verbs

- [x] 3.1 `init <remote-url>`: refuse existing store, clone (cleanup on failure so no partial store remains), then heal current worktree; host `git status --porcelain` stays clean afterwards
- [x] 3.2 `heal`: idempotent create/repair/remove-orphaned links + rewrite exclude block; quiet no-op when healthy; report restores and quarantines
- [x] 3.3 `adopt <path>`: refuse tracked/nested/store-colliding paths; move into store, link back, update exclude block
- [x] 3.4 `sync`: commit -A (default message, overridable), pull --rebase, push; surface conflicts and stop without pushing; "already in sync" no-op path
- [x] 3.5 `status`: store presence, dirty count, unpushed/behind counts, current-worktree link health, quarantine leftovers, suspicious store-root entries (README.md etc.); exit 0 always
- [x] 3.6 `detach`: remove managed links (offer known worktrees from main), remove exclude block, store untouched; verify detach→heal round-trip

## 4. Hooks

- [x] 4.1 `hooks/hooks.json` with SessionStart and Stop entries via `${CLAUDE_PLUGIN_ROOT}`
- [x] 4.2 SessionStart hook script: silent fast exit outside git repos / storeless repos; otherwise `heal`, output only when something changed (D6)
- [x] 4.3 Stop hook script: warn with dirty/unpushed counts + "run sync" nudge; silent when clean/absent; never mutates anything (D6)

## 5. Skill

- [x] 5.1 Root `SKILL.md`: triggers (init/adopt/sync/status/detach intents), init dialogue asking for remote URL, verb mapping, prefer `--dry-run` before destructive/bulk actions

## 6. Verification

- [x] 6.1 `scripts/smoke.sh`: disposable-fixture end-to-end — fake host repo + bare artifact remote; init → write via symlink → sync → clean -fdx → heal → adopt → detach→heal round-trip; assert host porcelain clean throughout
- [x] 6.2 Worktree pass in smoke: `git worktree add`, heal there, confirm shared store/exclude and per-worktree links; concurrent-lock check
- [x] 6.3 Manual session test: `claude --plugin-dir` in a fixture repo — SessionStart heals a deleted link, Stop warns on dirty store, skill-guided init dialogue works
- [x] 6.4 Initial commit of the plugin repo once smoke passes
