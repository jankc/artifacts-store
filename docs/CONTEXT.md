# Context and decision reasoning

Handoff document for agents picking up this repo fresh. Captures the history, the
reasoning behind settled decisions, prior-art references, and verified platform facts
that are NOT derivable from the OpenSpec artifacts alone. Written 2026-07-30 at the end
of the exploration/planning session with Jan.

## 1. How we got here

1. **lnd-core transport, v1** (`ai-marketplace` repo, `plugins/lnd-core/scripts/
   lnd-artifacts.sh`): per-project private artifact repo cloned to
   `<project>/.lundegaard/`, a `linked/` directory inside it as a managed map,
   symlinks from project root into `linked/`, auto-commit/push on the Claude Stop hook,
   entangled with governance machinery (traits, signoff, secret scan, doctor).
2. **It broke on git worktrees**: the store lived in the working tree, so every worktree
   had its own store copy and `.lundegaard` had to be git-ignored per worktree.
3. **Fix attempt**: OpenSpec change `lnd-store-in-git-common-dir` on branch
   `feat/lnd-store-in-git-common-dir` of the ai-marketplace repo — moved the store to
   `.git/lnd/store/` inside lnd-core. Planning completed (0/30 tasks implemented),
   validated the common-dir idea, then was ABANDONED in favor of this repo. Its
   design.md is still a useful quarry (link-target validation, lock placement,
   migration thinking).
4. **The pivot (this repo)**: Jan decided to stop fixing lnd-core entirely and start
   fresh with a single-purpose standalone plugin — artifacts only, no governance.
   lnd-core stays untouched as reference; the marketplace repo is not involved.
   Distribution via the marketplace comes later, after the plugin is proven standalone.

## 2. Why the store lives in the git common dir

`git rev-parse --git-common-dir` from any worktree resolves to the main clone's `.git`.
Putting the store there gives, for free:

- **Worktree sharing with zero config** — every worktree of the clone sees the same
  store instantly; no per-worktree clones, no sync between worktrees.
- **One exclude file for all worktrees** — `info/exclude` lives in the common dir, so a
  single managed block covers the main worktree and every linked worktree. This is
  exactly the thing the working-tree model could not do.
- **Structural leak-proofing** — content under `.git/` can never be committed to the
  customer remote.
- **`git clean` survivability** — with the old model, the ignored `.lundegaard/`
  directory would be DELETED by `git clean -ffdx`, including unpushed commits. (Plain
  `-fdx` spares it — git's nested-repo protection needs the second `-f` — and
  `git stash --all` skips it too; verified on git 2.50.1. But `-ffdx` is a common
  "scorched earth" recipe, e.g. in CI cleanup steps, precisely because it removes
  nested repos.) Now no working-tree command can touch the store: clean only removes
  the symlinks (trivially restored by `heal`).
- Nested repos inside `.git/` are a known-good pattern (people version `.git/hooks`
  this way). All store git operations still use explicit `git -C "$STORE"`.

Accepted costs (documented, not solved): `rm -rf .git` / nuke-and-reclone destroys
unpushed artifacts (mitigation: eager sync habit + loud Stop warning + status);
backup tools that skip `.git/` won't back the store up (the remote is the backup);
search tools don't follow symlinks by default (`rg -L`).

## 3. Ailien as prior art — and what we inverted

`/Users/jank/dev/work/lunde/ailien` (see its README + `infect` script) solves the
sibling problem: version AI tool configs across customer repos without committing them.
This plugin reuses its proven mechanics:

- **First-level linking rule** — link every first-level entry (dirs AND files) of the
  live layer; no nested discovery. Here the "live layer" is the store root itself.
- **Marker-delimited managed block in `.git/info/exclude`** that doubles as teardown
  state for our `detach` verb (ailien's `--cure`; we renamed it because `cure` and
  `heal` are synonyms and read as the same operation — see design.md D4).
- **Quarantine instead of delete** — pre-existing paths at a managed name are renamed
  `<name>.quarantined-<timestamp>`, never removed.
- **`--dry-run` discipline** on every mutating operation.

What we deliberately INVERTED: ailien is one central repo pushing configs into many
host repos via a `.targets` map (plus a `dna/` seeding layer). This plugin is the
opposite topology — each host project pulls its OWN artifact repo into its own `.git`.
Consequences: no `.targets`, no central mapping, no seeding layer, and ailien's
`--worktree-init` becomes unnecessary (the common dir shares everything; only symlinks
are per-worktree, and the SessionStart heal hook creates those).

