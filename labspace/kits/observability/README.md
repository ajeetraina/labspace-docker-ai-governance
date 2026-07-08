# Observability Kit - sbx + MCP

A small dashboard that tails the `sbx` daemon log and your local `docker/mcp-gateway` container logs, normalises them into one event stream, and serves a live web UI on `http://localhost:8090`.

Useful for:

- Watching policy decisions land as you run commands inside a sandbox
- Demonstrating Pillar 3 (Audit + Visibility) with a real UI rather than `tail -f` on a JSONL file
- Workshop / talk demos where the audit trail needs to be visible on screen

## What it shows

Three live sources, normalised into one event stream:

1. **`sbx` daemon log** (`sandboxes/sandboxd/daemon.log`, JSONL) - every `governance policy evaluation` event
   - Decision (allow / deny), resource (e.g. `paste.ee:443`), matched rule, deny reason (explicit / implicit), source (local / remote)
   - Sandbox/agent/session fields when sbx emits them (lifecycle events do, policy events don't yet)
2. **`sbx` MCP log** (`sandboxes/sandboxd/mcp/mcp.log`, logfmt) - gateway lifecycle events (setup, start, errors)
3. **`docker/mcp-gateway` container stdout** - every running gateway container, log lines classified as `call-tool` / `list-tools` / `list-resources` when patterns match

Plus:

- **Synthesised user identity** stamped on every event from `$USER` / `$LABSPACE_USER`. Visible in the header and in the new User column.
- **MCP server destination detection** - events targeting `mcp.*`, `mcp-*`, `gateway.docker.com` get a purple dot in the table and surface in the "MCP servers reached" panel.
- **MCP-only view** - one-click filter to hide non-MCP events.

## What it deliberately doesn't show

- **Native user identity.** As of sbx v0.32.0, audit events still don't carry user identity. The user shown is synthesised from the host `$USER` - accurate for single-developer machines, useless for multi-tenant. Docker's marketing promises native user identity in audit events; when it lands we'll consume it automatically (the field name is just `user` or `user_email` - we already pass `Raw` through, so it'll surface).
- **Prompts or tool-call payloads.** The sbx proxy does MITM TLS interception so it *could* log request bodies, but doesn't. Only network metadata is captured. Almost certainly a deliberate privacy default.
- **Per-tool audit for hosted MCP servers.** A call from your agent to a Notion MCP tool shows up only as a TCP connect to `mcp.notion.com:443` - you can see *that* the server was reached, not *which tool* was invoked or *what arguments* were passed. This requires upstream changes to the gateway and/or sbx.
- **Cross-machine aggregation.** This is per-host. For org-wide audit, forward the JSONL daemon log to a SIEM.

## Quick start

From this directory:

```bash
docker compose up -d --build
open http://localhost:8090
```

To also run a local `docker/mcp-gateway` alongside (so MCP traffic shows up in the dashboard):

```bash
docker compose --profile with-gateway up -d --build
```

The gateway runs with `--verbose=true` so per-request log lines are emitted to stdout. The dashboard tails them automatically.

In a separate terminal, trigger some events:

```bash
mkdir -p ~/workdemo/scratch && cd ~/workdemo/scratch
sbx run shell .
# inside the sandbox:
curl -sS https://collabnix.com -o /dev/null -w "%{http_code}\n"
curl -sS https://example.com -o /dev/null -w "%{http_code}\n"
```

You should see two new `deny` rows appear in the dashboard in real time.

## Configuration

| Env var | Default | Notes |
|---|---|---|
| `SBX_DAEMON_LOG` | `/var/log/sbx/sandboxes/sandboxd/daemon.log` | Path **inside the container**; the compose file mounts the macOS host path read-only. Change the volume on Linux. |
| `LISTEN_ADDR` | `:8090` | Host:port the HTTP server listens on. |

### Linux

The host path differs from macOS. Edit `compose.yaml` and replace the volume line with:

```yaml
- "${HOME}/.local/share/com.docker.sandboxes:/var/log/sbx:ro"
```

### Running the MCP gateway alongside

Variant B in Section 06 of the lab spins up a local `docker/mcp-gateway` on port 8811. Run that gateway in the **same compose project** (or any project - this dashboard discovers gateway containers by image name across all Docker contexts) and its logs will appear in the dashboard automatically.

## API

- `GET /api/events` - JSON array of recent events (last 1000)
- `GET /api/ws` - WebSocket stream of new events as they arrive
- `GET /api/health` - `ok`

## What about prompts and tool calls?

This is the first question every reviewer asks, so it deserves a direct answer.

### Prompts (the actual text the user typed at the agent)

**Not logged.** The sbx network proxy does MITM TLS interception, so it *could* technically read request bodies - but it doesn't. The daemon log captures destination, port, decision, and matched rule. Nothing about request content.

This is almost certainly a deliberate product choice. Logging prompt content has serious privacy and legal implications, and security teams have very different stances on whether content inspection is acceptable. The cautious default - metadata yes, bodies no - is what ships today.

### MCP tool calls

**Partially captured, and only for gateways you run yourself.** Two scenarios:

| Scenario | What you can see |
|---|---|
| `sbx mcp add local-ddg --command docker --args ...` (Mode 4, local stdio) | The subprocess runs on your host. Wrap it yourself if you want audit. |
| `sbx mcp add ddg-image --url docker.io/mcp/duckduckgo` (docker.io image) | If routed through a gateway you run with `--verbose=true`, the dashboard surfaces `list-tools` / `call-tool` lines from the gateway's stdout. Classification is heuristic, not structured. |
| `sbx mcp add notion --url https://mcp.notion.com/mcp` (Mode 1, hosted) | **Nothing.** The tool call happens between Docker's hosted MCP control plane and the remote server. You see the TCP connect to `mcp.notion.com:443` in the sbx network log; you do not see which Notion tool was called. |

To actually get structured tool-call audit, the upstream `docker/mcp-gateway` would need to emit JSONL audit records per call. It doesn't today. Filing a feature request against [docker/mcp-gateway](https://github.com/docker/mcp-gateway) is the right path.

### Who triggered each event

**Not captured.** The sbx daemon log has no `user`, `sandbox_id`, or `agent` field - only the operation and decision. On a single-developer machine this is fine; for org-wide audit you'd need either:

- sbx to enrich each event with `user_email` from the Docker login session (no API change needed; just a feature request), or
- A separate identity stream correlated with these events at SIEM ingest time

### What this dashboard does and doesn't promise

- ✅ Shows *what* was decided and *why*, in real time
- ✅ Surfaces every domain a sandbox tried to reach
- ✅ Aggregates denies by rule and destination
- ❌ Does not show prompt content
- ❌ Does not show structured MCP tool calls (only loose log lines from your local gateway)
- ❌ Does not show user identity
- ❌ Does not aggregate across machines

If a security review needs (3), (4), or (5), the honest answer today is "roadmap" - and the dashboard makes that gap visible rather than hiding it.

## Caveats

- The sbx daemon log location is **not a public API**. If `sbx` changes the path or format, the dashboard breaks; you can patch the `parseAndBroadcastSbx` function in `backend/main.go` to match the new shape.
- The MCP gateway log parser is heuristic (regex/contains). It works for the upstream `docker/mcp-gateway` image but won't catch tool-call payloads in structured form unless the image emits them as JSON, which today it does not consistently. Running the gateway with `--verbose=true` gives you more text to parse but not more structure.
- This is a **developer self-service** tool. Don't expose it to the internet; it has no auth and reads sensitive log data.
