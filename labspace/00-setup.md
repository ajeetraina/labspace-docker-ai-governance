# Setup

Welcome to the Docker AI Governance lab.

Before you start, set the **organization** you'll be using throughout. Most commands and links in later sections substitute `$$org$$` for whatever you set here.

::variableDefinition[org]{prompt="Which Docker Hub organization will you use?"}

Enter your own Docker Hub organization name in the field above. Every `$$org$$` reference in later sections uses whatever you set here.

## What you need

- **`sbx` (Docker Sandboxes)** installed - Docker Desktop is **not** required
- **Admin access** to a Docker Hub organization so you can configure AI governance policies
- **A terminal** in the right-hand panel - most commands are click-to-run

## Quick check

Verify sbx is installed:

```bash no-run-button
sbx version
```

If it's not installed, then run the following command:

```bash no-run-button
brew install docker/tap/sbx
```

Verify you're logged in to Docker:

```bash no-run-button
docker login
```

If you're a member of multiple organizations, make sure the org you set above (`$$org$$`) matches one where you have admin rights - otherwise you won't be able to set policies in Section 03.

When you're ready, move to Section 01.
