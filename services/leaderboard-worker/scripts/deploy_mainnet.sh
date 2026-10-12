#!/usr/bin/env bash
# One-shot mainnet setup for the leaderboard Worker (README.md, "Mainnet"),
# plus the Helius URLs on the devnet Worker so a real Genesis Token counts
# there too and devnet payments are checked through Helius.
#
#   bash scripts/deploy_mainnet.sh <helius-api-key>
#
# The key is only ever piped into `wrangler secret put`; it is never written
# to a file. Every step is safe to run again.
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="${1:?usage: bash scripts/deploy_mainnet.sh <helius-api-key>}"
W="npx --yes wrangler@4"

echo "--- devnet Worker: Helius RPCs"
printf '%s' "https://mainnet.helius-rpc.com/?api-key=$KEY" | $W secret put MAINNET_RPC_URL
printf '%s' "https://devnet.helius-rpc.com/?api-key=$KEY" | $W secret put DEVNET_RPC_URL

echo "--- mainnet D1 schema"
$W d1 execute yeetfleet-mainnet --remote --file schema.sql --env mainnet -y

echo "--- mainnet Worker: deploy, then its secrets"
$W deploy --env mainnet
printf '%s' "https://mainnet.helius-rpc.com/?api-key=$KEY" | $W secret put MAINNET_RPC_URL --env mainnet
# 32 random bytes as hex, without needing node on PATH; never an empty secret
# (the Worker refuses every sign-in without one).
SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
[ ${#SECRET} -eq 64 ] || { echo "couldn't make a session secret" >&2; exit 1; }
printf '%s' "$SECRET" | $W secret put SESSION_SECRET --env mainnet

echo "--- check"
URL="https://yeetfleet-mainnet.yeetfleet-leaderboard-worker.workers.dev"
curl -s -m 20 "$URL/shop" | head -c 400; echo
