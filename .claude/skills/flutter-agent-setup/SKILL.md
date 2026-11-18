---
name: flutter-agent-setup
description: Use when starting or onboarding a Flutter/Dart app repo, to wire up the Dart & Flutter MCP server, flutter_scene agent skills and the shared-skills sync so coding agents can run and inspect the app.
---

# Flutter agent setup

Run these in the project repo. Ask before installing anything on the user's machine.

## 1. Dart & Flutter MCP server

Needs Dart 3.9+ / a current Flutter SDK. Add it to the project's `.mcp.json` so every agent gets it:

```json
{
  "mcpServers": {
    "dart": { "command": "dart", "args": ["mcp-server"] }
  }
}
```

Or for one machine only: `claude mcp add --transport stdio dart -- dart mcp-server`.
Docs: https://docs.flutter.dev/ai/mcp-server

## 2. 3D (only if the app uses flutter_scene)

`flutter_scene` (MIT) ships agent skills: run `dart run flutter_scene:skills` after adding the package, and commit what it generates under `.claude/skills/`.

## 3. Shared skills

Copy `templates/project/sync-shared-skills.yml` from the `agent-skills` repo into `.github/workflows/` and list the plugins the project wants (for an app: `core mobile-dev`). Run it once by hand from the Actions tab.

## Done when

- `dart` MCP tools appear in a Claude Code session in this repo.
- `.claude/skills/` contains the synced shared skills and a `.shared-skills-manifest` file.
