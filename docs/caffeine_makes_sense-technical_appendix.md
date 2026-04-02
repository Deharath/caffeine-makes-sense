# Caffeine Makes Sense — Technical Appendix (v1.0.3)

_As of April 2, 2026_  
`SCRIPT_VERSION=1.0.3`

## Scope

Caffeine Makes Sense (CMS) is a Build 42 caffeine-fatigue mod with shared simulation code for singleplayer and multiplayer. The runtime replaces vanilla's flat fatigue deletion with pharmacokinetic caffeine profiles, gameplay-facing fatigue masking, and sleep-quality penalties that are expressed mainly as reduced sleep recovery rather than a one-shot wake penalty.

The current docs are organized around two core references:
- Design intent: [caffeine_makes_sense-design_manifesto.md](./caffeine_makes_sense-design_manifesto.md)
- Runtime and implementation details: this appendix

## Design Summary

Core design intent:
- replace vanilla's instant fatigue removal with time-based caffeine kinetics
- keep true fatigue accumulating underneath the visible masked value
- keep one shared caffeine curve and differentiate items mainly by dose
- make rebound emerge from fading masking, not a scripted crash penalty
- make bedtime caffeine degrade sleep quality primarily through reduced sleep recovery
- tune masking against Project Zomboid's threshold-heavy fatigue gameplay rather than a literal real-world percent-less-sleepy reading
- use stress only as an acute overstimulation signal for abuse, not as a baseline caffeine tax

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
- pills: strongest dose
- coffee: medium dose
- tea: mild dose

Kinetics are now intentionally near-shared across sources:
- one caffeine model
- one onset/decay family
- item differences are expressed mainly through dose magnitude and gameplay convenience
- the current projection is intentionally strongest in the meaningful `0.60-0.80` gameplay band and tapers harder again by `0.85+`

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
- gameplay fatigue projection with a stronger mid/high-fatigue band curve tuned around PZ's threshold-heavy penalties

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
- caffeine reduces sleep recovery continuously during the sleep window
- the planner rebases from `realFatigue`, but CMS does not add its own extra hours on top of that baseline
- there is no separate wake-time fatigue bite anymore

Instead:
- `OnSleepingTick` accumulates a weighted sleep disruption score across the sleep window
- early sleep is weighted more heavily than late sleep
- the weighted sleep disruption score also drives a continuous `sleepRecoveryPenaltyFraction`
- CMS counteracts a fraction of vanilla fatigue recovery while the player is asleep
- sleep planning now rebases from CMS `realFatigue` rather than masked visible fatigue
- in multiplayer, CMS now leaves sleep fully vanilla. Sleep planner hooks and
  sleep-recovery penalties are singleplayer-only because the dedicated-server
  sleep/fast-forward seam is too brittle for custom scheduling without false
  fast-forward persistence after wake.
- AMS can still extend planned sleep for poor armor sleep conditions, but CMS itself leaves extra planner hours to the real-fatigue baseline
- if caffeine is still active after wake, visible fatigue may remain somewhat masked

### Acute Stress Model

The current stress penalty is an acute overstimulation channel:
- it is derived mainly from current `rawStimLoad`
- it starts only once stimulant load rises above a safe band
- hidden debt mildly amplifies it, but does not trigger it on its own
- CMS owns only its own temporary stress contribution and layers it onto vanilla stress

This means:
- normal coffee use stays clean
- one ordinary pill may create a slight edge but usually not a visible stress moodle
- sustained stacking and all-nighter abuse can build toward `Tense` and `Agitated`
- the caffeine-owned contribution decays back out as stimulant load falls or the player sleeps

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
- `sleepRecoveryPenaltyFraction`
- `lastSleepRecoveryPenaltyFraction`
- `lastSleepRecoveryFatigue`
- `caffeineStressCurrent`
- `caffeineStressTarget`
- `lastAppliedCaffeineStress`

## Module Inventory

### Entry / Client
- `client/CaffeineMakesSense_Main.lua` — client boot facade, event registration, SP tick wiring, dev panel hotkey/context menu
- `client/CaffeineMakesSense_HealthPanelHook.lua` — compact health-panel status line that shows `Caffeine: <level>` when stimulant load is meaningfully present; in stacked mode it publishes the line for NMS to host instead of relying on wrapper order
- `client/CaffeineMakesSense_SleepHooks.lua` — planner hooks for `ISSleepDialog` and auto-sleep in singleplayer only; MP now hard-defers to vanilla sleep
- `client/CaffeineMakesSense_Tick.lua` — thin client wrapper into shared runtime tick
- `client/CaffeineMakesSense_State.lua` — thin client wrapper into shared state/runtime helpers
- `client/CaffeineMakesSense_Hooks.lua` — consume hooks for `OnEat`, `ISDrinkFluidAction`, and `ISEatFoodAction`; also handles dev recording dose events and MP dose forwarding

### Dev-only Client
- `client/dev/CaffeineMakesSense_DevPanel.lua` — debug overlay, recording UI, CSV export, reset helper; present in dev builds and stripped from release builds

