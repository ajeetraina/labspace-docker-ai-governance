# AI Governance — Overall Architecture

How a single org policy, authored once, is enforced across the sandbox **and**
every MCP tool call — with every decision landing in one audit/visibility stream.

## At a glance

Policy is authored in **Docker Hub → AI Governance** (Settings UI or the AI
Governance API) and synced to the laptop at `docker login` — it takes precedence.
The coding agent runs in a **container inside a MicroVM** on the host; all
enforcement — **network proxy, network policy, and filesystem policy** — lives on
the host in the `sbx` daemon, *around* the sandbox. The **MCP Gateway** the agent
calls (set by `SBX_MCP_URL`) is either **local** (on your laptop) or **remote**
(Docker-hosted). Every decision is audited.

```mermaid
flowchart TB
    subgraph HUB["Docker Hub — AI Governance"]
        direction TB
        SPACER[" "]
        SETTINGS["Governance Settings (UI)"]
        API["AI Governance API"]
        SPACER ~~~ SETTINGS ~~~ API
    end

    subgraph HOST["HOST — developer laptop"]
        subgraph VM["MicroVM"]
            subgraph CON["Container"]
                AGENT["Coding agent"]
            end
        end

        subgraph DAEMON["sbx daemon — policy + audit"]
            NET["Network proxy<br/>+ network policy"]
            FS["Filesystem policy"]
        end

        LOCALGW["Local MCP Gateway<br/>localhost:8811"]
        AUDIT[("Audit log")]
    end

    REMOTEGW["Remote MCP Gateway<br/>gateway.docker.com"]
    INTERNET["Internet"]
    BLOCK["Blocked"]

    HUB -. "policy synced at docker login · takes precedence" .-> DAEMON

    AGENT -- "network" --> NET
    AGENT -- "file access" --> FS
    AGENT -- "MCP calls · local" --> LOCALGW
    AGENT -- "MCP calls · remote" --> REMOTEGW

    NET -- "allow" --> INTERNET
    NET -- "deny" --> BLOCK
    FS -- "deny" --> BLOCK
    NET -. log .-> AUDIT
    FS -. log .-> AUDIT

    classDef hub fill:#eef2ff,stroke:#6366f1,color:#000
    classDef vm fill:#ecfdf5,stroke:#10b981,color:#000
    classDef pol fill:#fff7ed,stroke:#f59e0b,color:#000
    classDef gw fill:#eff6ff,stroke:#3b82f6,color:#000
    classDef deny fill:#fef2f2,stroke:#ef4444,color:#000
    classDef hidden fill:none,stroke:none,color:none
    class SPACER hidden
    class SETTINGS,API hub
    class AGENT vm
    class NET,FS pol
    class LOCALGW,REMOTEGW gw
    class BLOCK deny
```

Policy is set in Docker Hub (**AI Governance Settings** UI or the **AI Governance
API**) and takes precedence. `SBX_MCP_URL` selects the gateway:
`http://localhost:8811` (local, on your laptop) or `https://gateway.docker.com`
(remote, Docker-hosted and org-governed).

## The full picture

Where the policy comes from, and how MCP tool calls are governed and audited:

