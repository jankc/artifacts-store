# codex-runtime — delta spec

## Purpose

Makes the skill functional outside Claude Code: engine resolution that does not depend
on Claude-specific environment, textual substitutes for the two Claude-only lifecycle
hooks, and verified Codex discoverability of the plugin.

## ADDED Requirements

### Requirement: The skill resolves the engine without Claude-specific environment

The skill SHALL name the engine by a resolution rule usable in any runtime: the plugin's
own `scripts/lnd-artifacts.sh` via `${CLAUDE_PLUGIN_ROOT}` when that variable is set,
otherwise the vendored `$(git rev-parse --git-common-dir)/lundegaard.engine.sh`. When
neither resolves (no store yet and no plugin environment), the skill SHALL direct the
agent to ask the user for the path rather than guess install locations.

#### Scenario: Claude session

- **WHEN** the skill runs where `CLAUDE_PLUGIN_ROOT` is set
- **THEN** verbs are invoked through `${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh`

#### Scenario: Codex session in an initialized project

- **WHEN** the skill runs without `CLAUDE_PLUGIN_ROOT` in a project whose store exists
- **THEN** verbs are invoked through the vendored engine in the Git common dir

#### Scenario: Codex session, first init

- **WHEN** the skill runs without `CLAUDE_PLUGIN_ROOT` in a project with no store and
  the user asks to initialize
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
