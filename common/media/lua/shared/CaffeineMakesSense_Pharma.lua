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
-- Small benefit when fresh, strongest benefit in the mid/high-fatigue band,
-- then tapering again near exhaustion so caffeine never fully resurrects a
-- severely sleep-deprived character.
function Pharma.projectDisplayedFatigue(realFatigue, maskStrength, suppressionFrac, projectionShapeScale)
    local real = clamp(realFatigue or 0, 0, 1)
    local mask = clamp(maskStrength or 0, 0, 1)
    local suppression = clamp(suppressionFrac or 0, 0, 1)
    local shapeScale = math.max(0, tonumber(projectionShapeScale) or 1.8)
    local fatigueShape = math.pow(real, 2.5) * math.pow(math.max(0, 1 - real), 0.6)
    local delta = mask * suppression * shapeScale * fatigueShape
    return clamp(real - delta, 0, 1)
end

return Pharma
