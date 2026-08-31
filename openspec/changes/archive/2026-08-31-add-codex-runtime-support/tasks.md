# Tasks — add-codex-runtime-support

Depends on `vendor-engine-for-agentless-bootstrap` being implemented first: the skill
must already live at `skills/lnd-artifacts/SKILL.md` and the vendored engine must exist
for resolution step 2 to mean anything. Read that change's design (B1–B9) and this
change's design (C1–C4) before starting.

## 1. Skill text

- [x] 1.1 Replace the `ENGINE="${CLAUDE_PLUGIN_ROOT}/…"` line with the C1 resolution rule: plugin root when `CLAUDE_PLUGIN_ROOT` is set, else `$(git rev-parse --git-common-dir)/lundegaard.engine.sh`, else ask the user for the path (never guess)
- [x] 1.2 Add the session-start substitute rule: run `status` before starting artifact work; run `heal` when it reports link damage (C2)
- [x] 1.3 Add the stop substitute rule: after a task that edited artifacts, report unsynced state and suggest `sync`; restate that `sync` is never run unasked, adjacent to the nudge so they read as one rule (C2)
- [x] 1.4 Extend the initialization dialogue for the Codex first-init case: no store + no `CLAUDE_PLUGIN_ROOT` → ask for the engine/checkout path (C4)

## 2. Documentation

- [x] 2.1 README: add a "Codex" section — discovery wiring through `~/.agents/skills` (concrete symlink commands, mirroring the existing Claude hop examples), the degraded mode (no auto-heal, no Stop warning), and its compensations (vendored one-liner + the skill's status/sync rules)
- [x] 2.2 docs/CONTEXT.md §5: append the verified Codex facts from task 3.1 (search paths, `skills/` descent or not, any skill-root env var), with the Codex version they were checked against

## 3. Wiring and verification

- [x] 3.1 Determine Codex's actual skill search paths empirically (`codex --help`, current Codex docs, or a probe session) — do not assume; note whether Codex descends into a plugin's `skills/` dir or needs the skill dir linked directly (C3 fallback)
- [x] 3.2 Wire the user-level hop on this machine per the verified facts (e.g. `~/.codex/skills/lnd-artifacts` → `~/.agents/skills/lnd-artifacts`, or the C3 fallback shape)
- [x] 3.3 Verify in a real Codex run (non-interactive `codex exec` is fine): the skill is visible, and in a disposable initialized fixture it can drive `status` through the vendored engine; record how this was verified in docs/CONTEXT.md §5
- [x] 3.4 Verify Claude is unregressed: `claude -p` with `--plugin-dir` still resolves the engine via `CLAUDE_PLUGIN_ROOT` (resolution step 1), and the smoke suite still passes
- [x] 3.5 Confirm `hooks/hooks.json` and both hook scripts are byte-identical to before this change (hooks are explicitly untouched)
