# Caffeine Makes Sense — Technical Appendix (v0.1.0)

_As of March 10, 2026_  
`SCRIPT_VERSION=0.1.0`

## Scope

Caffeine Makes Sense (CMS) is a Build 42 caffeine-fatigue mod with shared simulation code for singleplayer and multiplayer. The runtime replaces vanilla's flat fatigue deletion with pharmacokinetic caffeine profiles, gameplay-facing fatigue masking, and sleep-quality penalties that are expressed mainly as wake fatigue remainder rather than shortened-feeling sleep.

The current docs are organized around two core references:
- Design intent: [caffeine_makes_sense-design_manifesto.md](./caffeine_makes_sense-design_manifesto.md)
- Runtime and implementation details: this appendix

## Design Summary

Core design intent:
- replace vanilla's instant fatigue removal with time-based caffeine kinetics
- keep true fatigue accumulating underneath the visible masked value
- differentiate pills, coffee, and tea by onset, half-life, and mask scale
- make rebound emerge from fading masking, not a scripted crash penalty
- make bedtime caffeine degrade sleep quality primarily through a wake fatigue remainder

Runtime split:
- singleplayer uses the client runtime path plus the shared simulation core
- multiplayer server receives dose events and runs the same shared fatigue/sleep formulas
- shared pharmacology and runtime logic live in `shared/` so SP and MP do not drift

## Build Layout

- Mod root (`CaffeineMakesSense/`): metadata and assets (`mod.info`, `poster.png`)
- `common/`: source-of-truth Lua and docs
- `42/`: `42/mod.info` override
- `common/media/lua/client/dev/`: dev-only client tooling stripped from release builds

## Runtime Model

### Pharmacokinetics

Profiles are defined in [CaffeineMakesSense_Config.lua](../common/media/lua/shared/CaffeineMakesSense_Config.lua):
- pills: fastest onset, strongest dose
- coffee: slower onset, smoother arc
- tea: mild and shorter-lived

Each dose stores:
- `doseLevel`
- `doseMinute`
- `profileKey`
- `category`

[CaffeineMakesSense_Pharma.lua](../common/media/lua/shared/CaffeineMakesSense_Pharma.lua) handles:
- smoothstep onset into peak
- exponential half-life decay
- saturating mask strength from aggregate mask load
- saturating sleep disruption strength from aggregate stimulant load
- gameplay fatigue projection with a higher-centered fatigue-band curve

### Fatigue Projection

CMS tracks two fatigue concepts:
- `realFatigue`: underlying fatigue that keeps moving normally
- displayed fatigue: gameplay-facing value written back to the player stat

While awake:
- aggregate `rawStimLoad` and `maskLoad` are computed from active doses
- `maskLoad` becomes `maskStrength`
- displayed fatigue is projected downward from `realFatigue`
- `hiddenFatigue = realFatigue - displayedFatigue`

While asleep:
- displayed fatigue is pinned to `realFatigue`
- awake masking is intentionally not shown during the sleep window

### Sleep Model

The current sleep penalty model is "sleep quality first":
- no in-sleep recovery slowdown as the main mechanic
- no scheduler modification in this pass
- no explicit wake-timing meddling

Instead:
- `OnSleepingTick` accumulates a weighted sleep disruption score across the sleep window
- early sleep is weighted more heavily than late sleep
- on wake, CMS applies a bounded `wakePenalty` once to `state.realFatigue`
- if caffeine is still active after wake, visible fatigue may remain somewhat masked

Important state fields in [CaffeineMakesSense_Runtime.lua](../common/media/lua/shared/CaffeineMakesSense_Runtime.lua):
- `realFatigue`
- `hiddenFatigue`
- `peakStimThisCycle`
- `wasSleeping`
- `sleepStartMinute`
- `sleepLastAccumMinute`
- `sleepWeightedDisruption`
- `sleepWeightedMinutes`
- `sleepPeakDisruption`
- `sleepDisruptionScore`
- `sleepPendingWakeFatigue`
- `lastWakeFatiguePenalty`

## Module Inventory

### Entry / Client
- `client/CaffeineMakesSense_Main.lua` — client boot facade, event registration, SP tick wiring, dev panel hotkey/context menu
- `client/CaffeineMakesSense_Tick.lua` — thin client wrapper into shared runtime tick
- `client/CaffeineMakesSense_State.lua` — thin client wrapper into shared state/runtime helpers
- `client/CaffeineMakesSense_Hooks.lua` — OnEat dose entrypoint, dev recording dose events, MP dose forwarding

### Dev-only Client
- `client/dev/CaffeineMakesSense_DevPanel.lua` — debug overlay, recording UI, CSV export, reset helper; present in dev builds and stripped from release builds

### Shared
- `shared/CaffeineMakesSense_Config.lua` — tuning defaults for profiles, projection, and sleep disruption
- `shared/CaffeineMakesSense_ItemDefs.lua` — caffeine item catalog, hot-drink mappings, pill mappings
- `shared/CaffeineMakesSense_Pharma.lua` — onset/decay, mask strength, sleep disruption strength, fatigue projection
- `shared/CaffeineMakesSense_Runtime.lua` — shared state model, dose storage, fatigue tick logic, sleep session logic
- `shared/CaffeineMakesSense_MPCompat.lua` — MP constants and command names
- `shared/CaffeineMakesSense_Boot.lua` — boot-time vanilla item patching

### Server
- `server/CaffeineMakesSense_MPServerRuntime.lua` — MP dose receive path and per-minute server tick using shared runtime

## Item Integration

[CaffeineMakesSense_ItemDefs.lua](../common/media/lua/shared/CaffeineMakesSense_ItemDefs.lua) currently wires:
- caffeine pills: `Base.PillsVitamins`
- brewed coffee items: `Base.HotDrink*` mug/tumbler variants
- brewed tea items: `Base.HotDrinkTea*`
- direct consumables kept for compatibility/reference: `Base.Coffee2`, `Base.Teabag2`, `Base.ChocolateCoveredCoffeeBeans`

The active gameplay path is `OnEat = CMS_OnEatCaffeine`, registered at boot on supported items.

## Diagnostics And Recording

The dev panel can be opened without the Lua Dev Console:
- `Numpad 6`
- debug world context menu: `CMS Dev Panel`

Recording CSV currently includes:
- elapsed/game time
- stage
- `raw_stim_load`
- `mask_load`
- `mask_pct`
- `fatigue_pre`
- `fatigue_post`
- `real_fatigue_est`
- `hidden_debt`
- `sleep_disruption_pct`
- `wake_fatigue_penalty`
- `sleep_session_min`
- dose events and profile tags

Analyzer:
- `tools/caffeine_makes_sense/scripts/analyze_recording.py`
- supports older sleep-penalty CSVs and current sleep-disruption CSVs

## Current Behavior Notes

As of the current build:
- pills are modeled as roughly `200 mg` doses
- coffee is intentionally a bit generous in gameplay terms so it remains worth brewing
- one-pill bedtime use is intended to be mildly bad, not a ruined night
- heavier bedtime stimulant burden should scale up disruption and wake penalty without collapsing sleep duration into the old artifact