## 4. Decision log (with the reasoning that didn't fit design.md)

Design.md D1–D8 are the settled decisions. Extra rationale worth preserving:

- **1 artifact repo = 1 customer project** (Jan, 2026-07-23, reaffirmed at pivot):
  the transport boundary must equal the client-isolation boundary. Branch-per-project
  sharing was analyzed and deferred; subdirectory sharing rejected outright. The old
  model's known orphan-branch gap (init creating a missing branch from current HEAD,
  inheriting another project's artifacts) simply evaporates here: init is a plain
  `git clone` of a dedicated repo.
- **`linked/` manifest dropped**: once 1 repo = 1 project, the indirection bought
  nothing — the store root listing IS the manifest, `adopt` is just a move + link.
- **Skill/plugin, not lnd-core**: Jan explicitly wants lnd-core abandoned as the
  vehicle. It remains a REFERENCE for e.g. lock/validation details, nothing more.
- **Hooks: heal + warn, never auto-sync** (Jan confirmed): SessionStart heal is what
  makes worktrees zero-touch and recovers from `git clean`; Stop only warns about
  dirty/unpushed store state. Auto-commit/push on Stop (the lnd-core behavior) was the
  rejected third option; "no hooks at all" (pure ailien-style manual) was rejected
  because it silently accumulates unpushed state. Deleting `hooks/hooks.json` degrades
  gracefully to manual mode.
- **`.git/lundegaard` flat, not `.git/lnd/store`**: one obvious entry in a `.git`
  listing; no hierarchy for its own sake.
- **`adopt` refuses tracked paths**: adopting tracked content would force a visible
  deletion commit in the customer repo — the exact footprint this tool exists to avoid.
- **Store root is payload-only**: a README.md or root .gitignore in the artifact repo
  would get symlinked into the customer repo root. Same discipline as ailien's
  `hosts/<key>/`; per-tool runtime ignores live inside each tool folder
  (e.g. `.claude/.gitignore`). No skip-list until it hurts (skip `.git` only).
- **Relative symlinks, recomputed per worktree at heal time**: survive moving the
  clone; linked worktrees get longer `../..`-style paths since their roots live
  elsewhere on disk. Validation always compares RESOLVED targets, not link text.
- **No Windows support initially**: ailien's junction/hardlink dance is out of scope.

## 5. Verified runtime facts

### 5a. Claude Code plugin facts (checked 2026-07-30 against docs)

- `claude --plugin-dir <path>` loads a plugin from a local directory, session-only,
  repeatable flag; local copy shadows a same-named marketplace plugin for the session.
- `/reload-plugins` hot-reloads skills, commands, hooks, and plugin MCP/LSP servers
  mid-session (monitors need a restart).
- Manifest: `.claude-plugin/plugin.json`, only `name` is required. Only the manifest
  lives under `.claude-plugin/`; all component dirs (`skills/`, `commands/`, `hooks/`,
  `scripts/`, …) sit at the plugin root.
- A single-skill plugin may place `SKILL.md` directly at the plugin root (invocation
  name via frontmatter `name:`). This repo no longer does — it moved to
  `skills/lnd-artifacts/SKILL.md` (B8), which both runtimes accept.
- **Verified 2026-07-30, after the B8 layout move** (headless `claude -p` probes, run
  from `/tmp`, i.e. outside the checkout):
  - `claude -p '…' --plugin-dir <checkout>` → the skill is available (answered "Yes").
  - **Skills-dir hop still resolves.** With no `--plugin-dir` at all, the chain
    `~/.claude/skills/lnd-artifacts → ~/.agents/skills/lnd-artifacts → <checkout>` loads
    the plugin as `lnd-artifacts@skills-dir` and descends into `skills/lnd-artifacts/`:
    a probe asked the skill for its worktree-init one-liner and quoted the line that only
    exists in the moved `skills/lnd-artifacts/SKILL.md`. The B9 fallback (repointing the
    symlinks one level deeper) was NOT needed.
  - **Hooks ride along on that path.** In a scratch project with a store and a deleted
    `.claude` link, a session started with no `--plugin-dir` reported the SessionStart
    hook's `additionalContext` ("lnd-artifacts (SessionStart heal): link .claude -> …")
    and the link was restored — so `hooks/hooks.json` is loaded through the skills-dir
    install too, with `${CLAUDE_PLUGIN_ROOT}` resolving to the checkout root.
- Plugin hooks go in `hooks/hooks.json` with the same schema and event types as user
  settings hooks (SessionStart, Stop, …); reference scripts via
  `${CLAUDE_PLUGIN_ROOT}`. Plugin hooks and user hooks merge; both run.
