# lnd-artifacts

A Claude Code and Codex plugin that versions your AI tool artifacts (`.claude/`, `openspec/`,
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
    lundegaard.engine.sh <- runnable copy of the engine (agentless bootstrap)
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

# 2. inside the customer project, run /lnd-artifacts:help for what this is, the live
#    artifact status and the verb list. Then just ask Claude to set up artifact
#    management — the skill knows where the engine lives. Or run it yourself:
$ENGINE init git@host:team/project-artifacts.git

# 3. work normally; when you want to publish artifact changes:
$ENGINE sync
```

The first `init` runs from the plugin checkout. After it, every project carries its own
runnable copy of the engine, so outside a session `$ENGINE` is simply
`"$(git rev-parse --git-common-dir)/lundegaard.engine.sh"` — see
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

Inside a Claude session you never need a path — Claude Code substitutes the plugin's
absolute path into the skill text, so the skill reaches the plugin's own engine. Outside
one (shell, git hook, worktree-init tooling, Codex),
**do not reference the plugin at all**: `init` leaves a runnable copy of the engine in the
project's git common dir, and that copy is what every external caller should use.

```sh
ENGINE="$(git rev-parse --git-common-dir)/lundegaard.engine.sh"
```

The copy is a plain file next to the store (`.git/lundegaard.engine.sh` in the main
worktree). It works with no plugin installed, no `PATH` entry and no environment
variables, and every worktree of the clone resolves the same path.

Why not just pin a plugin path? Because none of them is stable:

| Path | Why not |
| --- | --- |
| `~/.claude/plugins/cache/<mkt>/lnd-artifacts/<version>/…` | version-pinned; moves on every upgrade |
| `~/.claude/skills/lnd-artifacts/…` | tied to one `CLAUDE_CONFIG_DIR`; invisible to sessions using another |
| `${CLAUDE_PLUGIN_ROOT}/…` | substituted into Claude skill and command text, and set for hook processes — never present in the shell you or an agent types into |

Publishing the plugin to a marketplace makes this worse, not better — the install path
then carries a version component that changes under your feet.

Three things worth knowing about the vendored copy:

- **Don't edit it.** `heal` overwrites it whenever its version differs from the running
  plugin's (upgrade *or* downgrade), so local edits are lost. Project-specific behavior
  belongs in the store, not in the engine.
- **`git clean` cannot remove it.** It lives inside `.git/`, like the store. `status`
  reports its version, so drift is visible; `heal` refreshes it, and the SessionStart hook
  runs `heal`, so an upgraded plugin propagates on the next session with no user action.
- It is a script under `.git/` that your tooling executes — no new trust boundary
  (`.git/hooks` already runs arbitrary code in any repo you check out), but worth knowing.

The first `init` still needs the plugin, since there is nothing vendored yet. Run it from
a Claude session, or by path into your checkout — the engine is self-contained POSIX shell
and does not care where it is called from.

### New worktrees without an agent

`heal` takes no arguments: it resolves the store from the current directory, so any
worktree-init hook that runs with the new worktree as its cwd is enough. This is the line
to put in that tooling:

```sh
E="$(git rev-parse --git-common-dir 2>/dev/null)/lundegaard.engine.sh"; [ -x "$E" ] && "$E" heal --quiet || true
```

For example, in worktrunk:

```toml
[[pre-start]]
lnd-artifacts = 'E="$(git rev-parse --git-common-dir 2>/dev/null)/lundegaard.engine.sh"; [ -x "$E" ] && "$E" heal --quiet || true'
```

Worktree-init configuration is global — it fires in every project you create a worktree
in, and most of them have no artifact store. The `[ -x "$E" ]` guard is what makes the
line a silent, zero-exit no-op there, and outside git repositories entirely. Keep it.

If you would rather have git do it with no per-tool config, the same line fits a
`post-checkout` hook (`git worktree add` fires it with the new worktree as cwd, and hooks
resolve from the common dir, so one file covers every worktree):

```sh
cat > "$(git rev-parse --git-common-dir)/hooks/post-checkout" <<'EOF'
#!/bin/sh
[ "$3" = 1 ] || exit 0            # branch checkouts only, not `git checkout -- <file>`
E="$(git rev-parse --git-common-dir)/lundegaard.engine.sh"
[ -x "$E" ] && "$E" heal --quiet || true
exit 0
EOF
chmod +x "$(git rev-parse --git-common-dir)/hooks/post-checkout"
```

That also repairs links on a plain `git switch`. Before using it, check that
`git config core.hooksPath` is unset (husky/lefthook redirect hooks and this file would
never run) and that the project has no existing `post-checkout` to clobber.
`git worktree add --no-checkout` does not fire it, and it is per-project — install it once
in each repo where you want it.

Without either of these the SessionStart hook still heals the worktree, but only once an
agent starts there — and that first session will not yet have the store's `CLAUDE.md` as
project instructions, because instruction files are collected before the hook restores
the link. Healing up front avoids that.

## Codex

The skill is runtime-neutral: its first engine candidate is the plugin path the runtime
substitutes into the skill text (Claude Code does this; Codex does not), and a candidate
that fails `[ -x ]` falls through to the vendored copy in the git common dir — so a Codex
session drives every verb in any initialized project. `/lnd-artifacts:help` is Claude-only:
Codex loads `skills/` and never sees `commands/`.

### Wiring

Codex discovers user-level skills in `$CODEX_HOME/skills` (`~/.codex/skills` when
`CODEX_HOME` is unset). Link the checkout in through the agent-neutral skills directory,
the same hop scheme as Claude:

```sh
mkdir -p ~/.agents/skills ~/.codex/skills
ln -sfn /path/to/lnd-artifacts        ~/.agents/skills/lnd-artifacts
ln -sfn ~/.agents/skills/lnd-artifacts ~/.codex/skills/lnd-artifacts
```

Codex descends into the plugin's `skills/` directory, so the link points at the checkout
root, not at `skills/lnd-artifacts`. Per project instead of per user, a
`.codex/skills/lnd-artifacts` link in the project works the same way.

The indirection is what makes the first `init` answerable: with no store yet there is
nothing vendored and no `CLAUDE_PLUGIN_ROOT`, so the skill asks you where the engine is,
and `~/.agents/skills/lnd-artifacts/scripts/lnd-artifacts.sh` is a stable answer.

### What Codex users do not get

The two lifecycle hooks are Claude Code plugin hooks and do not travel with the skill:

- **No SessionStart heal** — links are not repaired automatically when a session starts.
- **No Stop warning** — a session that never touches artifacts never mentions unsynced
  state on its own.

Three things compensate, in order of strength:

1. **The vendored one-liner** in worktree-init tooling or a `post-checkout` hook (see
   [New worktrees without an agent](#new-worktrees-without-an-agent)) — runtime-independent,
   and it heals *before* any agent starts, which the SessionStart hook cannot do.
2. **The skill's opening rule** — run `status` before artifact work, `heal` when it
   reports link damage.
3. **The skill's closing rule** — after editing artifacts, report unsynced state and
   suggest `sync`. As everywhere else, `sync` still runs only when you ask for it.

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
# /reload-plugins  inside the session after editing the skill, hooks or scripts
./scripts/smoke.sh                           # disposable-fixture end-to-end test
```

Layout:

```
.claude-plugin/plugin.json      Claude Code manifest
.codex-plugin/plugin.json       Codex mirror manifest (same name/version/description)
skills/lnd-artifacts/SKILL.md   the skill that drives the engine
commands/help.md                /lnd-artifacts:help — live status + verbs, read-only,
                                Claude Code only (Codex loads skills/ only)
scripts/lnd-artifacts.sh        the engine (all verbs)
scripts/smoke.sh                end-to-end test on throwaway fixtures
hooks/hooks.json                SessionStart (heal) + Stop (warn)
hooks/session-start.sh
hooks/stop.sh
```

Both manifests declare `"skills": "./skills/"` and must stay in version lockstep. The
engine's own `VERSION=` is what `heal` compares against the vendored copy, so it is the
source of truth for behavior; the manifest versions are packaging metadata that follow it.

Deleting `hooks/hooks.json` degrades the plugin gracefully to fully manual operation.
