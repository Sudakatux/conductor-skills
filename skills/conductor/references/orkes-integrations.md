# Orkes Integrations — AI Providers, Models and Access

On **OSS** Conductor an LLM provider is enabled by putting its key in the server's environment (`OPENAI_API_KEY`, …) and `llmProvider` is the provider name (`openai`). On **Orkes Conductor** (Enterprise — the server **requires auth**; check with `python3 "$CONDUCTOR_API" server-info`, SKILL.md Rule 17) that is not how it works: every provider is a named **integration** on the cluster, every model must be **registered under that integration**, and the calling application needs **access** to it. Skip any of the three and `LLM_*` tasks fail even though the workflow JSON is valid.

| Concept | What it is | Where it shows up in a task |
|---|---|---|
| Integration (provider) | A named, credential-backed connection, e.g. `openai-prod` of type `openai` | `llmProvider: "openai-prod"` — the **integration name**, not the type |
| Model (integration resource) | An exact provider model id registered under the integration, e.g. `gpt-4o-mini` | `model: "gpt-4o-mini"` |
| Access | Permission for an application / group / role on the integration | none — missing access surfaces as a 403 / access error at run time |

A `conductor` CLI new enough to pass `conductor integration add --help` (SKILL.md Rule 3.5) has `conductor integration add | list | models | add-model`. `integration add` asks for secrets with a **hidden prompt**, so the **user** runs it in their own terminal (§2); never the agent. Everything else here uses the bundled script (`conductor doctor` only checks *local* env vars, nothing on the cluster): `export CONDUCTOR_API="<path-to-this-skill>/scripts/conductor_api.py"`. It authenticates from `CONDUCTOR_SERVER_URL` + `CONDUCTOR_AUTH_KEY` / `CONDUCTOR_AUTH_SECRET`, or from a saved CLI profile with `--profile <name>` (the script reads the profile itself and never prints it — you still never open the YAML). Every `*-env` flag takes an environment variable **name** (`OPENAI_API_KEY`), never `$OPENAI_API_KEY` or the value.

## 1. Check what exists — before writing any LLM task for Orkes

```bash
python3 "$CONDUCTOR_API" --profile <p> integration-list --category AI_MODEL   # what this application can see
python3 "$CONDUCTOR_API" --profile <p> model-list --provider <integration>    # models under one integration
```

The list shows only integrations **shared with this application** (the
`default_app` application `conductor create-app` creates, or whichever key the
profile holds). An empty list does not mean the cluster has none.

- A suitable integration **and** an enabled model are visible → use their names
  (`llmProvider` = integration name, `model` = exact id) and tell the user which.
- The integration is visible but lacks the model → `model-save --provider <integration> --model <id>`
  (any signed-in identity may add a *new* model). If that returns 403, use §2.
- Nothing suitable is visible → §2. The provider key must come from the user,
  through a hidden prompt — never chat, command arguments, or an environment
  variable exported just for the agent. Only when the user says the key is
  **already** in the environment (CI, an admin key) use §3's script route.

## 2. Missing integration — the user creates it

The `default_app` application `conductor create-app` creates has `METADATA_MANAGER`
(+ `WORKER`), so it may create integrations. What it must not do is see the
provider key, so the **user** types it.

