# plugin-integration — delta spec

## Purpose

Restructures the plugin to the dual-runtime layout required by the ai-marketplace
conventions: the skill moves under `skills/`, and a Codex mirror manifest joins the
Claude one. Packaging only — no verb or hook behavior changes.

## ADDED Requirements

### Requirement: The skill lives in the dual-runtime layout

The plugin's single skill SHALL live at `skills/lnd-artifacts/SKILL.md` and the
repository SHALL NOT carry a root `SKILL.md`. The skill SHALL remain loadable in Claude
Code both via `claude --plugin-dir <repo>` and via a skills-directory symlink install.

#### Scenario: Loading from a local checkout after the move

- **WHEN** a session starts with `claude --plugin-dir <path-to-repo>`
- **THEN** the `lnd-artifacts` skill and both hooks are active, exactly as before the
  move

#### Scenario: No root skill remains

- **WHEN** the repository root is listed
- **THEN** it contains no `SKILL.md`; the only skill definition is
  `skills/lnd-artifacts/SKILL.md`

### Requirement: The plugin ships a Codex mirror manifest

The plugin SHALL carry `.codex-plugin/plugin.json` alongside
`.claude-plugin/plugin.json`. The two manifests SHALL agree on `name`, `version`, and
`description`, SHALL both declare the skills directory explicitly, and the Codex
manifest SHALL additionally carry an `interface` block (display name, short and long
description, developer name, category).

#### Scenario: Manifests agree

- **WHEN** both manifests are read
- **THEN** `name`, `version`, and `description` are identical and both declare
  `"skills": "./skills/"`
