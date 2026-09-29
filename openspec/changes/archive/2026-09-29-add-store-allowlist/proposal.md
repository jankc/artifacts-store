# Proposal — allow list of store entry names

## Why

Every first-level entry of the store root is linked into every worktree, whatever it is.
On macOS, opening `.git/lundegaard` in Finder drops a `.DS_Store` there. The next `heal`
linked it into all four JMHZ worktrees, and because the main worktree already had its own
Finder `.DS_Store`, heal quarantined that one to `.DS_Store.quarantined-<timestamp>`.
Someone then made the store copy local-only by hand, only so `sync` would stop trying to
commit it. Nothing in the engine separates artifacts from junk that just happens to sit in
the store root.

`docs/jak-plugin-funguje.md` already plans the remedy: an **allow list of first-level
names**, built into the engine, so adding a name to it is a plugin merge request and the
vendored engine carries each new list to every project. This change implements that
plan. It departs from the doc on two points, both so that junk has no effect instead of
just being reported:

- `heal` skips a name that isn't on the list; the doc has it link the name and only
  report it.
- `sync` leaves such a name out of the commit; the doc has it refuse to commit unless
  `--force` is given.

## What Changes

- The engine SHALL carry a fixed allow list of first-level store names: `.agents`,
  `.claude`, `.codex`, `.cursor`, `.gemini`, `.lnd-canon.json`, `.local`, `.opencode`,
  `.pi`, `.specify`, `.superset`, `.windsurf`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
  `docs`, `mise.toml`, `openspec`, `specs`. There are no per-project exceptions, no
  config file and no environment override.
- `heal` SHALL link only store entries on the list. A name not on the list is not linked,
  and a link to it left over from before is removed like any link whose entry is gone.
  A non-quiet `heal` names what it skipped. The SessionStart `heal --quiet` stays
  silent, so a Finder `.DS_Store` doesn't warn in every session.
- `sync` SHALL stage only untracked content under names on the list, plus changes to
  paths the store already tracks. A name not on the list that the store's git doesn't
  track is never committed, and `sync` names what it left out. Such names don't count as
  dirty for `sync`, `status` or the Stop hook.
- `adopt` (with or without `--local`) SHALL refuse a name that isn't on the list,
  explaining that the list grows through the plugin.
- `status` SHALL list store entries that aren't on the list, marked as not linked and
  not synced. The existing heuristic for stray files at the store root (README, LICENSE,
  .gitignore …) is replaced by this report.
- Personal files inside a listed entry (for example `.claude/settings.local.json`) are
  kept out by a `.gitignore` committed in the store, which applies to the whole team.
  That already works; the `sync` spec now states it and gets a scenario, and the engine
  needs no personal-file list of its own.
- A new read-only verb, `allowed`, SHALL print the list one name per line, so the Stop
  hook reads the same list the engine uses.
- **BREAKING** for any store whose root holds a name that isn't on the list: that entry
  stops being linked on the next `heal`. The only store in use today (JMHZ) holds only
  names on the list.
- Scenarios that exercise gitignore/glob metacharacters through a first-level name
  (`[draft]`) move to nested paths, because `adopt` no longer accepts such a first-level
  name.

Non-goals: an engine-defined list of personal or junk paths nested inside listed
entries — a `.gitignore` committed in the store covers them; the server-side CI check from the doc; checking the content of
listed entries.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `artifact-linking`: linking, the managed exclude block and `adopt`/`adopt --local`
  are limited to names on the allow list; a non-listed entry is skipped and its old
  link removed.
- `artifact-sync`: `sync` never commits untracked non-listed entries and doesn't count
  them as dirty; `status` reports non-listed entries; the local-only guard scenario
  uses a nested path.
- `plugin-integration`: the Stop hook's dirty count ignores untracked non-listed
  entries; the SessionStart heal stays silent about them.

## Impact

- `scripts/lnd-artifacts.sh`: the list, `store_entries`, `do_heal` reporting, `cmd_adopt`,
  `cmd_sync` staging, `store_dirty_count`, `cmd_status`, the new `allowed` verb, usage
  text, `VERSION` bump.
- `hooks/stop.sh`: dirty count filtered through the engine's `allowed` list.
- `scripts/smoke.sh`: fixtures that use names not on the list (`.private`, `.teamdir`,
  `probe.md`, `[draft]`, `README.md` at the store root) move to names on the list or to
  nested paths; new cases for skip, leave-out, refusal and the `allowed` verb.
- `skills/lnd-artifacts/SKILL.md`, `README.md`, `docs/jak-plugin-funguje.md`:
  document the list, the verb, and the two points where this departs from the plan.
- `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`: version bump, so `heal`
  refreshes vendored engines.
