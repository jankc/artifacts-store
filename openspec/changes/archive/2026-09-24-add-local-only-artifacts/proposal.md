# Proposal — local-only artifacts

## Why

Some artifacts belong in the store's reach but not in its history. The typical case is a
personal `.claude/` in a project whose team shares only `openspec/` and `CLAUDE.md`: it
must stay out of the customer repo, it must be visible in every worktree of the clone,
and it must never be pushed to the artifact remote that teammates pull from.

Today there is no supported way to do that. Leaving `.claude/` as a real directory in the
worktree root keeps it out of the store's remote but loses the worktree sharing (and
`git clean -fdx` deletes it). Adopting it shares it across worktrees but the next `sync`
pushes it to everyone.

Git already has the exact mechanism: the store is a git clone, and its private
`info/exclude` ignores paths for that one clone without committing anything. An entry
that sits in the store root but is ignored by the store's git is linked into every
worktree (the store listing is filesystem-based), covered by the host exclude block, and
skipped by `sync`'s `add -A`. What is missing is a verb that sets it up, a status line
that makes it visible, and one guard: **a plain `pull --rebase` silently overwrites an
ignored local file when the remote introduces the same path** — verified in a scratch
repo, exit status 0, local content replaced by the remote's.

## What Changes

- `adopt --local <path>` SHALL move the path into the store and link it back exactly
  like `adopt`, and additionally mark it local-only by adding `/<name>` to the store's own
  `info/exclude`. It SHALL refuse when the store's remote branch already carries that
  name.
- `sync` SHALL never commit local-only content (already true through `add -A`; now a
  contract), and SHALL stop before integrating remote changes that would write into a
  local-only path, naming the paths, instead of letting git overwrite them.
- `status` SHALL list local-only store entries and state that they are not backed up by
  the remote.
- `usage` text, `skills/lnd-artifacts/SKILL.md` (verb table, a rule for local-only
  entries, how to share one later) and the README gain the new flag.
- No change to linking, the host exclude block, heal, detach or the hooks — the
  existing filesystem-based listing already handles local-only entries.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `artifact-linking`: `adopt` gains a `--local` form that keeps the adopted entry out of
  the store's history while linking it like any other entry.
- `artifact-sync`: `sync` gains the local-only commit exclusion and the overwrite guard;
  `status` reports local-only entries.

## Impact

- `scripts/lnd-artifacts.sh`: option parsing (`--local`), `cmd_adopt`, `cmd_sync` (both
  the upstream path and the no-upstream fetch/rebase/reset path), `cmd_status`, `usage`.
- `scripts/smoke.sh`: a local-only section.
- `skills/lnd-artifacts/SKILL.md`, `README.md`, `docs/CONTEXT.md` (the overwrite fact).
- The vendored engine picks the change up through the existing version-drift refresh in
  `heal`; no bootstrap change.
- Local-only entries have no remote backup. `rm -rf .git`, a fresh clone, or a store
  re-`init` loses them. This extends the accepted cost from CONTEXT §2 (unpushed work is
  lost with `.git`) from "until the next sync" to "always", and `status` says so.

## Out of Scope

- **Making an already-shared entry local-only.** That is a `git rm --cached` in the
  store, which pushes a deletion to every teammate. It must stay a deliberate manual act.
- **Sharing a local-only entry later.** Deleting its line from the store's `info/exclude`
  is enough — the next `sync` commits it. Documented, not a verb.
- **Nested local-only paths** (`.claude/settings.local.json` inside a shared `.claude/`).
  Not supported. Team-wide tool ignores already go in the tool folder's `.gitignore`
  (Rule 8).
- **A separate unversioned local store** (e.g. `.git/lundegaard.local/`). Rejected in
  design.md.
