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


- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [ttyd](https://github.com/tsl0922/ttyd) — powers the embedded terminal panel:
  - **macOS** — `brew install ttyd`
  - **Linux** — `sudo apt install ttyd`
  - **Windows** — `scoop install ttyd` (see **Running on Windows** below)
- [sbx](https://github.com/docker/sbx-releases) — runs **natively** on each OS using that OS's own hypervisor (Apple Hypervisor.framework / Windows Hypervisor Platform / Linux KVM):
  - **macOS** — `brew install docker/tap/sbx`
  - **Windows 11 (x86_64)** — `winget install -h Docker.sbx` (see **Running on Windows** below)
  - **Linux** — `sudo apt install ./DockerSandboxes-linux-amd64-ubuntu2604.deb` (or the Docker apt repo — see Section 00)
- **Admin access** to a Docker Hub organization with AI Governance enabled
- **A logged-in Docker CLI** (`docker login` with your org credentials)


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


1. Enable the Windows Hypervisor Platform (elevated PowerShell), then reboot — this changes boot-time kernel components:

   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
   ```

2. Install and log in to `sbx`:

   ```powershell
   winget install -h Docker.sbx
   sbx login
   ```

3. Install [`ttyd`](https://github.com/tsl0922/ttyd) (serves the right-hand terminal panel) and start it on port 8085, running native PowerShell where `sbx` is available:

   ```powershell
   scoop install ttyd
   ttyd -W -p 8085 -w $env:USERPROFILE powershell.exe
   ```

   > `-W` allows input (writable), `-p 8085` is the port the labspace panel connects to, and `-w $env:USERPROFILE` sets the working directory to your home folder (equivalent to `C:\Users\<you>`).

4. In a second PowerShell window, start the labspace UI (needs Docker Desktop running):

   ```powershell
   git clone https://github.com/ajeetraina/labspace-sbx
   cd labspace-sbx
   docker compose -f compose.yaml -f compose.override.yaml up
   ```

5. Open http://localhost:3030 — the **lab instructions** are on the left and the **PowerShell terminal** (with native `sbx`) is on the right.

> [!NOTE]
> The bundled launcher `start-labspace.ps1` automates steps 3–4 (starts `ttyd` on 8085, then `docker compose up`). It requires `ttyd` on your `PATH` (e.g. via `scoop install ttyd`).

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

### `ttyd` port already in use

```
ERROR: ttyd failed to start on port 8085
```

Find the existing ttyd process and kill it, then restart the launcher:

- **macOS / Linux** — `lsof -i :8085` → `kill <PID>`
- **Windows (PowerShell)** — `Get-NetTCPConnection -LocalPort 8085 | Select-Object OwningProcess` → `Stop-Process -Id <PID> -Force`

### Windows: `ttyd` (`:8085`) is up but the Labspace UI (`:3030`) never appears

Symptom: `docker ps` shows `labspace-docker-ai-governance-interface-1` (and the other Labspace containers) in **`Created`** status instead of **`Up`**. On Windows, `docker compose up` occasionally creates the stack's containers via the OCI provider but doesn't actually start them, so nothing binds `:3030`.

Fix — from a second PowerShell window in the repo root, start what compose already created:

```powershell
docker compose -f compose.yaml -f compose.override.yaml start
```

Then re-open http://localhost:3030. If a specific container is still stuck, start it directly:

```powershell
docker start labspace-docker-ai-governance-interface-1 `
             labspace-docker-ai-governance-configurator-1 `
             labspace-docker-ai-governance-workspace-1 `
             labspace-docker-ai-governance-host-republisher-1
```

If the stack is in a wedged state from a prior run, clear it and start fresh:

```powershell
docker compose -f compose.yaml -f compose.override.yaml down
pwsh -File start-labspace.ps1
```

To kill the ttyd process if it is running by any chance:

```powershell
Get-NetTCPConnection -LocalPort 8085 | Select-Object -ExpandProperty OwningProcess | ForEach-Object { Stop-Process -Id $_ -Force }
```
