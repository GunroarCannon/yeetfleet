# level-gen.md — Cross-level arcs & the meta loop

**Companion to:** `level-setup.md` (level anatomy, generator grammar) and `GAMEDOC.md` §8/§9/§11.
What happens *between* levels: arcs, run mode, and how all of it is shown without text walls.

---

## 1. Cross-level arcs

An arc is unfinished business that survives the level-end screen. Three arc
types, each carried by a system that already exists in the plan:

| Arc | Carrier | Loop |
|---|---|---|
| **Grudge** | M5 `RepStore` (saved, not session-scoped) | Witnessed chaos → hunters escalate → a "clear your name" chain closes the arc |
| **Favor** | M5 witnesses, inverted | Rescue the same faction twice → their ships fly formation with you, their territory opens |
| **Garage** | unlock track | Medals → next hull → every old level replays as a new physics problem |

Arc state is data — plain dictionaries, per the `RepStore` serialisation rule —
so the generator can attach arc beats to generated levels deterministically:

```
arc_beat(level N) = f(seed, arc_state, N)
```

No arc is ever authored per level; arcs are derived state, like everything else.

## 2. Communicating arcs with (almost) no words

The game's own rules (§9 icons, §11 behaviour-not-numbers) applied to arcs:

- **The level's opening composition IS the arc status.** A patrol already facing
  your spawn = they remember. A bounty wing at the map edge = grudge hot.
- **Escalation of pursuers is the meter.** One angry scout → a coordinated wing
  → a heavy with a grudge banner. Who shows up *is* the number; no bar needed.
- **Recurring NPCs are the favour meter.** The hauler you saved in level 3 shows
  up in level 7 and honks. Behaviour, not a friendship bar.
- **Faction emblem + red pulse = arc active. Emblem alone, paled = resolved.**
  Same one-look vocabulary as 🚨 / 🎯 / 📦.
- **One line is permitted on the level-end screen** (menu space, not in-world):
  "The Magnetic Union remembers." Four words beat any reputation panel.
- **Wordbank names can carry a beat:** "Old Debts", "The Hunt", "Reckoning".

**Acceptance test:** after two encounters, a player can describe the arc in
their own words. If they can't, escalate the *behaviour* — never add text.

## 3. Modes (decision record)

**Run mode / roguelike layer: considered and rejected.** Permadeath resets
fight "the universe remembers", and run-balance is a tuning treadmill.
Two modes, one simulation:

| Mode | Job |
|---|---|
| **Campaign** | authored chapters; onboarding; primary arc carrier |
| **Sandbox** | the infinite toy; clip generator |

The daily seed ships as a single seeded generator level, not a separate mode.

## 4. One-more-turn kit (level-end levers)

1. **Dangled medal** — show the near-miss: "Impacts 6 — Gold needs ≤5".
   Same-seed levels make it a skill claim, not a grind hint.
2. **Next twist, one line**, icon-first: "Next: the cargo is explosive."
3. **Always three buttons: [Next] [Replay] [Sandbox]** — an infinite-mode
   fallback one tap from every level end; nobody hits a menu wall.
4. **Failure advances the story** — notoriety, medal bank, sometimes spawns the
   next level ("after the wreck, a salvage crew heard about you…").
5. **Garage shows the next hull** always 1–2 levels away, silhouette + medal
   icons only. Each unlock re-sells every old level.
