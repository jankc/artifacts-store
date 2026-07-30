# artifact-store — delta spec

## Purpose

Manages the lifecycle of the per-project artifact store: a private Git repository cloned
into the host project's Git common dir, shared by all worktrees of the clone and
structurally incapable of leaking into the customer repository.

## ADDED Requirements

### Requirement: Store location is resolved from the Git common dir

The engine SHALL resolve the store location as `<git-common-dir>/lundegaard`, where
`<git-common-dir>` is obtained from the host repository (`git rev-parse --git-common-dir`)
and normalized to an absolute path. All verbs SHALL operate on this single location
regardless of which worktree they are invoked from.

#### Scenario: Resolution from the main worktree

- **WHEN** any verb runs from the main worktree of a host repository
- **THEN** the store path resolves to `<main-worktree>/.git/lundegaard`

#### Scenario: Resolution from a linked worktree

- **WHEN** any verb runs from a linked worktree of the same clone
- **THEN** the store path resolves to the same `<main-worktree>/.git/lundegaard` as from
  the main worktree

#### Scenario: Not inside a Git repository

- **WHEN** any verb runs outside a Git working tree
- **THEN** the engine exits non-zero with a message stating a Git repository is required
  and changes nothing

### Requirement: init clones the artifact remote into the store location

`init <remote-url>` SHALL clone the given remote into the store location and then perform
linking and exclude-block setup for the current worktree. It SHALL refuse to run when a
store already exists at the location, pointing the user at `heal` and `status` instead.

#### Scenario: Fresh initialization

- **WHEN** `init git@host:team/project-artifacts.git` runs in a host repository with no
  existing store
- **THEN** the remote is cloned to `<git-common-dir>/lundegaard`, first-level entries are
  linked into the worktree root, and the managed exclude block is written

#### Scenario: Store already exists

- **WHEN** `init <url>` runs and `<git-common-dir>/lundegaard` already exists
- **THEN** the engine exits non-zero without cloning and tells the user the store is
  already initialized and to use `heal` or `status`

#### Scenario: Missing remote URL

- **WHEN** `init` runs without a remote URL argument
- **THEN** the engine exits non-zero with usage guidance and changes nothing

#### Scenario: Clone failure leaves no partial store

- **WHEN** the clone fails (bad URL, no access)
- **THEN** no store directory remains at the store location and no links or exclude
  entries are created

### Requirement: The store is invisible to the host repository

After any verb completes, `git status --porcelain` in the host repository SHALL report no
changes attributable to the store or its links: the store lives under the Git common dir
and every created symlink is covered by the managed exclude block.

#### Scenario: Host status stays clean after init

- **WHEN** `init` completes successfully in a host repository with a clean working tree
- **THEN** `git status --porcelain` in the host repository produces no output

### Requirement: Mutating verbs serialize on a store lock

Mutating verbs (`init`, `heal`, `adopt`, `sync`, `detach`) SHALL acquire an exclusive lock
scoped to the store before making changes, so concurrent invocations from different
worktrees or sessions cannot interleave. If the lock cannot be acquired within a bounded
wait, the verb SHALL exit non-zero naming the lock path.

#### Scenario: Concurrent sync from two worktrees

- **WHEN** `sync` is invoked from two worktrees of the same clone at the same time
- **THEN** one invocation completes fully before the other begins, or the second exits
  non-zero reporting the held lock

### Requirement: Mutating verbs support dry-run

Every mutating verb SHALL accept `--dry-run`, printing the full plan of actions it would
take while changing nothing on disk (no clone, no links, no exclude edits, no commits).

#### Scenario: Dry-run init

- **WHEN** `init <url> --dry-run` runs in a host repository with no store
- **THEN** the planned clone target, link names, and exclude entries are printed and no
  filesystem or Git change occurs
