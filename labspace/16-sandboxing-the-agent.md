# Sandboxing the Agent

The Problem Statement showed an agent reaching straight into your secrets. 
The fix is to stop running it on bare metal and run it inside a **sandbox** ~ an isolated MicroVM where the agent only sees the directory you hand it, never touches the rest of your host, and never holds your real API key.

This section gets `sbx` ready, wires up your agent, and runs it sandboxed. (Install and `docker login` were covered in **Setup**.)

**Time:** ~10 minutes

**Prerequisites:** Section 00 - Setup (sbx installed, logged in).

## Step 1 - Confirm sbx is ready

Every exercise from here depends on `sbx` running on your host. **Do not skip this.**

```bash no-run-button
sbx version
```

Expected: a version string like `sbx 0.32.x`. If it's missing, jump back to **Setup** and install it.

Make sure you're logged in so org policy and secrets are available:

```bash no-run-button
sbx login
```

Complete the on-screen prompts if needed.

## Step 2 - Set up your agent

This lab works with any mainstream coding agent. Pick the provider whose API key you have — the rest of the section adapts to your choice.

::variableSetButton[🟣 Anthropic + Claude]{variables="provider=anthropic,agent=claude,secretName=anthropic"}
::variableSetButton[🟢 OpenAI + Codex]{variables="provider=openai,agent=codex,secretName=openai"}
::variableSetButton[🔵 Google + Gemini]{variables="provider=gemini,agent=gemini,secretName=google"}

:::conditionalDisplay{variable="provider" hasNoValue}
> [!NOTE]
> Pick a provider above to reveal its steps.
:::

:::conditionalDisplay{variable="provider" requiredValue="anthropic"}
### Anthropic configuration

You'll run **Claude Code** inside the sandbox, authenticated to Anthropic. Store your API key:

```bash no-run-button
sbx secret set -g anthropic
```
:::

:::conditionalDisplay{variable="provider" requiredValue="openai"}
### OpenAI configuration

You'll run **Codex** inside the sandbox, authenticated to OpenAI. Store your API key:

```bash no-run-button
sbx secret set -g openai
```
:::

:::conditionalDisplay{variable="provider" requiredValue="gemini"}
### Gemini configuration

You'll run **Gemini CLI** inside the sandbox, authenticated to Google. Store your API key:

```bash no-run-button
sbx secret set -g google
```
:::

Verify the secret was stored (the value is masked):

```bash no-run-button
sbx secret ls
```

You should see a line for your provider with the value shown as `****…****`.

> [!IMPORTANT]
> Secrets live in your **OS keychain** and are injected at the network proxy — *after* the request leaves the sandbox. The agent inside never sees the raw API key. That's the credential-isolation guarantee, covered in depth in the **Credential Isolation** section.

## Step 3 - Run the agent, sandboxed

Now the usage. Create a workspace and launch your agent **inside** a sandbox:

```bash no-run-button
mkdir -p ~/workdemo && cd ~/workdemo
sbx run $$agent$$ .
```

You land in the agent, same as on the host in the Problem Statement — but now it's inside a MicroVM that only mounted *this* directory. Ask it the same question:

```
Search the host for API keys, cloud credentials, and SSH private keys —
check ~/.aws, ~/.ssh, ~/.docker, and any .env files. Show me what you found.
```

This time it comes up **empty**. Your `~/.ssh`, `~/.aws`, and `~/.docker` were never mounted into the sandbox, so they don't exist inside it — and even the API key the agent *uses* is only a sentinel, with the real value injected on the wire outside. The blast radius from the Problem Statement is gone.

> [!NOTE]
> Here the agent can't reach those paths simply because the sandbox didn't mount them. Sections 03–04 add the next layer — **org policy** that governs which paths and hosts *any* sandbox may touch, enforced for every developer, including the workspace you *do* mount.

## What you've set up

- `sbx` verified and logged in
- Your provider's key stored as a governed secret (keychain, never in the sandbox)
- Your agent running inside an isolated sandbox instead of on bare metal

That's the shift: from an agent that runs *as you* to one that runs *inside a boundary*. What decides how wide that boundary is — which paths, which hosts, which tools — is **policy**. Next, **The Policy Model** shows how those policies are authored once and reach every developer.
