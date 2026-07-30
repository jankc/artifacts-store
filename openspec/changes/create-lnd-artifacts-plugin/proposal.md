# Proposal — create the lnd-artifacts plugin

## Why

AI tool artifacts (`.claude/`, `openspec/`, `CLAUDE.md`, …) inside customer repositories
must be versioned and shared across a team without ever being committed to the customer's
remote. The previous attempt (lnd-core's `.lundegaard/` transport) entangled artifact
transport with governance machinery and broke under git worktrees because the store lived
in the working tree and had to be re-ignored per worktree. This plugin starts fresh: a
single-purpose, standalone plugin whose only job is artifact transport, with the store in
the git common dir where worktree sharing is free and leakage into the customer remote is
structurally impossible.

## What Changes

- New standalone repository `lnd-artifacts` that IS a Claude Code plugin (installable via
  `claude --plugin-dir` during development, marketplace-ready later).
- New artifact store model: a private artifact repository is cloned into the host
  project's git common dir at `<common-dir>/lundegaard` (i.e. `.git/lundegaard` in the
  main worktree), resolved via `git rev-parse --git-common-dir`.
- Ailien-style linking: every first-level entry of the store root except `.git` is
  symlinked into the project root. The store root is the manifest — no `linked/`
  indirection, no adopt manifest, no categories.
- A marker-delimited managed block in `<common-dir>/info/exclude` ignores the symlinks;
  because the exclude file lives in the common dir, one block covers the main worktree
  and every linked worktree. The block doubles as state for `detach`.
- One POSIX script `scripts/lnd-artifacts.sh` implements all verbs:
  `init <remote-url>`, `heal`, `adopt <path>`, `sync`, `status`, `detach` — each with
  `--dry-run` support.
- Worktree support: `heal` (re)materializes symlinks in the current worktree; the store
  and exclude block are shared via the common dir, so a new worktree needs only `heal`.
- Plugin hooks: a `SessionStart` hook runs `heal` (self-repair after `git clean`, new
  worktrees just work); a `Stop` hook only WARNS when the store has uncommitted or
  unpushed changes. Hooks never commit or push — `sync` is always an explicit human/skill
  action.
- One skill (`SKILL.md`) that teaches Claude when and how to drive the script
  (initialization dialogue asking for the remote URL, adopt/sync/status/detach flows).

## Capabilities

### New Capabilities

- `artifact-store`: lifecycle of the per-project artifact store in the git common dir —
  init (clone from remote), location resolution, locking, and safety guards.
- `artifact-linking`: first-level symlinking of store entries into the project root,
  managed exclude block, heal/adopt/detach semantics, quarantine of pre-existing paths,
  and worktree behavior.
- `artifact-sync`: explicit commit/pull-rebase/push flow, status reporting (dirty and
  unpushed state), and conflict surfacing.
- `plugin-integration`: plugin manifest, skill, SessionStart heal hook, and Stop
  warn-only hook contracts.

### Modified Capabilities

None — this is a fresh repository with no existing specs.

## Impact

- New repo contents: `.claude-plugin/plugin.json`, `SKILL.md`, `scripts/lnd-artifacts.sh`,
  `hooks/hooks.json`, `README.md`.
- Host projects gain: `<common-dir>/lundegaard/` (store clone), a managed block in
  `<common-dir>/info/exclude`, and root-level symlinks. Nothing is ever added to the
  customer repository's tracked content.
- lnd-core (in the ai-marketplace repo) is untouched; it serves as reference only.
  Ailien's `infect` is the design inspiration for linking, exclude management, and
  quarantine behavior.
- Trade-offs accepted: worktrees share unpushed artifact state; artifacts under `.git/`
  are invisible to backup tools that skip `.git`; `rm -rf .git` destroys unpushed
  artifacts (mitigated by eager `sync` and loud `status`/Stop warnings).
