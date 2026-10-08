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

## Test

```sh
npm test          # node --test, Node 22.5+ (node:sqlite)
```

## Deploy (once)

```sh
npx wrangler@4 login
npx wrangler@4 d1 create yeetfleet           # paste the id into wrangler.toml
npx wrangler@4 d1 execute yeetfleet --remote --file schema.sql
npx wrangler@4 secret put SESSION_SECRET      # openssl rand -hex 32
npx wrangler@4 secret put MAINNET_RPC_URL     # https://mainnet.helius-rpc.com/?api-key=…
npx wrangler@4 deploy                         # prints https://yeetfleet.<you>.workers.dev
```

Then set `ChainApi.URL` in the game to the printed URL. After a schema
change, run the `d1 execute` line again (every statement is idempotent).

## What is and isn't trusted

- Sign-in: the signature, the domain, the address and a one-use nonce no
  older than 5 minutes. A captured sign-in can't be replayed.
- Seeker status: the wallet must hold a Token-2022 NFT whose mint is a
  member of the Seeker Genesis group; only the group's authority can add
  members. Checked on mainnet at every sign-in. If the RPC is down, the last
  answer stands.
