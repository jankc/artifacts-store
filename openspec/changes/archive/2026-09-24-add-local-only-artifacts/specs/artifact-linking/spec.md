# Spec Delta — artifact-linking

## ADDED Requirements

### Requirement: adopt --local keeps an adopted entry out of the store's history

`adopt --local <path>` SHALL do everything `adopt <path>` does — same refusals, same move,
same link, same host exclude-block update — and additionally mark the entry local-only
in the store's own per-clone ignore rules (the store repository's `info/exclude`), so the
store's git never tracks it. A local-only entry SHALL be linked, healed, quarantined
around, and detached exactly like any other first-level store entry, in every worktree of
the clone. `adopt --local` SHALL refuse a name that the store's remote branch already
carries, because that entry is already shared and making it local would require deleting
it for every other clone. Nothing about local-only entries SHALL be written to the host
repository or committed to the store.

#### Scenario: Adopting a directory as local-only

- **WHEN** `adopt --local .claude` runs and `.claude/` is an untracked real directory in
  the worktree root
- **THEN** `.claude` becomes a first-level store entry, a symlink replaces it in the
  worktree root, the host exclude block gains `.claude`, the store's `info/exclude` gains
  `/.claude`, and `git -C <store> status --porcelain` does not list it

#### Scenario: Local-only entry reaches every worktree

- **WHEN** `.claude` was adopted with `--local` and `heal` runs in another worktree of the
  same clone
- **THEN** that worktree gets a `.claude` symlink resolving to the same store entry

#### Scenario: Name already shared on the remote is refused

- **WHEN** `adopt --local .claude` runs and the store's remote branch (as of the last
  fetch) contains `.claude`
- **THEN** the engine exits non-zero explaining the entry is already shared and nothing
  changes

#### Scenario: Dry-run shows the local-only step

- **WHEN** `adopt --local .claude --dry-run` runs
- **THEN** the plan lists the move, the link, the host exclude-block entry and the store
  `info/exclude` entry, and nothing on disk changes

#### Scenario: Names with gitignore metacharacters stay local-only

- **WHEN** `adopt --local '[draft]'` runs for an untracked directory `[draft]/`
- **THEN** the store's `info/exclude` gains a pattern matching exactly `[draft]`, the
  store's git does not list it, and the host repository's status stays clean

#### Scenario: --local outside adopt is rejected

- **WHEN** any verb other than `adopt` is invoked with `--local`
- **THEN** the engine exits non-zero with usage guidance and changes nothing
