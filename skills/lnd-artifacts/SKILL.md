---
name: lnd-artifacts
description: Manage this project's AI artifacts (.claude/, openspec/, CLAUDE.md, …) in a private artifact repository that is never committed to the customer repo. Use when the user wants to set up / initialize artifact management, adopt an existing artifact folder into the store, sync (commit + push) artifact changes, check artifact status, repair broken artifact symlinks, or remove the setup.
---

# lnd-artifacts

Artifacts live in a private git clone at `<git-common-dir>/lundegaard` (i.e.
`.git/lundegaard` in the main worktree). Its first-level entries are symlinked into the
project root and ignored through a managed block in `<git-common-dir>/info/exclude`, so
nothing ever reaches the customer's remote.

The engine is a POSIX script. Resolve `$ENGINE` in this order, and stop at the first
step that yields an existing file:

1. **`${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh`** — the plugin's own engine, always
   current with the installed plugin. The runtime substitutes the plugin's absolute path
   into this text before you read it (Claude Code does; nothing is read from the shell
   environment), so in a Claude session the path below is already absolute and passes
   `[ -x ]`. A runtime that substitutes nothing leaves a path that cannot exist, and
   resolution falls through to step 2.
2. **`$(git rev-parse --git-common-dir)/lundegaard.engine.sh`** — otherwise (Codex or any
   other runtime). Every initialized project carries this vendored copy; it works
   identically in every runtime and in every worktree.
3. **Ask the user** for the path to the engine or to the plugin checkout. This case is
   the first-ever `init` in a project outside Claude Code: no store exists yet, so there
   is nothing vendored, and step 1 was left unsubstituted. Never guess install
   locations and never search the filesystem for the checkout.

```sh
ENGINE="${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh"
[ -x "$ENGINE" ] || ENGINE="$(git rev-parse --git-common-dir)/lundegaard.engine.sh"
```

Always run it from inside the project (any worktree). It never modifies the host
repository — no commits, no staging, no config writes.

`init` also leaves a runnable copy of the engine at
`<git-common-dir>/lundegaard.engine.sh`, refreshed by `heal` whenever the plugin's version
changes. That copy is how a project gets artifacts **without an agent** — e.g. in a brand
new worktree. Tell users to put this line in their worktree-init tooling (worktrunk
`pre-start`, a `post-checkout` hook, a Makefile target); the `[ -x "$E" ]` guard makes it a
silent no-op in projects with no store and outside git repositories, so it is safe to
configure globally:

```sh
E="$(git rev-parse --git-common-dir 2>/dev/null)/lundegaard.engine.sh"; [ -x "$E" ] && "$E" heal --quiet || true
```

Never suggest editing that copy — `heal` overwrites it on version drift. `status` reports
its version.

## When to use this skill

| The user says … | Verb |
| --- | --- |
| "set up artifact management", "connect the artifact repo", "init lnd-artifacts" | `init <remote-url>` |
| "my `.claude` symlink is gone", "links are broken", "new worktree has no artifacts" | `heal` |
| "put `.opencode/` into the artifact repo", "adopt this folder" | `adopt <path>` |
| "keep my `.claude/` out of the shared artifact repo", "personal, not for the team, but in every worktree" | `adopt --local <path>` |
| "sync/push/commit the artifacts", "save my artifact changes" | `sync` |
| "are the artifacts up to date?", "what is the artifact state?" | `status` |
| "remove the artifact links", "unhook this project" | `detach` |

## Verbs

```sh
"$ENGINE" init <remote-url>   # clone the artifact repo into the common dir and link it
"$ENGINE" heal                # idempotent repair of links + exclude block
"$ENGINE" adopt <path>        # move an untracked first-level path into the store
"$ENGINE" adopt --local <path>  # same, but never commit or push it (local-only)
"$ENGINE" sync [-m "msg"]     # commit -A, fetch + rebase, push
"$ENGINE" status              # read-only health report
"$ENGINE" detach [--all-worktrees]  # remove links + exclude block, keep the store
```

Every mutating verb takes `--dry-run`.

## Rules

1. **Open with `status`.** Before starting any artifact-related work, run
   `"$ENGINE" status`. If it reports missing or broken links, run `"$ENGINE" heal` before
   doing anything else. Claude Code does this automatically in a SessionStart hook;
   runtimes without hooks (Codex) rely on this rule, so never skip it there.
