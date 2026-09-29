# Design — allow list of store entry names

## Context

See proposal.md — Why. The engine facts this design builds on:

- `store_entries()` lists the store root on the filesystem, minus `.git`. `do_heal`,
  `sync_exclude`, `cmd_status` and the fallback in `cmd_detach` all consume that one
  listing. `do_heal` already removes a root symlink into the store whose name is no
  longer in the listing, both through the managed block and through a direct scan of
  the worktree root, so it also removes links in worktrees whose block entry is gone.
- `cmd_detach` unlinks the names in the managed block first and uses `store_entries`
  only when there's no block. Links created by an older engine are therefore still
  removed after the list shrinks.
- `sync` stages with `add -A`. `store_dirty_count`, which `sync` and `status` use, and
  `hooks/stop.sh`, which has its own copy of the count, count
  `status --porcelain --untracked-files=all` lines.
- The engine is vendored as one file (`lundegaard.engine.sh`), and `heal` refreshes the
  copy whenever `VERSION` differs.

Verified on git 2.54.0 in a scratch repo, 2026-09-29: `git add -A -- .
':(exclude,literal).DS_Store' ':(exclude,literal)[draft]' ':(exclude,literal)notes'`
exits 0. It stages untracked and tracked changes everywhere else, skips an ignored
directory silently, and matches `[draft]` literally. A following `git add -u` stages the
modification of the tracked `notes/t` but leaves the untracked `notes/new` alone.

## Goals / Non-Goals

**Goals:**
- One definition of the allow list, inside the engine file, so vendoring carries it.
- A name not on the list has no effect on the worktrees, on the store's history, or on
  the dirty counts.
- Migration needs no extra step: the first `heal` after the upgrade removes old links.

**Non-Goals:**
- Filtering nested paths (`.claude/.DS_Store`, `.claude/settings.local.json`).
- A server-side check, `--force`, or per-project exceptions.

## Decisions

### D1 — The list is a newline-separated string constant in the engine

`ALLOWED_ENTRIES` sits beside the other globals, one name per line, and an
`is_allowed <name>` helper tests a name with `grep -Fqx`. `store_entries()` gains no
filter, because `status` still needs to see names that aren't on the list. Instead, a
new `linked_entries()` (store entries filtered through `is_allowed`) replaces
`store_entries` wherever the result is "what gets linked": `do_heal`, `sync_exclude`
callers, `cmd_adopt`, the `status` link count, and the `cmd_detach` fallback. A second
helper, `unlisted_entries()`, yields the rest.

*Alternatives:* a file shipped next to the engine breaks the one-file vendored copy; a
file in the store lets each project extend the list, which defeats curating it (see
the doc); a `case` pattern can't be printed for `allowed` or the Stop hook without
keeping a second copy.

### D2 — Names off the list never enter the linking path

`do_heal` iterates `linked_entries`, so a name off the list is never passed to
`ensure_link`, never quarantines anything, and never enters the managed block. Old
links fall to the existing "entry disappeared" cleanup unchanged. After linking, `heal`
prints `skip <name> (not on the allow list)` for each unlisted entry through `info`, the
existing quiet-aware printer: silent under `--quiet` (SessionStart), shown otherwise.
Skips are not counted as changes, so a healthy store with junk still reports healthy.

### D3 — sync stages by exclusion, then updates tracked paths

`cmd_sync` stages with
`git add -A -- . ':(exclude,literal)<u1>' ':(exclude,literal)<u2>' …` over
`unlisted_entries`, followed by `git add -u`. The first command skips ignored content
exactly as before, so local-only entries stay out. The second one picks up changes to
tracked paths under names off the list, so a store that committed such a name before
this change keeps syncing it and a dirty tracked file never blocks the rebase. `sync`
then names each unlisted entry that had untracked content as left out.

*Alternative:* listing the allowed names as positive pathspecs (`git add -A -- .claude
openspec …`) fails when an allowed name is missing or ignored (`git add` exits 1 for an
ignored explicit path), so every name would need its own existence and ignore checks.
With exclusion, a pathspec for a name that doesn't exist is simply a no-op.

### D4 — Dirty = tracked changes anywhere + untracked content under allowed names

`store_dirty_count` becomes the sum of `status --porcelain --untracked-files=no` lines and
the `??` lines of `status --porcelain --untracked-files=all -- . <same exclusions>`. That
is exactly what D3 would stage, so `sync` never reports dirty work it then refuses to
commit.

### D5 — `allowed` verb; the Stop hook asks the engine for the list

`allowed` prints `ALLOWED_ENTRIES` and exits, with no repository resolution, no lock and
no store. `hooks/stop.sh` runs the engine it ships beside
(`"$(dirname "$0")/../scripts/lnd-artifacts.sh" allowed`), builds the same exclusions
from the store root, and counts as in D4. If the engine can't be run, the hook falls
back to today's unfiltered count: a spurious warning is safer than a missed one.

*Alternative:* the hook calls `status` and greps its summary. That's heavier on a
10-second timeout and couples the hook to human-readable output.

### D6 — adopt refuses before any other check that changes nothing

`cmd_adopt` tests `is_allowed "$ca_name"` right after resolving the name, before taking
the lock, for both plain and `--local`. The message names the entry and says the list
is part of the plugin (`lnd-artifacts allowed` shows it).

### D7 — status replaces the hygiene heuristic

The `README|LICENSE|.gitignore…` "payload-only" warning goes; everything it caught is
now simply off the list. A new line, `  unlisted : <names> — not on the allow list; not
linked, untracked content not synced`, is printed when `unlisted_entries` is non-empty.
The `local` line keeps listing ignored first-level entries, which are now all names on
the list, since `adopt --local` refuses the rest.

## Risks / Trade-offs

- [A store somewhere holds a name that isn't on the list] → it stops being linked
  silently in SessionStart. Mitigation: `status` and a plain `heal` both name it; the
  fix is a plugin release that adds the name. The only known store (JMHZ) is fully
  covered.
- [`docs` and `specs` are on the list but often tracked by host repos] → the existing
  collision rule applies (host wins, `status` reports it); no new behaviour.
- [Metacharacter coverage shrinks] → `[draft]` can no longer be a first-level entry.
  The escaping code (`ignore_pattern`, the literal guard) stays, and its tests move to
  nested paths and to the exclude pathspec in D3.
- [The Stop hook depends on the engine being next to it] → it always is inside the
  plugin; the fallback covers a broken install.

## Migration Plan

Bump `VERSION` and both plugin manifests (0.2.0 → 0.3.0). On the first SessionStart
after the upgrade, `heal` refreshes the vendored engine and removes links to entries off
the list. No store or host change is needed. Rollback is installing 0.2.0: its `heal`
links everything again.