### Shared
- `shared/CaffeineMakesSense_Config.lua` — tuning defaults for profiles, projection, and sleep disruption
- `shared/CaffeineMakesSense_Compat.lua` — cross-mod compat registry bootstrap
- `shared/CaffeineMakesSense_HealthStatus.lua` — shared helper that maps meaningful stimulant load to the player-facing `Caffeine: <level>` status line using simple four-step wording (`Low` through `Very High`)
- `shared/CaffeineMakesSense_SleepPlanner.lua` — shared vanilla-equivalent sleep planning helpers used to rebase planner hours from real fatigue and keep CMS planner compensation separate from runtime sleep cost
- `shared/CaffeineMakesSense_ItemDefs.lua` — caffeine item catalog, hot-drink mappings, pill mappings
- `shared/CaffeineMakesSense_Pharma.lua` — onset/decay, mask strength, sleep disruption strength, fatigue projection
- `shared/CaffeineMakesSense_Runtime.lua` — shared state model, dose storage, fatigue tick logic, and SP-only sleep session logic; MP now hard-defers to vanilla sleep
- `shared/CaffeineMakesSense_MPCompat.lua` — MP constants and command names
- `shared/CaffeineMakesSense_Boot.lua` — boot-time vanilla item patching

### Server
- `server/CaffeineMakesSense_MPServerRuntime.lua` — MP dose receive path, server consume hook registration, snapshot/reset command handling, and per-minute server tick using shared runtime

## Item Integration

[CaffeineMakesSense_ItemDefs.lua](../common/media/lua/shared/CaffeineMakesSense_ItemDefs.lua) currently wires:
- caffeine pills: `Base.PillsVitamins`
- brewed coffee items: `Base.HotDrink*` mug/tumbler variants
- brewed tea items: `Base.HotDrinkTea*`
- direct consumables: `Base.Coffee2`, `Base.Teabag2`, `Base.ChocolateCoveredCoffeeBeans`

The active gameplay path is `OnEat = CMS_OnEatCaffeine`, registered at boot on supported items.
Fluid and hot-drink consume paths that bypass plain `OnEat` are also wrapped so vanilla flat coffee/tea fatigue changes are neutralized before CMS applies its own model.
Food consume fatigue reversal now hooks `ISEatFoodAction.perform`, because that is the live seam on MP clients; the older `complete` seam could miss the client consume path entirely.
`Base.Coffee2` and `Base.Teabag2` are intentionally stronger than one brewed serving when consumed directly, because the vanilla items represent multi-serving ingredient packages and CMS preserves fractional consumption scaling.

## Diagnostics And Recording

The dev panel can be opened without the Lua Dev Console:
- `Numpad 6`
- debug world context menu: `CMS Dev Panel`

In multiplayer, the panel reads authoritative server snapshots rather than unsynced local state. The panel reset action also routes through the server so it clears real MP caffeine state instead of only wiping the client view.
The player-facing health panel still allows a short fresh-local grace path for meaningful just-consumed load if the newest local dose is newer than the last server snapshot, so the caffeine line does not visibly lag the consume action while waiting for the authoritative echo.
The sleep block separates `Projected Penalty` from `Active Penalty`: projected penalty is the sleep-efficiency loss implied by the current caffeine load if the player slept now, while active penalty is the penalty actually being applied during an ongoing sleep session.
Sleep planning in MP now rebases from authoritative snapshot `displayedFatigue` / `realFatigue` when that snapshot exists, instead of trusting dormant client-local CMS state.
MP recording now forces a start/stop snapshot pass and still samples once per minute while connected to a server, so short authoritative sessions no longer save empty CSVs just because the local runtime tick is dormant. Rows also carry `sample_source`, `snapshot_updated_min`, and `snapshot_age_min` so stale authoritative snapshots and pending-snapshot placeholders are explicit instead of being silently timestamped as fresh local state.

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
- `stress_total_pct`
- `stress_cms_pct`
- `stress_target_pct`
- `sleep_disruption_pct`
- `sleep_recovery_penalty_pct`
- `sleep_projected_penalty_pct`
- `sleep_recovery_fatigue`
- `sleep_session_min`
- dose events and profile tags

Analyzer:
- `tools/analyze_recording.py`
- summarizes the current sleep-recovery schema

## Current Behavior Notes

As of the current build:
- pills are modeled as roughly `200 mg` doses
- coffee uses the same shared caffeine curve and is mainly differentiated by lower dose and preparation friction
- one-pill bedtime use is intended to be mildly bad, not a ruined night
- heavier bedtime stimulant burden should scale up disruption and sleep recovery loss without turning the planner into a perfect compensator
- all-nighter behavior is intentionally bounded: redosing can buy a long push through `Drowsy`/`Tired`, but severe fatigue still stops being meaningfully rescueable near the top end

## Cross-Mod Compat

CMS now acts as the fatigue coordinator for the stacked `Makes Sense` setup.

- CMS still owns canonical `realFatigue`, caffeine masking, and sleep-recovery composition.
- NMS can contribute deprivation-driven extra fatigue through compat callbacks
  instead of directly writing fatigue while CMS is present.
- AMS can contribute sleep-rigidity penalty fractions through compat callbacks
  instead of directly writing fatigue while CMS is present.
- the final vanilla fatigue write stays single-owner in stacked mode: CMS
  composes the external contributions into canonical fatigue first, then
  projects displayed fatigue once.
- dev verification also exposes CMS trace snapshots so the unified compat trace
  can show canonical fatigue, hidden fatigue, and stacked external fatigue
  contributions in one file.
