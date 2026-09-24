# Design — local-only artifacts

## Context

See proposal.md — Why. Three existing facts carry this design, and none of them changes:

- `store_entries()` is a filesystem listing of the store root minus `.git`
  (`scripts/lnd-artifacts.sh`, "store listing"), not `git ls-files`. An entry the store's
  git ignores is still listed, so `do_heal` links it in every worktree and
  `sync_exclude` puts it in the host exclude block.
- `sync` stages with `add -A`, and `store_dirty_count` uses `status --porcelain`. Both
  honor the store's ignore rules, so ignored content is already never committed and
  never counted as dirty (and so the Stop hook does not nag about it).
- `sync` integrates remote work in two places: `pull --rebase` when the branch has an
  upstream, and `fetch` + `rebase` (or `reset --hard` for an unborn branch) when it does
  not.

Two git behaviors were verified on git 2.54.0 in scratch repos on 2026-09-24:

1. **Integrating remote commits silently overwrites ignored local files.** Clone B
   ignores `/.claude/` via `info/exclude` and has `.claude/s` = `MINE`; clone A commits
   and pushes `.claude/s` = `THEIRS`; `git pull --rebase` in B exits 0 and `.claude/s`
   now reads `THEIRS`. Git treats ignored files as expendable. This is the one thing the
   change has to guard against; everything else already works.
