# Proposal — add a `/lnd-artifacts:help` command

## Why

The plugin has no user-typed entry point. Its only surface is a model-invocable skill,
which appears in the `/` menu as `/lnd-artifacts:lnd-artifacts` — a name that reads like
a packaging mistake and answers none of the three questions a person actually has when
they land in a project that already has a store:

1. What is this thing, and is it active here?
2. What state am I in right now — is the store linked, clean, pushed?
3. What can I ask for, and what will it do to my repo?

Today the only way to get those answers is to know the verb names already, or to ask in
prose and hope the skill triggers. A typed `/lnd-artifacts:help` is the discovery
affordance the plugin is missing, and it is the natural place to state the two things
users get wrong most often: that `sync` is never automatic, and that new worktrees are
healed by a one-liner rather than by starting an agent.

While designing this, one defect surfaced that the command would otherwise inherit.
The skill's step-1 engine resolution is specified as "use `${CLAUDE_PLUGIN_ROOT}` when
that variable is set" (`codex-runtime`, C1), and it is implemented as a shell test:

```sh
ENGINE="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/lnd-artifacts.sh}"
```

`CLAUDE_PLUGIN_ROOT` is **not** exported into the Bash tool's environment, so that test
always yields the empty string and every Claude session silently falls through to step 2.
What *does* work is render-time substitution: Claude Code replaces the literal
`${CLAUDE_PLUGIN_ROOT}` token in skill and command markdown with the plugin's absolute
path before the text reaches the model. Both facts were verified in a live session
(see design.md). C1's intent is correct and stays; the mechanism implementing step 1
does not work and must change, or the new command cannot reach the plugin's own engine
either.

## What Changes

- The plugin SHALL ship `commands/help.md`, surfacing as `/lnd-artifacts:help`.
- The command SHALL inject live engine output at expansion time — `status` and the
  engine's own `--help` — so the user sees real state, not a static description.
- It SHALL print the verb table, state that `sync` is never run unasked, give the
  worktree-init one-liner, and point at the README and the skill for deeper work.
- It SHALL be user-invocable only (`disable-model-invocation`), so it never competes
  with the main skill for automatic triggering.
- It lives in `commands/`, not `skills/`, so it stays a Claude Code surface: it depends
  on Claude-only render-time substitution and bash injection, and Codex — which descends
  into `skills/` only — never loads it. **The Codex mirror manifest is unchanged.**
- The skill's step-1 engine resolution SHALL stop using the `${CLAUDE_PLUGIN_ROOT:+…}`
  shell test and use the substituted absolute path instead, with the vendored engine
  remaining step 2 and the ask-the-user path remaining step 3.
- README gains the command in the layout listing and a line in the usage section;
  `docs/CONTEXT.md` §5a gains the verified substitution facts, and §5b's claim that the
  `${CLAUDE_PLUGIN_ROOT:+…}` test "is a reliable runtime discriminator" is corrected —
  it is constant-empty in every runtime.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `plugin-integration`: the plugin gains a `commands/` component and a user-invocable
  help surface; the layout requirement is no longer "one skill and nothing else".
- `codex-runtime`: the engine-resolution requirement keeps its three-step order but
  changes how step 1 is expressed, because the shell test it specified does not work.

## Impact

- One new file (`commands/help.md`), one edited skill section
  (`skills/lnd-artifacts/SKILL.md`, engine resolution), README and `docs/CONTEXT.md`.
- No engine change: `scripts/lnd-artifacts.sh` already implements `-h|--help|help` and
  `status`. The command is a presentation layer over output that exists.
- No hook change, no manifest change in either runtime. `commands/` is auto-discovered
  alongside the already-declared `"skills": "./skills/"`.
- Fixing step 1 makes Claude sessions use the *plugin's* engine again rather than the
  vendored copy. Behaviour is identical when versions match; when the plugin is newer
  than the vendored copy, sessions now get the newer engine immediately instead of after
  the next `heal`. The first-ever `init` inside Claude Code stops falling through to the
  step-3 "ask the user where the plugin lives" prompt, which was never intended for
  Claude sessions.

## Out of Scope

- **Commands for the other verbs.** No `/lnd-artifacts:sync`, `:init`, `:adopt`,
  `:detach`. Mutating verbs carry dialogue rules (dry-run first, ask for the remote URL,
  never sync unasked) that live in the skill; duplicating them across command files is
  how they drift apart. `:help` is read-only and duplicates nothing.
- **A Codex equivalent.** Codex ignores `commands/`, and its prompt mechanism is
  user-level (`~/.codex/prompts`), not shippable inside a plugin. Codex users keep the
  skill, which already carries the same verb table.
- **Relitigating C1's three-step order.** Only the expression of step 1 changes.
