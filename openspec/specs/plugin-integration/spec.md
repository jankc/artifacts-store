# plugin-integration Specification

## Purpose
Packages the artifact engine as a standalone plugin in the dual-runtime layout: a skill
under `skills/` that drives the script, a Claude manifest plus a Codex mirror manifest,
a read-only `/lnd-artifacts:help` command, a SessionStart hook that self-heals links,
and a Stop hook that only warns — so the plugin is useful loaded directly from its repo,
before any marketplace exists.

## Requirements

### Requirement: The repository is a self-contained loadable plugin

The repository root SHALL be a valid Claude Code plugin named `lnd-artifacts`
(manifest at `.claude-plugin/plugin.json`) loadable via `claude --plugin-dir <repo>`,
with hook commands referencing scripts through `${CLAUDE_PLUGIN_ROOT}` so the plugin
works from any checkout location.

#### Scenario: Loading from a local checkout

- **WHEN** a session starts with `claude --plugin-dir <path-to-repo>`
- **THEN** the `lnd-artifacts` skill and both hooks are active for that session with no
  marketplace or installation step

### Requirement: SessionStart hook heals silently and cheaply

The plugin SHALL register a SessionStart hook that runs `heal` for the current worktree
when (and only when) an artifact store exists for the enclosing repository. In projects
without a store, and outside Git repositories, the hook SHALL exit zero quickly and
produce no user-visible output. The hook SHALL never clone, commit, or push. Store
entries skipped because they are not on the allow list SHALL NOT produce output from the
hook.

#### Scenario: Session in an initialized project

- **WHEN** a session starts in a worktree of a clone with an initialized store and a
  missing managed link
- **THEN** the link is restored during session start

#### Scenario: Session in an unrelated project

- **WHEN** a session starts in a repository with no store
- **THEN** the hook exits zero with no output and no side effects

#### Scenario: Junk in the store root stays quiet

- **WHEN** a session starts in a healthy initialized project whose store root also holds
  `.DS_Store`
- **THEN** the hook produces no output

### Requirement: Stop hook warns about unsynced artifacts and does nothing else

The plugin SHALL register a Stop hook that, when the store has uncommitted changes or
unpushed commits, emits a warning naming the counts and suggesting `sync`. Uncommitted
changes SHALL be counted the way `sync` and `status` count them, so untracked store
entries not on the allow list do not count. The hook SHALL never commit, push, or
otherwise mutate the store or the host repository, and SHALL stay silent when the store
is clean, absent, or the directory is not a Git repository.

#### Scenario: Dirty store at stop

- **WHEN** a session stops while the store has uncommitted changes or unpushed commits
- **THEN** a warning is shown reporting the unsynced state and suggesting `sync`

#### Scenario: Clean store at stop

- **WHEN** a session stops with a clean, fully pushed store
- **THEN** the hook produces no output and exits zero

#### Scenario: Junk alone does not trigger the warning

- **WHEN** a session stops with a fully pushed store whose only untracked content is
  `.DS_Store` at the store root
- **THEN** the hook produces no output and exits zero

### Requirement: The skill drives the engine conversationally

The plugin SHALL ship a single skill that (a) triggers on artifact-management intents
(initialize/adopt/sync/status/detach), (b) for initialization asks the user for the
artifact remote URL before running `init`, and (c) maps each intent to the corresponding
script verb, preferring `--dry-run` previews before destructive or bulk operations.

#### Scenario: Guided initialization

- **WHEN** the user asks to set up artifact management in a project
- **THEN** the skill asks for the artifact repository remote URL and runs `init` with it,
  reporting the resulting links

### Requirement: The skill lives in the dual-runtime layout

The plugin's single skill SHALL live at `skills/lnd-artifacts/SKILL.md` and the
repository SHALL NOT carry a root `SKILL.md`. The skill SHALL remain loadable in Claude
Code both via `claude --plugin-dir <repo>` and via a skills-directory symlink install.

#### Scenario: Loading from a local checkout after the move

- **WHEN** a session starts with `claude --plugin-dir <path-to-repo>`
- **THEN** the `lnd-artifacts` skill and both hooks are active, exactly as before the
  move

#### Scenario: No root skill remains

- **WHEN** the repository root is listed
- **THEN** it contains no `SKILL.md`; the only skill definition is
  `skills/lnd-artifacts/SKILL.md`

### Requirement: The plugin ships a Codex mirror manifest

The plugin SHALL carry `.codex-plugin/plugin.json` alongside
`.claude-plugin/plugin.json`. The two manifests SHALL agree on `name`, `version`, and
`description`, SHALL both declare the skills directory explicitly, and the Codex
manifest SHALL additionally carry an `interface` block (display name, short and long
description, developer name, category).

#### Scenario: Manifests agree

- **WHEN** both manifests are read
- **THEN** `name`, `version`, and `description` are identical and both declare
  `"skills": "./skills/"`

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
