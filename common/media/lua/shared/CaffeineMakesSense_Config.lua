CaffeineMakesSense = CaffeineMakesSense or {}

CaffeineMakesSense.DEFAULTS = {
    -- Shared caffeine kinetics across sources. The molecule is the same; item
    -- differentiation now comes mainly from dose and convenience rather than
    -- heavily divergent per-item pharmacology.
    PillOnsetMinutes = 25,
    PillHalfLifeMinutes = 240,
    PillMaskScale = 1.00,
    CoffeeOnsetMinutes = 25,
    CoffeeHalfLifeMinutes = 240,
    CoffeeMaskScale = 1.00,
    TeaOnsetMinutes = 25,
    TeaHalfLifeMinutes = 240,
    TeaMaskScale = 1.00,

    -- Peak masking strength (0-1). With the current stronger gameplay projection,
    -- this is allowed to reach full masking budget at high stimulant load.
    PeakMaskStrength = 1.00,

    -- Minimum caffeine level (fraction of peak) below which the effect is negligible.
    NegligibleThreshold = 0.05,

    -- Caffeine dose per item category.
    -- Scaled to real mg: coffee=95mg=1.0, pill=200mg=2.0, tea=47mg=0.5.
    DoseCoffee = 1.0,
    DoseTea = 0.5,
    DoseCoffeePackage = 5.0,
    DoseTeabag = 0.85,
    DoseCoffeeBeans = 0.6,
    DoseVitamins = 2.0,

    -- Maximum caffeine level from stacking doses (prevents infinite stacking).
    MaxCaffeineLevel = 4.0,

    -- Active suppression budget applied through the gameplay projection curve.
    -- Tuned high enough that one pill can temporarily hold fatigue thresholds
    -- instead of just softening the climb by decorative amounts.
    SuppressionFraction = 0.80,

    -- Extra gain on the gameplay projection curve.
    -- Combined with SuppressionFraction, this controls how hard caffeine can
    -- pull effective fatigue down in the meaningful 0.60-0.80 gameplay band.
    ProjectionShapeScale = 4.00,

    -- Maximum instantaneous sleep-disruption strength derived from active
    -- stimulant load while asleep. This feeds the weighted sleep-session score.
    SleepDisruptionStrengthMax = 0.60,

    -- Maximum fraction of vanilla sleep recovery that caffeine can erase while
    -- asleep. This is a continuous sleep-efficiency penalty, not a wake-time hit.
    SleepRecoveryPenaltyMaxFrac = 0.20,

    -- Acute overstimulation stress is a temporary CMS-owned contribution layered
    -- onto vanilla stress. It starts building below pill-level peak overlap so
    -- ordinary strong use can feel edgy, while sustained stacking is what
    -- pushes the player toward visible stress moodles.
    StressLoadStart = 1.35,
    StressLoadMax = 4.0,
    StressTargetMax = 0.70,
    StressCurvePower = 1.10,
    StressDebtAmpHidden = 0.25,
    StressDebtAmpMax = 0.35,
    StressRiseTauMinutes = 20,
    StressDecayTauMinutes = 90,
    StressSleepDecayTauMinutes = 45,

    -- Tick cap for catch-up slicing (same pattern as AMS).
    DtMaxMinutes = 3,
    DtCatchupMaxSlices = 240,
}

return CaffeineMakesSense.DEFAULTS
