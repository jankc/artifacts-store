# artifact-bootstrap Specification

## Purpose
Makes the engine reachable without knowing where the plugin is installed, by keeping a
working copy of it inside the host project's Git common dir. This is what lets worktree
creation materialize artifacts with no agent running and no per-user setup.

## Requirements

### Requirement: init vendors the engine into the Git common dir

`init` SHALL write an executable copy of the engine to
`<git-common-dir>/lundegaard.engine.sh` as part of a successful initialization. The copy
SHALL be functionally identical to the engine that produced it, so that running it
requires no plugin, no PATH entry and no environment variables.

#### Scenario: Fresh init leaves a runnable engine

- **WHEN** `init <remote-url>` completes successfully
- **THEN** `<git-common-dir>/lundegaard.engine.sh` exists, is executable, and reports the
  same version as the engine that ran `init`

#### Scenario: The vendored engine survives the plugin disappearing

- **WHEN** the plugin installation is removed after `init` and
  `<git-common-dir>/lundegaard.engine.sh heal` runs in a worktree with missing links
- **THEN** the links are created exactly as they would be by the plugin's own engine

#### Scenario: Dry-run init does not vendor

- **WHEN** `init <remote-url> --dry-run` runs
- **THEN** the planned vendoring is reported and no file is written

#### Scenario: Failed init leaves no vendored engine

- **WHEN** the clone step of `init` fails
- **THEN** no store and no vendored engine remain

### Requirement: The vendored engine is not payload and not host content

The vendored engine SHALL live beside the store rather than inside it, so that it is
never symlinked into the worktree root, never committed by `sync`, and never visible as a
change in the host repository.

#### Scenario: Store stays payload-only

- **WHEN** the engine has been vendored and `heal` then `sync` run
- **THEN** the store root listing is unchanged, `git -C <store> status --porcelain`
  produces no output, and no `lundegaard.engine.sh` symlink exists in the worktree root

#### Scenario: Host repository stays clean

- **WHEN** the engine has been vendored
- **THEN** `git status --porcelain` in the host repository produces no output

### Requirement: heal keeps the vendored engine current

`heal` SHALL compare its own version with the vendored copy's and rewrite the copy when
they differ, so that upgrading (or downgrading) the plugin propagates without user
action. When the versions match, `heal` SHALL leave the file untouched and SHALL NOT
report a change.

#### Scenario: Upgraded plugin refreshes the copy

- **WHEN** the vendored copy reports an older version than the running engine and `heal`
  runs
- **THEN** the copy is replaced with the running engine and the refresh is reported

#### Scenario: Matching versions are a no-op

- **WHEN** the vendored copy and the running engine report the same version and `heal`
  runs with everything else healthy
- **THEN** nothing is written and `heal` reports a healthy state

#### Scenario: Missing copy is restored

- **WHEN** the vendored engine has been deleted and `heal` runs in an initialized project
- **THEN** the copy is recreated

### Requirement: A worktree-init command works without the plugin

Running the vendored engine's `heal --quiet` from a newly created worktree SHALL
materialize that worktree's managed links, and the documented invocation SHALL be a
silent, zero-exit no-op in repositories that have no artifact store and outside Git
repositories, so it is safe to configure globally.

#### Scenario: New worktree is materialized by tooling

- **WHEN** a linked worktree is created and the documented invocation runs with that
  worktree as the working directory
- **THEN** all managed links are created in it and the host repository stays clean

#### Scenario: Unmanaged project is untouched

- **WHEN** the documented invocation runs in a Git repository with no artifact store, or
  outside any Git repository
- **THEN** it produces no output and exits zero

#### Scenario: Invocation from a subdirectory

- **WHEN** the documented invocation runs from a nested subdirectory of a managed
  worktree
- **THEN** the links are created at that worktree's root

### Requirement: detach removes the vendored engine

`detach` SHALL remove the vendored engine together with the managed links and the exclude
block, leaving the store intact, so that a detached project carries no lnd-artifacts
machinery outside the store itself.

#### Scenario: Detach clears the bootstrap

- **WHEN** `detach` runs in an initialized project
- **THEN** `<git-common-dir>/lundegaard.engine.sh` no longer exists, the store is intact,
  and a later `heal` run from the plugin restores both the links and the vendored engine

### Requirement: status reports the vendored engine

`status` SHALL report whether the vendored engine is present and which version it is, so
that version drift and a missing bootstrap are visible without changing anything.

#### Scenario: Drift is visible

- **WHEN** `status` runs and the vendored copy's version differs from the running
  engine's
- **THEN** the output names both versions and points at `heal` to refresh

#### Scenario: Missing bootstrap is visible

- **WHEN** `status` runs in an initialized project whose vendored engine was deleted
- **THEN** the output states it is missing and points at `heal`
