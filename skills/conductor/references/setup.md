# Server Setup

Connect the agent to a Conductor server. Run the preflight once per session,
before the first command that talks to a server (SKILL.md Rule 15).

## Connect with `conductor create-app`

`conductor create-app` has the user sign in from their browser, creates (or
reuses) an application — `default_app` unless `--name <app>` says otherwise —
with an access key, and saves that key as a CLI profile. No key or secret is
typed, pasted or printed, so **the agent runs it**; the user only signs in and
clicks **Approve**.

### 1. Resolve the CLI

```bash
sh <skill-dir>/scripts/ensure-cli.sh          # Windows: powershell -File <skill-dir>\scripts\ensure-cli.ps1
```

- Prints `CONDUCTOR_BIN=<path>` → use that full path for every later
  `conductor` command (`~/.local/bin` is often not on the agent's PATH).
- Exit 3 → no CLI, or one too old to have `create-app`. Ask once (Rule 3), then
  `sh <skill-dir>/scripts/ensure-cli.sh --install`. It downloads the pinned
  release from GitHub, verifies its sha256 and installs to `~/.local/bin`
  (`%LOCALAPPDATA%\Programs\conductor` on Windows). No sudo, no Node, no shell
  startup edits.
- A checksum mismatch: stop and report it.

### 2. Pick the server and profile

| Request says | Server | Profile |
|---|---|---|
| a URL (`connect to https://acme.orkesconductor.com`, a `Conductor server:` line) | that URL | `acme` (host's first label) |
| a profile name that exists | that profile's server | that name |
| nothing, and `conductor config list` shows **no** profiles | `https://developer.orkescloud.com` | `developer` |
| nothing, and profiles exist | ask which one (one question, Rule 14) | — |

Never fall back to `developer` silently: when you use it by default, say
*"Using Developer Edition. Give me a URL to use another Conductor server."*

### 3. Reuse a working profile

```bash
"$CONDUCTOR_BIN" config list                      # names only; never read the YAML
"$CONDUCTOR_BIN" --profile acme whoami
```

Success → skip to the task. A 401/403 or "Profile doesn't exist" → step 4.

### 4. Create the application key

Tell the user: *"Opening your browser to connect to acme.orkesconductor.com —
sign in and click **Approve**."* Then run, with a long timeout (it waits up to
5 minutes):

```bash
"$CONDUCTOR_BIN" create-app --server https://acme.orkesconductor.com --profile acme
# another application name: --name billing-agent   (default: default_app)
# replacing a broken profile non-interactively: add --yes
```

What happens: the CLI listens on `127.0.0.1`, opens
`https://acme.orkesconductor.com/?setup=cli&port=…&state=…&app=default_app`, the
user signs in and approves, the Launch Pad finds or creates that application
(roles `METADATA_MANAGER` + `WORKER`), creates an access key and hands it to the CLI, which saves
`~/.conductor-cli/config-acme.yaml` and checks the key. Output ends with
`✓ Saved profile "acme"`.

### 5. Verify, then do the task

```bash
"$CONDUCTOR_BIN" --profile acme whoami
"$CONDUCTOR_BIN" --profile acme workflow list --json
```

Continue the original request with `--profile acme`. Don't stop at "setup
complete".

### When your command is blocked

A permission prompt the user declines, or an auto-mode safety check, can stop
you from running `create-app` (it creates an access key on the cluster). Don't
retry it, rephrase it, switch to another way of connecting, or carry on with
the task. Reply with the exact command, filled in, for the user to run:

```bash
/Users/me/.local/bin/conductor create-app --server https://acme.orkesconductor.com --profile acme
```

In Claude Code they can type `! <command>` so it runs in the session. End the
turn; when they say **done**, continue at step 5 (`whoami`).

### When the browser can't reach the CLI

`create-app` times out when the browser runs on another machine (SSH, a container,
a cloud agent) or the page can't post back. It prints a fallback: open
`https://<server>/?setup=key`, then the user runs, **in their own terminal**:

```bash
conductor config save --profile acme
```

and enters the server URL (`…/api`), `Enterprise`, `1` (API Key + Secret), and
the key id and secret the page shows. Never ask for those values in chat, never
read the clipboard or the profile YAML. If the server has no Launch Pad
approval page, the user creates the key under **Access Control → Applications**
instead (application `default_app`, roles `METADATA_MANAGER` + `WORKER`).

A pasted secret is compromised: follow SKILL.md Rule 5.

## Local server (OSS)

A local OSS server needs no access key:

```bash
"$CONDUCTOR_BIN" server start
"$CONDUCTOR_BIN" config save --profile localhost   # http://localhost:8080/api, OSS, no auth
"$CONDUCTOR_BIN" --profile localhost workflow list --json
```

Use `--profile localhost` only when the user asks for local.

## Profiles

Profiles live in `~/.conductor-cli/config-<profile>.yaml` and may hold
credentials: discover them with `conductor config list`, never by reading the
files. Add another server any time with `conductor create-app --server <url>`.

The Python fallback script (`scripts/conductor_api.py`) does **not** support
`create-app`; it reads a profile via `--profile <name>` (internally, never printed)
or `CONDUCTOR_SERVER_URL` plus injected credentials.

**Fallback** — only when the CLI cannot be installed at all (see SKILL.md
Rule 3): `export CONDUCTOR_API="<path-to-this-skill>/scripts/conductor_api.py"`
and see [fallback-cli.md](fallback-cli.md).

## Without `create-app`: an explicit URL or environment variables (CI)

For CI, containers and servers that already have credentials injected. Interactive
users on Orkes should use [`conductor create-app`](#connect-with-conductor-create-app).

### Choose and normalize a server

If the user already supplied a server URL or selected a profile, use it
immediately. For an interactive first-time setup, use [`conductor create-app`](#connect-with-conductor-create-app). Otherwise ask the user:

- **Option A** — Start a local server (good for development/testing).
- **Option B** — Connect to an existing remote server.

Don't assume — present both.

**Option A — local server:**

```bash
conductor server start
# custom port:
conductor server start --port 3000
# verify:
conductor server status
```

**Option B — existing server:**

`CONDUCTOR_SERVER_URL` is the API base and must end in `/api`. A UI/root URL with
no path is normalized by appending `/api`; do not append it twice and do not
rewrite a URL that already has a non-root deployment path.

```bash
# https://developer.orkescloud.com/ -> https://developer.orkescloud.com/api
export CONDUCTOR_SERVER_URL="https://developer.orkescloud.com/api"

# For Orkes / Enterprise servers:
export CONDUCTOR_SERVER_TYPE="Enterprise"
```

Examples:

| User supplied | Use |
|---|---|
| `https://developer.orkescloud.com/` | `https://developer.orkescloud.com/api` |
| `https://pg-qa.orkesconductor.com` | `https://pg-qa.orkesconductor.com/api` |
| `https://host.example/api` | unchanged |

### Test connectivity and handle auth

```bash
conductor workflow list
```

If this succeeds without credentials, the server has no auth — it is **OSS** — go to Step 4.

If you get **401 or 403**, the server requires authentication — it is **Enterprise (Orkes)**: set `CONDUCTOR_SERVER_TYPE=Enterprise`. (`python3 "$CONDUCTOR_API" server-info` makes the same check without sending credentials.) The same applies
when the user explicitly says the target requires auth; an unauthenticated probe
is then unnecessary.

Never ask the user to paste a key, secret, or token into chat. Ask them to inject
the variables through their shell, CI secret store, or the application's secure
environment settings. Check only whether the variable names are present; never
print their values and never use `set -x`, `env`, or credential-bearing CLI
arguments.

```bash
# Key + Secret (recommended for Orkes / Enterprise)
# Set securely outside the agent transcript:
#   CONDUCTOR_AUTH_KEY
#   CONDUCTOR_AUTH_SECRET

# Or a pre-existing token
#   CONDUCTOR_AUTH_TOKEN
```

Re-test: `conductor workflow list`

> **Auth behavior:** Orkes exchanges `CONDUCTOR_AUTH_KEY` +
> `CONDUCTOR_AUTH_SECRET` at `POST /api/token`, then sends the returned JWT in
> `X-Authorization`. The CLI, SDKs, and bundled Python fallback perform this
> exchange automatically. An explicit `CONDUCTOR_AUTH_TOKEN` takes precedence.
> The fallback keeps the exchanged token in memory only and never prints it.
> These are **Conductor access** credentials only. LLM-provider keys
> (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, …) live on the Conductor server (on
> Orkes: in cluster integrations — [orkes-integrations.md](orkes-integrations.md)), never
> in the client environment — say so when reporting the connection.

If the user pasted a credential into chat, follow SKILL.md Rule 5: treat it as
compromised, do not use or repeat it, and recommend rotation.

### Verify

```bash
conductor whoami                 # useful on authenticated Enterprise servers
conductor workflow list
```

Report the result to the user. Setup complete.

## Enable agents (only if the user will build or call agents)

```bash
export CONDUCTOR_API="<path-to-this-skill>/scripts/conductor_api.py"   # used with the CLI for agent verbs it lacks
conductor agent list                              # table or "No agents found." = agent runtime on
python3 "$CONDUCTOR_API" providers-status          # which LLM providers have keys on the SERVER
```

- `conductor server start` already passes `--conductor.integrations.ai.enabled=true --agentspan.embedded=true`, so a local server is ready.
- A remote server needs `conductor.integrations.ai.enabled=true` (+ `agentspan.embedded=true`, `spring.main.allow-bean-definition-overriding=true`) and provider keys in **its** environment (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, …). Keys never go in agent code.
- **Orkes (Enterprise):** LLM providers are cluster **integrations**, not server env vars — list them with `python3 "$CONDUCTOR_API" integration-list --category AI_MODEL` and create/extend them per [orkes-integrations.md](orkes-integrations.md). `conductor doctor` only inspects local env vars, not the cluster's integrations.
- MCP / OpenAPI tool discovery is outbound deny-all: `conductor.ai.outbound.allowed-origins=https://tools.example.com` (`conductor.ai.outbound.allow-private-networks=true` for localhost in dev).
- OSS secrets: `${workflow.secrets.NAME}` resolves from `CONDUCTOR_SECRET_NAME` env vars on the server (default `conductor.secrets.type=env`).
- Symptom of a disabled runtime: an `AGENT` task with `agentType: "conductor"` fails with `AGENT requires 'agentUrl'`.

Then continue with [agents.md](agents.md) and [agent-sdks.md](agent-sdks.md).

## Additional named profiles (manual)

Prefer `conductor create-app --server <url> --profile <name>`. The manual form:

The current CLI saves profiles interactively. This is deliberate: putting
`--auth-key` or `--auth-secret` values in a command would expose them in shell
history, process listings, and agent/tool transcripts.

```bash
conductor config save --profile dev
conductor config save --profile prod
```

Run those commands in the user's terminal and answer the interactive prompts for
server URL, server type, and credentials. Do not send the secret through chat or
an agent-executed command. Profiles live in
`~/.conductor-cli/config-<profile>.yaml`; treat the files as sensitive.

List profiles and use one without reading its file:

```bash
conductor config list
conductor --profile dev whoami
conductor --profile dev workflow list --json
```

## Updating this skill

If the user asks to upgrade or you suspect this skill is outdated:

```bash
# macOS / Linux
curl -sSL https://conductor-oss.github.io/conductor-skills/install.sh | bash -s -- --all --upgrade

# Windows
irm https://conductor-oss.github.io/conductor-skills/install.ps1 -OutFile install.ps1; .\install.ps1 -All -Upgrade
```
