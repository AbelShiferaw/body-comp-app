---
name: writing-skills
description: Use when creating, editing or moving a reusable skill, or when a procedure has been repeated across projects and should become a shared skill in the agent-skills repo.
---

# Writing shared skills

Shared skills live in the `agent-skills` GitHub repo, grouped into plugins by topic.
Project repos receive copies through the sync workflow, so edit the source here, never the copy in a project.

## Where a skill goes

- Useful in more than one project: `agent-skills/plugins/<topic>/skills/<skill-name>/SKILL.md`.
  Pick an existing plugin (`core`, `mobile-dev`, ...) or add a new one, and list it in `.claude-plugin/marketplace.json`.
- Only useful in one project: that project's `.claude/skills/<skill-name>/SKILL.md`, committed to the project repo.
- Never put a skill only in `~/.claude/skills`: cloud sessions and other machines cannot see it.

## Writing the skill

1. Folder name and `name:` are the same kebab-case slug. Do not use "claude" or "anthropic" in it.
2. `description:` is one sentence that says *when* to use the skill. It decides whether the skill loads, so name the triggers (tools, file types, tasks).
3. Keep `SKILL.md` short (under ~300 lines). Put long reference material in sibling files and link them by relative path.
4. Write steps an agent can follow without the original conversation: commands, file paths, what "done" looks like.
5. No secrets, tokens, personal data or machine-specific paths.

## Shipping a change

1. Bump `version` in the plugin's `.claude-plugin/plugin.json` (installed copies only update on a version bump).
2. Run `claude plugin validate . --strict` from the repo root. CI runs the same check.
3. Open a PR. After merge, project repos pick it up on their next sync run (weekly, or run the "Sync shared skills" workflow by hand).
