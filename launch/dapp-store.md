# Yeetfleet on the Solana dApp Store

The listing kit for the Solana Mobile dApp Store (and the CLOCK IN
hackathon's submission). The Play Store kit is `launch.md`; the art and
screenshots are shared.

## What's ready

| Item | Where | Notes |
|---|---|---|
| Signed release APK (devnet) | `../Yeetfleet-release-devnet.apk` (outside the repo) | `"$GD" --headless --path . --export-release "Android" ../Yeetfleet-release-devnet.apk`. Live devnet leaderboard, dSKR |
| Mainnet APK | preset **Android dApp Store** (feature tag `mainnet`) → `../Yeetfleet-dappstore-mainnet.apk` | Real SKR. Build it only after the mainnet Worker is up (`services/leaderboard-worker/README.md`, "Mainnet"); until then it plays offline and unranked |
| Signing key | `~/.config/yeetfleet/yeetfleet-dappstore.keystore`, alias `yeetfleet`; password in `~/.config/yeetfleet/dappstore-keystore.txt` | **Back both up now.** Every future update must be signed with this key; lose it and the app can never be updated. It's the dApp Store's own key, not a Play key, as the store requires. SHA-256 `49:45:C4:6E:…:56:E6:D7` |
| Icon 512×512 | `launch/icon_512.png` | |
| Screenshots (≥4, ≥1080 px each side, one orientation) | `launch/screenshots/01_home.png` … `09_skr_shop.png`, 1920×1080 | `"$GD" --path . --audio-driver Dummy --script launch/tools/store_shots.gd` (windowed) |
| Feature graphic | `launch/feature_graphic.png` (1024×500) | |

Version: `version/code` must go up by one for every release (both presets
start at 1); `version/name` is free text (1.0.0).

## Listing copy

- **Name:** Yeetfleet
- **Short description:** Sling your ship into space fights. One daily sortie, one leaderboard, SKR for the extras.
- **Long description:**

  Pull back, let go, YEET. Yeetfleet is a one-thumb space brawler: drag from
  your ship to sling it across the fight, ram pirates to bits and stop time on
  every wreck.

  **Daily Sortie.** One level a day, the same for every pilot. Practise as
  much as you like; a Seeker gets one ranked run a day, armed with a
  fingerprint in the Seed Vault before launch. Climb the ranked board, keep
  your streak alive.

  **Built for Seeker.** Sign in with Solana in one prompt. The Seeker Genesis
  Token is your ranked pass and comes with the Genesis livery. Haptics on
  every launch and hit, and an optional tilt-to-aim.

  **SKR, for the extras.** An extra ranked run, liveries worn over every
  hull, sling trails. Every payment is checked on chain by the leaderboard
  before anything is granted. Tip a rival straight from the board, wallet to
  wallet.

  Plus the full campaign: seeded levels that branch with the way you play, a
  garage of ships to buy and upgrade, and a lot of cartoon explosions.

- **Category:** Games → Action
- **Website / support:** https://gunroarcannon.github.io, also the app's
  Mobile Wallet Adapter identity. Its `/.well-known/assetlinks.json` lists
  `com.critbox.yeetfleet` with the **debug** key only; `launch/assetlinks.json`
  is that file with the release key added. Copy it to the Pages repo's
  `.well-known/` before release, or Phantom asks for approval again on every
  reconnect from the release APK.
- **Privacy:** the game saves on the device. Signed in, the leaderboard
  Worker keeps the wallet's public key, the pilot name, the day's runs and
  SKR orders. No other personal data.

## Publishing: the steps only you can do

From the Solana Mobile docs (checked 2026-10-09; confirm on the portal):

1. Make a **publisher account** in the dApp Store Publisher Portal and pass
   its **KYC/KYB** check.
2. Connect a Solana wallet as the **publisher wallet**, holding about
   **0.2 SOL** (mainnet) for the NFT mints and the ArDrive upload. Keep this
   wallet: every future release needs it.
3. Create the app: upload the APK, the icon, the screenshots and the copy
   above. Choose ArDrive for storage. The portal mints the App NFT and the
   Release NFT.
4. Later releases: bump `version/code`, export, sign with the same key, and
   publish a new release (the portal, or the `dapp-store` CLI with a
   `DAPP_STORE_API_KEY`).

Sources: [submit a new app](https://docs.solanamobile.com/dapp-publishing/submit-new-app),
[prepare your dApp](https://docs.solanamobile.com/dapp-publishing/prepare),
[build and sign an APK](https://docs.solanamobile.com/dapp-store/build-and-sign-an-apk),
[publishing releases](https://docs.solanamobile.com/dapp-store/publishing_releases).

## Going to mainnet: the order, and what it costs

1. **Worker (free).** Cloudflare's free plan runs the Worker and its D1
   database at this scale. Get a free Helius key (Solana's public RPC
   refuses Cloudflare), then in a Git Bash:
   `bash services/leaderboard-worker/scripts/deploy_mainnet.sh <helius-key>`.
   It sets the RPC URL and a random `SESSION_SECRET`, and deploys. Check
   `curl <mainnet worker>/shop` says `"cluster":"mainnet"`, and
   `curl -i <mainnet worker>/.well-known/assetlinks.json` answers
   `Content-Type: application/json` (that is what clears Phantom's
   "identity could not be verified" banner). Redeploy the devnet Worker
   (`npx wrangler@4 deploy`) for the same route.
2. **Treasury (no SOL needed).** `2ZGn8kxk…n4R1` receives the SKR. The
   payer's wallet creates the treasury's SKR token account on the first
   purchase (`create_ata` defaults to true, payer = the buyer), so the
   treasury needs no SOL and you pay nothing. Back its key up, or better
   point `Chain.TREASURY` and `TREASURY` in `wrangler.toml` at an address
   from a wallet you already keep safe (Phantom, a hardware wallet): the
   Worker only needs the public address, never a key. Real SKR only: do a
   25 SKR test purchase from a second wallet before launch.
3. **Mainnet APK (free).** `"$GD" --headless --path . --export-release
   "Android dApp Store" ../Yeetfleet-dappstore-mainnet-1.apk` (the preset with
   the `mainnet` feature, signed with the dApp Store key). Bump
   `version/code` for every later release.
4. **Test on a real phone.** Phantom's Testnet Mode OFF. On mainnet only a
   real Seeker Genesis Token ranks (`DEV_GENESIS_OWNERS` is devnet only), so
   the ranked run needs a Seeker or a wallet that holds one.
5. **Publisher portal.** KYC/KYB, then the publisher wallet with about
   **0.2 SOL** as a cushion (the only real cost: the NFT mints, a small
   priority fee, and the ArDrive upload sized by the APK, 93 MB; what isn't
   spent stays in the wallet),
   upload APK, icon, screenshots, copy. Review is 3-5 business days. Solana
   Mobile takes no fee on in-app purchases (their FAQ, checked 2026-10-12).

## Hackathon checklist (CLOCK IN)

- [x] Android APK using Mobile Wallet Adapter (release-signed)
- [ ] Public repo (push `solana-integrated` and the plugin repo)
- [x] Demo video: `launch/video/out/yeetfleet_demo.mp4` (with your voice: `VOICEOVER.md`) and `yeetfleet_demo_music.mp4` (trailer); phone parts recorded on the Redmi. Re-record the wallet clip after the devnet Worker redeploy to drop the red banner
- [x] Pitch deck: https://claude.ai/artifact/WNeRy32jTnQMgqxb7uio4m (private until shared from its Share menu)
- [ ] dApp Store listing (the steps above)
