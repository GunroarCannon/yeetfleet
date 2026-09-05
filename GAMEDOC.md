# Project Nebula — Game Design Document

**Version:** 2026-09-05 · supersedes the direction implied by `GAMEPLAY_IDEAS.md`
**Status:** direction locked, systems unbuilt

---

## 1. The pitch

> **A physics-driven space sandbox where you are free to fuck around, and the universe remembers what you did.**

Not space GTA. Not a space simulator. Not space pinball. The closest emotional
reference is Goat Simulator's *"shit happens"* energy sitting on top of a real
orbital sandbox, with a physics system the player can gradually master.

The one-sentence test for every feature: **does it produce a story the player
would tell someone else?**

> *"I accidentally started a war because I bumped into a cargo ship."*
> *"I was trying to steal one crate and somehow destroyed a space station."*
> *"I spent 40 minutes trying to escape a faction I pissed off."*

That is the product. Procedural generation is not the pitch — it is the engine
that manufactures those stories.

---

## 2. The one rule everything obeys

> ### Predictable rules + unpredictable situations.
> ### Never random rules + random situations.

This is the line the whole design walks. A collision must always resolve the
same way given the same inputs. The *situations* are chaotic because the world
is dense and everything is physical — not because the simulation is noisy.

The player should be able to reach:

> *"I know what is going to happen if I do this."*

…and then execute it. That sentence is where mastery lives. Any feature that
makes it less true is a bug, no matter how funny it is once.

**Corollary:** the player can have fun without understanding the simulation, but
understanding it makes them better at having fun. Nothing is gated behind
understanding gravity. Everything is *improved* by understanding gravity.

---

## 3. Two modes, one simulation

The project carries two front-ends over one set of systems.

### 3.1 Sandbox (the focus — everything below is written for this)

No menus, no quest log, no docking screens. You fly, you touch things, the
world reacts and remembers. This is where development effort goes.

### 3.2 Career (secondary, later)

The Elite-like layer from `GAMEPLAY_IDEAS.md` — economy, contracts, stations,
long-term progression. It is **not cancelled**, it is **deferred**, and it must
be built on the same physics and the same in-world delivery of missions. A
career contract is still handed to you by a ship that flies up to you; it is
just also written down somewhere.

**Rule:** no system may exist only in Career. If it cannot be expressed as a
physical thing in the sandbox, it does not ship.

---

## 4. Controls: normal, but the ship is a real object

Standard controls. Nothing exotic.

| Input | Action |
|---|---|
| Throttle | Accelerate / reverse |
| Stick | Pitch, yaw |
| Q / E | Roll |
| Boost | Short powerful impulse along the nose |
| Fire | Weapons |
| Assist toggle | Cycles assist → damping → manual |

What makes it ours is not the control scheme, it is what the ship *is*: a mass
with momentum, angular momentum, a collision impulse, and weak stabilisation.

### The distinction that defines the game

| A normal space game | This game |
|---|---|
| Hit asteroid → lose 5 HP | Hit asteroid → **WHAM** → the asteroid goes flying → you spin → you clip another ship → that ship hits a planet → a faction gets angry → you escape at 40% hull |

You did not "lose control." You are now **in a situation you have to recover
from.** That is the entire difference, and it is a physics decision, not a
narrative one.

### Boost is the recovery tool

Physics creates chaos; the player needs one button that says **"NOPE. I'M
GOING THIS WAY."**

```
     asteroid                you hit it              BOOST
        ●                      ● ↗
                                                        🚀 →→→
       🚀 →                🚀 ↙  (spinning)          (control regained)
```

Boost is therefore not a speed upgrade. It is a **skillful recovery tool** with
a cooldown, and mastering *when* to spend it is a core skill. It costs from the
same capacitor as the guns, so a pilot who boosts out of everything has nothing
left to shoot with.

---

## 5. Ships have physical identity

Ship class is expressed through mass and inertia, not through a stat card.
The builder already lets players assemble hulls; those hulls must now *fly*
differently for physical reasons.

| Ship | Feels like | Pros | Cons |
|---|---|---|---|
| **Tiny scout** | A ping-pong ball | Turns instantly, extremely manoeuvrable | Gets thrown around constantly; every impact is a crisis |
| **Cargo hauler** | A wrecking ball | Hard to shift, enormous collision force, plows through traffic | Turns like a brick; cannot dodge, only absorb |
| **Fighter** | Balanced | The reference point | No extremes to exploit |
| **Experimental** | Frictionless | Drifts forever; the player who masters it learns *"oh shit, I can use planets to turn"* | Punishing without gravity literacy |

