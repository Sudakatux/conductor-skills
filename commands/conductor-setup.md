---
name: conductor-setup
description: First-time Conductor setup — get the CLI, connect with conductor create-app, verify
---

Connect the user to a Conductor server using [skills/conductor/references/setup.md](../skills/conductor/references/setup.md#connect-with-conductor-create-app).

Don't skip checks. Specifically:

- Run `sh <skill-dir>/scripts/ensure-cli.sh` (Windows: `ensure-cli.ps1`) and use the `CONDUCTOR_BIN` path it prints for every command. On exit 3, **ask the user before** running it with `--install` (one checksum-verified download to `~/.local/bin`; no sudo, no Node). If it then says that dir is not on PATH, ask once whether to add it to the startup file it names; on a yes run it with `--add-to-path` (Windows: `-AddToPath`) and tell the user to open a new terminal.
- Server: a URL the user named wins. With none and no existing profiles, use Developer Edition (`https://developer.orkescloud.com`) and say so in one line; if profiles exist, ask which. Profile: `developer`, or the host's first label.
- If that profile exists, `whoami` it; when it works, stop here.
- Otherwise tell the user to sign in and click **Approve** in the browser, then **run** `"$CONDUCTOR_BIN" create-app --server <root-url> --profile <name>` yourself (long timeout; no secret is typed or printed).
- On timeout (browser on another machine), give the `?setup=key` link it prints and have the user run interactive `conductor config save --profile <name>` in their own terminal.
- Never ask for credentials in chat, put them in command arguments, read the clipboard, or read `~/.conductor-cli/config-*.yaml`.
- Local OSS only when asked: `conductor server start` and an interactive `localhost` profile (`http://localhost:8080/api`, OSS, no auth).

End with `"$CONDUCTOR_BIN" config list` and `"$CONDUCTOR_BIN" --profile <name> whoami`.