2. **Preview first.** Run `--dry-run` before `init`, `adopt` and `detach`, show the user
   the plan, and only then run for real. `heal` and `sync` may be run directly, but a
   `--dry-run` is still welcome when the state looks unusual.
3. **`init` needs a remote URL — ask for it.** Never invent one, never reuse another
   project's artifact repo: one artifact repository serves exactly one customer project.
   If the user does not have one yet, tell them to create an empty private repo and give
   you its clone URL.
4. **Never commit or push on your own initiative.** `sync` is an explicit user decision.
   Suggest it when `status` shows unsynced work; do not run it as a side effect of
   another task.
5. **Close by naming unsynced state.** When a task edited artifacts, finish by reporting
   that the store has uncommitted or unpushed changes and suggesting `"$ENGINE" sync`.
   This is a sentence, not an action — rule 4 still holds, so wait for the user to ask.
   Claude Code also warns about this in a Stop hook; in runtimes without hooks this rule
   is the only nudge the user gets.
6. **Never work around a refusal.** If `adopt` refuses a tracked path, do not
   `git rm --cached` it — explain that tracked content belongs to the customer repo.
7. **Report quarantines loudly.** `heal`/`adopt` rename anything foreign found at a
   managed name to `<name>.quarantined-<timestamp>`. Tell the user what was quarantined
   and let them decide whether to merge the contents into the store or delete it.
8. **Keep the store root payload-only.** Every first-level entry of the store gets
   symlinked into the project root, so never create `README.md`, `.gitignore` or other
   housekeeping files at the store root. Tool-level ignores go inside the tool folder
   (e.g. `.claude/.gitignore`).
9. **Local-only entries have no backup — say so.** `adopt --local` marks the entry in the
   store's own `info/exclude` (`.git/lundegaard/.git/info/exclude`): every worktree of this
   clone sees it, `sync` never pushes it, and deleting `.git` or re-cloning loses it. Tell
   the user that when adopting. To share one later, delete its line from that file and
   `sync`. Never `git rm --cached` a shared store entry to make it local-only — that
   pushes a deletion to every teammate. If `sync` stops because the remote would write
   into local-only paths, show the message verbatim and let the user choose: move their
   copy out of the way, or share it.
10. **Edit artifacts through the project-root symlinks** (`.claude/…`, `openspec/…`) as
   usual — they are the same files as in the store.

## Initialization dialogue

0. Resolve `$ENGINE`. If step 1's path was never substituted — it still reads
   `${CLAUDE_PLUGIN_ROOT}/…`, so no runtime told you where the plugin lives — **and** there
   is no vendored engine in the git common dir, this is the first-ever `init` outside
   Claude Code: say so and ask the user where the plugin lives, e.g. "I need the path to
   the lnd-artifacts engine (`<checkout>/scripts/lnd-artifacts.sh`) — where is the
   checkout?". If they have
   the agent-neutral skills directory wired, the answer is
   `~/.agents/skills/lnd-artifacts/scripts/lnd-artifacts.sh`. Do not search for it and do
   not proceed without an answer; after `init` the vendored copy makes every later run in
   this project self-resolving.
1. Run `"$ENGINE" status`. If it reports a store, there is nothing to initialize — offer
   `heal` or `status` instead.
2. Ask the user for the artifact repository remote URL (e.g.
   `git@host:team/<project>-artifacts.git`). Confirm it belongs to this project only.
3. `"$ENGINE" init <url> --dry-run`, show the plan.
4. `"$ENGINE" init <url>`, then report which links were created.
5. If the store was empty, offer to `adopt` the artifact folders that already exist in
   the project (`.claude`, `openspec`, `CLAUDE.md`, …) and then `sync`.

## Troubleshooting

- **"not inside a git working tree"** — the project must be a git repo; the store lives
  in its git common dir.
- **"an artifact store already exists"** — use `heal`/`status`; `init` never overwrites.
- **"could not acquire the store lock"** — another run is in progress; if the reported
  PID is dead, the message includes the exact `rm -rf` to clear it.
- **rebase conflict during `sync`** — the store is left mid-rebase on purpose. Inspect it
  with `git -C <store> status`, resolve and stage the files, then run
  `git -C <store> rebase --continue` (repeat as needed), or abandon with
  `git -C <store> rebase --abort`. Run `sync` again only after the rebase has finished or
  been aborted. Do not force-push.
- **`git clean -fdx` wiped the links** — expected; `heal` restores them, the store lives
  in `.git/` and survives.