A player choosing a hauler is choosing a *different physics problem*, not a
worse turn rate.

---

## 6. Space is the pinball table

There are no special pinball levels. Gravity is simply everywhere.

- Planets pull.
- Stars pull hard.
- Black holes pull ridiculously.
- Some ships carry gravity generators.

You aim at Planet A. At the right approach angle you **slingshot** and end up
somewhere else entirely.

> **A beginner:** *"Why the fuck did my ship fly over there?"*
> **An experienced player:** *"hehehe, gravity."*

Same event, different player. That gap is the progression curve, and it costs
nothing to author — the orbital mechanics already exist.

**Design consequence:** gravity must never be silently corrected for the
player. If an assist quietly cancels a slingshot, the game deletes its own best
moment. Assists must disengage on impact and stay disengaged long enough for
the consequence to become visible.

### Dimensionality

Full 6DOF is the default — the player can fly in any direction and orbits work
in any plane. A **plane-locked arcade variant** exists as a separate scene for
readability testing and as a possible simplified mode; it must never become a
second physics implementation.

---

## 7. Physics is the universal interaction language

Do not require a button for everything. Objects have **physical affordances**.

| You see | You can |
|---|---|
| A floating crate | Fly into it → collected |
| An enemy | Shoot it, **or ram it** |
| An asteroid | Mine it, **or hit it into something** |
| A ship | Trade, ram, shoot, follow, or steal its dropped cargo |
| A damaged ship | Bump it and physically **tow** it somewhere |

Touch is the default verb. Flying through a resource cluster collects it:

```
     ◆ ◆ ◆
  ◆ ◆ 🚀 ◆ ◆        VRRRRMMMM
     ◆ ◆
```

Fast, wordless, mobile-friendly. Then depth arrives underneath the same
gesture: different ships have different collection radii; some objects explode
on contact; some belong to a faction and touching them is theft.

**One simple interaction, many rules layered on it.** That is cheaper than many
interactions, and it is what makes the physics system pay for itself.

---

## 8. Missions never stop the action

This is a hard rule.

**Forbidden:**
> MISSION ACCEPTED → open menu → read paragraph → click accept → open map →
> find objective.

**Required:** missions appear as things *happening in the world*.

You are flying. A notification blooms for ~1.5 seconds:

```
        🚨
   DISTRESS SIGNAL


      🚀 enemy
         ↓
🚀 ← civilian
```

You do not accept anything. You go help them, or you do not, and you keep
flying either way. No pause, no confirmation, no log entry.

### Missions as physical objects

| Mission | How it exists in the world |
|---|---|
| **Cargo run** | A friendly ship flies to you with a 📦 icon. You bump it. `CARGO ATTACHED`. Now get it somewhere. |
| **Rescue** | A damaged ship spins helplessly under 🚨. Approach → `TOW` appears → bump it and drag it home. |
| **Bounty** | A ship wearing a 🎯 marker. There is no briefing. You know. |
| **Faction incident** | You ram a patrol. `⚠ HOSTILE` above it. Five minutes later, `⚠ FACTION: ANGRY`. Their ships start recognising you. |

---

## 9. The visual language

Everything is communicated with a tiny, learnable icon vocabulary. **Do not put
constant text on screen.**

| Situation | Signal |
|---|---|
| Friendly | Blue / green indicator |
| Enemy | Red |
| Neutral | White |
| Valuable | Gold |
| Mission | Floating icon |
| Distress | Pulsing 🚨 |
| Wanted | 🎯 target symbol |
| Cargo | 📦 package symbol |
| Resource | ◆ crystal / material symbol |
| New discovery | Brief `!` |
| Faction anger | Faction emblem + red pulse |

The player should eventually read these without translation:
🚨 = something is happening · 🎯 = something wants to kill something ·
📦 = something I can carry · ◆ = something valuable.

**Event bubbles, not quest logs.** A signal appears for ~1.5s, then the *actual
event* is visible in the world. If you are interested, fly there. If not, keep
going. Nothing waits for you.

---

## 10. The universe generates incidents constantly

This is where the Goat Simulator energy comes from. You are flying and the
world simply *does things*:

- Two ships collide (you did not cause it)
- Pirates attack a cargo hauler
- A meteor hits a planet
- A giant ship loses control
- A faction patrol starts chasing another faction
- A rare resource drifts past
- A black hole drags several ships toward it

And sometimes:

- **You cause something stupid.**

That last one is the magic. The incident system's real job is not to entertain
you directly — it is to **put enough moving physical objects near each other
that the player's mistakes become spectacular.**