```mermaid
flowchart TB
    subgraph ADMIN["Org Admin — Policy Authoring (one source of truth)"]
        UI["Admin Console<br/>app.docker.com/admin/orgs/&lt;org&gt;"]
        API["Governance API<br/>hub.docker.com/v2/orgs/&lt;org&gt;/governance/policies"]
    end

    POLICY[("Org Governance Policy<br/>network · filesystem · MCP rules")]
    UI --> POLICY
    API --> POLICY

    POLICY -. "fetched at<br/>docker login<br/>(sbx policy reset)" .-> DAEMON

    subgraph HOST["Developer Machine"]
        DAEMON["sbx daemon (sandboxd)<br/>caches policy · enforces · audits<br/>fail-closed: no policy ⇒ deny-all"]

        subgraph SBOX["Sandbox (isolated)"]
            AGENT["Agent<br/>(Claude Code)"]
        end

        STDIO["Local stdio MCP server<br/>runs on HOST, full user perms<br/>(ungoverned — outside both boundaries)"]
        AUDITLOG[("daemon.log (JSONL)<br/>governance policy evaluation<br/>allow / deny + reason + trace_id")]
        DASH["Observability dashboard<br/>localhost:8090 (tails the log)"]
    end

    DAEMON --- SBOX
    DAEMON -- "net + fs decisions" --> AUDITLOG
    AUDITLOG --> DASH

    AGENT == "tool calls<br/>SBX_MCP_URL" ==> GW

    subgraph GWZONE["MCP Gateway (single governed control plane)"]
        GW["mcp-gateway<br/>aggregates backends<br/>tools: mcp__mcp-gateway__*"]
    end

    GW -- "policy check + audit<br/>per tool call" --> AUDITLOG
    AGENT -. "ungoverned path" .-> STDIO

    GW --> WIKI["local-wiki<br/>(Wikipedia MCP)"]
    GW --> REMOTE["Remote OAuth server<br/>(Notion / GitHub / …)"]
    GW --> IMG["docker.io image server<br/>(DuckDuckGo / …)"]

    classDef admin fill:#e8f0fe,stroke:#4285f4,color:#000
    classDef policy fill:#fff4e5,stroke:#f59e0b,color:#000
    classDef gw fill:#e6f4ea,stroke:#34a853,color:#000
    classDef warn fill:#fce8e6,stroke:#ea4335,color:#000
    classDef audit fill:#f3e8fd,stroke:#9333ea,color:#000
    class UI,API admin
    class POLICY policy
    class GW gw
    class STDIO warn
    class AUDITLOG,DASH audit
```

## How to read it

1. **Author once.** An org admin writes policy in the Admin Console UI or via the
   Governance API — both land in the same org policy (network, filesystem, MCP rules).
2. **Propagate.** On `docker login` with org credentials, the `sbx` daemon fetches
   and caches that policy (`sbx policy reset` forces a refresh).
3. **Enforce in two places, from the same policy:**
   - **Sandbox runtime** — the daemon checks every **network** and **filesystem**
     action at the boundary. Fail-closed: no policy loaded ⇒ everything denied.
   - **MCP Gateway** — every **tool call** the agent makes flows through one
     `mcp-gateway` endpoint (set by `SBX_MCP_URL`), where MCP policy applies.
4. **Audit everything.** Each decision is written to `daemon.log` as a structured
   JSONL `governance policy evaluation` record (allow/deny, reason, `trace_id`),
   which the observability dashboard tails live.

## The two gateway choices (`SBX_MCP_URL`)

```mermaid
flowchart LR
    A["Agent in sandbox"] -- SBX_MCP_URL --> CHOICE{"which gateway?"}
    CHOICE -- "http://localhost:8811" --> LOCAL["Local MCP Gateway<br/>Compose or Desktop MCP Toolkit<br/>you front it · you control what's registered"]
    CHOICE -- "https://gateway.docker.com" --> HOSTED["Hosted control plane<br/>MCP Gateway Enterprise<br/>org controls what's registerable · central audit"]
    CHOICE -. "registry.modelcontextprotocol.io" .-> BAD["catalog, not a gateway<br/>→ 501 / 'No MCP servers configured'"]

    classDef good fill:#e6f4ea,stroke:#34a853,color:#000
    classDef bad fill:#fce8e6,stroke:#ea4335,color:#000
    class LOCAL,HOSTED good
    class BAD bad
```

| | Local gateway | `gateway.docker.com` |
|---|---|---|
| `SBX_MCP_URL` | `http://localhost:8811` | `https://gateway.docker.com` |
| Who runs it | You (Compose / Desktop) | Docker (hosted) |
| Governs | what *you* register | what your org *allows* (policy enforced) |
| Central audit | local log only | org audit trail |
| Best for | learning the mechanics | the real governance story |

> **Not a gateway:** `registry.modelcontextprotocol.io` is a discovery *catalog*.
> Pointing `SBX_MCP_URL` at it unlocks the `sbx mcp` CLI but cannot provision a
> gateway — attach fails with `501` / "No MCP servers configured."

## The key insight

The agent never talks to individual MCP servers — it talks to **one aggregated
`mcp-gateway`** endpoint, with every backend's tools namespaced
`mcp__mcp-gateway__<tool>`. That single chokepoint is where MCP governance and
audit happen. **Local stdio servers are the exception**: they run on the host,
outside both the sandbox boundary and the gateway — convenient, but ungoverned.
