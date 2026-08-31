# lnd-artifacts — agent instructions

This repository IS a Claude Code plugin (one skill + one read-only `/lnd-artifacts:help`
command + one POSIX script + two hooks) that manages per-project AI artifacts: a private
artifact repo cloned into the host project's git common dir (`.git/lundegaard`), with its
first-level entries symlinked into the project root and ignored via a managed block in
`.git/info/exclude`.

## Current state

- **No active changes.** All four are implemented, verified and archived under
  `openspec/changes/archive/`; the merged behaviour lives in `openspec/specs/`
  (artifact-store, artifact-linking, artifact-sync, artifact-bootstrap,
  codex-runtime, plugin-integration). Read those specs first — they are the current
  contract. The archived changes carry the reasoning:
  1. `create-lnd-artifacts-plugin` — all verbs, hooks, smoke suite (decisions D1–D8).
  2. `vendor-engine-for-agentless-bootstrap` — vendor the engine into the git common
     dir (B1–B7) + dual-runtime repo layout (B8–B9: `skills/<name>/SKILL.md`,
     Codex mirror manifest).
  3. `add-codex-runtime-support` — make the skill work under Codex (C1–C4:
     runtime-neutral engine resolution, hook-compensation rules, verified discovery).
  4. `add-help-command` — the read-only `/lnd-artifacts:help` command (H1–H5), plus
     the step-1 engine-resolution fix: `CLAUDE_PLUGIN_ROOT` is never in the agent's
     shell, only substituted into skill/command text at render time.
- Those decisions are settled — don't relitigate them.
- For any change, read `proposal.md` → `design.md` → `specs/*/spec.md` → `tasks.md`,
  in that order.
- `docs/CONTEXT.md` holds the history and reasoning behind the settled decisions,
  prior-art references (ailien, lnd-core), verified Claude Code plugin mechanics, and
  §6 the deferred multi-repo analysis. Read it before questioning any design choice.

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
