#!/usr/bin/env bash
#
# setup-policies.sh - provision the labspace AI Governance policy via the
# Docker AI Governance API instead of clicking through the Admin Console.
#
# It creates (idempotently) the same rules you would otherwise add by hand in
# Section 03 (network) and Section 04 (filesystem):
#
#   Network policy  "Labspace AI Governance - network"
#     allow AI services      (allow)  api.anthropic.com:443, api.openai.com:443, ...
#     allow Docker services  (allow)  *.docker.com:443, *.docker.io:443, dhi.io:443
#     deny exfiltration      (deny)   paste.ee, pastebin.com, hooks.slack.com
#
#   Filesystem policy "Labspace AI Governance - filesystem"
#     allow workdemo           (allow)  ~/workdemo/**
#     deny credentials         (deny)   ~/.ssh/**, ~/.aws/**, ~/.config/gcloud/**, ...
#
# A policy holds rules for a single domain (network OR filesystem), so this
# script provisions one policy per domain.
#
# Usage:
#   export ORG=your-docker-org
#   export TOKEN="eyJ..."            # admin/owner JWT (see below to mint one)
#   bash setup-policies.sh [network|filesystem|all]   # default: all
#
# No TOKEN yet? Exchange a username + PAT for one:
#   export ORG=your-docker-org
#   export USERNAME=your-username
#   export PASSWORD=your-pat-or-password
#   bash setup-policies.sh
#
# Re-running is safe: existing policies are reused and rules already present
# (matched by name) are skipped.

set -euo pipefail

BASE_URL="https://hub.docker.com/v2"
DOMAIN_ARG="${1:-all}"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required but not installed." >&2; exit 1; }
done

: "${ORG:?Set ORG to your Docker organization name (export ORG=your-org)}"

# Mint a token from USERNAME/PASSWORD if one wasn't supplied.
if [[ -z "${TOKEN:-}" ]]; then
  if [[ -n "${USERNAME:-}" && -n "${PASSWORD:-}" ]]; then
    echo "→ Exchanging credentials for a bearer token..."
    TOKEN="$(curl -fsS -X POST "$BASE_URL/users/login" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg u "$USERNAME" --arg p "$PASSWORD" '{username:$u, password:$p}')" \
      | jq -r '.token')"
    [[ -n "$TOKEN" && "$TOKEN" != "null" ]] || { echo "ERROR: failed to obtain a token." >&2; exit 1; }
  else
    echo "ERROR: set TOKEN, or set USERNAME and PASSWORD so a token can be minted." >&2
    exit 1
  fi
fi

AUTH=(-H "Authorization: Bearer $TOKEN")
JSON=(-H "Content-Type: application/json")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# find_or_create_policy <policy-name> -> echoes the policy id
find_or_create_policy() {
  local name="$1" id
  id="$(curl -fsS "${AUTH[@]}" "$BASE_URL/orgs/$ORG/governance/policies" \
        | jq -r --arg n "$name" '.data[]? | select(.name == $n) | .id' | head -n1)"
  if [[ -n "$id" && "$id" != "null" ]]; then
    echo "$id"
    return
  fi
  curl -fsS -X POST "${AUTH[@]}" "${JSON[@]}" \
    "$BASE_URL/orgs/$ORG/governance/policies" \
    -d "$(jq -n --arg n "$name" '{name:$n}')" \
    | jq -r '.id'
}

# existing_rule_names <policy-id> -> echoes one rule name per line
existing_rule_names() {
  local pid="$1"
  curl -fsS "${AUTH[@]}" "$BASE_URL/orgs/$ORG/governance/policies/$pid" \
    | jq -r '.allowlist_v0.rules[]?.name'
}

# add_rule <policy-id> <name> <decision> <actions-json> <resources-json>
add_rule() {
  local pid="$1" name="$2" decision="$3" actions="$4" resources="$5"
  if printf '%s\n' "$EXISTING" | grep -qxF "$name"; then
    echo "   - rule '$name' already present, skipping"
    return
  fi
  curl -fsS -X POST "${AUTH[@]}" "${JSON[@]}" \
    "$BASE_URL/orgs/$ORG/governance/policies/$pid/rules" \
    -d "$(jq -n --arg n "$name" --arg d "$decision" \
              --argjson a "$actions" --argjson r "$resources" \
              '{name:$n, decision:$d, actions:$a, resources:$r}')" >/dev/null
  echo "   ✓ rule '$name' ($decision) created"
}

NET_ACTIONS='["connect:tcp","connect:udp"]'
FS_ACTIONS='["read","write"]'

setup_network() {
  echo "→ Network policy"
  local pid; pid="$(find_or_create_policy "Labspace AI Governance - network")"
  echo "   policy id: $pid"
  EXISTING="$(existing_rule_names "$pid")"
  add_rule "$pid" "allow AI services" allow "$NET_ACTIONS" \
    '["api.anthropic.com:443","api.openai.com:443","platform.claude.com:443","*.googleapis.com:443","statsig.anthropic.com:443"]'
  add_rule "$pid" "allow Docker services" allow "$NET_ACTIONS" \
    '["*.docker.com:443","*.docker.io:443","dhi.io:443"]'
  add_rule "$pid" "deny exfiltration" deny "$NET_ACTIONS" \
    '["paste.ee","pastebin.com","hooks.slack.com"]'
}

setup_filesystem() {
  echo "→ Filesystem policy"
  local pid; pid="$(find_or_create_policy "Labspace AI Governance - filesystem")"
  echo "   policy id: $pid"
  EXISTING="$(existing_rule_names "$pid")"
  add_rule "$pid" "allow workdemo" allow "$FS_ACTIONS" \
    '["~/workdemo/**"]'
  add_rule "$pid" "deny credentials" deny "$FS_ACTIONS" \
    '["~/.ssh/**","~/.aws/**","~/.config/gcloud/**","~/.kube/config","~/.docker/config.json"]'
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
case "$DOMAIN_ARG" in
  network)    setup_network ;;
  filesystem) setup_filesystem ;;
  all)        setup_network; setup_filesystem ;;
  *) echo "ERROR: unknown argument '$DOMAIN_ARG' (use network | filesystem | all)" >&2; exit 1 ;;
esac

cat <<EOF

Done. The rules are live in Hub for org "$ORG".

Pull them down to this machine and confirm they show as ORIGIN: remote:

  sbx policy reset    # choose Balanced when prompted
  sbx policy ls

(Org changes also propagate to every developer automatically within ~5 minutes.)
EOF
