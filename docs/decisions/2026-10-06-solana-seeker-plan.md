# Solana Seeker integration: plan (branch `solana-integrated`)

Target: the CLOCK IN Solana Mobile hackathon (Seeker). Four judging pillars,
25% each: **stickiness**, **UX polish**, **innovation / mobile hardware**,
**demo**. There's also a separate $10k bounty for the best **SKR** utility.
Required: an Android APK using Mobile Wallet Adapter, a public repo, a demo
video, a pitch deck, and a Solana dApp Store listing.

Status 2026-10-08: the plugin passed P0–P2 on the API 36 emulator with
Phantom (SIWS, SOL and dSKR transfers confirmed on devnet); **G0 is done**.
The wallet plugin
lives in its own repo, `critbox-godot-solana-mobile` (its plan is
`docs/PLAN.md` there). This branch only consumes its release addon.

## The pitch in one line

**Yeetfleet** (the dApp Store name): sling your toy ship through a bullet-hell sortie. One daily
run per Seeker, a global leaderboard, a streak to protect, and SKR as the fuel
for everything extra.

## How each judging pillar is met

| Pillar | What earns it |
|---|---|
| Stickiness | **Daily Sortie**: one LevelGen seed per UTC day, the same for every pilot. One *ranked* attempt per Seeker Genesis Token, unlimited practice. Streak counter, weekly season, "beat your rival" push from the leaderboard. |
| UX | Guest play first; the wallet is asked for only when it pays off (going ranked). One Sign-In-With-Solana prompt does connect and sign-in together. No wallet popups mid-run. Every wallet wait has a busy state and a clean cancel. |
| Innovation / hardware | **Seed Vault "arm the sling"**: the ranked run ticket is signed with the fingerprint, as the launch itself. Haptics on sling release and hits. Optional gyro aim dial. The Seeker Genesis Token unlocks a Genesis Pilot badge and hull. |
| Demo | A scripted demo path (`Session.boot_module`), from connect through a ranked run and a leaderboard climb to an SKR tip, recorded on the phone. |

## Decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Wallet plumbing | Use the `critbox-godot-solana-mobile` addon (Kotlin MWA plugin + `SolanaMobileClient` GDScript wrapper, with a built-in mock wallet) dropped into `addons/solana_mobile/`. It is copied in, not a submodule | The user asked for the plugin in its own repo; copying keeps exports simple | the addon's API settles at 1.0, when a pinned release zip would be better |
| Game façade | New `modules/chain/`, `class_name Chain`, static API + `Notifier` signals, **same shape as `CoinStore`** | Matches the house pattern for a façade over a native singleton with a desktop fake | — |
| Cluster | Develop on **devnet** with our own test mint, "dSKR" (6 decimals, like SKR). Release builds use mainnet SKR `SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3` (classic SPL Token, 6 decimals, checked on chain 2026-10-06) | Real SKR is real money; devnet keeps tests free | — |
| Backend | **Cloudflare Worker + D1** in `services/leaderboard-worker/` on this branch | The user chose it. Free tier, keeps the Helius key out of the APK, has Ed25519 in WebCrypto | — |
| Identity | SIWS (Sign-In-With-Solana) → the Worker verifies the signature and checks the Seeker Genesis Token with Helius (`getTokenAccountsByOwnerV2`, skipping zero-balance accounts, group `GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te`), then issues a short session token. Rate limits and ranked attempts are keyed by the **Genesis Token mint**, not the wallet | Solana Mobile's own anti-sybil recipe; one Seeker = one ranked pilot | — |
| Non-Seeker phones | Fully playable: practice runs plus an *unranked* daily board. The ranked board needs a Seeker Genesis Token | Judges may test on any Android; the Seeker gets the premium status | — |
| Score trust | The server issues a run ticket (nonce + seed) at start. The client returns score, duration and stats; the Worker checks the ticket, the time window, and a score ceiling derived from the seed's par (`StarRating`). Full replay verification is out of scope | Honest about limits; security auditors are judges, so the pitch says exactly what is and isn't verified | if a cheater shows up during judging, add input-log replay |
| SKR uses | (1) **Extra ranked attempts** sent to a treasury, with a share burned. (2) **Seeker cosmetics**: hull paints, decals, sling trails. (3) **Tip a pilot**: a direct wallet-to-wallet SKR transfer from the leaderboard (no custody). (4) Stretch: **boss bounties** | Sinks plus social utility; nothing pay-to-win; no custody of user funds | — |
| Prize pools funded by entry fees | **Not doing** | Looks like gambling and is jurisdiction-dependent; season prizes come from the treasury or sponsors instead | if the organizers explicitly allow it |
| Payment check | Each SKR transfer carries a Memo with a server-issued order nonce. The Worker confirms it with Helius `getTransaction` (mint, amount, destination token account, memo, unused signature) before granting anything | No trust in the client's "I paid" | — |
| RevenueCat coins in the Seeker build | **Off** in the dApp Store build (Google Play Billing does not work outside Play). Coins stay earned in-game; the SKR shop replaces packs. Play builds keep `CoinStore` | Store rules, plus fewer dead buttons | — |
| SKR prices (2026-10-08) | Extra ranked attempt **25 SKR**, hull paint **50**, decal **75**, sling trail **100**; tip buttons **10 / 50 / 100**. In `Chain.PRICES` / `Chain.TIP_PRESETS` | SKR ≈ $0.016–0.022 (cap ~$111–152M, ATH $0.056): an attempt ≈ $0.50, cosmetics ≈ $1–2, so impulse-sized for a daily game | SKR moves more than ~2× either way |
| Burn share | **10%** of SKR received, burned by the treasury in weekly batches (`docs/solana-wallets.md`) | A per-payment burn needs a second instruction (and the payer burning their own tokens), which complicates the Worker's payment check; batches keep each payment a plain transfer | — |
| Treasury | A fresh keypair, `2ZGn8kxkJae4Q4sjU2uZiXT5x5ZtzSQh2P1KASYTn4R1`, same on both clusters; secret off-repo (`docs/solana-wallets.md`) | The user had none; one address keeps config simple | before mainnet: a hardware wallet or Squads multisig |
| SIWS nonce | The plugin's `sign_in` takes SIWS fields (plugin 0.2.0); the Worker issues a one-use nonce that expires in 5 min | Without it a captured sign-in could be replayed | — |
| Worker code | Plain JS, no dependencies; tests on Node's built-in runner + `node:sqlite` as a D1 stand-in; a local dev server for the game's headless checks | Nothing to install or keep updated; the same SQL runs in tests and in D1 | if the Worker outgrows one file per concern |
| Haptics | `Input.vibrate_handheld` (VIBRATE permission) behind a Juice dial, default on | No plugin needed; matches the dial convention | — |

