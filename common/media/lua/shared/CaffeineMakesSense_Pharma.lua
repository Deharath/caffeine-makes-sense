CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.Pharma = CaffeineMakesSense.Pharma or {}

local Pharma = CaffeineMakesSense.Pharma
local PROFILE_DEFAULTS = {
    coffee = { onsetKey = "CoffeeOnsetMinutes", halfLifeKey = "CoffeeHalfLifeMinutes", maskScaleKey = "CoffeeMaskScale" },
    tea = { onsetKey = "TeaOnsetMinutes", halfLifeKey = "TeaHalfLifeMinutes", maskScaleKey = "TeaMaskScale" },
    pill = { onsetKey = "PillOnsetMinutes", halfLifeKey = "PillHalfLifeMinutes", maskScaleKey = "PillMaskScale" },
}

local function clamp(value, minimum, maximum)
    local v = tonumber(value) or minimum
    if v < minimum then return minimum end
    if v > maximum then return maximum end
    return v
end

local function smoothstep(t)
    local x = clamp(t, 0, 1)
    return x * x * (3 - 2 * x)
end

function Pharma.getProfileOptions(options, profileKey)
    local key = tostring(profileKey or "coffee")
    local spec = PROFILE_DEFAULTS[key] or PROFILE_DEFAULTS.coffee
    return {
        onsetMinutes = tonumber(options and options[spec.onsetKey]) or 30,
        halfLifeMinutes = tonumber(options and options[spec.halfLifeKey]) or 210,
        maskScale = tonumber(options and options[spec.maskScaleKey]) or 1.0,
    }
end

-- Compute caffeine level for a single dose.
-- Uses a smooth onset ramp into exponential decay.
function Pharma.caffeineAtTime(caffeineLevel, minutesSinceDose, onsetMinutes, halfLifeMinutes)
    if caffeineLevel <= 0 or minutesSinceDose < 0 then
        return 0
    end
    if minutesSinceDose <= onsetMinutes then
        local progress = smoothstep(minutesSinceDose / math.max(0.01, onsetMinutes))
        return caffeineLevel * progress
    end
    local minutesPastPeak = minutesSinceDose - onsetMinutes
    local decayFactor = math.pow(0.5, minutesPastPeak / math.max(0.01, halfLifeMinutes))
    return caffeineLevel * decayFactor
end

-- Compute fatigue masking strength from the aggregate mask load.
function Pharma.maskStrength(maskLoad, peakMaskStrength, maxCaffeineLevel)
    if maskLoad <= 0 then
        return 0
    end
    local normalized = math.min(maskLoad / math.max(0.01, maxCaffeineLevel), 1.0)
    local strength = 1.0 - math.exp(-2.5 * normalized)
    return strength * peakMaskStrength
end

function Pharma.sleepDisruptionStrength(rawStimLoad, penaltyMax, maxCaffeineLevel)
    if rawStimLoad <= 0 then
        return 0
    end
    local normalized = math.min(rawStimLoad / math.max(0.01, maxCaffeineLevel), 1.0)
    local strength = 1.0 - math.exp(-2.0 * normalized)
    return clamp(strength * (tonumber(penaltyMax) or 0), 0, 1)
end

-- Project real fatigue to gameplay-facing fatigue.
-- The strongest relief lives in the meaningful tired band, where PZ's fatigue
-- penalties accelerate sharply. Fresh players get little benefit, while very
-- high fatigue still gets a small rescue instead of the curve collapsing to
-- nearly zero at 0.95-1.00.
function Pharma.projectDisplayedFatigue(realFatigue, maskStrength, suppressionFrac, projectionShapeScale)
    local real = clamp(realFatigue or 0, 0, 1)
    local mask = clamp(maskStrength or 0, 0, 1)
    local suppression = clamp(suppressionFrac or 0, 0, 1)
    local shapeScale = math.max(0, tonumber(projectionShapeScale) or 4.0)
    local coreShape = math.pow(real, 2.2) * math.max(0, 1 - real)
    local highFatigueCarry = 0
    if real > 0.85 then
        highFatigueCarry = math.pow((real - 0.85) / 0.15, 1.35) * 0.06
    end
    local fatigueShape = coreShape + highFatigueCarry
    local delta = mask * suppression * shapeScale * fatigueShape
    return clamp(real - delta, 0, 1)
end

return Pharma
