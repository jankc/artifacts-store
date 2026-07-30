# plugin-integration — delta spec

## Purpose

Packages the artifact engine as a standalone Claude Code plugin: one skill that drives
the script, a SessionStart hook that self-heals links, and a Stop hook that only warns —
so the plugin is useful loaded directly from its repo, before any marketplace exists.

## ADDED Requirements

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
produce no user-visible output. The hook SHALL never clone, commit, or push.

#### Scenario: Session in an initialized project

- **WHEN** a session starts in a worktree of a clone with an initialized store and a
  missing managed link
- **THEN** the link is restored during session start

#### Scenario: Session in an unrelated project

- **WHEN** a session starts in a repository with no store
- **THEN** the hook exits zero with no output and no side effects

### Requirement: Stop hook warns about unsynced artifacts and does nothing else

The plugin SHALL register a Stop hook that, when the store has uncommitted changes or
unpushed commits, emits a warning naming the counts and suggesting `sync`. The hook
SHALL never commit, push, or otherwise mutate the store or the host repository, and
SHALL stay silent when the store is clean, absent, or the directory is not a Git
repository.

#### Scenario: Dirty store at stop

- **WHEN** a session stops while the store has uncommitted changes or unpushed commits
- **THEN** a warning is shown reporting the unsynced state and suggesting `sync`

#### Scenario: Clean store at stop

- **WHEN** a session stops with a clean, fully pushed store
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
