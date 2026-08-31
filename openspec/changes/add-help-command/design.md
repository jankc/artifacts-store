# Design — `/lnd-artifacts:help`

## Context

See proposal.md — Why. Read C1 in `add-codex-runtime-support/design.md` before H4: this
change keeps C1's three-step order and replaces only the shell test that implements
step 1.

The engine already has everything the command needs to show: `usage()` behind
`-h|--help|help`, and `cmd_status()` behind `status`. Nothing in
`scripts/lnd-artifacts.sh` changes. This is a presentation and discovery change.

Five runtime facts were verified in live Claude Code sessions on 2026-08-03, against
the plugin loaded through the `~/.claude/skills/lnd-artifacts` → `~/.agents/skills` hop
(facts 1–4) and against a marketplace-installed plugin (fact 2's fenced-block half,
fact 5). They are the load-bearing evidence for H1 and H4 and belong in
`docs/CONTEXT.md` §5a:

1. **`CLAUDE_PLUGIN_ROOT` is absent from the Bash tool's environment.** `env | grep
   ^CLAUDE` in a session returns `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`,
   `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_PID`,
   `CLAUDE_EFFORT`, `CLAUDE_PLUGIN_DATA` — and no `CLAUDE_PLUGIN_ROOT`. It is set for
   hook processes and MCP servers, which is why `hooks/hooks.json` works and the skill's
   shell snippet does not.
2. **`${CLAUDE_PLUGIN_ROOT}` is text-substituted into plugin skill content at render
   time.** Invoking the skill rendered its step 1 as the absolute
   `/Users/jank/.claude/skills/lnd-artifacts/scripts/lnd-artifacts.sh`, while the fenced
   `sh` block below it kept the literal `${CLAUDE_PLUGIN_ROOT:+…}` text. Only the exact
   braced token is replaced; `$CLAUDE_PLUGIN_ROOT` without braces is not. Substitution
   reaches fenced code blocks too: rendering the installed `plugin-dev:plugin-structure`
   skill, whose body carries the exact token inside fenced bash and JSON blocks, showed
   every occurrence replaced — a plain exact-token string substitution over the whole
   body, not markdown-aware. (The unsubstituted fenced block observed above contained
   only the `:+` form, which is not the exact token — it never tested fences.)
3. **Claude Code prepends a "Base directory for this skill:" line** to rendered plugin
   skills, pointing at the skill's own directory — a second, independent way to locate
   bundled files.
4. **A plugin `commands/<name>.md` surfaces as `/<plugin>:<name>`.** The installed
   `mempalace` plugin ships `commands/help.md` and it appears as `/mempalace:help` —
   the exact filename→surface pattern this change wants (`commands/help.md` →
   `/lnd-artifacts:help`). Per the skills reference, custom commands and skills are the same
   mechanism: "A file at `.claude/commands/deploy.md` and a skill at
   `.claude/skills/deploy/SKILL.md` both create `/deploy` and work the same way."
5. **Skill bodies are cached when the plugin loads.** An edit to a SKILL.md did not
   appear in a same-session invocation; the skills reference confirms the file is not
   re-read. Task 4.5's verification therefore needs `/reload-plugins` (or a fresh
   session) after task 2.1's edit before the new resolution can be observed.

## Goals / Non-Goals

**Goals:**

- One typed command that answers "what is this", "what state am I in", "what can I ask
  for" without the user knowing a verb name first.
- Live state, not a static blurb: the answer must come from running the engine.
- Zero duplication of the skill's dialogue rules, so the two surfaces cannot drift.

**Non-Goals:**

- Making the command able to *do* anything. Read-only is a spec requirement, not a
  starting point to relax later.
- A second discovery surface for Codex. The skill is Codex's surface.
- Reworking C1's resolution order, the hooks, or the engine.

## Decisions

### H1 — `commands/help.md`, not `skills/help/SKILL.md`

Both layouts produce `/lnd-artifacts:help` (fact 4). `commands/` wins on three counts:

- **Codex isolation.** Codex descends into `skills/` (CONTEXT §5b) and would load a
  second skill whose body is full of Claude-only tokens — an unsubstituted
  `${CLAUDE_PLUGIN_ROOT}` and an unexecuted bash-injection block. Under `commands/`,
  Codex simply never sees it, and the Codex mirror manifest needs no thought.
- **It says what it is.** A command is a thing a person types. A skill is a thing the
  model may also decide to load; suppressing that requires `disable-model-invocation`
  anyway, at which point "skill" is a misnomer.
- **No manifest change.** `commands/` is auto-discovered next to the already-declared
  `"skills": "./skills/"`.

The cost: `AGENTS.md`'s "single skill + one POSIX script + two hooks" description gains a
fourth component. That description is a summary, not a constraint — no settled decision
says the plugin ships exactly one component type.

*Alternative rejected:* a second skill under `skills/`, for symmetry with the existing
layout. Symmetry is not worth handing Codex a broken skill.

### H2 — Live output via bash injection at expansion time, not tool calls

The command body uses Claude Code's dynamic context injection — ` ```! ` blocks — so the
engine runs while the command expands and its stdout is already in the prompt when the
model starts. Compared with telling the model "run `status` and show it":

- The user sees real output on the first response, with no tool-call round trip.
- The output is not paraphrasable — the model receives the engine's own text.
- It cannot be skipped, reordered, or "helpfully" turned into a mutating verb.

Engine resolution inside the injected block uses the substituted `${CLAUDE_PLUGIN_ROOT}`
token (fact 2), which is replaced *before* the shell sees it, so it works despite fact 1.

