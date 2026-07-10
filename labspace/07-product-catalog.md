# Product Catalog

The first demos proved governance with synthetic tests - `curl` to a denylisted host, a mount of `~/.ssh`. This section proves it on a **real application** with a **real autonomous coding agent**.

You'll point Claude at the [Product Catalog service](https://github.com/dockersamples/catalog-service-node) - a Node.js + Express API backed by Postgres, S3, Kafka, and an external inventory service - and hand it an autonomous task: fix a known bug and prove the fix with the project's Testcontainers integration suite. The whole time, the network and filesystem policies you configured in Sections 03 and 04 are the only thing standing between "autonomous" and "uncontained."

**Time:** ~15 minutes
**Prerequisites:** You completed Section 03 (network) and Section 04 (filesystem). You have an Anthropic API key **or** a Claude Pro/Max subscription.

## What you'll prove

- A coding agent runs **inside the sandbox microVM**, not on your host
- The agent builds and tests using the **sandbox's own Docker daemon** - never your host Docker
- The agent edits **bind-mounted source**, so its file changes land in your local tree for review
- The sandbox is only created because the workspace path matches a filesystem **allow** rule
- The agent reaches `api.anthropic.com` and package registries only because network policy **allows** them - and still can't exfiltrate to a denylisted host

## The mental model

Two things share the name "Product Catalog"; keep them separate:

| | The running app | The code the agent works on |
| --- | --- | --- |
| **What** | Live service + Postgres/Kafka/S3 stack | The repo files in `src/`, `test/` |
| **Where** | Your host (`docker compose up`), for *you* to explore | Bind-mounted into the sandbox, for the *agent* to edit |

The sandbox is the agent's **workbench**, not a deployment target. The catalog never "runs as a service" in the sandbox - it enters only as source to be modified, built, and tested.

## Step 1 - Allow the workspace path

The agent works on the catalog source on your laptop, so the sandbox needs to mount it. That mount only succeeds if a filesystem **allow** rule covers the path (Section 04's lesson).

In **[app.docker.com/accounts/$$org$$](https://app.docker.com/accounts/$$org$$)** → **AI governance** → **Filesystem access**, confirm the `allow workdemo` rule from Section 02 covers where you'll clone the repo:

- Action: **Allow**
- Filesystem path: `~/workdemo/**`
- Action scope: **Read, Write**
- Name: `allow workdemo`

> Use `**`, not `*` - a single `*` won't match across `/`, so `~/workdemo/*` would miss `~/workdemo/catalog-service-node/src`.

After editing any governance policy, force a fresh pull so the sandbox daemon doesn't serve a stale cache:

```bash no-run-button
sbx logout && sbx login
sbx policy ls --include-inactive | grep -i filesystem
```

You should see the allow rule with `ORIGIN: remote` before continuing.

## Step 2 - Clone the Product Catalog into the allowed path

```bash no-run-button
cd ~/workdemo
git clone https://github.com/dockersamples/catalog-service-node
cd catalog-service-node
```

The repo ships a known bug - a Kafka message drops the `upc` field when a product is published - plus a full Testcontainers integration suite that proves whether the bug is fixed. A clear goal with real tests: the ideal autonomous task.

## Step 3 - Give the agent its credentials

The sandbox proxy injects credentials so the key never enters the sandbox directly.

**API key:**

```bash no-run-button
echo 'sk-ant-api03-...' | sbx secret set -g anthropic -f
```

**Or Claude Pro/Max subscription** - mint a long-lived token on the host, then inject it as a custom secret the proxy swaps in for calls to `api.anthropic.com`:

```bash no-run-button
claude setup-token   # prints sk-ant-oat01-...
sbx secret set-custom -g \
  --host api.anthropic.com \
  --env CLAUDE_CODE_OAUTH_TOKEN \
  --placeholder 'sk-ant-oat01-{rand}' \
  --value 'sk-ant-oat01-...'
```

> `api.anthropic.com:443` is already in the AI-services network allow rule from Section 03 - the agent can reach Anthropic, and nothing else off-policy.

## Step 4 - Launch the autonomous agent

```bash no-run-button
sbx run --name catalog claude
```

This creates the sandbox (the filesystem allow rule lets the catalog directory mount) and drops you into Claude **inside the microVM**. Confirm the sandbox has its own Docker daemon - this is where all builds and tests will run:

```bash no-run-button
sbx exec catalog -- docker version --format '{{.Server.Version}}'
```

A version prints from a daemon that is **not** your host's. Container builds and Testcontainers happen here, fully isolated.

## Step 5 - Hand it the goal

In the agent session, give it the task in plain language:

```
There's a bug where the Kafka message published on product creation drops
the upc field. Find it, fix it, and prove the fix by running the integration
test suite. Iterate until the tests pass.
```

Now watch. The agent will, **entirely inside the sandbox**:

1. Read `src/services/PublisherService.js` and locate the dropped field
2. Edit the source (changes appear in your host tree via the bind mount)
3. Run `yarn integration-test` - which spins up **throwaway** Postgres, Kafka, and LocalStack containers via Testcontainers, inside the sandbox's Docker daemon
4. Read the results, iterate if needed, and stop when the suite is green

## Step 6 - Review the changes on your laptop

Because the source is bind-mounted, the agent's edits are already in your local tree. Open a host terminal:

```bash no-run-button
cd ~/workdemo/catalog-service-node
git diff
```

You review a small, contained diff - the agent never had access to your host's Docker, your SSH keys, or any off-policy network destination while producing it.

## Step 7 - Read the results

| Concern | Where it happened | Why it was safe |
| --- | --- | --- |
| Agent reasoning + edits | Sandbox microVM | Isolated VM; only the mounted workspace is visible |
| `docker build` / Testcontainers | Sandbox's own Docker daemon | Never touches host Docker - no blast radius |
| Reaching `api.anthropic.com` + npm registry | Through the proxy | Allowed by network policy; everything else denied |
| Exfil to `paste.ee` / unapproved host | Blocked | Network deny rule (Section 03) |
| Mounting `~/.ssh` or an unapproved dir | Would 403 at creation | Filesystem rules (Section 04) |
| The fix itself | Bind-mounted source | Lands in your local tree for human review |

## What you just demonstrated

This is the **golden path**: a developer (or CI) runs `sbx run claude`, the agent works fully autonomously on a real service - editing, building, running real integration tests - and produces a reviewable diff, all without a single approval prompt and without any ability to step outside the policy boundary.

Autonomy and governance aren't a trade-off here. The policies from Sections 03 and 04 are exactly what make hands-off autonomy *safe*:

- **Compute** is contained - builds and tests run in the sandbox's Docker, not yours
- **Network** is contained - the agent reaches only approved hosts
- **Filesystem** is contained - the agent mounts only approved paths, and its writes land only where allowed
- **Review** stays human - the diff surfaces on your laptop before anything merges

This is the payoff of the whole lab: **define policy once in the Admin Console, and a real autonomous agent on a real codebase stays inside the lines - automatically.**
