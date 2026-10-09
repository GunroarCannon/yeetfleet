# Yeetfleet leaderboard Worker

Cloudflare Worker + D1 behind Yeetfleet's ranked play. The game talks to it
through `ChainApi` (`modules/chain/scripts/chain_api.gd`). Plain JavaScript,
no dependencies: the tests run on Node's built-in test runner, SQLite and
WebCrypto.

| Route | What |
|---|---|
| `POST /auth/challenge` | a one-time nonce and the SIWS fields for the wallet |
| `POST /auth/verify` | `{public_key, signed_message, signature, name?}` → session token; checks the Seeker Genesis Token |
| `GET /me` | the signed-in pilot (`Authorization: Bearer <token>`) |
| `GET /daily` | today's day, when it ends; signed in, the streak and ranked runs left |
| `POST /run/start`, `POST /run/finish` | a Daily Sortie run's ticket, and its result |
| `GET /leaderboard?board=ranked\|open&day=` | the day's top pilots and the caller's place |
| `GET /shop` | the SKR catalog, mint, treasury; signed in, what's owned |
| `POST /order/new` | `{item}` → the amount, the memo (`yeetfleet:<order>`) and where to pay |
| `POST /order/verify` | `{order_id, signature}` → checked on chain, then granted |

Live (devnet): `https://yeetfleet.yeetfleet-leaderboard-worker.workers.dev`.

## Test

```sh
npm test          # node --test, Node 22.5+ (node:sqlite)
node scripts/devnet_pay_check.mjs   # a real dSKR payment on devnet, verified
WORKER_URL=https://yeetfleet.yeetfleet-leaderboard-worker.workers.dev node scripts/devnet_pay_check.mjs
```

`devnet_pay_check` needs the Solana CLI and a payer with devnet SOL and dSKR
(`~/.config/solana/id.json` by default); it spends 50 dSKR a run.

## Deploy (once)

```sh
npx wrangler@4 login
npx wrangler@4 d1 create yeetfleet           # paste the id into wrangler.toml
npx wrangler@4 d1 execute yeetfleet --remote --file schema.sql
npx wrangler@4 secret put SESSION_SECRET      # openssl rand -hex 32
npx wrangler@4 secret put MAINNET_RPC_URL     # https://mainnet.helius-rpc.com/?api-key=…  (needed:
                                              # Solana's public mainnet RPC refuses Cloudflare, so
                                              # without it no Genesis Token is ever found)
npx wrangler@4 deploy                         # prints https://yeetfleet.<you>.workers.dev
```

Then set `Chain.WORKER_URL` in the game to the printed URL. After a schema
change, run the `d1 execute` line again (every statement is idempotent).

## What is and isn't trusted

- Sign-in: the signature, the domain, the address and a one-use nonce no
  older than 5 minutes. A captured sign-in can't be replayed.
- Seeker status: the wallet must hold a Token-2022 NFT whose mint is a
  member of the Seeker Genesis group; only the group's authority can add
  members. Checked on mainnet at every sign-in. If the RPC is down, the last
  answer stands.
- SKR payments: an order's memo, the treasury's gain in the configured
  mint (from the transaction's token balances), a landed transaction with no
  error, and a signature that hasn't bought anything before. Who paid isn't
  checked. Devnet lookups fall back across keyless RPCs, since Solana's own
  refuses Cloudflare.
- Daily runs: a ticket, one finish, the time window and the score's range.
  The run isn't replayed on the server.

## Mainnet (real SKR)

Not deployed yet. The game's "Android dApp Store" export preset (feature tag
`mainnet`) uses mainnet SKR and `Chain.WORKER_URL_MAINNET`, which stays ""
(offline, unranked) until this is done:

```sh
npx wrangler@4 d1 create yeetfleet-mainnet          # id into [env.mainnet] in wrangler.toml
npx wrangler@4 d1 execute yeetfleet-mainnet --remote --file schema.sql --env mainnet
node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))" | npx wrangler@4 secret put SESSION_SECRET --env mainnet
npx wrangler@4 secret put MAINNET_RPC_URL --env mainnet   # a Helius mainnet URL: required, see below
npx wrangler@4 deploy --env mainnet                 # prints https://yeetfleet-mainnet.<you>.workers.dev
```

Then set `Chain.WORKER_URL_MAINNET` to the printed URL. Without
`MAINNET_RPC_URL` nothing works on mainnet: Solana's public RPC refuses
Cloudflare, so neither the Genesis check nor the payment check can run.
Before taking real SKR, consider moving the treasury to a hardware wallet or
a Squads multisig (`docs/solana-wallets.md`).
