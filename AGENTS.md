# lnd-artifacts — agent instructions

This repository IS a Claude Code plugin (single skill + one POSIX script + two hooks)
that manages per-project AI artifacts: a private artifact repo cloned into the host
project's git common dir (`.git/lundegaard`), with its first-level entries symlinked
into the project root and ignored via a managed block in `.git/info/exclude`.

## Current state

- `create-lnd-artifacts-plugin` is IMPLEMENTED and committed (all verbs, hooks, smoke
  suite). Its design decisions D1–D8 are settled — don't relitigate them.
- Two follow-up changes are IMPLEMENTED and verified (uncommitted, pending archive),
  in dependency order:
  1. `vendor-engine-for-agentless-bootstrap` — vendor the engine into the git common
     dir (decisions B1–B7) + dual-runtime repo layout (B8–B9: `skills/<name>/SKILL.md`,
     Codex mirror manifest).
  2. `add-codex-runtime-support` — make the skill work under Codex (decisions C1–C4:
     runtime-neutral engine resolution, hook-compensation rules, verified discovery).
- For any change, read `proposal.md` → `design.md` → `specs/*/spec.md` → `tasks.md`,
  in that order.
- `docs/CONTEXT.md` holds the history and reasoning behind the settled decisions,
  prior-art references (ailien, lnd-core), and verified Claude Code plugin mechanics.
  Read it before questioning any design choice.

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
# then /reload-plugins inside the session after editing skills/*/SKILL.md / hooks / scripts
./scripts/smoke.sh        # (task 6.1) disposable-fixture end-to-end test
```

Implementation is driven through OpenSpec: `/opsx:apply` to work tasks, `/opsx:verify`
before archiving. Update checkboxes in `tasks.md` as you complete tasks.
