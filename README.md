# Caffeine Makes Sense

**Build 42 mod for Project Zomboid.**

Caffeine is a masking agent, not a fatigue cure. This mod replaces vanilla's flat fatigue delete with a pharmacokinetic model: gradual onset, half-life decay, fatigue masking, and sleep-quality penalties through vanilla's existing systems.

No mana-potion pills. Just caffeine that behaves like caffeine.

## What It Does

**Fatigue masking.** Caffeine lowers displayed fatigue while active, but true fatigue keeps building underneath. When the caffeine fades, the hidden tiredness becomes visible again.

**Profile-based caffeine.** Pills hit fastest and hardest. Coffee rises more gradually. Tea is milder and shorter-lived.

**Onset and decay.** Caffeine ramps up instead of applying instantly, then fades by half-life rather than a flat timer.

**Natural rebound.** There is no fake crash debuff. The downside comes from masking wearing off and the debt underneath showing through.

**Sleep-quality penalty.** Bedtime caffeine degrades the value of sleep. You still sleep, but you wake worse than you would have without it.

**Stacking ceiling.** Multiple doses can extend the useful window, but stacking is capped and pushes more borrowed wakefulness into later consequences.

## Compatibility

- Singleplayer and multiplayer
- Build 42.14.0+
- No dependencies

## Documentation

| Document | Contents |
|---|---|
| [Design Manifesto](docs/caffeine_makes_sense-design_manifesto.md) | Core philosophy and player-facing goals |
| [Technical Appendix](docs/caffeine_makes_sense-technical_appendix.md) | Runtime structure, pharmacology model, sleep model, and module inventory |

## Source Code

Full source is on [GitHub](https://github.com/Deharath/caffeine-makes-sense).

- Mod ID: `CaffeineMakesSense`

## Author

Deharath
