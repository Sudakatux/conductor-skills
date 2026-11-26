---
name: conductor-setup
description: First-time Conductor setup — get the CLI, pick the server and its flavor, connect, verify
---

Connect the user to a Conductor server by following [skills/conductor/references/setup.md](../skills/conductor/references/setup.md#connect-to-a-server) step by step. Don't skip checks. It covers the CLI, the server choice, the OSS-or-Orkes probe, connecting (a profile, injected credentials, `create-app` on Developer Edition, or the manual key path), the `create-app` failure codes and the fallbacks.

Hold to these while you do:

- Get the CLI per SKILL.md Rule 3 (on PATH, else `npx --yes …`, a global install only after asking). Any `conductor` will do until you need `create-app`; check it right before (Rule 3.5).
- Find the flavor before connecting. OSS needs no auth and no `create-app`.
- `create-app` connected you only on exit 0 and a `✓ Saved profile` line. Never claim success otherwise. On `no_launchpad`, use the manual key path; don't retry.
- If a permission check blocks `create-app`, don't retry or work around it. Give the user the exact command, end the turn, and wait for **done**.
- Never ask for credentials in chat or read `~/.conductor-cli/config-*.yaml` (SKILL.md Rule 5).

End with `conductor config list` and `conductor --profile <name> whoami` (or `whoami` with the env vars, or `workflow list` on OSS).