2. **`git check-ignore --stdin` is NOT a usable oracle** (found in review). It reads its
   input as glob pathspecs, so a literal `[draft]` is never reported as ignored, and
   `--literal-pathspecs` / `--noglob-pathspecs` make it die ("pathspec magic not
   supported by this command"). The oracle is `git ls-files --others --ignored
   --exclude-standard --directory`: what the store actually ignores on disk, with an
   ignored directory collapsed to one `name/` line. Paths are then compared as strings.
3. **Gitignore lines need escaping.** `/[draft]` is a character class and does not match
   the entry `[draft]`; nor do unescaped `*`, `?`, `\` or a trailing space. This was
   already a latent bug in the host exclude block (such an entry's symlink showed up as
   untracked in the customer repo), and would have made `adopt --local` push the entry.

## Goals / Non-Goals

**Goals:**

- One flag on an existing verb, no new verb, no new state file, no change to the linking
  model.
- The only new safety logic is the overwrite guard, and it covers both integration paths
  in `sync`.

**Non-Goals:**

- Protecting local-only content from `rm -rf .git`, a fresh clone, or re-`init`. There is
  no remote copy; `status` states it, nothing more.
- Detecting that another clone of the same store made the same name local-only. Every
  clone's `info/exclude` is private and never compared.

## Decisions

### L1 — The store's own `info/exclude` is the local-only marker

The local-only set lives in the store repository's `info/exclude`, resolved with
`$(git -C "$STORE" rev-parse --absolute-git-dir)/info/exclude`. It is per clone, never committed, and
it lives inside the store, which is in the host's git common dir. That puts it outside
every host worktree, so all worktrees share it.

Alternatives rejected:

- **A root `.gitignore` in the store.** It would be a first-level entry, get symlinked
  into the customer root, and be pushed to every teammate, which would make the entry
  local-only for everyone. That breaks the payload-only rule and gets the scope wrong.
- **A tool-folder `.gitignore` (`.claude/.gitignore`, Rule 8).** Right for team-wide
  runtime ignores, wrong here: it is committed, and it cannot ignore the folder that
  contains it.
- **A separate unversioned directory (`.git/lundegaard.local/`) linked alongside the
  store.** Two listings feed heal and the exclude block. That brings name collisions
  between them, a second copy of the quarantine/wrong-target logic, and the
  two-sources-of-truth drift that CONTEXT §6 rejected for manifests. The chosen design
  keeps one listing, and git decides what is shared, the same principle as §6's
  branch model.
- **A manifest file naming local-only entries.** Same objection as in §6. Git ignore
  rules already are that manifest, and git enforces them.

### L2 — `adopt --local` appends one escaped `/<name>` line

It writes no marker block. The file belongs to the store clone, not to the host, and a
single anchored line is self-explanatory to anyone who opens it. The engine appends the
line only when an exact-match line is not already present, so re-running is harmless.
The leading `/` anchors it to the store root, so a same-named nested path elsewhere is
unaffected. The same form works for directories and files (`/.claude`, `/CLAUDE.md`).
The name goes through `ignore_pattern`, which backslash-escapes `[ ] \ * ? # !` and a
trailing space (fact 3). The host exclude block uses the same helper, and `read_managed`
undoes the escapes when it reads the block back as teardown state. Names containing a
newline are refused; no gitignore line can express them.

`--local` is a global option flag (`LOCAL=1`) like `--all-worktrees`. The dispatcher
rejects it for any verb other than `adopt`.

`adopt --local` refuses a name that already exists in the store's comparison ref
(upstream, else `origin/<branch>`, the same resolution `status` uses) as of the last
fetch. `adopt` stays offline, as it is today. When no comparison ref exists, it does not
check, and the sync guard (L3) is the backstop.

Order inside the locked section: move, link, host exclude block, store `info/exclude`.
If the last step fails, the entry is linked but shared. The next `status` shows it as not
local-only, and there has been no `sync` in between, so nothing has leaked.

### L3 — The overwrite guard: fetch, list incoming paths, compare with what is ignored

Immediately before each integration step in `cmd_sync`:

1. The target ref is already fetched: the no-upstream path fetches today, and the
   upstream path changes from `pull --rebase` to `fetch <upstream-remote>` + `rebase`
   with no argument. Plain `git rebase` rebases onto the configured upstream with
   `--fork-point`, the same thing `pull --rebase` does. Doing the fetch and the check on
   the same ref closes the gap a check-then-`pull` would leave, where the remote moves
   between the check and pull's own fetch. For an upstream on remote `.`, skip the fetch.
2. Incoming paths: `git diff --name-only HEAD...<target>` (what the remote side changed
   since the merge base). For the unborn-branch `reset --hard` case, use
   `git ls-tree -r --name-only <target>`.
3. Compare them with the store's ignored paths (fact 2). A hit is an incoming path that
   equals an ignored file or lies under an ignored directory: exactly what git would
   overwrite or write into a local-only area. Both listings use `-z` so no path quoting
   gets in the way, and a failed listing aborts the sync rather than passing it. Exit non-zero with that list, the store path, and the two ways
   out (rename the local content, or drop the ignore line to share it). The local commit
   from this run stays. The existing `release_lock` + `die` shape applies.

It stops even when the incoming file does not exist locally, as long as it lands inside
an ignored directory that does (remote adds `.claude/new` into a local-only `.claude/`). No data would be lost, but the local-only
entry would silently start carrying shared, tracked files. That is a decision the user
has to make, not something to discover later.

### L4 — `status` lists ignored first-level entries

The first-level lines of the same ignored-paths listing (fact 2) are the local-only
entries. The result is one `local    :` line naming them plus a note that they are
neither pushed nor backed up. Asking git rather than parsing the store's `info/exclude`
means an entry ignored by the user's global excludes is also shown.
That is correct: such an entry was already never synced, and until now nothing said so.

### L5 — Nothing else changes

Heal, quarantine, detach, the host exclude block, both hooks and the vendored-engine
refresh treat a local-only entry as an ordinary store entry, so they need no changes.
The `plugin-integration` spec's intent-to-verb mapping already covers `adopt`. The skill
gains a rule and a table row, but the spec requirement stands.

## Risks / Trade-offs

- [Local-only content has no backup] → `status` says so on every run; the skill tells the
  agent to mention it when adopting with `--local`. Accepted, same class as CONTEXT §2's
  "unpushed artifacts die with `.git`".
- [A teammate shares a name that is local-only here, so every `sync` in this clone stops]
  → The stop is the feature. Its message names both ways out, and the fix takes one
  command.
- [The upstream path's switch from `pull --rebase` to `fetch` + `rebase` changes the
  commands the smoke suite exercises] → Behavior is intended to be identical. The
  existing sync scenarios (clean sync, nothing to sync, rebase conflict) must pass
  unchanged, and they are the regression check.
- [User's global excludes make `status` show surprising local-only entries] → That is
  pre-existing, invisible state being surfaced, not new behavior.

## Migration Plan

No migration. Existing stores have no local-only entries until someone runs
`adopt --local`. The vendored engine picks up the new version on the next `heal` through
the existing version-drift refresh. Rollback: an older engine ignores nothing extra and
keeps working. The `info/exclude` lines still keep the content out of `add -A`, so only
the guard and the status line disappear.
