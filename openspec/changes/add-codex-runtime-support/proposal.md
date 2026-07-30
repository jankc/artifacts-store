# Proposal — Codex runtime support

## Why

The plugin's future home is the ai-marketplace repo, which is dual-runtime by
convention: every plugin runs in Claude Code and in Codex. The
`vendor-engine-for-agentless-bootstrap` change already gives the repo the dual-runtime
*layout* (`skills/<name>/SKILL.md`, `.codex-plugin/plugin.json`); this change makes the
skill actually *work* when Codex loads it.

Two things are Claude-specific today:

1. **Engine resolution.** SKILL.md names the engine as
   `${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh`. That variable exists only inside
   Claude Code hooks/skills; a Codex session has no way to run any verb from the skill
   text alone. (Notably, even lnd-core — the marketplace's flagship dual-runtime
   plugin — has not solved this; its skills also hardcode `${CLAUDE_PLUGIN_ROOT}`.)
2. **Lifecycle hooks.** SessionStart heal and the Stop warning are Claude plugin hooks.
   The marketplace's Codex model carries no hooks, so a Codex session gets no automatic
   heal and no unsynced-state warning — the exact failure mode (silently accumulating
   unpushed artifacts) that made "no hooks at all" the rejected option in the base
   design's D6.

The vendored engine (from `vendor-engine-for-agentless-bootstrap`) is what makes a fix
possible without any Codex-specific machinery: in every initialized project the engine
is reachable at `$(git rev-parse --git-common-dir)/lundegaard.engine.sh`, identically in
both runtimes.

## What Changes

- SKILL.md's engine resolution becomes a runtime-neutral two-step rule: use
  `${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh` when the variable is set (Claude),
  otherwise the vendored `$(git rev-parse --git-common-dir)/lundegaard.engine.sh`
  (any runtime, any initialized project). For the one case where neither exists — the
  first-ever `init` run from Codex — the skill directs the agent to ask the user for
  the checkout path rather than guessing.
- SKILL.md gains hook-compensation rules, phrased for runtimes without hooks: run
  `status` before starting artifact-related work (approximates SessionStart heal's
  freshness check; run `heal` if it reports broken links), and after editing artifacts
  mention the unsynced state and suggest `sync` (approximates the Stop warning). The
  "never sync on your own initiative" rule stays absolute.
- README gains a Codex section: how discovery works (project-level `.codex/skills/` is
  verified; the user-level wiring goes through the existing `~/.agents/skills`
  indirection), and what Codex users do NOT get (no auto-heal, no Stop warning — the
  vendored one-liner and the skill rules are the compensations).
- docs/CONTEXT.md §5 gains the empirically verified Codex facts (discovery paths, env
  var behavior), gathered during implementation.
- Hooks are untouched. Claude behavior is unchanged except for the added skill rules,
  which are harmless there (hooks make them mostly redundant).

## Capabilities

### New Capabilities

- `codex-runtime`: runtime-neutral engine resolution in the skill, hook-compensation
  rules, and Codex discoverability of the plugin.

### Modified Capabilities

- `plugin-integration`: the skill's engine-resolution and etiquette text changes (the
  capability's requirements about hooks and the Claude load path are unaffected).

## Impact

- Codex sessions can drive every verb in any initialized project, and get textual
  substitutes for the two hooks.
- Claude sessions see no behavioral change; the skill text is the only shared surface.
- One machine-level step remains per Codex user (wiring the skills directory), which is
  documented, not automated — same posture as the Claude skills-dir install.

## Out of Scope

- Marketplace catalog entries and the auditor pass (adoption-time work).
- Any Codex equivalent of hooks, if one appears later — this change assumes none.
- Windows (unchanged non-goal of the base design).
- Automating the per-user Codex wiring.