1. **Pick the provider and model.** From the prompt ("use Claude", "with
   GPT-4o"); otherwise ask once: *"Which LLM provider should this use —
   Anthropic, OpenAI, …?"* Map it to the integration type (`anthropic`,
   `openai`, `azure_openai`, `vertex_ai`, `aws_bedrock_anthropic`, `mistral`,
   …; `integration-defs --category AI_MODEL` lists them). Pick the model id as in
   §3 (current, from the provider's models page — not from memory).

2. **Give the user the exact command, then stop and wait.** This message is
   the one thing the user must act on, so it must contain the **complete,
   copy-pasteable command** in its own fenced code block — never "run the
   integration add command", never "the command above", never placeholders.
   First check `conductor integration add --help` (SKILL.md Rule 3.5: too old →
   ask, then update). Fill in every value: the exact `conductor` command you use
   (with the npx prefix if that's how it runs), the session's profile, the type and the exact model id. Send it
   as plain text in your reply (not only inside a tool call, a summary or a
   sub-agent's message), like this:

   > I need an Anthropic integration on acme before I can build this. In a
   > terminal of your own (not here), run:
   >
   > ```bash
   > conductor --profile acme integration add --type anthropic --model claude-sonnet-4-6
   > ```
   >
   > It asks for your Anthropic API key without showing it, checks the key,
   > creates the integration and adds claude-sonnet-4-6. Reply **done** when
   > it prints ✓ (or paste its error).

   Notes:
   - Never run it yourself: it needs the user's terminal (it refuses without
     one), and the key must not pass through you.
   - Other types use the same command; it asks for each field the server
     defines (Bedrock connection type, region, role ARN; Vertex service-account
     file path; Azure endpoint). Preset known non-secret values in the command
     with `--set field=value` so the user types less; secrets are refused there.
   - The application owns what it creates. Add `--share-with <their email>`
     only when you know it and the user wants to see it in the UI.

3. **End your turn and wait for the user.** Don't start a background poll and
   carry on, and don't build the workflow meanwhile — it depends on the
   integration's name and the user may need help with the command. When they
   reply **done** (or paste output), confirm:

   ```bash
   python3 "$CONDUCTOR_API" --profile <p> integration-wait --type anthropic --model claude-sonnet-4-6 --timeout 30
   ```

   - `{"ready": true, "llmProvider": "<name>", "model": "<id>"}` → use those
     names and carry on with the original task.
   - Exit 3 (`ready: false`) → read `next` and any output they pasted, say
     what's missing in one line, repeat the exact command (or the fix), and
     wait again.
   - Their output shows HTTP 403 → step 4.

4. **Fall back to manual steps in the UI** when the user has no terminal on
   the machine that holds the profile (a cloud or web agent, a remote
   container), prefers the UI, or `integration add` reports **HTTP 403** (the
   application lacks the role — e.g. it was approved before the role change:
   on Developer Edition, with the user's OK, rerun `conductor create-app --yes`
   (same `--server`, `--profile`; without `--yes` it fails `profile_exists`) and
   **Approve**; otherwise use the UI). Don't generate or guess a link to a UI page — describe the steps in
   words, naming the cluster the profile points to (e.g.
   acme.orkesconductor.com) and the profile's application:

   > In the Conductor UI on **acme.orkesconductor.com**:
   > 1. Go to **Integrations → New Integration → Anthropic**, enter your API key and save.
   > 2. Open that integration and **Add Model** → **claude-sonnet-4-6**.
   > 3. Share it with the **default_app** application: **Access Control → Applications → default_app → Integration** tab, and turn on that model. <!-- share-step: drop once the integrations page shares with the calling application itself -->
   >
   > Reply **done** when you've finished.

   Then end your turn and wait as in step 3.

5. **Stop** when neither works — `integration-wait` exits 4, or the user can't
   create integrations in the UI either (no **New Integration** button, a
   permission error): *"Neither the default_app application nor your account
   can create integrations on this cluster. Ask an admin to add an Anthropic
   integration with the model claude-sonnet-4-6 and share it with the
   default_app application, then tell me and I'll continue."*

Never ask for the key in chat. If the user pastes one anyway, Rule 5 applies
(treat it as compromised, don't use it, recommend rotating it).

## 3. Models

### Choosing the model

Pick the model id from the provider's **current** models page (WebSearch /
WebFetch, e.g. "Anthropic models overview") — never from memory; they change
monthly. Use the latest suitable one as the workflow's default `model`, and say
which in one line. The id must exactly match the provider's
(`claude-sonnet-4-6`, `gpt-4o-mini`). For a vector DB the "model" is the index
name. Azure OpenAI models are the user's *deployment names*: ask for them.
Bedrock ids must also be enabled in the user's AWS account/region.

### With admin or CI credentials only: create the integration from the script

`integration-save` works only for an identity allowed to create integrations
(an admin, or an application an admin gave `METADATA_MANAGER`), and only with
the key already in that process's environment (a CI secret store). It is never
the fix for an interactive Launch Pad / `conductor create-app` user — that's §2.

```bash
python3 "$CONDUCTOR_API" integration-save --name openai-prod --type openai \
  --config-env api_key=OPENAI_API_KEY --description "OpenAI for prod workflows"
```

| `--type` | Configuration keys (secret ones via `--config-env`) |
|---|---|
| `openai` | `api_key`; optional `endpoint`, `organizationId` |
| `anthropic` | `api_key`, `endpoint` (e.g. `https://api.anthropic.com`); optional `version`, `betaVersion`, `completionsPath` |
| `azure_openai` | `api_key`, `endpoint` |
| `vertex_ai` / `vertex_ai_gemini` | `projectName`, `environment` (region), `publisher`, `file` (service-account JSON) |
| `aws_bedrock_anthropic` / `aws_bedrock_cohere` / `aws_bedrock_titan` | `connectionType`, `region`; `ACCESS_KEY` → `user`, `api_key`; `EXTERNAL_ROLE` → `roleArn`, `externalId` |
| `mistral`, `cohere`, `grok`, `perplexity`, `huggingface` | `api_key` (+ `endpoint` where the provider needs one) |
| `ollama` | `endpoint` |
| Vector DBs (`--category VECTOR_DB`): `pineconedb`, `weaviatedb`, `pgvectordb`, `mongovectordb` | provider-specific; run `integration-defs --category VECTOR_DB` |

Secret-looking fields (`*key*`, `*secret*`, `*token*`, `*password*`, `*credential*`, `file`) are only accepted via `--config-env`, e.g. Vertex `--config-env file=VERTEX_SA_JSON` where the variable holds the service-account JSON. For any type not listed, or to confirm field names on this cluster, run `python3 "$CONDUCTOR_API" integration-defs --category AI_MODEL`. The `type` cannot be changed after creation. `integration-save` refuses an existing `--name`: `--overwrite` replaces the **whole** configuration, so pass every secret field again with `--config-env` or it is cleared.

Registering models from the script (same admin/CI identity, key in the environment):

When creating an AI integration from the script, register **every model the key can use**, not just the one the current workflow needs, so later workflows and agents don't hit "model not found". Discover models live — never from memory, they change monthly.

**Providers with a model-list API** (`openai`, `anthropic`, `mistral`, `cohere`, `grok`, `ollama`, and Gemini-API keys via `--source gemini`): ask the provider with the same key, then register the lot.

```bash
python3 "$CONDUCTOR_API" model-sync --provider openai-prod --type openai --key-env OPENAI_API_KEY --dry-run   # preview
python3 "$CONDUCTOR_API" model-sync --provider openai-prod --type openai --key-env OPENAI_API_KEY             # register all
```

`model-sync` calls the provider's own list endpoint (the key is sent only there), skips models already registered and fine-tunes (`--include-fine-tunes` to keep them), registers the rest, and reports `added` / `failed`. The integration must exist first. `--include` / `--exclude` take regexes when the user wants a subset (e.g. `--exclude '-[0-9]{4}-[0-9]{2}-[0-9]{2}$'` drops dated snapshots). `provider-models` prints the same list without touching Orkes. Custom gateways and Ollama hosts: `--endpoint <url>`.

**Providers without one** (`azure_openai` — models are the user's *deployment names*, ask for them; `aws_bedrock_*`, `vertex_ai*`, `perplexity`, `huggingface`): use **WebSearch / WebFetch** on the provider's official models page (e.g. "Amazon Bedrock supported models", "Vertex AI model garden Gemini models", "Perplexity API models") for the current model ids, show the list, then `model-save` each one. Bedrock ids must also be enabled in the user's AWS account/region.

**Either way, also look up what's current**: WebSearch / WebFetch the provider's models or deprecations page and tell the user which registered models are the latest (and which are deprecated), and use the latest suitable one as the workflow's default `model` — not a model remembered from training.

Single model: `python3 "$CONDUCTOR_API" model-save --provider openai-prod --model gpt-4o-mini`. The id must exactly match the provider's. For a vector DB the "model" is the index name. `--max-tokens` caps a model; `--disabled` keeps it registered but unusable.

## 4. Grant access

- The identity that **created** the integration gets full access automatically. With `conductor integration add` (§2) that is the profile's application (`default_app` unless `conductor create-app --name` chose another), so its workflows can use it at once; the user sees it in the UI only if it was shared back (`--share-with`) or they are an admin. When the user creates it in the UI (§2 step 4, manual steps), the user owns it, so it must be **shared** with the application: **Access Control → Applications → default_app → Integration** tab, toggle the models. <!-- share-step -->
- Other groups / roles / users: `python3 "$CONDUCTOR_API" grant-access --subject-type group --subject-id <group> --target-id openai-prod --access READ,EXECUTE` (`--target-type` defaults to `INTEGRATION_PROVIDER`).
- Don't guess an API subject id for an application; share it in the UI and confirm with `integration-wait` (it only succeeds once the application can see the model).
- Check: `python3 "$CONDUCTOR_API" access-list --target-id openai-prod`.

## 5. Use it in a workflow

```json
{
  "name": "summarize", "taskReferenceName": "summarize_ref", "type": "LLM_CHAT_COMPLETE",
  "inputParameters": {
    "llmProvider": "openai-prod",
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "message": "Summarize: ${workflow.input.text}"}]
  }
}
```

**Agents:** a Conductor Agent's `model="<provider>/<model>"` compiles to `llmProvider: "<provider>"`, so on Orkes the prefix must be an **integration name** with that model registered (e.g. `openai/gpt-4o-mini` → integration `openai`). Agent instructions travel in `messages`, so §6's template check doesn't apply to them.

Same rule for every `LLM_*` task; for `LLM_INDEX_TEXT` / `LLM_SEARCH_INDEX`, `vectorDB` is the vector integration name, `index` a registered index, and `embeddingModelProvider` / `embeddingModel` an AI integration name + registered embedding model. Prompt text in `instructions` / `promptName` / image `prompt` follows §6 — a saved template by name, or `allowRawPrompts: true`.

Verify end to end with a one-task test workflow before wiring the real one.

## 6. Prompts — saved templates by name (raw text needs `allowRawPrompts`)

On Enterprise the server treats a task's prompt field as the **name of a saved prompt template** and checks that the template is associated with the task's exact `integration:model`. Literal text there fails at run time with *"Prompt \<text\> is not associated with integration \<name\> and model \<model\>"* — unless the task sets `allowRawPrompts: true`.

| Field | Enterprise behaviour |
|---|---|
| `LLM_CHAT_COMPLETE.instructions` | template name; raw text needs `allowRawPrompts: true` |
| `LLM_TEXT_COMPLETE.promptName` (also `prompt`) | template name; raw text in `promptName` needs `allowRawPrompts: true` |
| `GENERATE_IMAGE.prompt` | raw text needs `allowRawPrompts: true` (or a template name) |
| `messages[]`, `GENERATE_AUDIO.text`, `GENERATE_VIDEO.prompt` | not gated |

**Default: put the prompt in a template and reference it by name.** Templates are versioned, reviewable, reusable across workflows, and the association doubles as an allow-list of the models a prompt may run on.

1. Write the template text to a file. Placeholders are `${name}`.
2. Save it and associate it with **every** `integration:model` the tasks use:
   `python3 "$CONDUCTOR_API" prompt-save --name ticket_summary --template-file ticket_summary.txt --model openai-prod:gpt-4o-mini --model openai-prod:gpt-4o`
   (re-run with the full `--model` list to add a model; `prompt-list` / `prompt-get` show what exists and its `variables`).
3. Reference it by name and pass runtime values through `promptVariables` (real Conductor expressions go **here**):

```json
{
  "name": "summarize", "taskReferenceName": "summarize_ref", "type": "LLM_CHAT_COMPLETE",
  "inputParameters": {
    "llmProvider": "openai-prod", "model": "gpt-4o-mini",
    "instructions": "ticket_summary",
    "promptVariables": {"ticket": "${workflow.input.ticket_text}", "tone": "brief"},
    "messages": [{"role": "user", "message": "${workflow.input.ticket_text}"}]
  }
}
```

`LLM_TEXT_COMPLETE` uses `"promptName": "ticket_summary"` the same way.

With `jsonOutput: true` on OpenAI models, the word **JSON must also appear in a `messages` entry** (e.g. *"…reply in JSON. Ticket: ${workflow.input.ticket}"*): the template is sent as the Responses API's `instructions`, which OpenAI's JSON-mode check ignores, so a template that says "JSON" alone fails with *"Response input messages must contain the word 'json'…"*.

**`${var}` placeholders only work inside a saved template.** In workflow JSON, `${...}` is a Conductor expression: `"instructions": "Summarize ${ticket}"` fails registration (*"taskReferenceName: ticket … is not defined in workflow definition"*). Inline text must use real expressions (`${workflow.input.ticket}`), not template placeholders.

**Raw text instead — only when the user explicitly asks for inline prompts** (never as your own default): keep the literal text and add `"allowRawPrompts": true` to the task. When you build a template, mention this alternative in one line. It is ignored on OSS, so it is safe in workflows that run on both.

OSS has no prompt registry: prompts are always literal text and `prompt-*` commands are refused.

## 7. Errors

| Symptom on Orkes | Cause | Fix |
|---|---|---|
| LLM task fails with integration / provider not found | `llmProvider` is the provider *type* (`openai`) or a typo, not an existing integration name | `integration-list`, use the exact name |
| Model not found / not enabled | Model not registered under that integration, or `--disabled` | `model-save`; on 403, the user adds it in the UI (§2) |
| 403 / access denied on the LLM task | The running application has no access to the integration | The user shares it with the application (§4), then `integration-wait` |
| "this server does not require auth, so it is OSS" / integration endpoints 404 | Server is OSS — integration APIs don't exist there (a 404 for one name on Enterprise = that integration doesn't exist) | OSS uses server env keys — see [setup.md](setup.md) Step 5 |
| *"Prompt … is not associated with integration … and model …"* | Literal text in `instructions` / `promptName` / image `prompt` without `allowRawPrompts`, or the template isn't associated with that `integration:model` | Use a template name and `prompt-save … --model <integration>:<model>`, or set `allowRawPrompts: true` (§6) |
| Registration fails: *"taskReferenceName: x … is not defined"* for prompt text | `${x}` template placeholder written inline in the workflow | Move the text into a saved template, or use a real expression (§6) |
| `integration-list` returns 403 / `integration-wait` exits 4 | This application can't list integrations | Stop: ask an admin to create and share the integration (§2 step 5) |
| `conductor integration add`: HTTP 403 | The profile's application lacks `METADATA_MANAGER` (approved before the role change, or the server doesn't allow it) | On Developer Edition, with the user's OK, re-run `conductor create-app --yes --server <url> --profile <p>` → **Approve**; elsewhere (or instead) the manual UI steps (§2 step 4) |
| `integration-save` returns 403 | This identity can't create integrations | §2: `conductor integration add` in the user's terminal, or the manual UI steps |
| `integration-save`: "already exists" | Name taken | Use it (add models with `model-save`), or, with admin/CI credentials, `--overwrite` with all secrets re-supplied |
| A `*-env` flag says the variable isn't set | Shell expanded `$VAR` into a value, or the variable isn't exported | Pass the bare name; ask the user to export it |

Never work around a missing integration with an `HTTP` task to the provider API (rule B10) — have the user create it (§2).
