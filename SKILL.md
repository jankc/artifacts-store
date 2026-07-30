---
name: lnd-artifacts
description: Manage this project's AI artifacts (.claude/, openspec/, CLAUDE.md, …) in a private artifact repository that is never committed to the customer repo. Use when the user wants to set up / initialize artifact management, adopt an existing artifact folder into the store, sync (commit + push) artifact changes, check artifact status, repair broken artifact symlinks, or remove the setup.
---

# lnd-artifacts

Artifacts live in a private git clone at `<git-common-dir>/lundegaard` (i.e.
`.git/lundegaard` in the main worktree). Its first-level entries are symlinked into the
project root and ignored through a managed block in `<git-common-dir>/info/exclude`, so
nothing ever reaches the customer's remote.

The engine is a POSIX script:

```
ENGINE="${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh"
```

Always run it from inside the project (any worktree). It never modifies the host
repository — no commits, no staging, no config writes.

## When to use this skill

| The user says … | Verb |
| --- | --- |
| "set up artifact management", "connect the artifact repo", "init lnd-artifacts" | `init <remote-url>` |
| "my `.claude` symlink is gone", "links are broken", "new worktree has no artifacts" | `heal` |
| "put `.opencode/` into the artifact repo", "adopt this folder" | `adopt <path>` |
| "sync/push/commit the artifacts", "save my artifact changes" | `sync` |
| "are the artifacts up to date?", "what is the artifact state?" | `status` |
| "remove the artifact links", "unhook this project" | `cure` |

## Verbs

```sh
"$ENGINE" init <remote-url>   # clone the artifact repo into the common dir and link it
"$ENGINE" heal                # idempotent repair of links + exclude block
"$ENGINE" adopt <path>        # move an untracked first-level path into the store
"$ENGINE" sync [-m "msg"]     # commit -A, pull --rebase, push
"$ENGINE" status              # read-only health report
"$ENGINE" cure [--all-worktrees]  # remove links + exclude block, keep the store
```

Every mutating verb takes `--dry-run`.

## Rules

1. **Preview first.** Run `--dry-run` before `init`, `adopt` and `cure`, show the user
   the plan, and only then run for real. `heal` and `sync` may be run directly, but a
   `--dry-run` is still welcome when the state looks unusual.
2. **`init` needs a remote URL — ask for it.** Never invent one, never reuse another
   project's artifact repo: one artifact repository serves exactly one customer project.
   If the user does not have one yet, tell them to create an empty private repo and give
   you its clone URL.
3. **Never commit or push on your own initiative.** `sync` is an explicit user decision.
   Suggest it when `status` shows unsynced work; do not run it as a side effect of
   another task.
4. **Never work around a refusal.** If `adopt` refuses a tracked path, do not
   `git rm --cached` it — explain that tracked content belongs to the customer repo.
5. **Report quarantines loudly.** `heal`/`adopt` rename anything foreign found at a
   managed name to `<name>.quarantined-<timestamp>`. Tell the user what was quarantined
   and let them decide whether to merge the contents into the store or delete it.
6. **Keep the store root payload-only.** Every first-level entry of the store gets
   symlinked into the project root, so never create `README.md`, `.gitignore` or other
   housekeeping files at the store root. Tool-level ignores go inside the tool folder
   (e.g. `.claude/.gitignore`).
7. **Edit artifacts through the project-root symlinks** (`.claude/…`, `openspec/…`) as
   usual — they are the same files as in the store.

## Initialization dialogue

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
- **rebase conflict during `sync`** — the store is left mid-rebase on purpose. Resolve it
  inside the store (`git -C <store> status`), then run `sync` again. Do not force-push.
- **`git clean -fdx` wiped the links** — expected; `heal` restores them, the store lives
  in `.git/` and survives.
