CaffeineMakesSense = CaffeineMakesSense or {}

CaffeineMakesSense.DEFAULTS = {
    -- Profile kinetics: pills hit faster and harder, coffee is smoother, tea is lighter.
    PillOnsetMinutes = 20,
    PillHalfLifeMinutes = 240,
    PillMaskScale = 1.00,
    CoffeeOnsetMinutes = 30,
    CoffeeHalfLifeMinutes = 210,
    CoffeeMaskScale = 0.80,
    TeaOnsetMinutes = 25,
    TeaHalfLifeMinutes = 150,
    TeaMaskScale = 0.60,

    -- Peak masking strength (0-1). At 1.0, caffeine at max dose fully suppresses
    -- the fatigue rate. Scaled by effective caffeine / max caffeine.
    PeakMaskStrength = 0.85,

    -- Minimum caffeine level (fraction of peak) below which the effect is negligible.
    NegligibleThreshold = 0.05,

    -- Caffeine dose per item category.
    -- Scaled to real mg: coffee=95mg=1.0, pill=200mg=2.0, tea=47mg=0.5.
    DoseCoffee = 1.0,
    DoseTea = 0.5,
    DoseCoffeeBeans = 0.6,
    DoseVitamins = 2.0,

    -- Maximum caffeine level from stacking doses (prevents infinite stacking).
    MaxCaffeineLevel = 4.0,

    -- Active suppression budget applied through the gameplay projection curve.
    -- This is not a flat multiplier on real fatigue; it scales the bell-shaped
    -- "most useful when meaningfully tired" masking layer.
    SuppressionFraction = 0.50,

    -- Extra gain on the gameplay projection curve.
    -- With the current higher-centered smooth hump, values around 1.8 push the
    -- strongest relief into the mid/high-fatigue band without letting caffeine
    -- trivialize near-exhaustion.
    ProjectionShapeScale = 1.8,

    -- Maximum instantaneous sleep-disruption strength derived from active
    -- stimulant load while asleep. This feeds the weighted sleep-session score.
    SleepDisruptionStrengthMax = 0.60,

    -- Maximum real-fatigue remainder added once on wake from the weighted sleep
    -- disruption score. Visible wake fatigue may still be partially masked by
    -- active caffeine after this is applied.
    SleepWakeFatigueMax = 0.12,

    -- Tick cap for catch-up slicing (same pattern as AMS).
    DtMaxMinutes = 3,
    DtCatchupMaxSlices = 240,
}

return CaffeineMakesSense.DEFAULTS
