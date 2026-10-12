# Yeetfleet

> **Plugin contribution:** the Godot Mobile Wallet Adapter plugin this game
> uses is in its own repo: **https://github.com/GunroarCannon/critbox-godot-solana-mobile**

Yeetfleet is a one-thumb space brawler for Solana Mobile, built in Godot 4.7.
Drag from your ship to sling it across the fight, ram pirates to bits, and stop
time on every wreck.

## What's in it

- **Daily Sortie:** one seeded level a day, the same for every pilot. Practise
  as much as you like. A Seeker Genesis Token holder gets one ranked run a day,
  armed in the Seed Vault before launch.
- **Sandbox:** free flight with incidents (pirate raids, meteor showers,
  distress calls) and three mini goals on the left of the screen.
- **Campaign:** seeded levels that branch with how you play, a garage of ships
  to buy and upgrade, and cartoon explosions.
- **Solana:** Sign-In-With-Solana in one prompt through Mobile Wallet Adapter.
  SKR pays for extras (an extra ranked run, liveries, sling trails, tips
  between pilots). The leaderboard Worker verifies each payment on-chain before
  it grants anything.
- **Seeker features:** haptics on launch and hit, tilt to aim, Seed Vault
  fingerprint for ranked runs.

## How the Solana side fits together

```
Godot client (modules/chain)        Leaderboard Worker (services/leaderboard-worker)
  Mobile Wallet Adapter  ───────────►  Sign-In-With-Solana sessions (D1)
  SKR transfer to treasury ─────────►  Reads the transaction from Solana (Helius RPC)
                                        Checks: mint, treasury, amount, memo, no error
                                        Grants the item, updates the board
```

The app never holds a private key. The treasury's public address is the only
thing the Worker needs.

## Layout

| Path | What's there |
|---|---|
| `modules/flight/` | Flight, sandbox, campaign, combat, power-ups, HUD |
| `modules/chain/` | Solana wallet façade: sign-in, SKR payments, tips |
| `modules/daily/` | Daily Sortie |
| `modules/menu/` | Menus, STORE, Pilot ID chip |
| `services/leaderboard-worker/` | Cloudflare Worker + D1: sessions, orders, payments, boards |
| `launch/` | Store listing kit, icons, screenshots, demo video kit |
| `docs/` | Design decisions (`docs/decisions/`), wallet addresses, demo script |

## Running it

Requires Godot 4.7 (GL Compatibility renderer).

```
Godot_v4.7-stable_win64_console.exe --path .          # run the game
```

Headless checks (add `--audio-driver Dummy` so they stay silent):

```
godot --path . --headless --audio-driver Dummy --script modules/flight/tools/sandbox_check.gd
godot --path . --headless --audio-driver Dummy --script modules/chain/tools/chain_check.gd
```

The Worker's tests need no dependencies:

```
cd services/leaderboard-worker && npm test
```

## Leaderboard Worker

The devnet Worker runs on Cloudflare's free plan. See
`services/leaderboard-worker/README.md` for setup, and for the mainnet deploy
(`scripts/deploy_mainnet.sh`, which needs a Helius RPC key).

## Builds

| Build | How |
|---|---|
| Devnet release APK | Preset "Android" with `--export-release` |
| Mainnet dApp Store APK | Preset "Android dApp Store" (feature tag `mainnet`), signed with the dApp Store key |

Keys are never in the repo. The signing keystore lives outside it, and the
treasury key is kept in the user's config folder.

## Status

- Devnet: sign-in, Daily Sortie, ranked runs and SKR payments (dSKR, a test
  token) are working end to end.
- Mainnet: the APK is built; the Worker still needs its mainnet deploy.

## Licence

To be decided before the public repo is opened. Until then, all rights are
reserved.
