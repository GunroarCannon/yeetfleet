# Yeetfleet demo voice-over, for an AI voice (Google AI Studio and the like)

The cut is `out/yeetfleet_demo.mp4` (1:21.6). 20 short lines, 169 words, each
with the second it starts and the window it has to fit. Generate **one audio
file per line** (an AI voice reads at its own speed and a long read drifts off
the picture), then `vo_place.sh` drops each file at its start time.

## The idea: an arc, not one volume

A judge scores the Solana part: wallet sign-in, the Seed Vault, SKR paid and
checked on chain. Those lines (07, 10-11, 14-18) have to be *heard*. A whole
80 seconds of furious shouting buries them, and the video's own sound is ducked
under the voice anyway. So the read goes:

| Beat | Lines | Energy |
|---|---|---|
| Hook | 01-03 | tense, held breath, then one explosive YEET |
| Title and play | 04-06 | gravelly announcer, grinning, fast |
| Wallet and Daily | 07-13 | confident and clear, a smirk, the weight on "one shot" |
| Proof | 14-18 | measured and trustworthy, still driving, firm on "on chain" and "never" |
| Seeker list | 19 | rapid staccato, one punch per word |
| End | 20 | the hook again, biggest yet |

## 1. The system prompt (AI Studio "System instructions", once)

```
You are the voice of a video game trailer for "Yeetfleet", a one-thumb space
brawler on Solana Mobile. You are a gravelly, charismatic announcer: a movie
trailer voice with a grin, never robotic, never reading.
- One voice, one character, the whole way through.
- Each message gives you a DIRECTION and the LINE. Perform the direction. Say
  the LINE exactly once, word for word. Never say the direction, a label, a
  number, or anything extra. No sound effects. No pause before the first word
  and none after the last.
- Keep to the TARGET length (seconds). Faster is better than slower.
- Pronunciation: "Yeet" rhymes with "heat". "Yeetfleet" is "YEET-fleet". "S K R"
  is three letters, "ess kay are". "Solana" is "so-LAH-na". "Seeker" is
  "SEE-ker". "Sortie" is "SOR-tee". "Livery" is "LIV-er-ee".
```

Voice: pick **one** and keep it for all 20 lines. For the growl, try
**Algenib** (gravelly) or **Fenrir** (excitable); **Puck** or **Zephyr** if you
want it lighter. Don't change between lines.

## 2. The lines

Paste each block as one message, export as WAV, name it by its number
(`01.wav` ... `20.wav`) in one folder. Leave the number and the words
"DIRECTION", "LINE" and "TARGET" in: they are for the model, and the system
prompt tells it not to say them. (Capitals in a line make a voice shout, so
the lines are written in sentence case and the direction does the shouting.)

```
DIRECTION: low, close to the mic, tense, a coiled growl. Drawing a bowstring.
LINE: Pull back.
TARGET: 0.8 s

DIRECTION: clipped, breath held, almost a whisper, the trigger about to go.
LINE: Let go.
TARGET: 0.7 s

DIRECTION: full-throat explosive shout, rage and joy, huge, cut off hard at the end.
LINE: Yeet!
TARGET: 1.0 s

DIRECTION: proud trailer announcer, a slam on "YEET-fleet", then a grin for the second half.
LINE: Yeetfleet. The one-thumb space brawler.
TARGET: 2.4 s

DIRECTION: fast, loud, excited, grinning, rising all the way. Punch "ricochets" and "boss".
LINE: Pull back, let go. Your ship ricochets off everything it hits, and every sector ends on a boss.
TARGET: 6.5 s

DIRECTION: cool and easy, a smirk, like it's nothing at all.
LINE: One tap connects your wallet.
TARGET: 2.0 s

DIRECTION: clear and confident, a touch slower on "Sign-In-With-Solana", a nod on "no sign-up", proud on "ranked pass".
LINE: One Sign-In-With-Solana prompt. No password, no sign-up. Your Seeker Genesis Token is your ranked pass.
TARGET: 7.5 s

DIRECTION: low gravel slam, chapter-card announcer, two hits.
LINE: The Daily Sortie.
TARGET: 1.6 s

DIRECTION: relaxed, friendly, quick, inviting.
LINE: One level a day. Practise all you like.
TARGET: 2.5 s

DIRECTION: conspiratorial, hushed, a click of weight on "armed".
LINE: A ranked run is armed in the Seed Vault.
TARGET: 3.0 s

DIRECTION: dramatic hush then a hit on "one shot", a beat of silence before "No retries", dead serious.
LINE: You sign, and it's one shot. No retries.
TARGET: 3.3 s

DIRECTION: excited, physical, laughing under the words, the thrill of it.
LINE: Every launch and every hit buzzes the phone. You feel every yeet.
TARGET: 5.0 s

DIRECTION: triumphant, rising, a win. Land hard on "straight away".
LINE: One shot, and the board updates straight away.
TARGET: 4.2 s

DIRECTION: switch to trustworthy and measured, a tech-confident tone, still driving. Hard on "on chain".
LINE: S K R buys the extras. A Cloudflare Worker checks every payment on chain before anything is granted.
TARGET: 6.4 s

DIRECTION: upbeat, friendly, a quick sales grin.
LINE: Twenty-five S K R buys an extra ranked run.
TARGET: 3.4 s

DIRECTION: crisp, satisfied, ticking a box.
LINE: One prompt, paid and checked on chain.
TARGET: 2.6 s

DIRECTION: celebratory, "Granted." lands like a stamp, then a quick happy run of the rest.
LINE: Granted. Liveries, trails, tips: wallet to wallet.
TARGET: 2.7 s

DIRECTION: earnest and sincere, a little slower, warm, firm and flat on the last sentence.
LINE: Godot, our own wallet plugin, and a Worker that checks everything on Solana. We never hold your keys.
TARGET: 6.6 s

DIRECTION: rapid-fire staccato, each word a punch, four hits in a row.
LINE: Seed Vault. Genesis pass. Haptics. Tilt to aim.
TARGET: 2.6 s

DIRECTION: the opening again, bigger: low and tense for "Pull back", sharp for "Let go", the loudest shout of the whole video on "Yeet", let it ring.
LINE: Yeetfleet. Pull back. Let go. Yeet!
TARGET: 3.8 s
```

