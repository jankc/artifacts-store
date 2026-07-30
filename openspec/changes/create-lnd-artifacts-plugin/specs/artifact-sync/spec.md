# artifact-sync — delta spec

## Purpose

Moves artifact changes between the local store and its remote as an explicit,
human-initiated action: commit everything, rebase on the remote, push, and report state
honestly — never automatically.

## ADDED Requirements

### Requirement: sync commits, rebases, and pushes the store

`sync` SHALL stage and commit all changes in the store (with a default message that can
be overridden), pull from the store remote with rebase, and push. All Git operations
SHALL target the store repository only; the host repository SHALL never be read from or
written to by `sync` beyond resolving the store location.

#### Scenario: Clean sync

- **WHEN** `sync` runs with local store changes and no remote divergence
- **THEN** one commit containing all changes is created and pushed, and the run reports
  the pushed commit

#### Scenario: Nothing to sync

- **WHEN** `sync` runs with a clean store that is up to date with its remote
- **THEN** no commit is created and the run reports the store is already in sync

#### Scenario: Rebase conflict is surfaced, not resolved

- **WHEN** the pull-rebase step hits a conflict
- **THEN** `sync` exits non-zero, reports the conflicted paths and the store location,
  leaves the store in its rebase state for manual resolution, and does not push

### Requirement: status reports store and link health

`status` SHALL report, without changing anything: whether a store exists, dirty file
count, unpushed commit count, behind-remote commit count (when cheaply determinable),
and per-worktree link health (missing, wrong-target, or quarantine leftovers) for the
current worktree.

#### Scenario: Unsynced work is visible

- **WHEN** `status` runs with 3 modified store files and 2 unpushed commits
- **THEN** the output states 3 dirty files and 2 unpushed commits

#### Scenario: No store initialized

- **WHEN** `status` runs in a host repository without a store
- **THEN** the output states no store is initialized and suggests `init`, exiting zero
