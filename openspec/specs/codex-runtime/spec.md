# codex-runtime Specification

## Purpose
Makes the skill functional outside Claude Code: engine resolution that does not depend
on Claude-specific environment, textual substitutes for the two Claude-only lifecycle
hooks, and verified Codex discoverability of the plugin.

## Requirements

### Requirement: The skill resolves the engine without Claude-specific environment

The skill SHALL name the engine by a resolution rule usable in any runtime: the plugin's
own `scripts/lnd-artifacts.sh` when the runtime tells the skill where the plugin lives,
otherwise the vendored `$(git rev-parse --git-common-dir)/lundegaard.engine.sh`. When
neither resolves (no store yet and no plugin location), the skill SHALL direct the agent
to ask the user for the path rather than guess install locations.

The plugin location SHALL be taken from the runtime's own substitution into the skill
text, not from an environment variable read by a shell command. `CLAUDE_PLUGIN_ROOT` is
absent from the environment the agent's shell runs in, so a shell test against it SHALL
NOT be what selects step 1 — in Claude Code such a test always fails and silently
degrades every session to step 2. In runtimes that perform no such substitution, the
unsubstituted step-1 path SHALL be recognizable as unavailable so that resolution falls
through to step 2 rather than producing a nonsense path.

#### Scenario: Claude session

- **WHEN** the skill runs in Claude Code, where the runtime substitutes the plugin's
  absolute path into the skill text
- **THEN** verbs are invoked through that plugin's `scripts/lnd-artifacts.sh`, including
  on the first-ever `init` in a project that has no store yet

#### Scenario: Claude session where the plugin engine is missing

- **WHEN** the substituted step-1 path does not name an executable file
- **THEN** resolution falls through to the vendored engine without an error being shown
  to the user

#### Scenario: Codex session in an initialized project

- **WHEN** the skill runs in a runtime that substitutes nothing, in a project whose store
  exists
- **THEN** step 1 is recognized as unavailable and verbs are invoked through the vendored
  engine in the Git common dir

#### Scenario: Codex session, first init

- **WHEN** the skill runs in a runtime that substitutes nothing, in a project with no
  store, and the user asks to initialize
- **THEN** the agent asks the user for the engine (or checkout) path and invents nothing

### Requirement: The skill compensates for absent lifecycle hooks

The skill SHALL instruct the agent to run `status` before starting artifact-related
work and to run `heal` when `status` reports link damage, and — after completing a task
that modified artifacts — to report unsynced store state and suggest `sync`. The skill
SHALL keep `sync` an explicit user decision; the nudge is a suggestion, never an action.

#### Scenario: Artifact work in a hook-less runtime

- **WHEN** the user asks for artifact work in a session where no SessionStart hook ran
- **THEN** the agent runs `status` first and repairs links via `heal` if needed before
  proceeding

#### Scenario: Unsynced state is surfaced without a Stop hook

- **WHEN** a task that edited artifacts completes and the store has uncommitted or
  unpushed changes
- **THEN** the agent mentions the unsynced state and suggests `sync`, and does not run
  `sync` unasked

### Requirement: The plugin is discoverable by Codex

The skill, in its `skills/<name>/SKILL.md` shape, SHALL be loadable by Codex, and the
README SHALL document the verified wiring for user-level availability (through the
agent-neutral `~/.agents/skills` indirection) plus what Codex users do not get (no
automatic heal, no stop warning) and how that is compensated.

#### Scenario: Codex session sees the skill

- **WHEN** a Codex session starts on a machine wired per the documented scheme
- **THEN** the lnd-artifacts skill is available and can drive `status` in an
  initialized project

#### Scenario: Docs state the degraded mode

- **WHEN** a Codex user reads the README's Codex section
- **THEN** it names the missing hooks, the vendored one-liner, and the skill's
  status/sync rules as the compensations