If a line comes back long, regenerate it with "TARGET: 0.3 s less, a bit
faster". `vo_place.sh` also speeds a line up to 1.3x on its own.

| # | Start | Window | On screen |
|---|---|---|---|
| 01 | 0:01.50 | 0.8 s | Hook: PULL BACK |
| 02 | 0:02.35 | 0.7 s | Hook: LET GO |
| 03 | 0:03.10 | 1.0 s | Hook: YEET! burst (lands 1.75 s into the hook) |
| 04 | 0:05.70 | 2.4 s | Title: YEETFLEET |
| 05 | 0:08.30 | 7.1 s | Gameplay |
| 06 | 0:15.75 | 2.1 s | Home: ONE TAP: CONNECT WALLET |
| 07 | 0:18.10 | 8.6 s | Phone: Phantom sign-in (the stamp) |
| 08 | 0:27.00 | 1.7 s | Chapter card: DAILY SORTIE |
| 09 | 0:28.90 | 2.7 s | Phone: Daily Sortie, caption 1 |
| 10 | 0:31.75 | 3.2 s | Phone: Daily Sortie, caption 2 (the stamp) |
| 11 | 0:35.05 | 3.5 s | Phone: Daily Sortie, caption 3 |
| 12 | 0:39.10 | 5.4 s | Ranked run |
| 13 | 0:44.90 | 4.8 s | Phone: board |
| 14 | 0:50.00 | 6.8 s | How SKR pays |
| 15 | 0:57.10 | 3.8 s | Phone: SKR shop, caption 1 |
| 16 | 1:01.10 | 2.8 s | Phone: SKR shop, caption 2 (the stamp) |
| 17 | 1:04.00 | 2.9 s | Phone: SKR shop, caption 3 |
| 18 | 1:07.10 | 7.1 s | Under the hood |
| 19 | 1:14.45 | 2.9 s | Seeker-native |
| 20 | 1:17.60 | 4.0 s | End card |

The same times and words are in `vo_lines.tsv` (the file `vo_place.sh` reads:
change a start time or a line there, then re-run).

## 3. Put them on the timeline

```bash
bash launch/video/vo_place.sh path/to/lines          # -> launch/video/out/vo_track.wav
bash launch/video/vo_mix.sh launch/video/out/vo_track.wav    # over the music cut -> out/yeetfleet_demo_vo.mp4
BASE=launch/video/out/yeetfleet_demo.mp4 bash launch/video/vo_mix.sh launch/video/out/vo_track.wav   # over the no-music cut
```

`vo_place.sh` trims the silence a voice leaves at the start and end of each
file, puts it at its start time and, if it runs longer than its window, speeds
it up to fit (at most 1.3x; past that it says **TOO LONG**: generate that line
again, shorter or with "a bit faster" in the direction). It prints each line's
length against its window.

## What not to claim

- Runs aren't replayed on the server: the score is checked for its range, the
  ticket and the time window. Don't say "cheat-proof".
- The devnet demo uses dSKR, a test token; say "S K R" for the mainnet build.
- The recording phone is a Redmi running Phantom, not a Seeker: "armed in the
  Seed Vault" is what the app does on a Seeker, so keep that wording.
- The treasury receives the SKR you pay for an extra, so don't say "we never
  hold your S K R" (the old line 18). "We never hold your keys" is true: the
  Worker only ever has the treasury's public address.

## The trailer (music only)

`out/yeetfleet_demo_music.mp4` as it is: the same cut with the game's songs and
the sound effects, no voice. Cut it down to 60 s by dropping the "How SKR pays"
(49.8 s) and "Under the hood" (67.0 s) parts if a platform wants it shorter.
