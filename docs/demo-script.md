# Yeetfleet demo video: shot list (CLOCK IN)

About 2 minutes, recorded on the phone (screen recording) with Phantom on
devnet, or on a Seeker for the Seed Vault shot. Judging pillars in brackets:
stickiness, UX, innovation/hardware, demo. Narration is a suggestion; captions
work as well.

**Before recording:** a fresh install of the release APK; Phantom in
Testnet mode (devnet) holding a little SOL and some dSKR
(`docs/solana-wallets.md` has the mint command); flight school done and
level 3 won, so SANDBOX and the DAILY SORTIE are open; the pilot wallet in
the Worker's `DEV_GENESIS_OWNERS` unless it holds a real Genesis Token.

| # | Time | On screen | Say |
|---|---|---|---|
| 1 | 0:00–0:10 | The home screen, the fight behind the title. A sling launch in a level, a ram, a wreck in slow-mo. | "Yeetfleet: pull back, let go, yeet. A one-thumb space brawler, built for Seeker." |
| 2 | 0:10–0:25 | Tap **CONNECT WALLET**. Phantom opens once: connect and sign in, one prompt. Back to the chip: key, SKR balance, **GENESIS**. Open the Pilot ID card. | "One Sign-In-With-Solana prompt connects the wallet and signs in to the leaderboard. The Seeker Genesis Token is the ranked pass." [UX] |
| 3 | 0:25–0:40 | **DAILY SORTIE**: today's level, the countdown, the streak, the RANKED / OPEN boards. | "One level a day, the same for every pilot. Practise all you like; one ranked run per Seeker. Keep your streak." [stickiness] |
| 4 | 0:40–0:55 | **RANKED RUN** → the wallet asks to sign "arm the sling" (on a Seeker: the fingerprint). The level loads. | "Each ranked run is armed in the Seed Vault: a fingerprint, not a bot. Back out and you keep the run." [innovation/hardware] |
| 5 | 0:55–1:15 | The flight: a few slings, hits (mention the haptics), a win. No RETRY on a ranked run. Back to the board: points and **RANK**. | "Every launch and hit buzzes the phone. One shot at it; the board updates straight away." |
| 6 | 1:15–1:35 | **+1 RANKED RUN · 25 SKR** → Phantom → "checking the payment on chain" → granted. Or the STORE's **SKR** tab: buy **24 KARAT**, it's WORN; the next flight's ship is gold. | "SKR buys the extras. Each payment carries an order memo; the leaderboard checks it on chain before it grants anything." [SKR utility] |
| 7 | 1:35–1:45 | On the board, **TIP** a rival 10 SKR. | "Tip a rival, wallet to wallet. We never hold anyone's SKR." |
| 8 | 1:45–2:00 | Settings: **BUZZ**, **TILT TO AIM**. End on the title. | "Seeker-native: Seed Vault, haptics, tilt to aim. Yeetfleet." |

**Proof shots for the judges** (optional end card): the payment on Solana
Explorer (devnet) with its `yeetfleet:<order>` memo; the repo's test runs
(`npm test`: 37 Worker tests; `devnet_pay_check`: a real dSKR payment
verified by the live Worker).

**What not to claim:** runs aren't replayed on the server; the score is
checked for its range, the ticket and the time window (README, "What is and
isn't trusted").
