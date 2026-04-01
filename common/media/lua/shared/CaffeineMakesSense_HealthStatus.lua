CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.HealthStatus = CaffeineMakesSense.HealthStatus or {}

local HealthStatus = CaffeineMakesSense.HealthStatus
local MEANINGFUL_LOAD_FRACTION = 0.10
local LOCAL_FRESH_MINUTES = 1.5

local function clamp(value, minimum, maximum)
    local v = tonumber(value) or minimum
    if v < minimum then
        return minimum
    end
    if v > maximum then
        return maximum
    end
    return v
end

function HealthStatus.firstNumber(defaultValue, ...)
    local value = select(1, ...)
    if type(value) == "number" then
        return value
    end

    local parsed = tonumber(value)
    if parsed == nil then
        return defaultValue
    end
    return parsed
end

function HealthStatus.getMeaningfulLoadThreshold(options)
    local maxCaffeine = math.max(0.01, HealthStatus.firstNumber(4.0, options and options.MaxCaffeineLevel))
    return maxCaffeine * MEANINGFUL_LOAD_FRACTION
end

function HealthStatus.chooseDisplayLoad(snapshot, localRawStimLoad, localNewestDoseMinute, nowMinute, options)
    local snapshotLoad = HealthStatus.firstNumber(nil, snapshot and snapshot.rawStimLoad)
    local localLoad = HealthStatus.firstNumber(nil, localRawStimLoad)
    if snapshotLoad == nil and localLoad == nil then
        return nil
    end

    local snapshotUpdatedMinute = HealthStatus.firstNumber(nil, snapshot and snapshot.updatedMinute)
    local snapshotSource = tostring((snapshot and snapshot.source) or "snapshot")
    local now = HealthStatus.firstNumber(nil, nowMinute)
    local newestDoseMinute = HealthStatus.firstNumber(nil, localNewestDoseMinute)
    local meaningfulThreshold = math.max(
        HealthStatus.firstNumber(0.05, options and options.NegligibleThreshold),
        HealthStatus.getMeaningfulLoadThreshold(options)
    )

    if localLoad ~= nil then
        local isFreshLocalDose = now ~= nil
            and newestDoseMinute ~= nil
            and newestDoseMinute <= now
            and (now - newestDoseMinute) <= LOCAL_FRESH_MINUTES
        local snapshotPredatesDose = snapshotUpdatedMinute == nil
            or (newestDoseMinute ~= nil and snapshotUpdatedMinute < newestDoseMinute)

        if localLoad >= meaningfulThreshold
            and isFreshLocalDose
            and snapshotPredatesDose
            and (snapshotLoad == nil or localLoad > snapshotLoad + 0.0001)
        then
            return {
                rawStimLoad = math.max(0, localLoad),
                source = "local_fresh",
                snapshotUpdatedMinute = snapshotUpdatedMinute,
            }
        end
    end

    if snapshotLoad ~= nil then
        return {
            rawStimLoad = math.max(0, snapshotLoad),
            source = snapshotSource,
            snapshotUpdatedMinute = snapshotUpdatedMinute,
        }
    end

    return {
        rawStimLoad = math.max(0, localLoad or 0),
        source = "local_runtime",
        snapshotUpdatedMinute = now,
    }
end

function HealthStatus.buildHealthLine(rawStimLoad, options)
    local load = math.max(0, HealthStatus.firstNumber(0, rawStimLoad))
    local maxCaffeine = math.max(0.01, HealthStatus.firstNumber(4.0, options and options.MaxCaffeineLevel))
    local negligible = math.max(0, HealthStatus.firstNumber(0.05, options and options.NegligibleThreshold))
    local meaningful = math.max(negligible, HealthStatus.getMeaningfulLoadThreshold(options))

    if load < meaningful then
        return {
            visible = false,
        }
    end

    local normalized = clamp(load / maxCaffeine, 0, 1)
    local label = "Very High"
    local colorKey = "bad"

    if normalized < 0.22 then
        label = "Low"
        colorKey = "dim"
    elseif normalized < 0.40 then
        label = "Medium"
        colorKey = "neutral"
    elseif normalized < 0.65 then
        label = "High"
        colorKey = "warn"
    end

    return {
        visible = true,
        label = label,
        text = "Caffeine: " .. label,
        colorKey = colorKey,
        rawStimLoad = load,
        normalized = normalized,
    }
end

return HealthStatus
