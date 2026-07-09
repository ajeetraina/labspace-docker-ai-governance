# Docker AI Governance Labspace

A hands-on lab that proves how Docker AI Governance policies flow from one Admin Console toggle to every developer's `sbx` sandbox, with empirical tests for both network and filesystem enforcement.

**Define once. Enforce everywhere.**

## What this lab proves

- Policies set in `app.docker.com/admin/orgs/<your-org>` flow automatically to any developer logged in with org credentials
- Network rules are enforced by an in-proxy `403` at request time
- Filesystem rules are enforced at sandbox creation time - denied mounts cause `sbx run` to fail before the agent ever runs
- The default-deny posture catches anything not covered by an allow rule
- Developers cannot override `ORIGIN: remote` policies locally
- MCP servers register through `sbx mcp` behind the **Docker MCP Gateway**, so sandboxed agents reach tools through one governed control plane
- Policies can be authored two ways - the Hub Admin Console UI or the **Docker AI Governance API** - both writing to the same source of truth

By the end you have a defensible enforcement story you can walk a security team through.

## Two ways to set up policies

This labspace supports two methods for authoring and applying AI Governance policies - both write to the same source of truth, so you can pick whichever fits your workflow:

1. **AI Governance API** - Drive the control plane programmatically over HTTP. Author, update, and apply policies via API calls (see Section 11). Ideal for automation, CI/CD, and infrastructure-as-code workflows.
2. **Manual Setup** - Use the Hub Admin Console UI at `app.docker.com/admin/orgs/<your-org>` to toggle and author policy rules by hand. Ideal for getting started and for teams who prefer a visual workflow.

## Getting Started

### Prerequisites


- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (on Windows, enable **WSL2 integration** for your distro)
- [ttyd](https://github.com/tsl0922/ttyd) — powers the right-hand terminal panel:
  - **macOS** — `brew install ttyd`
  - **Linux / WSL2** — `sudo apt install ttyd`
- [sbx](https://github.com/docker/sbx-releases):
  - **macOS** — `brew install docker/tap/sbx`
  - **Windows** — run the lab under WSL2 and install the Linux build inside it (see **Running on Windows** below)
  - **Linux** — `sudo apt install ./DockerSandboxes-linux-amd64-ubuntu2604.deb` (or the Docker apt repo — see Section 00)
- **Admin access** to a Docker Hub organization with AI Governance enabled
- **A logged-in Docker CLI** (`docker login` with your org credentials)

> [!NOTE]
> The lab content adapts to your OS: on **Section 00 - Setup** you pick macOS / Windows / Linux, and every OS-specific install command and file path in later sections switches to match.

### Quick Start (macOS / Linux)

```bash
git clone https://github.com/ajeetraina/labspace-sbx
cd labspace-sbx
bash start-labspace.sh
```

Open http://localhost:3030

- **Left panel** → Lab instructions
- **Right panel** → Your host terminal with `sbx` ready to use

### Running on Windows

> [!IMPORTANT]
> **The recommended path on Windows is WSL2.** The right-hand terminal is served by [`ttyd`](https://github.com/tsl0922/ttyd), which has no reliable native-Windows build. Inside WSL2 everything — `ttyd`, `sbx`, and the launcher — works exactly as it does on Linux.

1. Install WSL2 and a distro (once), then open your Ubuntu shell:

   ```powershell
   wsl --install -d Ubuntu
   ```

2. In Docker Desktop, enable **Settings → Resources → WSL Integration** for that distro.

3. From the WSL2 (Ubuntu) shell, install the prerequisites and launch:

   ```bash
   sudo apt update && sudo apt install -y ttyd
   sudo apt install ./DockerSandboxes-linux-amd64-ubuntu2604.deb   # sbx (Linux build)
   git clone https://github.com/ajeetraina/labspace-sbx
   cd labspace-sbx
   bash start-labspace.sh
   ```

Then open http://localhost:3030 in your Windows browser.

> [!NOTE]
> A native PowerShell launcher (`start-labspace.ps1`) is included for users who already have `ttyd` on Windows (e.g. via `scoop install ttyd`). It mirrors `start-labspace.sh`, but because native-Windows `ttyd` is unreliable, **WSL2 above is the supported path**. Note that `sbx` under WSL2 is the Linux build — this lab exercises Linux `sbx`, which is what the demos assume.

If you don't have an organization yet, you can still walk through Sections 00-02 conceptually - the demo sections (03, 04) need org-level admin access to add policy rules.

## Lab structure

| # | Section | Time | What you do |
| --- | --- | --- | --- |
| 00 | Setup | 2 min | Pick your org and verify sbx is installed |
| 01 | Why AI Governance | 3 min | Horror stories, three pillars framing |
| 02 | The Policy Model | 5 min | Conceptual: two policy-authoring paths (Hub Admin Console + Governance API) and how org → developer policy flow works |
| 03 | Network Enforcement Demo | 10 min | Three `curl` commands, three outcomes (allow / deny / default-deny) |
| 04 | Filesystem Enforcement Demo | 10 min | Three `sbx run` attempts, same three outcomes |
| 07 | Product Catalog | 15 min | Turn an autonomous coding agent loose on a real Node.js app, contained by your policies |
| 06 | MCP Hands-On | 15 min | Register MCP servers with `sbx mcp` behind the Docker MCP Gateway (remote OAuth, docker.io image, local stdio) |
| 08 | Observability | 10 min | Inspect the audit trail and the live sbx/MCP dashboard |
| 09 | Monitoring Policies | 10 min | Watch policy decisions as they happen |
| 10 | Audit Logging | 10 min | Trace every allow/deny back to a rule |
| 11 | Governance API | 15 min | Drive the same control plane programmatically over HTTP |
| 05 | What's Next | 5 min | Preview of audit trails and MCP Tool Governance |

Total walkthrough: ~110 minutes.

## Troubleshooting

In case you face issue related to ttyd:

```
ERROR: ttyd failed to start on port 8085
```

Just try to use `lsof -i :8085` to find the existing ttyd process ID and kill it using `kill` command. Restart the start-labspace script.



