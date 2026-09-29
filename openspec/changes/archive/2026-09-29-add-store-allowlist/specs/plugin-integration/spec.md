## MODIFIED Requirements

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
