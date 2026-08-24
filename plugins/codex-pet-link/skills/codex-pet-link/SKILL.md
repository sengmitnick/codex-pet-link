---
name: codex-pet-link
description: Install, start, stop, diagnose, or change privacy settings for the local Codex Pet Link BLE helper used by a Rokid cyber pet.
---

# Codex Pet Link

Use the installed `codex-pet-link` command for service operations. Do not create a second helper process when the launchd service is already loaded.

## Commands

- `codex-pet-link status --json`: inspect whether the helper is loaded.
- `codex-pet-link doctor --json`: diagnose installation, sessions, and service state.
- `codex-pet-link ensure`: start the singleton service if needed.
- `codex-pet-link restart`: restart it after an upgrade or Bluetooth failure.
- `codex-pet-link privacy titles-off`: send status and phase without a task title.
- `codex-pet-link privacy titles-on`: restore short task titles.

When the command is missing, follow the repository `INSTALL.md`. After installing or updating the plugin, start a new Codex task so `SessionStart` and task activity hooks are loaded. Never remove or edit `~/.codex/sessions` while diagnosing this helper.
