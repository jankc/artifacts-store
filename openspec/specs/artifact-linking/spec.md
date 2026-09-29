# artifact-linking Specification

## Purpose
Materializes the artifact store into the host project: first-level entries of the store
root whose names are on the engine's allow list are symlinked into the worktree root, ignored via a managed block in the common
dir's `info/exclude`, and kept healthy across worktrees, `git clean`, and store changes.

## Requirements

### Requirement: The engine carries a fixed allow list of store entry names

The engine SHALL define one allow list of first-level store entry names: `.agents`,
`.claude`, `.codex`, `.cursor`, `.gemini`, `.lnd-canon.json`, `.local`, `.opencode`,
`.pi`, `.specify`, `.superset`, `.windsurf`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
`docs`, `mise.toml`, `openspec`, `specs`. Names SHALL match exactly and case-sensitively.
The list SHALL be part of the engine itself: no file in the store, the host repository
or the user's configuration, and no environment variable, SHALL extend or shrink it.
A read-only `allowed` verb SHALL print the list, one name per line, and change nothing.

#### Scenario: allowed prints the list

- **WHEN** `allowed` runs, inside or outside a project with a store
- **THEN** it prints each allowed name on its own line, exits zero, and changes nothing
  on disk

#### Scenario: A store file cannot extend the list

- **WHEN** the store root contains a file or directory with any name, including one
  that looks like configuration
- **THEN** the list printed by `allowed` is unchanged

### Requirement: First-level store entries are linked into the worktree root

The engine SHALL create one symlink in the current worktree root for every first-level
entry of the store root whose name is on the allow list, pointing at that entry inside
the store. Both directories and regular files SHALL be linked. There is no manifest and
no nested discovery: the store root listing, filtered by the allow list, IS the set of
managed links. A first-level entry whose name is not on the allow list (for example a
Finder `.DS_Store`) SHALL NOT be linked, SHALL NOT be listed in the managed exclude
block, and a symlink to it left over from an earlier engine version SHALL be removed like
the link of an entry that no longer exists. `heal` without `--quiet` SHALL name each
skipped entry; `heal --quiet` SHALL NOT mention skipped entries.

#### Scenario: Directories and files are linked

- **WHEN** the store root contains `.claude/`, `openspec/`, and `CLAUDE.md` and `heal`
  runs in a worktree
- **THEN** the worktree root contains symlinks `.claude`, `openspec`, and `CLAUDE.md`
  each resolving to the corresponding entry under the store

#### Scenario: The store's .git is never linked

- **WHEN** `heal` runs
- **THEN** no `.git`-named symlink to the store is created in the worktree root

#### Scenario: An entry not on the allow list is skipped

- **WHEN** the store root contains `.claude/` and `.DS_Store` and `heal` runs
- **THEN** the worktree root gets a `.claude` symlink but no `.DS_Store` symlink, the
  managed exclude block lists `.claude` but not `.DS_Store`, and the output names
  `.DS_Store` as skipped

#### Scenario: A real file at a skipped name is left alone

- **WHEN** the store root contains `.DS_Store`, the worktree root already has a real
  `.DS_Store` file, and `heal` runs
- **THEN** the worktree's `.DS_Store` is byte-identical before and after and nothing is
  quarantined

#### Scenario: An old link to a skipped entry is removed

- **WHEN** a worktree has a `.DS_Store` symlink into the store from an earlier engine
  version and `heal` runs
- **THEN** the symlink is removed, the store's `.DS_Store` is untouched, and the managed
  exclude block no longer lists `.DS_Store`

#### Scenario: Quiet heal says nothing about skipped entries

- **WHEN** the store root contains `.DS_Store`, every allowed entry is already linked,
  and `heal --quiet` runs
- **THEN** it produces no output

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
entry (customer content wins), and `status` SHALL report it as a collision. Entries not
on the allow list are never linked, so nothing is quarantined on their behalf.

#### Scenario: Real directory at a managed name

- **WHEN** `heal` runs and a real directory `.claude/` exists in the worktree root while
  the store provides `.claude`
- **THEN** the directory is renamed to `.claude.quarantined-<timestamp>` and a symlink
  `.claude` to the store entry is created

#### Scenario: Store entry collides with tracked host content

- **WHEN** `heal` runs and the store provides an allowed entry whose name is tracked by
  the host repository (e.g. `docs`)
- **THEN** the tracked path is left untouched, the engine warns about the collision and
  skips that entry, and `status` reports it as a collision until the store entry is
  renamed or removed

### Requirement: adopt moves a path into the store and links it back

`adopt <path>` SHALL move a first-level untracked (or ignored) path from the worktree
root into the store root, create the managed symlink in its place, and update the
exclude block. It SHALL refuse paths tracked by the host repository, paths outside the
worktree root's first level, names already present in the store, and names not on the
allow list. The refusal for a name not on the list SHALL say that the list is part of
the plugin and grows through a plugin change.

#### Scenario: Adopting an untracked directory

- **WHEN** `adopt .opencode` runs and `.opencode/` is an untracked real directory in the
  worktree root
- **THEN** `.opencode` becomes a first-level entry of the store, a symlink replaces it in
  the worktree root, and the exclude block gains `.opencode`

#### Scenario: Tracked path is refused

- **WHEN** `adopt docs` runs and `docs/` is tracked by the host repository
- **THEN** the engine exits non-zero explaining tracked content belongs to the host
  repository and nothing changes

#### Scenario: A name not on the allow list is refused

- **WHEN** `adopt notes` runs and `notes/` is an untracked real directory in the
  worktree root
- **THEN** the engine exits non-zero naming `notes` as not on the allow list, and
  `notes/` stays where it was, the store is unchanged, and no link is created

### Requirement: detach removes links and exclude block, preserving the store

`detach` SHALL remove all managed symlinks from the current worktree (and, when run from
the main worktree, offer to detach known linked worktrees), remove the managed exclude
block, and leave the store itself untouched, so a later `heal` fully restores the setup.

#### Scenario: Detach then heal round-trip

- **WHEN** `detach` runs and afterwards `heal` runs in the same worktree
- **THEN** after `detach` no managed links or exclude block remain, the store is intact,
  and after `heal` links and exclude block are fully restored

### Requirement: adopt --local keeps an allowed entry out of the store's history

`adopt --local <path>` SHALL do everything `adopt <path>` does — same refusals (the allow
list included), same move, same link, same host exclude-block update — and additionally
mark the entry local-only in the store's own per-clone ignore rules (the store
repository's `info/exclude`), so the store's git never tracks it. A local-only entry
SHALL be linked, healed, quarantined around, and detached exactly like any other allowed
first-level store entry, in every worktree of the clone. `adopt --local` SHALL refuse a
name that the store's remote branch already carries, because that entry is already
shared and making it local would require deleting it for every other clone. Nothing
about local-only entries SHALL be written to the host repository or committed to the
store.

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

#### Scenario: A name not on the allow list is refused with --local too

- **WHEN** `adopt --local '[draft]'` runs for an untracked directory `[draft]/`
- **THEN** the engine exits non-zero naming `[draft]` as not on the allow list and
  nothing changes

#### Scenario: --local outside adopt is rejected

- **WHEN** any verb other than `adopt` is invoked with `--local`
- **THEN** the engine exits non-zero with usage guidance and changes nothing