---

## 11. Factions are memory, not a number

A faction is not a reputation bar. It is a set of ships that **remember your
ship.**

You destroy their cargo hauler. The game does *not* say `Reputation −10`.
Instead, later, in their territory, a patrol sees you:

> `IDENTIFIED: HOSTILE`

…and starts chasing. And you think: *"Oh shit. These guys still remember me."*

That is worth more than any number, and it costs less UI.

### Physics is faction identity

Factions are distinguished by how their ships *behave physically*, so the
player learns the simulation by learning the politics.

| Faction type | Physical signature |
|---|---|
| Heavy | Barely move when hit; ramming them is a mistake |
| Light | Go flying everywhere; fun to scatter, hard to hit |
| Magnetic | Their ships attract nearby objects — your cargo drifts toward them |
| Gravity tech | They alter trajectories; fighting near them is disorienting |
| Explosive idiots | Their ships detonate on death; killing one in a crowd is a chain reaction |

Eventually the player thinks *"oh shit, those are the magnetic guys"* — and
they have learned a physics rule through play, without a tutorial.

**Scope for now:** memory is session-length. Grudges last until you quit. The
system is built behind an interface so persistence can be switched on later
without touching anything that consumes it.

---

## 12. Art direction

Two complete looks, switched by one global toggle.

### Grounded (current)

Faceted low-poly, lit solid metal, panel lines, weathering, dense starfields,
noisy procedural planets.

### Friendly (the new target)

**Round, chunky, soft.** Everything reads as approachable and slightly toy-like.

```
 GROUNDED                FRIENDLY
  /\____/\                ______
 |        |              (      )   fat, stubby,
  \______/                \____/    beveled, no
   sharp facets                     sharp facets
   spec + rim                       soft wrap light
   noisy planet bands               3 flat colour bands
   900 stars                        a few big soft stars
```

This is **not a shader-only change.** Silhouettes actually change: hulls and
rocks get beveled corners, inflated volumes, and fatter proportions. Rocks
become potatoes. Because the mesh cache has to rebuild, the toggle is allowed
to reload the scene.

Both looks share one palette definition, one lighting model, and one set of
meshes generated at different roundness values. Never two hand-authored asset
sets — that would kill the procedural-part advantage permanently.

### Two tuning labs (developer-facing, shipped in the build)

1. **Style lab** — a ship and a planet side by side with dials for roundness,
   chunkiness, banding, outline, saturation, planet detail, star density.
   Reloading the scene on change is acceptable.
2. **Physics lab** — a cartoony flight test bed where every physics constant is
   a live slider: mass influence, restitution, spin transfer, knockback,
   hitstop, boost impulse, gravity strength and falloff.

These are how the feel gets found. They are not optional tooling — the whole bet
is on feel, and feel is found by dragging sliders, not by reasoning.

---

## 13. The core loop

```
              FLY
               ↓
        SEE SOMETHING
               ↓
       "what happens if..."
               ↓
      BUMP / SHOOT / BOOST
               ↓
       PHYSICS GOES BRRRR
               ↓
         CONSEQUENCE
               ↓
      "OH SHIT THAT'S COOL"
               ↓
              FLY
```

Underneath:

```
                 PROCEDURAL GALAXY
                         │
       ┌─────────┬───────┼────────┐
       ↓         ↓       ↓        ↓
    Ships     Planets  Factions  Events
       │         │       │        │
       └─────────┴───────┼────────┘
                         ↓
                  EMERGENT CHAOS
```

---

## 14. Anti-goals

Written down so they can be pointed at later.

- **No quest menus.** Ever. Not even "just for the career mode."
- **No random physics.** Chaos comes from density and momentum, never noise.
- **No assist that silently undoes a consequence.** Assists help you fly; they
  never delete the story.
- **No damage numbers as the primary feedback.** The primary feedback is that
  the thing you hit *moved*.
- **No reputation bars.** Memory is expressed by behaviour: who chases you.
- **No second physics implementation** for the plane-locked mode, mobile, or
  the cartoony style. One simulation, parameterised.
- **No hand-authored second art set.** One mesh pipeline, a roundness dial.
- **No feature that only makes sense in Career mode.**

---

## 15. Platform

PC and mobile. GL Compatibility renderer, one UI layout that serves a phone and
a desktop, controls behind progressive-disclosure menus rather than a permanent
button wall. The physics budget is set by the weaker target, and every system is
designed against that ceiling — see `TECHNICAL_PLAN.md`.
