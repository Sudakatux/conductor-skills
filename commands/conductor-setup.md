---
name: conductor-setup
description: First-time Conductor setup — get the CLI, connect with conductor create-app, verify
---

Connect the user to a Conductor server by following [skills/conductor/references/setup.md](../skills/conductor/references/setup.md#connect-with-conductor-create-app) step by step. Don't skip checks. It covers the server and profile choice, the `create-app` failure codes and the fallbacks.

Hold to these while you do:

- Use the `CONDUCTOR_BIN` path `ensure-cli.sh` prints for every command, and ask before it installs anything (SKILL.md Rule 3).
- You're connected only on exit 0 and a `✓ Saved profile` line. Never claim success otherwise.
- If a permission check blocks `create-app`, don't retry or work around it. Give the user the exact command, end the turn, and wait for **done**.
- Never ask for credentials in chat or read `~/.conductor-cli/config-*.yaml` (SKILL.md Rule 5).

End with `"$CONDUCTOR_BIN" config list` and `"$CONDUCTOR_BIN" --profile <name> whoami`.
