# lnd-artifacts

A Claude Code plugin that versions your AI tool artifacts (`.claude/`, `openspec/`,
`CLAUDE.md`, …) in a **private artifact repository** — without ever committing them to
the customer's repository.

The artifact repo is cloned into the host project's git **common dir**
(`.git/lundegaard`), and every first-level entry of its root is symlinked into the
project root. Those symlinks are ignored through a managed block in
`<git-common-dir>/info/exclude`, so the customer repo's `git status` stays clean and the
artifacts are structurally incapable of leaking into the customer remote.

```
customer-project/
  .git/
    lundegaard/          <- the artifact repo (a normal git clone)
      .claude/
      openspec/
      CLAUDE.md
    info/exclude         <- managed block ignoring the links below
  .claude      -> .git/lundegaard/.claude
  openspec     -> .git/lundegaard/openspec
  CLAUDE.md    -> .git/lundegaard/CLAUDE.md
  src/ ...                (the customer's own, untouched content)
```

## Why the common dir

- **Worktrees are free.** `git rev-parse --git-common-dir` resolves to the main clone's
  `.git` from every linked worktree, so all worktrees share one store, one remote and one
  `info/exclude` block. A new worktree only needs `heal` to get its symlinks.
- **Leak-proof.** Nothing under `.git/` can be committed to the customer remote.
- **`git clean -fdx` survivable.** Clean removes the symlinks, never the store; the
  SessionStart hook heals them back.

## Quick start

```sh
# 1. load the plugin (session-only, no marketplace needed)
claude --plugin-dir /path/to/lnd-artifacts

# 2. inside the customer project, ask Claude to set up artifact management,
#    or run the engine directly:
/path/to/lnd-artifacts/scripts/lnd-artifacts.sh init git@host:team/project-artifacts.git

# 3. work normally; when you want to publish artifact changes:
/path/to/lnd-artifacts/scripts/lnd-artifacts.sh sync
```

## Verbs

| Verb | What it does |
| --- | --- |
| `init <remote-url>` | Clone the artifact repo into `<git-common-dir>/lundegaard`, then link. Refuses if a store already exists. |
| `heal` | Idempotent self-repair: create missing links, fix wrong ones, drop orphans, rewrite the exclude block. |
| `adopt <path>` | Move an untracked first-level path into the store and link it back. |
| `sync` | Commit everything in the store, `pull --rebase`, push. Explicit, never automatic. |
| `status` | Store presence, dirty/unpushed counts, link health, quarantine leftovers. Never changes anything. |
| `detach` | Remove the managed links and the exclude block. The store is left untouched — `heal` restores everything. |

Every mutating verb accepts `--dry-run` and prints the full plan without touching disk.

## Conventions and constraints

- **The store root is payload-only.** Every first-level entry except `.git` gets
  symlinked into the customer's project root, so the artifact repo must not carry
  housekeeping files at its root — no `README.md`, no root `.gitignore`. Per-tool runtime
  ignores belong inside the tool folder (e.g. `.claude/.gitignore`). `status` warns when
  it spots such an entry.
- **One artifact repo = one customer project.** No shared or multi-project stores.
- **Pre-existing paths are quarantined, never deleted.** A real `.claude/` directory
  sitting where a link belongs is renamed `.claude.quarantined-<timestamp>` and reported
  loudly. Quarantined paths are deliberately *not* ignored, so you see them.
- **The engine never touches the host repository.** No commits, no staging, no config
  changes — only the store and the symlinks.
- **Hooks never commit or push.** SessionStart runs `heal`; Stop only warns about
  unsynced state. `sync` is always a human decision.
- POSIX shell + git + coreutils only. No Windows support (POSIX symlinks).

## Risks worth knowing

- **`rm -rf .git` or a fresh re-clone destroys unpushed artifacts.** The store lives in
  `.git/`. Sync eagerly; the Stop hook and `status` make unsynced state loud.
- **Backup tools that skip `.git/` will not back up the store.** The artifact remote is
  the backup.
- **Search tools don't follow symlinks by default** — `rg -L` if you want the artifacts
  included from the project root.
- **Worktrees share unpushed artifact state.** Two worktrees editing the same artifact
  file is last-write-wins locally; real conflicts surface at `sync` rebase time.

## Development

```sh
claude --plugin-dir /path/to/lnd-artifacts   # load, session-only
# /reload-plugins  inside the session after editing SKILL.md, hooks or scripts
./scripts/smoke.sh                           # disposable-fixture end-to-end test
```

Layout:

```
.claude-plugin/plugin.json   manifest
SKILL.md                     the single skill that drives the engine
scripts/lnd-artifacts.sh     the engine (all verbs)
scripts/smoke.sh             end-to-end test on throwaway fixtures
hooks/hooks.json             SessionStart (heal) + Stop (warn)
hooks/session-start.sh
hooks/stop.sh
```

Deleting `hooks/hooks.json` degrades the plugin gracefully to fully manual operation.
