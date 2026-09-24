# artifact-sync Specification

## Purpose
Moves artifact changes between the local store and its remote as an explicit,
human-initiated action: commit everything, rebase on the remote, push, and report state
honestly — never automatically.

## Requirements

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
count, unpushed and behind-remote commit counts when a usable upstream or remote-tracking
comparison exists (and an explicit `unknown` state otherwise), per-worktree link health
(missing, wrong-target, or quarantine leftovers) for the current worktree, and every
first-level store entry that the store's git ignores, marked as local-only and not backed
up by the remote.

#### Scenario: Unsynced work is visible

- **WHEN** `status` runs with 3 modified store files and 2 unpushed commits
- **THEN** the output states 3 dirty files and 2 unpushed commits

#### Scenario: Publication state is unknown without a comparison ref

- **WHEN** `status` runs for a store branch with no usable upstream or remote-tracking ref
- **THEN** unpushed and behind state are reported as unknown rather than as false zero or
  whole-history counts

#### Scenario: No store initialized

- **WHEN** `status` runs in a host repository without a store
- **THEN** the output states no store is initialized and suggests `init`, exiting zero

#### Scenario: Local-only entries are listed

- **WHEN** `status` runs and `.claude` is a local-only store entry
- **THEN** the output lists `.claude` as local-only and states that local-only entries are
  not pushed and are lost if the store is deleted or re-cloned

### Requirement: sync never commits local-only content

`sync` SHALL commit only paths the store's git does not ignore. Content ignored by the
store — local-only entries created by `adopt --local`, and any pattern the user added to
the store's `info/exclude` — SHALL never be staged, committed, or pushed, and SHALL NOT
count as dirty for `sync`, `status`, or the Stop-hook warning.

#### Scenario: Local-only edits are not synced

- **WHEN** a file under a local-only `.claude` entry is edited and `sync` runs with no
  other changes
- **THEN** no commit is created and the run reports the store is already in sync

#### Scenario: Shared and local-only edits together

- **WHEN** a file under shared `openspec/` and a file under local-only `.claude/` are both
  edited and `sync` runs
- **THEN** the pushed commit contains the `openspec/` change and nothing under `.claude/`

### Requirement: sync refuses to overwrite local-only content

Before integrating remote commits into the store (rebase, or initializing an empty
branch from the remote), `sync` SHALL check whether those commits add or modify any path
that is an ignored, untracked file in the store or lies inside an ignored directory
present in the store, matching path names literally (glob metacharacters in names have
no special meaning). If any such path exists, `sync`
SHALL exit non-zero before integrating, name the paths and the store location, leave the
store's working tree and every ignored path unchanged, and not push. Local commits made
earlier in the same run SHALL remain, unpushed. The user resolves it by renaming the
local-only content or dropping its ignore rule, then runs `sync` again.

#### Scenario: Teammate pushes a path that is local-only here

- **WHEN** `.claude` is local-only in this clone, another clone pushes `.claude/settings.json`
  to the artifact remote, and `sync` runs here
- **THEN** `sync` exits non-zero naming `.claude/settings.json`, the local
  `.claude/settings.json` is byte-identical before and after, and nothing is pushed

#### Scenario: Names with glob metacharacters are guarded literally

- **WHEN** `[draft]` is local-only in this clone and another clone pushes `[draft]/f`
- **THEN** `sync` exits non-zero naming `[draft]/f` and the local `[draft]/f` is unchanged

#### Scenario: Unrelated remote changes still integrate

- **WHEN** `.claude` is local-only and the remote only carries new commits under
  `openspec/`
- **THEN** `sync` rebases onto them and pushes as usual
