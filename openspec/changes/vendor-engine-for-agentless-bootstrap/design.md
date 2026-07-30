# Design — vendor the engine for agentless bootstrap

## Context

This change comes out of a working session on 2026-07-30, immediately after
`create-lnd-artifacts-plugin` was implemented and committed. The trigger was a plain
question from Jan: *"what if I need the artifacts even before I run any agent?"* — he
drives worktrees with tooling (worktrunk) and today configures the predecessor system
like this:

```toml
[[pre-start]]
infect = "{{ primary_worktree_path }}/../ailien/infect --worktree-init"
```

He wants the equivalent line for this plugin. `heal` is already exactly the right verb —
it takes no arguments and resolves the store from the current directory, so any
worktree-init hook running with the new worktree as cwd is enough. The problem is purely
**how to name the engine** in that line.

### The path problem (the core of this change)

Every path to the engine that exists today is unstable for at least one class of user:

- **Marketplace install** — `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.
  Verified layout against the installed `codex` plugin, which ships `scripts/` at exactly
  that shape. Deterministic in shape, but the version component changes on every upgrade,
  so any user-written hook breaks silently.
- **Skills-dir install** — `~/.claude/skills/<name>/`, which auto-loads as
  `<name>@skills-dir`. Scoped to one `CLAUDE_CONFIG_DIR`. Verified: with
  `CLAUDE_CONFIG_DIR=~/.claude-work`, a session answers **NO** to "is the lnd-artifacts
  skill available" while the same plugin is installed under `~/.claude/skills`.
- **`${CLAUDE_PLUGIN_ROOT}`** — only set while a Claude hook or skill runs. Verified not
  exported into an interactive shell.
- **A copy on `PATH`** (e.g. `~/.local/bin/lnd-artifacts`) — works, and survives both
  plugin upgrade and plugin deletion (verified), but assumes the user has such a
  directory and that it is on PATH. Jan's objection, and a fair one.

The conclusion that drove the design: **publishing to a marketplace does not solve this,
it makes it worse.** The answer must be independent of where the plugin is installed.

### What the git common dir already gives us

`git rev-parse --git-common-dir` resolves to the same physical directory from every
worktree of a clone, from any subdirectory, and in `--separate-git-dir` and
bare+worktrees layouts. The store, the lock, and the exclude block already rely on it.
Adding the engine to that set means everything the tool needs lives in one place that
git itself tells you how to find.

## Goals / Non-Goals

**Goals:**

- One command line, identical for every user and every project, that materializes
  artifacts in a new worktree with no agent running.
- Zero user-facing install step and zero PATH assumptions.
- Immune to plugin upgrade, plugin uninstall, `CLAUDE_CONFIG_DIR` differences, and the
  choice of agent (Codex included).

**Non-Goals:**

- Windows. The vendored path works under Git Bash, but linking does not (POSIX symlinks
  need Developer Mode plus `core.symlinks=true`). A Windows user would get past locating
  the engine and then fail creating symlinks. Windows remains the base design's declared
  non-goal and needs its own change (junctions for directories, copies for files).
- Bootstrapping the first `init`. Something must run once per project.
- Installing git hooks into host repositories (see B6).

## Decisions

### B1 — Vendor location: `<git-common-dir>/lundegaard.engine.sh`

A sibling of the store, next to `lundegaard.lock`. Not inside the store, for the same
reason the lock is not (D5 of the base design): anything at the store root is payload —
it would be symlinked into the customer's project root by D2 and committed by `sync`'s
`git add -A`. Not in `hooks/` either, because that directory belongs to git and may be
redirected by `core.hooksPath`.

Verified: after vendoring, the store root listing is unchanged and
`git -C <store> status --porcelain` is empty.

### B2 — A copy, not a symlink

A symlink into the plugin install would reintroduce the exact problem this change exists
to solve — it breaks on upgrade (version-pinned cache path) and on uninstall. The engine
is a single self-contained POSIX script with no dependencies, so a copy is a complete,
working artifact.

Verified: the engine was copied to an unrelated directory, run from there, then the
"plugin" directory was deleted entirely — `git worktree add` still materialized both
links, and `--version` still worked.

### B3 — `heal` refreshes the copy on version drift

The copy ages when the plugin is upgraded. `heal` compares its own `VERSION` against the
vendored copy's and rewrites it when they differ. Because the SessionStart hook runs
`heal` every session, an upgraded plugin propagates on the next session with no user
action. Worst case the vendored copy is one session behind, and it only ever runs
`heal` — the most stable verb, and the one with no network or history side effects.

Rejected: refreshing on every `heal` unconditionally (needless writes into `.git` on
every session); refreshing only at `init` (the copy would never update).

Implementation note for the implementer: compare cheaply. Grepping `^VERSION=` out of the
vendored file is enough; do not shell out to the vendored copy to ask it, since a corrupt
copy must still be replaceable.

### B4 — The documented one-liner, and why it carries a guard

```sh
E="$(git rev-parse --git-common-dir 2>/dev/null)/lundegaard.engine.sh"; [ -x "$E" ] && "$E" heal --quiet || true
```

Worktree-init configuration is **global** — it fires in every project the user creates a
worktree in, and most of those have no artifact store. The `[ -x "$E" ]` guard makes the
line a silent `exit 0` there, which is why the guard is part of the contract rather than
a nicety.

Verified in four scenarios: managed worktree (links created), unmanaged repo (silent,
exit 0), outside any git repo (silent, exit 0), nested subdirectory of a worktree
(exit 0; `heal` targets the worktree root regardless of cwd).

Note the guard also removes the need to change `heal --quiet` semantics for storeless
repos — an earlier sketch required that, this one does not. An implementer may still
consider it separately, but it is not part of this change.

### B5 — `detach` removes it, `status` reports it

`detach` already removes the links and the exclude block while preserving the store; the
vendored engine belongs to the same managed set, so it goes too. `status` reports its
presence and version, which is what makes B3's drift visible when a user asks why an old
behavior persists.

### B6 — Rejected: auto-installing a `post-checkout` hook

This was designed and verified end-to-end before being dropped. `git worktree add` fires
`post-checkout` with cwd set to the new worktree, and hooks resolve from the common dir,
so one hook file covers every worktree — a fully automatic version of this change that
requires the user to write nothing at all. It works (verified: plugin deleted, worktree
added, links materialized).

It was rejected for this change because Jan explicitly said he is happy owning the
worktree-init script — and the hook route carries real costs that vendoring alone does
not: it writes into `.git/hooks`, must respect `core.hooksPath` (husky, lefthook), must
not clobber an existing `post-checkout`, and does not fire under
`git worktree add --no-checkout`.

Note that B1–B5 are a strict prerequisite for it. If the hook route is ever revisited,
the hook body is three lines and references only the vendored engine:

```sh
[ "$3" = 1 ] || exit 0
E="$(git rev-parse --git-common-dir)/lundegaard.engine.sh"
[ -x "$E" ] && "$E" heal --quiet || true
```

### B7 — Rejected: an `install-cli` verb copying the engine onto `PATH`

Considered as the previous iteration of this change: `lnd-artifacts install-cli
[--prefix DIR]` writing a copy to `~/.local/bin`, making the documented line simply
`lnd-artifacts heal --quiet`. Verified working, including across a simulated plugin
upgrade and uninstall.

Rejected because it assumes a PATH directory that not every user has, needs a
per-machine install step, needs its own refresh mechanism, and would need a Windows
answer of its own. Vendoring into the common dir achieves the same result with no
install step and no PATH — one `cp` at `init` replaces the entire verb.

### B8 — Fold the dual-runtime layout into this change

Decided with Jan on 2026-07-30: the future home of this plugin is the ai-marketplace
repo, whose `NAMING-CONVENTIONS.md` hard rule 2 requires `skills/<name>/SKILL.md` —
a root `SKILL.md` is an auditor ERROR and is not loaded by Codex at all. The move is
pure restructuring with no behavior change in Claude Code (verified fact in
docs/CONTEXT.md §5: Claude accepts both shapes), so it rides along with this change's
documentation work rather than getting a change of its own. This supersedes the base
design's D8 layout sketch (root `SKILL.md`); the follow-up `add-codex-runtime-support`
change builds on this layout and carries all Codex *behavior*.

Concretely:

- `SKILL.md` → `skills/lnd-artifacts/SKILL.md` (frontmatter unchanged).
- `.codex-plugin/plugin.json` added, mirroring `.claude-plugin/plugin.json` (same
  `name`/`version`/`description`/`author`) plus an `interface` block modeled on
  `lnd-quick-commit` in the ai-marketplace repo (`displayName`, `shortDescription`,
  `longDescription`, `developerName`, `category: "Engineering"`, `defaultPrompt`).
- Both manifests declare `"skills": "./skills/"` explicitly, the way `lnd-core` does,
  rather than relying on directory auto-discovery.
- The two manifests must stay in version lockstep; `heal`'s B3 drift check reads the
  engine's `VERSION=`, so the engine remains the single source of truth for behavior —
  manifest versions are packaging metadata that follow it.

### B9 — Risk: skills-dir installs must survive the move

Jan's live install goes `~/.claude*/skills/lnd-artifacts → ~/.agents/skills/lnd-artifacts
→ this checkout`, relying on the documented skills-dir auto-load (`<name>@skills-dir`).
Today that entry finds a root `SKILL.md`; after the move it must be picked up as a
*plugin directory* containing `skills/lnd-artifacts/SKILL.md`. Verify both load paths
after the move — `claude --plugin-dir <repo>` and the skills-dir hop — and record the
result in docs/CONTEXT.md §5. If the skills-dir auto-load turns out not to descend into
`skills/`, the fallback is repointing the `~/.claude*/skills/lnd-artifacts` links one
level deeper (at `<checkout>/skills/lnd-artifacts`), which keeps the hop scheme intact —
but hooks would then no longer ride along, so record whichever shape actually works.

## Evidence

All of the following was verified on disposable fixtures during the 2026-07-30 session,
against git 2.50.x on macOS:

| Claim | Result |
| --- | --- |
| Engine runs correctly from an arbitrary location | yes — copied to a fake cache dir, ran `init` from there |
| Vendored copy works after the plugin is deleted | yes — `git worktree add` still linked both entries |
| Vendored copy is not payload | store listing unchanged, `git -C <store> status --porcelain` empty |
| One-liner is silent + exit 0 in unmanaged repos and outside git | yes |
| `heal` targets the worktree root from a nested subdir | yes |
| Skills-dir install is invisible to another `CLAUDE_CONFIG_DIR` | yes — session answered NO |
| Marketplace cache path carries the version | yes — `…/codex/1.0.4/scripts` on this machine |

## Risks / Trade-offs

- [Stale vendored copy runs old behavior] → B3 refresh, `status` reports the version;
  bounded to one session after an upgrade.
- [~35 KB per project inside `.git/`] → accepted; smaller than a single object pack.
- [A user edits the vendored copy] → it is overwritten on version drift, not merged. Say
  so in the README; the store is the place for project-specific behavior, not the engine.
- [Executing a script out of `.git/`] → no new trust boundary: `.git/hooks` already runs
  arbitrary code in any repo you have checked out. Worth a sentence in the README anyway.
- [Vendored copy is not refreshed when the plugin is *downgraded*] → B3 compares for
  difference, not for "newer", so a downgrade also refreshes. Intentional: the running
  plugin is the source of truth.

## Open Questions

- Should `init --dry-run` print the vendoring step? (Almost certainly yes — every other
  mutation is previewable; called out here so it is not forgotten.)
- Should the vendored copy be named with a version suffix to make drift visible in a
  `.git` listing? Leaning no — one stable filename is what makes the one-liner writable.
- Does any consumer need a machine-readable `status` (e.g. `--json`) to check drift in
  CI? Not required by this change; note it if a second consumer appears.
