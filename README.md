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

# 2. inside the customer project, just ask Claude to set up artifact management —
#    the skill knows where the engine lives. Or run it yourself:
$ENGINE init git@host:team/project-artifacts.git

# 3. work normally; when you want to publish artifact changes:
$ENGINE sync
```

`$ENGINE` is whatever stable path you pin for `scripts/lnd-artifacts.sh` — see
[Invoking the engine outside a session](#invoking-the-engine-outside-a-session).

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

## Invoking the engine outside a session

Inside a Claude session you never need a path — the skill resolves the engine through
`${CLAUDE_PLUGIN_ROOT}`. Outside one (shell, git hook, worktree-init tooling, Codex)
there is no discovery mechanism that spans agents, so **pin one stable path yourself**.

Three paths that look tempting and are not stable:

| Path | Why not |
| --- | --- |
| `~/.claude/plugins/cache/<mkt>/lnd-artifacts/<version>/…` | version-pinned; moves on every upgrade |
| `~/.claude/skills/lnd-artifacts/…` | tied to one `CLAUDE_CONFIG_DIR`; invisible to sessions using another |
| `${CLAUDE_PLUGIN_ROOT}/…` | only set while a Claude hook or skill is running |

What works is one indirection you control. If you keep an agent-neutral skills directory,
point it at the checkout and have each agent's config dir hop through it:

```sh
ln -s /path/to/lnd-artifacts            ~/.agents/skills/lnd-artifacts
ln -s ../../.agents/skills/lnd-artifacts ~/.claude/skills/lnd-artifacts
ln -s ../../.agents/skills/lnd-artifacts ~/.claude-work/skills/lnd-artifacts
```

Anything under `~/.claude*/skills/` auto-loads as a plugin (`<name>@skills-dir`) with its
skill and hooks, no marketplace needed. The canonical engine path is then:

```sh
ENGINE="$HOME/.agents/skills/lnd-artifacts/scripts/lnd-artifacts.sh"
```

Move the checkout later and you fix one symlink. Referencing the checkout directly works
too — the engine is self-contained POSIX shell and doesn't care where it is called from.

### New worktrees without an agent

`heal` takes no arguments: it resolves the store from the current directory, so any
worktree-init hook that runs with the new worktree as its cwd is enough. For example, in
worktrunk:

```toml
[[pre-start]]
lnd-artifacts = "$HOME/.agents/skills/lnd-artifacts/scripts/lnd-artifacts.sh heal"
```

Better still, let git do it with no per-tool config. `git worktree add` fires
`post-checkout` with the new worktree as cwd, and hooks live in the common dir, so one
file covers every worktree of the clone:

```sh
cat > "$(git rev-parse --git-common-dir)/hooks/post-checkout" <<'EOF'
#!/bin/sh
[ "$3" = 1 ] || exit 0            # branch checkouts only, not `git checkout -- <file>`
"$HOME/.agents/skills/lnd-artifacts/scripts/lnd-artifacts.sh" heal --quiet 2>/dev/null || true
exit 0
EOF
chmod +x "$(git rev-parse --git-common-dir)/hooks/post-checkout"
```

This also repairs links on a plain `git switch`. Before using it, check that:

- `git config core.hooksPath` is unset — husky/lefthook redirect hooks and this file
  would never run;
- the project has no existing `post-checkout` — append the two lines instead of
  overwriting;
- you keep the `2>/dev/null || true`: in a repo without a store `heal` exits non-zero,
  and you do not want that noise on every checkout.

`git worktree add --no-checkout` does not fire the hook, and the hook is per-project —
install it once in each repo where you want it.

Without either of these the SessionStart hook still heals the worktree, but only once an
agent starts there — and that first session will not yet have the store's `CLAUDE.md` as
project instructions, because instruction files are collected before the hook restores
the link. Healing up front avoids that.

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
