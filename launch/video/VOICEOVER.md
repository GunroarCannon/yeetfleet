# Yeetfleet demo: voice-over script

> For an AI voice (Google AI Studio and the like), use **`VOICEOVER_AI.md`**:
> one timed line per file, and `vo_place.sh` puts each at its second. This
> page is the plain read-through for a human reader.

For the 1:22 cut (`out/yeetfleet_demo.mp4`, no music). About 150 words, a
calm, quick read, about 2.6 words a second; leave the gaps, the sound effects
and the music carry them. Times are where each part starts in the video
(`out/seg/times.txt`); the lines are timed to fit, so read each inside its
window.

| Time | Part (on screen) | Window | Say |
|---|---|---|---|
| 0:00.0 | Studio splash | 1.4 s | *(silence)* |
| 0:01.4 | **Hook**: PULL BACK. LET GO. YEET! | 4.2 s | "Pull back. *(beat)* Let go. *(beat)* **Yeet!**" (land YEET on the burst, 1.75 s in) |
| 0:05.6 | **Title**: YEETFLEET | 2.6 s | "Yeetfleet. A one-thumb space brawler." |
| 0:08.2 | **Gameplay** | 7.5 s | "Thumb on the ship, pull back, let go. It ricochets off everything it hits, and every sector ends on a boss." |
| 0:15.7 | **Home**: ONE TAP: CONNECT WALLET | 2.2 s | "One tap connects your wallet." |
| 0:17.9 | **Phone, Phantom** (the stamp) | 9.0 s | "One Sign-In-With-Solana prompt: connected and signed in. The Seeker Genesis Token is your ranked pass." |
| 0:26.9 | **Chapter**: DAILY SORTIE | 1.9 s | "The Daily Sortie." |
| 0:28.8 | **Phone, Daily Sortie** | 10.0 s | "One level a day, the same for every pilot. Practise all you like. A ranked run is armed in the Seed Vault: you sign, one shot, no retry." |
| 0:38.8 | **Ranked run** | 6.0 s | "No retry. Every launch and every hit buzzes the phone." |
| 0:44.8 | **Phone, board** | 5.0 s | "One shot at it, and the board updates straight away." |
| 0:49.8 | **How SKR pays** | 7.2 s | "SKR buys the extras. The wallet pays with an order memo; the leaderboard checks it on chain before it grants anything." |
| 0:57.0 | **Phone, SKR shop** | 10.0 s | "Twenty-five SKR for an extra ranked run. One prompt, checked on chain, granted. Liveries, trails, and tip a rival, wallet to wallet." |
| 1:07.0 | **Under the hood** | 7.4 s | "A Godot game, our own Mobile Wallet Adapter plugin, Phantom and the Seed Vault, and a Cloudflare Worker that checks everything on Solana. We never hold anyone's SKR." |
| 1:14.4 | **Seeker-native** | 3.0 s | "Seed Vault, Genesis pass, haptics, tilt to aim." |
| 1:17.4 | **End card** | 4.2 s | "Yeetfleet. Pull back. Let go. Yeet." |

## Read-through (no times)

> Pull back. Let go. Yeet! Yeetfleet, a one-thumb space brawler. Thumb on the
> ship, pull back, let go. It ricochets off everything it hits, and every
> sector ends on a boss. One tap connects your wallet. One
> Sign-In-With-Solana prompt: connected and signed in. The Seeker Genesis
> Token is your ranked pass. The Daily Sortie. One level a day, the same for
> every pilot. Practise all you like. A ranked run is armed in the Seed Vault:
> you sign, one shot, no retry. Every launch and every hit buzzes the phone.
> One shot at it, and the board updates straight away. SKR buys the extras.
> The wallet pays with an order memo; the leaderboard checks it on chain
> before it grants anything. Twenty-five SKR for an extra ranked run. One
> prompt, checked on chain, granted. Liveries, trails, and tip a rival,
> wallet to wallet. A Godot game, our own Mobile Wallet Adapter plugin,
> Phantom and the Seed Vault, and a Cloudflare Worker that checks everything
> on Solana. We never hold anyone's SKR. Seed Vault, Genesis pass, haptics,
> tilt to aim. Yeetfleet. Pull back. Let go. Yeet.

Say the name "Yeetfleet" like "yeet-fleet"; the SKR token is "S-K-R".

## What not to claim

Runs aren't replayed on the server: the score is checked for its range, the
ticket and the time window. The devnet demo uses dSKR, a test token; say
"SKR" only for the mainnet build. If you say "Seeker", the phone in the
recording is a Redmi running Phantom, not a Seeker: the Seed Vault line is
what the app does on a Seeker, so keep it phrased as "armed in the Seed
Vault", not "as you can see".

## The two videos

- **The demo, with your voice**: record the lines (a quiet room, a phone mic
  close up is fine), save as `vo.wav`, then
  `bash launch/video/vo_mix.sh vo.wav` puts it over
  `out/yeetfleet_demo_music.mp4`, the game's songs ducked under it
  (`out/yeetfleet_demo_vo.mp4`). Or over the no-music cut:
  `BASE=out/yeetfleet_demo.mp4 bash launch/video/vo_mix.sh vo.wav`.
- **The trailer**: `out/yeetfleet_demo_music.mp4` as it is: the same cut with
  the songs and the effects, no voice. Cut it shorter by dropping the "How
  SKR pays" and "Under the hood" parts if a platform wants 60 s.