**As shipped, the block carries no shell resolution chain.** Implementation surfaced a
constraint (verified 2026-08-03, `docs/CONTEXT.md` §5a): injected commands pass the same
static permission check as Bash tool calls, a failed check silently kills the whole
invocation (`num_turns: 0`, empty result), and `[ -x "$E" ]` / `$(git rev-parse …)`
indirection is rejected as not statically analyzable — runnable only under a blanket
`Bash` grant, which would pre-approve unprompted Bash for the model and undercut the
read-only SHALL. The command therefore runs the plugin engine directly, twice, each
invocation exactly allowlisted in `allowed-tools`
(`Bash(${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh status)` and `… --help`) and
guarded with `|| echo "(short explanation)"`, so no-store, outside-git and
unreachable-engine degrade to a sentence instead of a raw error (spec: "Invoked outside
a git repository"). The vendored-engine fallback is not needed here: in Claude the
command and the engine ship in the same plugin, so step 1 cannot be missing while the
command exists. The skill keeps the full three-step chain (H4).

*Alternative rejected:* prose instructions plus a model-driven `Bash` call under
`allowed-tools`. That reintroduces the round trip and makes the output paraphrasable —
the two properties injection was chosen for.

### H3 — The command narrates; the skill governs

The command body carries only what a first-time reader needs: the verb table, the
"`sync` is never automatic" rule, the worktree one-liner, and pointers to the README and
the skill. It does **not** restate rules 2–9 of the skill. If the user's next message
asks for actual work, the skill loads and governs it — that is the handoff, and the
command says so explicitly rather than trying to be self-sufficient.

`disable-model-invocation: true` keeps the command out of automatic triggering. Without
it, two surfaces describing the same verbs compete, and the model would sometimes answer
an artifact request from the shorter, rule-free one.

### H4 — Fix step 1 by using the substituted path, not a shell test

C1 step 1 stays "the plugin's own engine, when the runtime tells us where the plugin is".
Only the expression changes: the skill states the substituted absolute path in prose and
in its snippet, and tests it with `[ -x ]` like any other candidate:

```sh
ENGINE="${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh"
[ -x "$ENGINE" ] || ENGINE="$(git rev-parse --git-common-dir)/lundegaard.engine.sh"
```

In Claude the first line becomes an absolute path and the `-x` test passes. In Codex the
token is not substituted; when the agent's shell runs the snippet, the unset variable
expands to empty and the tested path is `/scripts/lnd-artifacts.sh`, which fails `-x` —
it falls through to the vendored engine, exactly as C1 intends. (One accepted edge: a
shell running under `set -u` aborts on the unset variable instead of falling through.
The snippet cannot guard with `${CLAUDE_PLUGIN_ROOT:-}` because only the exact braced
token is substituted in Claude — the guard would break step 1 there.) The `${VAR:+…}`
form was doing the opposite of discriminating: it looked like a runtime test and was in
fact a constant empty string in every runtime.

This is why the fix ships here rather than as its own change: the command's resolution
(H2) and the skill's resolution must be the same two lines, and shipping a help surface
that prints a rule the skill cannot execute would be worse than the bug.

*Alternative rejected:* `${CLAUDE_SKILL_DIR}/../../scripts/lnd-artifacts.sh`. Documented
and substituted in both content and `allowed-tools`, but relative-path arithmetic out of
a skill directory is fragile against layout moves, and the plugin already moved once
(B8). `${CLAUDE_PLUGIN_ROOT}` names what it means.

### H5 — Archive order

This change's `codex-runtime` delta is a MODIFIED requirement whose base text lives in
`add-codex-runtime-support`, which is implemented but not archived, so
`openspec/specs/codex-runtime/spec.md` does not exist yet. Archive
`add-codex-runtime-support` (and its predecessor `vendor-engine-for-agentless-bootstrap`)
before this one, or the MODIFIED block has nothing to match against.

## Risks / Trade-offs

- **Bash injection may not substitute `${CLAUDE_PLUGIN_ROOT}` inside a command file.**
  Fact 2 covers plugin *skill* bodies, fenced blocks included; what remains unverified —
  and undocumented — is whether substitution is applied to a `commands/*.md` `!`
  injection line before it executes, and whether `!` execution needs `allowed-tools`.
  → Task 1.2 verifies it in a live session before the rest is built. If it fails,
  fall back to `${CLAUDE_SKILL_DIR}`-relative resolution, and if that also fails, drop to
  the H2 alternative (prose + `allowed-tools`). The spec is written in terms of observable
  behaviour, so none of these fallbacks change it.
- **Injected `status` output is stale by the time the user reads a long answer.** Trivial
  here — the command is read-only and the user is looking at a snapshot on purpose.
- **The command duplicates the verb table, which also lives in the skill and the README.**
  Three copies drift. → The verb table is generated in the command by running the engine's
  own `--help`, so the only hand-written copy of "the user says X → verb Y" stays in the
  skill.
- **Changing step 1 changes which engine Claude sessions run.** Sessions move from the
  vendored copy back to the plugin's. Identical when versions match; when they differ, the
  plugin's is by definition the newer one, and `heal` refreshes the vendored copy anyway
  (B3). → Covered by the smoke suite continuing to pass.
- **`disable-model-invocation` accepted values.** `true` is safe on all versions; the
  `yes`/`on`/`1` spellings need v2.1.218+. → Use `true`.

## Migration Plan

Additive. No store, link, exclude-block, or manifest change; nothing to migrate and
nothing to roll back beyond deleting `commands/help.md` and reverting the skill's two
resolution lines.

## Open Questions

None.
