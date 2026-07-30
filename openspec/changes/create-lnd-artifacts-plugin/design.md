# Design — lnd-artifacts plugin

## Context

See proposal.md — Why. Two prior systems shape this design:

- **lnd-core transport** (ai-marketplace repo, reference only): proved the per-project
  private artifact repo model, broke on worktrees because the store lived in the working
  tree (`<project>/.lundegaard/`) and had to be re-ignored per worktree. Its
  `lnd-store-in-git-common-dir` change proposal validated the common-dir move but stayed
  entangled with governance hooks; it is abandoned, not migrated.
- **ailien** (`~/dev/work/lunde/ailien`): proved first-level symlinking of live layers
  into customer repos, marker-delimited `info/exclude` blocks as cure state, quarantine
  instead of delete, and `--dry-run` discipline. This plugin inverts ailien's topology:
  instead of one central repo infecting many hosts via a `.targets` map, each host pulls
  its own artifact repo into its own `.git`.

Constraints: POSIX shell + git + coreutils only (no runtime dependencies); must behave
identically from main and linked worktrees; must never create tracked changes in the
customer repository; hooks must be safe to fire in arbitrary unrelated projects.

## Goals / Non-Goals

**Goals:**

- One script, one skill, two hooks; the store root listing is the only manifest.
- Zero-touch worktrees: store, exclude block, and remote config shared via the common
  dir; only symlinks are per-worktree, and SessionStart heal materializes them.
- Every mutating action previewable (`--dry-run`) and reversible (`cure` ↔ `heal`).

**Non-Goals:**

- No governance, traits, signoff, or secret-scanning (lnd-core territory).
- No multi-project or branch-per-project store sharing — 1 artifact repo = 1 customer
  project stays the standing decision.
