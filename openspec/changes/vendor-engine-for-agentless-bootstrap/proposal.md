# Proposal — vendor the engine into the git common dir for agentless bootstrap

## Why

Today the only zero-effort way to materialize artifact symlinks in a **new worktree** is
to start a Claude session there and let the SessionStart hook run `heal`. That is
backwards: the files should exist before any agent runs. Users create worktrees with
tooling (worktrunk, shell functions, Makefile targets, plain `git worktree add`), and
that tooling needs a command it can call.

Writing such a command is currently impossible to document for a general user, because
every path to the engine is unstable:

| candidate path | why it fails |
| --- | --- |
| `~/.claude/plugins/cache/<mkt>/lnd-artifacts/<version>/scripts/…` | version-pinned — moves on every plugin upgrade |
| `~/.claude/skills/lnd-artifacts/scripts/…` | tied to one `CLAUDE_CONFIG_DIR`; invisible to sessions using another |
| `${CLAUDE_PLUGIN_ROOT}/scripts/…` | only set while a Claude hook or skill is running |
| `~/.local/bin/lnd-artifacts` (copy on PATH) | assumes that dir exists and is on PATH — not true for every user |

Publishing to a marketplace does **not** fix this; it makes it worse, because the
install path then carries a version component that changes under the user's feet.

The fix is to stop referencing the plugin at all. The engine is a single self-contained
POSIX script with no dependencies, so `init` can leave a copy inside the host project's
git common dir — the one location that is derivable from anywhere with
`git rev-parse --git-common-dir`, which the store, lock, and exclude block already
depend on. A worktree-init command then names nothing about where the plugin lives.

## What Changes

- `init` SHALL additionally write a copy of the engine to
  `<git-common-dir>/lundegaard.engine.sh` (executable), a sibling of the store.
- `heal` SHALL refresh that copy when the running engine is a different version, so the
  vendored copy tracks plugin upgrades without user action (SessionStart runs `heal`).
- `detach` SHALL remove the vendored copy along with the links and the exclude block.
- `status` SHALL report the vendored engine's presence and version.
- README SHALL document the single line users put in worktree-init tooling:

  ```sh
  E="$(git rev-parse --git-common-dir 2>/dev/null)/lundegaard.engine.sh"; [ -x "$E" ] && "$E" heal --quiet || true
  ```

- No new verb, no user-facing install step, no PATH assumption.

Additionally, this change carries the repo-layout half of dual-runtime packaging, folded
in here so the repository is restructured exactly once (the Codex-behavior half is the
separate `add-codex-runtime-support` change, which builds on this layout):

- The root `SKILL.md` SHALL move to `skills/lnd-artifacts/SKILL.md`. The marketplace's
  naming conventions require this shape (root `SKILL.md` is an auditor ERROR), and Codex
  only loads skills from `skills/<name>/SKILL.md`. Claude Code accepts both shapes, so
  nothing changes for Claude sessions.
- A `.codex-plugin/plugin.json` mirror manifest SHALL be added alongside
  `.claude-plugin/plugin.json`, following the shape of `lnd-quick-commit` in the
  ai-marketplace repo (same name/version/description plus an `interface` block). Both
  manifests SHALL declare the skills directory and stay in version lockstep.

## Capabilities

### New Capabilities

- `artifact-bootstrap`: vendoring the engine into the git common dir, keeping it current,
  removing it on detach, and the agentless worktree-init contract it enables.

### Modified Capabilities

- `artifact-store`: `init` gains the vendoring step; `detach` (specified in
  `artifact-linking`) gains the removal step.
- `artifact-sync`: `status` additionally reports the vendored engine.
- `plugin-integration`: the skill moves to the `skills/<name>/SKILL.md` layout and the
  plugin gains a Codex mirror manifest (delta in `specs/plugin-integration/spec.md`).

## Impact

- Host projects gain one ~35 KB file at `<git-common-dir>/lundegaard.engine.sh`. It is
  invisible to `git clean`, never symlinked into the project root, and not inside the
  store, so `sync`'s `git add -A` cannot commit it.
- Users of any agent (or none) get a stable command. Codex users get the same line
  without Codex packaging existing.
- Removes the need for the `install-cli` / PATH-copy approach that was considered and
  rejected (see design.md).
- The repo layout becomes marketplace-convention-compliant and Codex-loadable; the only
  observable difference in Claude Code is the skill's path inside the plugin. Existing
  `~/.claude*/skills/` symlink installs must be re-verified after the move (see B9).

## Out of Scope

- **Windows.** The vendored path works there under Git Bash, but linking itself does not
  (POSIX symlinks need Developer Mode plus `core.symlinks`). Windows stays the declared
  non-goal of the base design and is its own decision.
- **Bootstrapping the very first `init`.** Something must run once per project — an agent
  session or a manual invocation by path. That is accepted: `init` is once per project,
  worktree creation is constant.
- Installing git hooks (`post-checkout`) into host repos. Considered and deferred — see
  design.md.
