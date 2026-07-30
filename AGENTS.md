# lnd-artifacts — agent instructions

This repository IS a Claude Code plugin (single skill + one POSIX script + two hooks)
that manages per-project AI artifacts: a private artifact repo cloned into the host
project's git common dir (`.git/lundegaard`), with its first-level entries symlinked
into the project root and ignored via a managed block in `.git/info/exclude`.

## Current state

- Planning is DONE, implementation has NOT started. Everything is uncommitted on `main`.
- The active OpenSpec change is `create-lnd-artifacts-plugin` — read, in order:
  1. `openspec/changes/create-lnd-artifacts-plugin/proposal.md` (why, scope, trade-offs)
  2. `.../design.md` (decisions D1–D8 — these are settled, don't relitigate)
  3. `.../specs/*/spec.md` (behavior contracts: artifact-store, artifact-linking,
     artifact-sync, plugin-integration)
  4. `.../tasks.md` (the work breakdown; start at task 1.1)
- `docs/CONTEXT.md` holds the history and reasoning behind those decisions, prior-art
  references (ailien, lnd-core), and verified Claude Code plugin mechanics. Read it
  before questioning any design choice.

## Hard constraints (from decisions already made with Jan)

- POSIX shell + git + coreutils only. No other runtime dependencies.
- The engine must NEVER commit, push, or otherwise mutate the HOST repository, and the
  hooks must never commit or push the STORE either — `sync` is always explicit.
- 1 artifact repo = 1 customer project. No shared multi-project stores, no categories,
  no `linked/` manifest indirection — the store root listing is the manifest.
- The store root is payload-only: no README.md or root .gitignore in artifact repos
  (every first-level entry except `.git` gets symlinked into the customer repo root).
- Do NOT touch or import from lnd-core (ai-marketplace repo) — reference only.
- No AI attribution anywhere in commits or PRs (no Co-Authored-By, no "Generated with").

## Dev loop

```bash
claude --plugin-dir /Users/jank/dev/work/lunde/lnd-artifacts   # load plugin, session-only
# then /reload-plugins inside the session after editing SKILL.md / hooks / scripts
./scripts/smoke.sh        # (task 6.1) disposable-fixture end-to-end test
```

Implementation is driven through OpenSpec: `/opsx:apply` to work tasks, `/opsx:verify`
before archiving. Update checkboxes in `tasks.md` as you complete tasks.
