# Tasks

## 1. The list, the `allowed` verb, and linking

- [x] 1.1 Add `ALLOWED_ENTRIES`, `is_allowed`, `linked_entries` and `unlisted_entries` to `scripts/lnd-artifacts.sh` (D1), and the read-only `allowed` verb with usage text (D5); verify `sh scripts/lnd-artifacts.sh allowed` prints the 19 names from the proposal, from inside and outside a git repo, and exits 0
- [x] 1.2 Switch `do_heal`, the `sync_exclude` callers, the `status` link count and the `cmd_detach` fallback to `linked_entries`, and print `skip <name> (not on the allow list)` through `info` after linking (D2); verify with `sh -n scripts/lnd-artifacts.sh` and the smoke cases in 1.4
- [x] 1.3 Move smoke fixtures that put names not on the list into the store root (`.private`, `.teamdir`, `probe.md`) to names on the list, and switch the tracked-collision case from `README.md` to a host-tracked `docs/`; verify `./scripts/smoke.sh` passes with no new cases yet
- [x] 1.4 Add smoke cases for artifact-linking: `.DS_Store` in the store is not linked and not in the managed block; a real `.DS_Store` in the worktree is byte-identical and not quarantined; an old `.DS_Store` link is removed by `heal` in both worktrees; `heal --quiet` prints nothing; plain `heal` names the skip; `allowed` is unaffected by store content; verify `./scripts/smoke.sh` passes
- [x] 1.5 Update the README (store layout, verb table with `allowed`) and `docs/jak-plugin-funguje.md` (the allow-list section now describes shipped behaviour, including the two points where heal and sync depart from the original plan); verify every command shown in the README runs as written against a smoke fixture (`./scripts/smoke.sh --keep`)

## 2. adopt

- [x] 2.1 Make `cmd_adopt` refuse a name not on the list before taking the lock, for both plain and `--local` (D6); verify with smoke cases: `adopt notes` exits non-zero naming `notes`, leaves `notes/` in place and the store unchanged; `adopt --local '[draft]'` is refused the same way
- [x] 2.2 Replace the `[draft]` local-only adopt scenario in `scripts/smoke.sh` with the refusal from 2.1; verify `./scripts/smoke.sh` passes
- [x] 2.3 Update `skills/lnd-artifacts/SKILL.md`: `adopt` refuses names not on the list, point to `allowed`, and say that a new name means a plugin change; verify the skill's verb table matches `lnd-artifacts --help`

## 3. sync and status

- [x] 3.1 Stage in `cmd_sync` with `add -A -- . ':(exclude,literal)<unlisted>'…` followed by `add -u`, and print each unlisted entry with untracked content as left out (D3); verify with smoke cases: an untracked `.DS_Store` plus an `openspec/` edit pushes only the `openspec/` change; a store whose only content is `.DS_Store` reports already in sync
- [x] 3.2 Rewrite `store_dirty_count` as tracked changes plus untracked content under allowed names (D4); verify with a smoke case where `status` reports 0 dirty files with only `.DS_Store` present
- [x] 3.3 Add a smoke case for content already tracked under a name off the list: commit `notes/todo.md` into the store by hand, modify it, `sync` pushes the change, `status` names `notes` as unlisted; verify `./scripts/smoke.sh` passes
- [x] 3.4 Replace the payload-only heuristic in `cmd_status` with the `unlisted` line (D7), and rewrite the store-hygiene smoke section to assert it for `README.md` and `.DS_Store`; verify `./scripts/smoke.sh` passes
- [x] 3.5 Move the literal-guard sync scenario from first-level `[draft]` to `openspec/[draft]/`, ignored through the store's `info/exclude`; verify the smoke case exits non-zero naming `openspec/[draft]/f` and the local file is unchanged
- [x] 3.6 Add a smoke case for a committed store `.gitignore`: commit `.claude/.gitignore` listing `settings.local.json`, create `.claude/settings.local.json` with `GIT_CONFIG_GLOBAL=/dev/null`, run `sync`; verify nothing under it is pushed and `status` reports 0 dirty files (no engine change expected)
- [x] 3.7 Document the leave-out behaviour and the `unlisted` status line in the README and `SKILL.md` (rule on closing with unsynced state); verify the documented `status` output matches a real run against a smoke fixture

## 4. Hooks

- [x] 4.1 Make `hooks/stop.sh` get the list from `../scripts/lnd-artifacts.sh allowed` and count dirty work as in D4, falling back to the unfiltered count if the engine can't be run (D5); verify with smoke cases: a pushed store with only `.DS_Store` gives no Stop output; an `openspec/` edit still warns
- [x] 4.2 Add a smoke case: the SessionStart hook in a healthy store with `.DS_Store` produces no output; verify `./scripts/smoke.sh` passes

## 5. Release

- [x] 5.1 Bump `VERSION` in `scripts/lnd-artifacts.sh` and both plugin manifests to 0.3.0; verify `lnd-artifacts --version` and both `plugin.json` files agree and the smoke vendoring cases pass
- [x] 5.2 Run `openspec validate add-store-allowlist --strict` and the full `./scripts/smoke.sh`; verify both pass
- [x] 5.3 In the JMHZ project, run the new engine's `heal` and `status`; verify all 11 entries stay linked, nothing is reported as unlisted, and `status` reports no dirty work caused by junk