- Marketplace adoption later = a `marketplace.json` entry whose `source` points at this
  repo (git URLs supported); nothing in the plugin changes.
- Docs: https://code.claude.com/docs/en/plugins.md ,
  https://code.claude.com/docs/en/plugins-reference.md ,
  https://code.claude.com/docs/en/hooks.md

### 5b. Codex facts (checked 2026-07-30 against `codex-cli 0.146.0`, macOS)

Gathered empirically while implementing `add-codex-runtime-support` (C3): `codex --help`,
`codex plugin --help`, `codex doctor`, strings of the shipped binary, and four
`codex exec` probes.

- **User-level skills directory: `$CODEX_HOME/skills`, defaulting to `~/.codex/skills`.**
  Codex's own bundled `skill-installer`/`skill-creator` skills state it verbatim
  ("Installs into `$CODEX_HOME/skills/<skill-name>` (defaults to `~/.codex/skills`)"),
  and it is where the built-in skills live (`~/.codex/skills/.system/`). Verified by
  wiring a link there and observing the skill become available.
- **Codex descends into a plugin's `skills/` dir.** The wiring used was the same hop
  scheme as Claude: `~/.codex/skills/lnd-artifacts` → `~/.agents/skills/lnd-artifacts` →
  `<checkout>` (the checkout *root*, which has no `SKILL.md`). A probe run from a fixture
  under `/tmp` reported the absolute path it read as
  `<checkout>/skills/lnd-artifacts/SKILL.md` and quoted the worktree-init one-liner and
  the exact Rules count from it. So the C3 fallback (linking `skills/lnd-artifacts`
  directly) was NOT needed — though it remains available and would work, the skill text
  being self-contained.
- **Project-level discovery is `.codex/skills/<name>/SKILL.md`** — pre-existing fact in
  this repo (`.codex/skills/openspec-*` load in Codex sessions here).
- **No skill-root or plugin-root environment variable.** A probe printing the session's
  `env` showed only `CODEX_SANDBOX`, `CODEX_SANDBOX_NETWORK_DISABLED`, `CODEX_THREAD_ID`,
  `CODEX_MANAGED_BY_NPM`, `CODEX_MANAGED_PACKAGE_ROOT`, `CODEX_CI`, and TUI logging vars —
  nothing pointing at the loaded skill. Skill locations are injected into the prompt
  instead, as a `## Skills` catalog with a `### Skill roots` alias table (`r0` → path).
  This closes the design's open question: there is no Codex analogue of
  `CLAUDE_PLUGIN_ROOT`, which is exactly why C1's step 2 (the vendored engine) is the
  resolution mechanism outside Claude. `CLAUDE_PLUGIN_ROOT` itself is absent in a Codex
  session, so C1's `${CLAUDE_PLUGIN_ROOT:+…}` test is a reliable runtime discriminator.
- **Engine resolution verified end-to-end.** In a disposable fixture under `/tmp` (bare
  "remote" + host repo + `init` + `adopt .claude`), `codex exec -C <fixture>` asked to
  report artifact status via the skill answered with
  `ENGINE=/tmp/…/host/.git/lundegaard.engine.sh` and the verbatim `status` output — i.e.
  it took resolution step 2 (vendored copy), not the checkout script.
- **Codex 0.146.0 does have a hook system** (`~/.codex/hooks.json` and project
  `.codex/hooks.json`, with `session_start` / `user_prompt_submit` / `stop` /
  `post_tool_use` events and per-hook trust hashes in `config.toml`). It is user- and
  project-scoped, not something a *skill* carries, so it does not change C2 — the skill
  cannot ship hooks the way the Claude plugin can. If Codex ever lets plugins declare
  hooks, that is the follow-up the proposal explicitly left out of scope.

## 6. Reference paths

- Ailien (linking/exclude/quarantine prior art): `/Users/jank/dev/work/lunde/ailien`
  — read `README.md`, then `infect` (exclude block ~lines 440–540, worktrees ~688–760).
- lnd-core (reference ONLY, do not modify):
  `/Users/jank/dev/work/lunde/ai-marketplace` → `plugins/lnd-core/scripts/lnd-artifacts.sh`
  (Jan works in worktrees under `/Users/jank/dev/work/lunde/worktrees/ai-marketplace/`).
- Abandoned predecessor change (design quarry): branch `feat/lnd-store-in-git-common-dir`
  in that repo, `openspec/changes/lnd-store-in-git-common-dir/{proposal,design}.md`.
