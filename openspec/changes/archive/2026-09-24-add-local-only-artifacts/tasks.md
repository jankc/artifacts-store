# Tasks — add-local-only-artifacts

Read design.md (L1–L5) first. L3 is the only new safety logic; the rest is a flag, one
appended line and one status line on top of behavior that already works.

## 1. Engine: `adopt --local`

- [x] 1.1 Parse `--local` into `LOCAL=1` in `main`; make the dispatcher die with usage when `LOCAL=1` and the verb is not `adopt`. Verify that `engine status --local` exits non-zero and changes nothing
- [x] 1.2 In `cmd_adopt`, when `LOCAL=1`: resolve the store's exclude path with `git -C "$STORE" rev-parse --git-path info/exclude`, and refuse when the name exists in the store's comparison ref (upstream, else `origin/<branch>`; skip the check when neither exists) (L2). Verify that `adopt --local <name>` refuses a name already present on the remote branch
- [x] 1.3 After the existing move, link and `sync_exclude`, append `/<name>` to the store's `info/exclude` unless an exact line already exists. Add a `report` line for it, and a matching `would …` line in the dry-run branch. Verify that `git -C "$STORE" status --porcelain` does not list the adopted entry and that dry-run writes nothing
- [x] 1.4 End with a different closing message for `--local`: it is local-only, not pushed, not backed up. Do not suggest `sync`. Verify by reading the output
- [x] 1.5 Add `--local` to `usage()` (the options block and the `adopt` line)

## 2. Engine: sync overwrite guard (L3)

- [x] 2.1 Add a helper that takes a target ref and prints the incoming paths that are ignored and untracked in the store: `git diff --name-only HEAD...<ref>` piped to `git check-ignore --stdin`, or `git ls-tree -r --name-only <ref>` when HEAD is unborn. It prints nothing when the list is clean
- [x] 2.2 Upstream path: replace `pull --rebase` with `fetch <upstream-remote>` (skip it for remote `.`), then the guard against `@{u}`, then `rebase` with no argument, keeping the existing conflict and `sync_rebase_stop` handling byte-for-byte in behavior. Keep the dry-run plan wording, or update the smoke assertion that matches `pull --rebase from origin/main`
- [x] 2.3 No-upstream path: run the guard against `$cs_remote/$cs_remote_branch` after the existing fetch and before both `reset --hard` and `rebase`
- [x] 2.4 On a hit, `release_lock` and `die` listing the paths, the store location, and the two ways out: rename the local content, or remove its line from the store's `info/exclude` to share it. Verify that the local commit from the run survives unpushed

## 3. Engine: status (L4)

- [x] 3.1 In `cmd_status`, after the links block, collect `store_entries` names for which `git -C "$STORE" check-ignore -q` succeeds and print one `local     :` line naming them, plus "not pushed; lost if the store is deleted or re-cloned". Print nothing when there are none. Verify that the existing status output is unchanged in a store with no local-only entries

## 4. Smoke suite

- [x] 4.1 Add a `local-only` section after `adopt`: `adopt --local` a `.private` directory with a dry-run first. Assert the link exists, the host exclude block contains `/.private`, the store's `info/exclude` contains `/.private`, the store's porcelain status is empty, and the host is clean
- [x] 4.2 Edit a file under `.private` and one under `openspec/`, then `sync`. Assert the remote has the `openspec/` change and `git -C "$REMOTE" ls-tree main -- .private` is empty
- [x] 4.3 In the linked worktree, `heal`, then assert `.private` links to the same store entry
- [x] 4.4 Guard: from `$SEED`, commit and push `.private/<same file>` with other content, then run `sync` in the host. Assert it exits non-zero, names the path, leaves the local file byte-identical, and leaves the remote HEAD unchanged. Then drop the local-only content, confirm `sync` succeeds again, and restore the fixture for the later sections
- [x] 4.5 Assert that `adopt --local` refuses a name already on the remote, and that `status` lists `.private` as local-only
- [x] 4.6 Run `./scripts/smoke.sh`: it passes in full, including the unchanged sync scenarios, which are the regression check for 2.2

## 5. Skill, README, context

- [x] 5.1 `skills/lnd-artifacts/SKILL.md`: add a table row ("keep `.claude/` out of the shared repo", "personal, not for the team" → `adopt --local <path>`), the verb line, and a rule. Say it has no remote backup when adopting. Sharing later means deleting the line from the store's `info/exclude` and then `sync`. Never `git rm --cached` a shared entry to make it local. Report a sync guard stop verbatim and let the user pick the way out
- [x] 5.2 `README.md`: add `adopt --local <path>` to the verbs table and a short "Local-only artifacts" paragraph covering what it is, the no-backup cost, and how to share later
- [x] 5.3 `docs/CONTEXT.md` §4: add the decision (store `info/exclude` over a separate local dir, with a pointer to L1), and add the verified fact that integrating remote commits silently overwrites ignored files, which is why the guard exists
- [x] 5.4 `/reload-plugins`, then in a scratch project ask in prose to "keep my .claude out of the shared artifact repo". Verify the skill picks `adopt --local` with a dry-run first

## 6. Review fixes

- [x] 6.1 Bump the engine and both plugin manifests to 0.2.0 so `heal` refreshes vendored copies (they only refresh on version drift). Verify with `grep 0.2.0` across the engine and the manifests, and check that the smoke vendoring assertions pass
- [x] 6.2 Add `ignore_pattern` (escapes `[ ] \ * ? # !` and a trailing space) and use it for the store `info/exclude` line and the host managed block. `read_managed` undoes the escapes, and names containing a newline are refused. Verify with smoke "names with gitignore metacharacters…" and a manual detach/heal round-trip with `[draft]`, `a*b`, `b\s`, `x `, `#hash`, `!bang`
- [x] 6.3 Replace `check-ignore` in the guard and in status with a literal comparison against `ls-files --others --ignored --exclude-standard --directory` (it globs its input). Verify that a pushed `[draft]/f` stops `sync` and that status lists `[draft]`
