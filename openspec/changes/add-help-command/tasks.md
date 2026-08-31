# Tasks — add-help-command

Read design.md (H1–H5) first, and C1 in `add-codex-runtime-support/design.md` before
touching task 2.1. Task 1.2 gates everything else: if `${CLAUDE_PLUGIN_ROOT}` is not
substituted inside a command's bash-injection block, H2's fallback applies and tasks
3.x change shape.

Archive order matters — see H5: `vendor-engine-for-agentless-bootstrap` and
`add-codex-runtime-support` must be archived before this change.

## 1. Verify the mechanics before building on them

- [x] 1.1 Confirm a plugin `commands/<name>.md` surfaces as `/lnd-artifacts:help` — create a stub `commands/help.md`, `/reload-plugins`, and check the `/` menu shows the namespaced name
- [x] 1.2 Confirm `${CLAUDE_PLUGIN_ROOT}` is substituted inside a ` ```! ` bash-injection block in that stub (echo the token and inspect the injected output). If it is not, fall back to `${CLAUDE_SKILL_DIR}`-relative resolution, and if that also fails, to H2's `allowed-tools` alternative — record which one was used
- [x] 1.3 Confirm `disable-model-invocation: true` keeps the stub out of automatic loading: ask in prose for artifact work and check the `lnd-artifacts` skill triggers instead

## 2. Skill engine resolution (H4)

- [x] 2.1 Replace the `${CLAUDE_PLUGIN_ROOT:+…}` shell test in `skills/lnd-artifacts/SKILL.md` with `ENGINE="${CLAUDE_PLUGIN_ROOT}/scripts/lnd-artifacts.sh"` guarded by `[ -x "$ENGINE" ]`, keeping the vendored copy as step 2 and ask-the-user as step 3
- [x] 2.2 Reword step 1's prose so it no longer says "when `CLAUDE_PLUGIN_ROOT` is set" — the runtime substitutes the path into the text; the shell never reads the variable
- [x] 2.3 Reword initialization-dialogue step 0 the same way: the Codex first-init trigger is an unsubstituted step-1 path plus no vendored engine, not an unset variable

## 3. The command

- [x] 3.1 Write `commands/help.md` frontmatter: `description` naming the plugin's purpose, `disable-model-invocation: true`
- [x] 3.2 Add the injection block — resolve the engine per H2 (`[ -x ]` chain, `2>/dev/null` on the git call), then run `status` and `--help`, each guarded so a missing engine or missing repo prints a short explanatory line instead of a raw error — **shipped as two exactly-allowlisted engine invocations with `|| echo` guards instead of a shell resolution chain: injected commands pass a static permission check that rejects unanalyzable shell, so the `[ -x ]`/`$(git …)` chain could only run under a blanket `Bash` grant (see docs/CONTEXT.md §5a, 2026-08-03)**
- [x] 3.3 Write the body: what the plugin is in two sentences, how to read the injected `status`, the "`sync` is never run unasked" rule, the worktree-init one-liner, and the handoff sentence pointing at the skill for real work and the README for depth
- [x] 3.4 Verify the body restates no skill rule beyond the sync one (H3) and hand-writes no verb table — the verb list comes from the injected `--help`

## 4. Verify against the spec scenarios

- [x] 4.1 Initialized project: `/lnd-artifacts:help` shows that project's real `status` output and the engine's verb list
- [x] 4.2 Git repo with no store: says no store is set up, explains `init` needs a user-supplied remote URL, does not error and does not ask where the plugin lives
- [x] 4.3 Outside a git working tree: verbs and guidance still shown, no raw git error as the answer
- [x] 4.4 Read-only: capture the store, symlinks and `info/exclude` before and after an invocation in a fixture and diff them — nothing changed
- [x] 4.5 Claude unregressed after 2.1: a session resolves the engine to the plugin's `scripts/lnd-artifacts.sh` (step 1), and `./scripts/smoke.sh` passes
- [x] 4.6 Codex unaffected: no help command registered, the skill still resolves to the vendored engine in an initialized fixture, both manifests byte-identical to before this change

## 5. Documentation

- [x] 5.1 README: add `commands/help.md` to the Development layout listing and mention `/lnd-artifacts:help` where the plugin's usage is introduced
- [x] 5.2 docs/CONTEXT.md §5a: append the five verified facts from design.md's Context, dated, with how each was checked — including that `CLAUDE_PLUGIN_ROOT` is absent from the Bash tool environment but substituted into skill/command text
- [x] 5.3 docs/CONTEXT.md §5b: correct the sentence claiming the `${CLAUDE_PLUGIN_ROOT:+…}` test "is a reliable runtime discriminator" — the variable is absent from the agent's shell in every runtime, so the test is constant-empty and discriminates nothing; without this fix §5a and §5b contradict each other after 5.2
- [x] 5.4 AGENTS.md: update the one-line plugin description so it names the command alongside the skill, script and hooks
