---
description: What lnd-artifacts is, this project's live artifact status, and the verbs it offers — AI artifacts in a private repo, never committed to the customer repo
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh status), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh --help)
---

```!
echo "=== status ==="
${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh status 2>&1 || echo "(no artifact state readable here — the engine needs a git repository, and the store lives in that repository's git common dir)"
echo
echo "=== verbs ==="
${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh --help 2>&1 || echo "(the engine is not reachable from this session, so its verb list cannot be shown)"
```

Open your answer by reproducing both injected blocks above, verbatim and complete, inside a
fenced code block — every line, summarizing and omitting nothing, the engine version and the
verb list included. Explain them afterwards, in the terms below; whatever the state, the
explanation must say that `sync` runs only when the user asks, and must quote the
worktree-init one-liner below verbatim. Answer from that injected output alone: run no
verb, no command, no tool. This is a read-only briefing.

**What this plugin is.** lnd-artifacts keeps a project's AI artifacts (`.claude/`,
`openspec/`, `CLAUDE.md`, …) in a private artifact repository cloned into the host
project's git common dir (`.git/lundegaard`), with every first-level entry symlinked into
the project root and ignored through a managed block in `<git-common-dir>/info/exclude`.
The artifacts are therefore structurally incapable of reaching the customer's remote, and
every worktree of the clone shares one store.

**Reading the status block.** `store` is where the artifact repo lives and `state` says
whether it exists; `engine` reports the vendored copy's version and whether it drifted from
the running plugin; `dirty` and `unpushed` count artifact work that has not reached the
artifact remote; the link lines are the health of the project-root symlinks, and anything
missing or broken is what `heal` repairs. If the status says no store is initialized, `init`
is the way in, and it needs the clone URL of a private repo serving this one project — the
user supplies that URL; never invent one or reuse another project's. If the status says the
engine needs a git repository, that is what it means: there is nothing to report outside a
git working tree. Quarantine lines mean something real was found sitting where a managed
link belongs and was renamed aside, not deleted.

**Syncing is never automatic.** `sync` commits and pushes the store only when the user asks
for it. Point out that `dirty` or `unpushed` is non-zero and offer to sync; never sync as a
side effect of other work.

**New worktrees without an agent.** `init` leaves a runnable copy of the engine in the git
common dir, so links can be restored with no session at all. This line belongs in
worktree-init tooling (worktrunk `pre-start`, a `post-checkout` hook, a Makefile target) —
the guard makes it a silent no-op in projects with no store and outside git repositories:

```sh
E="$(git rev-parse --git-common-dir 2>/dev/null)/lundegaard.engine.sh"; [ -x "$E" ] && "$E" heal --quiet || true
```

**Where to go next.** This command only reports. Ask in prose for the work itself — "set up
artifact management", "adopt `openspec/` into the store", "sync the artifacts", "my links
are broken" — and the `lnd-artifacts` skill takes over, carrying the dialogue rules that
govern each verb. The plugin's README covers the design, the vendored engine and the Codex
wiring in depth.