## Module and API shape (planned)

```
modules/chain/                       class_name Chain (façade)
  scripts/chain.gd                   connect(), sign_in(), disconnect(), pubkey(),
                                     is_seeker(), has_genesis(), skr_balance(),
                                     pay_skr(amount, memo) / tip(pubkey, amount)
                                     → Notifier signals (connected, failed, paid…)
  scripts/chain_api.gd               HTTP client for the Worker (session token)
  tools/chain_check.gd               mock: connect, cancel, no-wallet, pay, tip
modules/daily/                       class_name DailySortie
  scripts/daily_sortie.gd            today(), start_ranked(), submit(), streak()
  scripts/ui/leaderboard_panel.gd    day / season / friends-by-tip tabs
  tools/daily_check.gd               seed stable per date, one ranked attempt,
                                     offline fallback is unranked
services/leaderboard-worker/         Worker + D1 (wrangler), its own tests
  /auth/challenge  /auth/verify  /daily  /run/start  /run/finish
  /leaderboard  /order/new  /order/verify
```

Menu touch points: a **Pilot ID** chip (wallet, Genesis badge, SKR balance),
a **Daily Sortie** button on home, the leaderboard screen, and an SKR tab in
the existing shop. The new screens get shots at both phone sizes.

## Milestones (after plugin milestones P0–P2 are green on the phone)

| # | Done when |
|---|---|
| G0 ✅ | Addon copied in; `Chain` façade over the addon client and its mock; `chain_check` passes headless (2026-10-08, 23 checks) |
| G1 ✅ (code) | Pilot ID chip: connect / SIWS / disconnect / reconnect on the phone with Phantom; Seeker detection. Done headless (`pilot_chip_check`) and in shots; the on-phone pass is batched with G4's |
| G2 ✅ (code) | Worker deployed: SIWS verify, Genesis Token check, session token; D1 schema; Worker tests. Written and tested (14 Node tests, `chain_server_check` end to end); **deploy waits on the user's Cloudflare login** (`services/leaderboard-worker/README.md`) |
| G3 | Daily Sortie: ranked ticket → run → submit → leaderboard; streaks; `daily_check` passes |
| G4 | SKR: order → transfer with memo → verify → grant (extra attempt, cosmetic); tip a pilot. Devnet dSKR end to end |
| G5 | Hardware polish: "arm the sling" signature, haptics, gyro dial; menu shots at phone sizes |
| G6 | Ship: release keystore, mainnet config, dApp Store publish (publisher + app NFTs, needs SOL), demo video, deck |

## Open questions for the user

- The hackathon deadline (it sets how much of G4's stretch and G5 fits).
- G2 needs a Cloudflare account login (`npx wrangler@4 login`) and,
  ideally, a Helius key for the mainnet Genesis check.
- Answered 2026-10-08: app name **Yeetfleet**; SKR prices and burn share as
  above (revisit freely); treasury created.
