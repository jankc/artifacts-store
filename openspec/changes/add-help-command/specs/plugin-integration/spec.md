# plugin-integration — delta spec

## ADDED Requirements

### Requirement: The plugin ships a user-invocable help command

The plugin SHALL ship a command at `commands/help.md`, invocable in Claude Code as
`/lnd-artifacts:help`. The command SHALL be user-invocable only: the model SHALL NOT be
able to load it automatically, so it never competes with the `lnd-artifacts` skill for
triggering on artifact-related prose.

The command SHALL be read-only. It SHALL NOT create, move, or delete anything, SHALL NOT
run any mutating verb (`init`, `adopt`, `sync`, `detach`, `heal`), and SHALL NOT be usable
as a route around the skill's dialogue rules.

#### Scenario: The command is discoverable by name

- **WHEN** the plugin is loaded in a Claude Code session and the user opens the `/` menu
- **THEN** `/lnd-artifacts:help` is listed with a description naming the plugin's purpose

#### Scenario: The command is not model-invocable

- **WHEN** the user asks in prose for artifact work
- **THEN** the `lnd-artifacts` skill is what triggers, and the help command is not loaded
  automatically

#### Scenario: The command mutates nothing

- **WHEN** `/lnd-artifacts:help` runs in a project with a store
- **THEN** the store, the symlinks, the exclude block, and the host repository are all
  byte-identical to their state before the invocation

### Requirement: The help command reports live state alongside static guidance

When invoked in a project that has an artifact store, the command SHALL show the output
of the engine's `status` verb and the engine's own usage text, obtained by running the
engine rather than restated in prose. It SHALL additionally present the verb table, the
rule that `sync` is never run without the user asking, the agentless worktree-init
one-liner, and a pointer to the README and the skill for work beyond a status check.

#### Scenario: Invoked in an initialized project

- **WHEN** the user runs `/lnd-artifacts:help` in a project whose store exists
- **THEN** the response contains that project's actual `status` report — store path,
  sync state, link health, vendored engine version — and the engine's verb list

#### Scenario: Invoked in a project with no store

- **WHEN** the user runs `/lnd-artifacts:help` in a git repository that has no store
- **THEN** the response says no store is set up, explains that `init` needs a remote URL
  the user supplies, and does not error out or ask the user where the plugin lives

#### Scenario: Invoked outside a git repository

- **WHEN** the user runs `/lnd-artifacts:help` outside any git working tree
- **THEN** the response still shows the verb list and explains that a git repository is
  required, without a raw git error being the whole answer

#### Scenario: Guidance the command always carries

- **WHEN** `/lnd-artifacts:help` runs in any of the above states
- **THEN** the response states that syncing is an explicit user decision, and gives the
  worktree-init one-liner for materializing artifacts without an agent

### Requirement: The help command is a Claude Code surface only

The command SHALL live under `commands/`, which Codex does not load, and its presence
SHALL NOT change either runtime manifest. The Codex mirror manifest SHALL continue to
agree with the Claude manifest on `name`, `version`, and `description`, and both SHALL
continue to declare only the skills directory.

#### Scenario: Codex is unaffected

- **WHEN** a Codex session loads the plugin
- **THEN** the `lnd-artifacts` skill is available exactly as before, no help command is
  registered, and no Codex-only file was added

#### Scenario: Manifests unchanged

- **WHEN** both manifests are read after this change
- **THEN** neither declares a `commands` path, and they still agree on `name`, `version`,
  and `description`
