# artifact-linking Specification

## Purpose
Materializes the artifact store into the host project: first-level entries of the store
root are symlinked into the worktree root, ignored via a managed block in the common
dir's `info/exclude`, and kept healthy across worktrees, `git clean`, and store changes.

## Requirements

### Requirement: First-level store entries are linked into the worktree root

The engine SHALL create one symlink in the current worktree root for every first-level
entry of the store root except `.git`, pointing at that entry inside the store. Both
directories and regular files SHALL be linked. There is no manifest and no nested
discovery: the store root listing IS the set of managed links.

#### Scenario: Directories and files are linked

- **WHEN** the store root contains `.claude/`, `openspec/`, and `CLAUDE.md` and `heal`
  runs in a worktree
- **THEN** the worktree root contains symlinks `.claude`, `openspec`, and `CLAUDE.md`
  each resolving to the corresponding entry under the store

#### Scenario: The store's .git is never linked

- **WHEN** `heal` runs
- **THEN** no `.git`-named symlink to the store is created in the worktree root

### Requirement: Managed exclude block covers all links

The engine SHALL maintain a marker-delimited block in `<git-common-dir>/info/exclude`
containing one ignore entry per managed link (and nothing else). The block SHALL be
created or rewritten in place on `init`, `heal`, and `adopt`, and content outside the
markers SHALL never be modified. Because the file lives in the common dir, the block
applies to every worktree of the clone.

#### Scenario: Block matches the link set

- **WHEN** `heal` completes with store entries `.claude`, `openspec`, `CLAUDE.md`
- **THEN** the managed block in `<git-common-dir>/info/exclude` contains exactly those
  three entries between its start and end markers

#### Scenario: User content outside the block is preserved

- **WHEN** `info/exclude` already contains user-authored rules and `heal` rewrites the
  managed block
- **THEN** the user-authored rules are byte-identical before and after

### Requirement: heal is idempotent self-repair

`heal` SHALL create missing links, repair links whose target does not resolve to the
expected store entry, remove managed links whose store entry no longer exists, and
rewrite the exclude block — and SHALL be a no-op when everything is already correct.
`heal` SHALL only ever delete symlinks whose target resolves inside the store; anything
else at a managed name is quarantined, never deleted.

#### Scenario: Links restored after git clean

- **WHEN** `git clean -fdx` removed the worktree's managed symlinks and `heal` runs
- **THEN** all links are recreated and the run reports what was restored

#### Scenario: New worktree bootstrap

- **WHEN** `heal` runs in a freshly created linked worktree of an initialized clone
- **THEN** all managed links are created in that worktree without cloning or touching
  the store

#### Scenario: Already healthy

- **WHEN** `heal` runs and every link and the exclude block are already correct
- **THEN** nothing on disk changes and the run reports a healthy state

### Requirement: Pre-existing paths are quarantined, never deleted

When a managed link should be created at a name where a real file, real directory, or
foreign symlink (target outside the store) already exists, the engine SHALL rename the
existing path to `<name>.quarantined-<timestamp>` before linking, and SHALL report each
quarantine loudly. The engine SHALL never delete or overwrite pre-existing content.
Exception: a path tracked by the host repository SHALL NOT be moved at all — moving it
would surface as a deletion in the customer repository. The engine SHALL warn, skip that
entry (customer content wins), and `status` SHALL report it as a collision.

#### Scenario: Real directory at a managed name

- **WHEN** `heal` runs and a real directory `.claude/` exists in the worktree root while
  the store provides `.claude`
- **THEN** the directory is renamed to `.claude.quarantined-<timestamp>` and a symlink
  `.claude` to the store entry is created

#### Scenario: Store entry collides with tracked host content

- **WHEN** `heal` runs and the store provides an entry whose name is tracked by the host
  repository (e.g. `README.md`)
- **THEN** the tracked path is left untouched, the engine warns about the collision and
  skips that entry, and `status` reports it as a collision until the store entry is
  renamed or removed

### Requirement: adopt moves a path into the store and links it back

`adopt <path>` SHALL move a first-level untracked (or ignored) path from the worktree
root into the store root, create the managed symlink in its place, and update the
exclude block. It SHALL refuse paths tracked by the host repository, paths outside the
worktree root's first level, and names already present in the store.

#### Scenario: Adopting an untracked directory

- **WHEN** `adopt .opencode` runs and `.opencode/` is an untracked real directory in the
  worktree root
- **THEN** `.opencode` becomes a first-level entry of the store, a symlink replaces it in
  the worktree root, and the exclude block gains `.opencode`

#### Scenario: Tracked path is refused

- **WHEN** `adopt docs` runs and `docs/` is tracked by the host repository
- **THEN** the engine exits non-zero explaining tracked content belongs to the host
  repository and nothing changes

### Requirement: detach removes links and exclude block, preserving the store

`detach` SHALL remove all managed symlinks from the current worktree (and, when run from
the main worktree, offer to detach known linked worktrees), remove the managed exclude
block, and leave the store itself untouched, so a later `heal` fully restores the setup.

#### Scenario: Detach then heal round-trip

- **WHEN** `detach` runs and afterwards `heal` runs in the same worktree
- **THEN** after `detach` no managed links or exclude block remain, the store is intact,
  and after `heal` links and exclude block are fully restored
