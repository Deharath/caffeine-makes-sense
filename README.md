# Caffeine Makes Sense

**Build 42 mod for Project Zomboid.**

Caffeine is a masking agent, not a fatigue cure. This mod replaces vanilla's flat fatigue delete with a time-based caffeine model: gradual onset, decay over time, fatigue masking, and sleep-quality penalties through vanilla's existing systems.

No mana-potion pills. Just caffeine that behaves like caffeine inside Project Zomboid's exaggerated fatigue system.

## What It Does

**Fatigue masking.** Caffeine lowers displayed fatigue while active, but true fatigue keeps building underneath. When the caffeine fades, the hidden tiredness becomes visible again.

**Meaningful threshold relief.** The strongest gameplay benefit lands where PZ fatigue actually starts to hurt: the Drowsy and Tired bands. Caffeine helps you keep going. It does not make you truly rested.

**Dose-driven balance.** The molecule is the same. Pills, coffee, and tea use the same core model and differ mainly by dose and convenience. Want pill-like push from drinks? Drink more caffeine.

**Onset and decay.** Caffeine ramps in instead of applying instantly, then fades over time instead of working like a flat coupon.

**Natural rebound.** There is no fake crash debuff. The downside comes from masking wearing off and the debt underneath showing through.

**Sleep-quality penalty.** Bedtime caffeine degrades the value of sleep. You still sleep, but the sleep is worse, and heavier stimulant burden before bed is worse again.

**Stacking ceiling.** Multiple doses can extend the useful window, but stacking is capped and pushes more borrowed wakefulness into later consequences.

## Compatibility

- Singleplayer and multiplayer
- Build 42.15+
- No dependencies

## Documentation

| Document | Contents |
|---|---|
| [Design Manifesto](docs/caffeine_makes_sense-design_manifesto.md) | Core philosophy and player-facing goals |
| [Technical Appendix](docs/caffeine_makes_sense-technical_appendix.md) | Runtime structure, pharmacology model, sleep model, and module inventory |

## Dev Tooling

The git repo includes two development-facing tools:

- Dev panel and CSV recording for caffeine traces
- Recording parser for analyzing captured caffeine runs: [tools/analyze_recording.py](tools/analyze_recording.py)

The Workshop package is stripped of the dev panel and related diagnostics.

## Source Code

Full source is on [GitHub](https://github.com/Deharath/caffeine-makes-sense).

- Mod ID: `CaffeineMakesSense`

## Author

Deharath
