# codex-runtime — delta spec

## MODIFIED Requirements

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
