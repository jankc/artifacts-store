# Tasks — vendor-engine-for-agentless-bootstrap

Read `proposal.md` and `design.md` first — design.md carries the reasoning, the rejected
alternatives (B6 `post-checkout` hook, B7 `install-cli`) and the evidence table. Do not
re-litigate B1/B2 without reading the base design's D2 and D5.

## 1. Vendoring

- [x] 1.1 Resolve the vendored path `<git-common-dir>/lundegaard.engine.sh` alongside `STORE`/`LOCK_DIR` in the store-resolution helper (B1)
- [x] 1.2 Vendor helper: copy the running engine to the vendored path, `chmod +x`, write atomically (temp file + `mv`) so a concurrent worktree-init never sees a half-written script
- [x] 1.3 Version helper: read `^VERSION=` out of the vendored copy by text, not by executing it, so a corrupt copy is still replaceable (B3)

## 2. Verb integration

- [x] 2.1 `init`: vendor after a successful clone + heal; report it as a change; ensure `--dry-run` prints the planned vendoring and writes nothing; ensure the clone-failure cleanup path leaves no vendored engine
- [x] 2.2 `heal`: vendor when the copy is missing, refresh when versions differ, stay silent and change nothing when they match (B3)
- [x] 2.3 `detach`: remove the vendored engine with the links and exclude block; keep the store intact (B5)
- [x] 2.4 `status`: report present/missing and the vendored version, naming both versions on drift; still exit 0 always (B5)

## 3. Documentation

- [x] 3.1 README: add the worktree-init one-liner with its `[ -x "$E" ]` guard to the "Invoking the engine outside a session" section, replacing the `$HOME/.agents/...` guidance as the recommended route; keep the pinned-path table as the explanation of why
- [x] 3.2 README: note that the vendored copy is overwritten on version drift (don't edit it), and that it lives in `.git/` so `git clean` cannot remove it
- [x] 3.3 `SKILL.md`: mention that a project is bootstrapped after `init`, so the skill can answer "how do I get artifacts in a new worktree without starting Claude?"

## 4. Dual-runtime layout (B8/B9)

- [x] 4.1 `git mv SKILL.md skills/lnd-artifacts/SKILL.md` (frontmatter unchanged); add `"skills": "./skills/"` to `.claude-plugin/plugin.json`
- [x] 4.2 Create `.codex-plugin/plugin.json` mirroring name/version/description/author plus an `interface` block modeled on `lnd-quick-commit` in the ai-marketplace repo; keep versions in lockstep with `.claude-plugin/plugin.json`
- [x] 4.3 Update references to the root-skill layout: README Layout/Development sections, `openspec/config.yaml` context line ("one root SKILL.md"), and AGENTS.md's repo description if it names the root skill
- [x] 4.4 Verify both Claude load paths after the move — `claude --plugin-dir <repo>` and the `~/.claude*/skills` symlink hop (`claude -p 'is the lnd-artifacts skill available?'` is enough) — and record the verified outcome in docs/CONTEXT.md §5; if the skills-dir hop no longer resolves, apply the B9 fallback and record that instead

## 5. Verification

- [x] 5.1 Smoke: assert `init` vendors an executable copy whose `--version` matches, and that `--dry-run` does not
- [x] 5.2 Smoke: delete/replace the plugin copy of the engine, run the documented one-liner in a fresh worktree, assert links appear and host porcelain stays clean
- [x] 5.3 Smoke: the one-liner is silent and exits 0 in a storeless repo, outside a git repo, and from a nested subdirectory of a managed worktree
- [x] 5.4 Smoke: version drift (rewrite the vendored `VERSION`) is refreshed by `heal` and reported by `status`; matching versions are a no-op
- [x] 5.5 Smoke: `detach` removes the vendored engine and `heal` restores it; store untouched throughout
- [x] 5.6 Smoke: after vendoring, store root listing is unchanged and `sync` does not commit the engine
