# Design — Codex runtime support

## Context

Follows `vendor-engine-for-agentless-bootstrap` (layout + vendored engine) and depends
on it: the runtime-neutral engine path this change relies on is the vendored copy that
change creates. Read that change's design (B1–B9) first; read the base design's D6 for
why hooks are heal+warn and why hook-less operation is a *designed* degraded mode.

Known machine state that shaped this design (Jan's setup, 2026-07-30): the agent-neutral
skills dir `~/.agents/skills/lnd-artifacts` → checkout symlink already exists, with hops
from `~/.claude/skills/` and `~/.claude-work/skills/`. `~/.codex/skills/` does not exist
yet. This repo's own `.codex/skills/openspec-*` dirs prove Codex loads project-level
skills from `.codex/skills/`.

## Goals / Non-Goals

**Goals:**

- Every verb drivable from a Codex session in an initialized project, with no
  Codex-specific engine machinery.
- Textual compensation for the two missing hooks, weak but explicit.
- Verified, recorded facts about Codex skill discovery (not assumptions).

**Non-Goals:**

- Parity with Claude's hook automation. Codex users run in D6's degraded mode plus the
  vendored worktree one-liner; that is the accepted design, not a gap to close here.
- Codex-side packaging beyond what the layout change already added.

## Decisions

### C1 — Engine resolution order: plugin root, then vendored copy, then ask

The skill instructs (in order):

1. `${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh` when the variable is set — a Claude
   session, where this is always correct and version-current.
2. `$(git rev-parse --git-common-dir)/lundegaard.engine.sh` otherwise — any initialized
   project, any runtime. At worst one session stale (B3 refresh semantics), and `heal`
   is the verb that refreshes it.
3. Neither resolvable (no store yet, outside Claude): ask the user for the engine or
   checkout path. Never guess install locations — the path instability table in the
   vendoring proposal is exactly why.

Rejected: detecting Codex via its own env vars (undocumented, version-dependent, and
unnecessary — absence of `CLAUDE_PLUGIN_ROOT` is the only signal needed); shipping a
resolver script (it would itself need resolving — same regress the vendoring change
killed).

### C2 — Hook compensation is skill text, not machinery

Two rules added to SKILL.md:

- **Session-start substitute:** before starting artifact work, run `status`; if it
  reports broken/missing links, run `heal`. This is on-demand rather than automatic,
  which is acceptable because the vendored worktree one-liner (B4) covers the
  materialize-before-any-agent case better than the SessionStart hook ever did.
- **Stop substitute:** after a task that edited artifacts, report unsynced state and
  suggest `sync`. The existing rule 3 ("never sync on your own initiative") is
  unchanged and explicitly restated next to the new rule so the nudge cannot be read as
  license to auto-sync.

What is knowingly lost relative to Claude: the *unprompted* end-of-session warning. A
Codex user who never asks about artifacts is never nudged. Accepted: the alternative is
Codex-side machinery this change explicitly avoids; the Stop warning still exists for
every Claude session touching the same project, and `status` makes the state loud on
first contact.

These rules are harmless under Claude (hooks already cover them; the skill doing a
`status` first is good practice anyway), so the skill text stays single-source with no
runtime conditionals beyond C1.

### C3 — Discovery: verify, wire through the existing indirection, record

Project-level discovery (`.codex/skills/<name>/SKILL.md`) is already proven in this
repo. User-level discovery must be verified empirically during implementation — check
`codex --help` / current Codex docs for the skills search paths, then wire the same hop
scheme as Claude: `~/.codex/skills/lnd-artifacts` (or whatever the verified path is) →
`~/.agents/skills/lnd-artifacts` → checkout. Record the verified facts (search paths,
whether Codex exposes a skill-root variable, whether it descends into a plugin's
`skills/` dir) in docs/CONTEXT.md §5, alongside the Claude facts, with the Codex version
checked against.

If Codex turns out to only load `skills/<name>/SKILL.md` via its plugin/marketplace
mechanism and not via a plain skills dir, the fallback is symlinking the skill directory
itself (`~/.codex/skills/lnd-artifacts` → `<checkout>/skills/lnd-artifacts`) — the skill
text is self-contained after C1, so it works loaded standalone.

### C4 — First `init` from Codex: ask, don't bootstrap

The one flow that has no stable path is the first-ever `init` in a project, run from
Codex. Options rejected: hardcoding Jan's `~/.agents/skills` path into the skill (it's
one user's convention, not a contract); teaching `init` to self-locate (regress). The
skill asks the user for the path, and the README documents the `~/.agents/skills`
scheme as the recommended way to have a stable answer. The vendoring change accepted
"something must run once per project" — this is that same acceptance, one runtime over.

## Risks / Trade-offs

- [Skill text grows; Claude sessions re-read compensation rules they don't need] →
  kept to a few lines; a `status` before artifact work is good hygiene in both runtimes.
- [Codex discovery facts may change between Codex versions] → facts recorded with
  version checked; the C3 fallback shape is version-independent.
- [Vendored engine one session stale in Codex-only projects] → inherent to B3; `status`
  reports drift and points at `heal`.
- [User declines to give a path at first init] → nothing happens; no degraded write.

## Open Questions

- Does Codex set any env var pointing at the loaded skill's directory? If yes, a later
  change could add it as resolution step 1b; verify and record either way.
- Should the store's own payload (e.g. a project `AGENTS.md`) carry a sync-nudge line
  for Codex-heavy projects? Deferred — that's per-project content, not plugin behavior.