- No seeding/templating layer (ailien's `dna/` stays in ailien).
- No automatic commit/push, ever.
- No Windows support initially (POSIX symlinks; ailien's junction dance is out of scope).

## Decisions

### D1 — Store path: `<git-common-dir>/lundegaard`, flat

`git rev-parse --git-common-dir` output may be relative (`.git`) — always normalize
against the invocation directory to an absolute path. Chosen over the old proposal's
`.git/lnd/store` nesting: one obvious directory in a `.git` listing, no hierarchy for
its own sake. Nested repos inside `.git/` are a known-good pattern (cf. versioned
`.git/hooks`); all store Git operations use `git -C "$STORE"` explicitly rather than
relying on discovery.

### D2 — Link rule: first-level entries, skip only `.git`; store stays payload-only

Matches ailien's live-layer rule exactly. No skip-list, no `.lndignore`, no underscore
convention until it hurts. Consequence: the store repo must not carry housekeeping files
at its root (no `README.md`, no root `.gitignore`) — per-tool runtime ignores live
inside each tool folder (`.claude/.gitignore`), same convention ailien uses for
`hosts/<key>/`. Alternative considered: keep lnd-core's `linked/` manifest dir —
rejected, pure indirection once 1 repo = 1 project.

### D3 — Symlinks are relative, computed per worktree at heal time

Relative links (`.claude -> .git/lundegaard/.claude` from the main worktree; a
`../..`-style path from linked worktrees, since their roots live elsewhere on disk)
survive moving the whole clone; absolute links break. Each `heal` recomputes the
relative path from the current worktree root to the resolved store. Link validation
compares fully resolved targets (realpath), not link text.

### D4 — Exclude block: marker-delimited, rewritten as a whole, doubles as cure state

Markers `# >>> lnd-artifacts managed >>>` / `# <<< lnd-artifacts managed <<<` in
`<git-common-dir>/info/exclude`. The engine always regenerates the full block from the
current store listing (plus `/.<name>.quarantined-*` noise is NOT excluded — quarantines
must stay visible). Everything outside the markers is preserved verbatim. `cure` reads
the block to know what it once managed, then removes it — same mechanism as ailien's
`--cure`.

### D5 — Locking: `mkdir` lock beside the store, in the common dir

`<git-common-dir>/lundegaard.lock` created with `mkdir` (atomic on POSIX), bounded retry
(10 × 1s), PID + timestamp + verb recorded in `owner` inside it for stale-lock
diagnostics. Lives in the common dir so all worktrees of the clone contend on the same
lock. Stale locks (dead PID) are reported with removal instructions, not auto-removed.

Amended during implementation: the original path `<store>/.lnd-artifacts.lock` breaks two
other decisions, because anything at the store root is payload. D2 would symlink the lock
into the customer's project root (heal enumerates the store root *while holding the
lock*), and `sync`'s `git add -A` would commit it into the artifact repo. Moving it one
level up to the common dir keeps D5's actual requirement — one lock shared by every
worktree — and additionally lets `init` lock before the store exists.

### D6 — Hooks: SessionStart = heal, Stop = warn; both no-op fast outside managed repos

Both hooks short-circuit in this order: not a git repo → exit 0 silent; no store at the
resolved common dir → exit 0 silent. SessionStart then runs `heal` (quiet unless it
changed something). Stop runs the dirty/unpushed check (`git -C "$STORE" status
--porcelain` + `rev-list @{u}..`) and emits a `systemMessage`-style warning with counts
and a "run sync" nudge. Chosen over full auto-sync (the lnd-core behavior being
abandoned) and over no hooks at all: heal is what makes worktrees zero-touch, and
warn-only keeps pushing a human decision. Deleting `hooks/hooks.json` degrades the
plugin gracefully to fully manual.

### D7 — adopt refuses tracked paths (and so does heal's quarantine)

Adopting a path tracked by the host repo would require a visible deletion commit in the
customer repository — exactly the footprint this tool exists to avoid. Untracked and
ignored paths only. Alternative (auto `git rm --cached` + exclude) rejected as a
customer-repo mutation.

The same reasoning extends to `heal` (found during implementation): when a store entry
collides with a path the host repo *tracks*, quarantining it would surface as a deletion
in the customer's working tree. So heal refuses to move tracked content, warns, and skips
that one entry — customer content wins — and `status` reports it as `COLLISION`.
Untracked and ignored collisions are still quarantined as specified.

### D8 — Repo layout: single-skill plugin, script at `scripts/`

```
lnd-artifacts/
  .claude-plugin/plugin.json    name: lnd-artifacts
  SKILL.md                      single root skill (name via frontmatter)
  scripts/lnd-artifacts.sh      all verbs: init|heal|adopt|sync|status|cure
  scripts/smoke.sh              disposable-fixture end-to-end test
  hooks/hooks.json              SessionStart + Stop → ${CLAUDE_PLUGIN_ROOT}/scripts/...
  README.md
```

Dev loop: `claude --plugin-dir ~/dev/work/lunde/lnd-artifacts` + `/reload-plugins`.
Marketplace adoption later = one `marketplace.json` entry pointing at this repo;
nothing here changes.

## Risks / Trade-offs

- [`rm -rf .git` / re-clone destroys unpushed artifacts] → eager `sync` habit, Stop-hook
  warning makes unsynced state loud, `status` shows unpushed counts first.
- [Backup tools and search skip `.git/` or don't follow symlinks (ripgrep needs `-L`)] →
  accepted; the remote is the backup; document in README.
- [`git clean -fdx` removes managed symlinks] → by design survivable: store is safe in
  `.git/`, SessionStart heal restores links; documented as a feature, not a bug.
- [Store root housekeeping file would get linked into customer root (D2)] → convention
  documented in README + `status` warns on suspicious root entries (e.g. `README.md`).
- [Host `.git` is a file (submodule) or `--separate-git-dir`] → always trust
  `rev-parse --git-common-dir`; never string-build `.git` paths.
- [Two worktrees editing the same artifact file] → inherent to shared-store model
  (accepted in the prior proposal too); last write wins locally, conflicts surface at
  `sync` rebase.

## Migration Plan

Nothing exists in production. No migration from lnd-core's `.lundegaard/` model is
implemented; if a project has one, the documented path is: push it, remove the local
directory, `init` fresh with the same remote. Rollback = `cure` (links and exclude gone,
store intact) or delete the store dir entirely after pushing.

## Open Questions

- Whether the Stop warning should also fire when the store is *behind* the remote
  (requires a fetch — cost vs. freshness); deferable, default is no fetch in hooks.
- Codex-side packaging (`.codex-plugin/`) — deferred until the Claude flow is proven.
