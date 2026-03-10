CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.Runtime = CaffeineMakesSense.Runtime or {}

local Runtime = CaffeineMakesSense.Runtime
local DEFAULTS = CaffeineMakesSense.DEFAULTS or {}

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function clamp(value, minimum, maximum)
    local v = tonumber(value) or minimum
    if v < minimum then return minimum end
    if v > maximum then return maximum end
    return v
end

local function getStateKey()
    local MP = CaffeineMakesSense.MP or {}
    return tostring(MP.MOD_STATE_KEY or "CaffeineMakesSenseState")
end

function Runtime.clamp(value, minimum, maximum)
    return clamp(value, minimum, maximum)
end

function Runtime.safeCall(target, methodName, ...)
    return safeCall(target, methodName, ...)
end

function Runtime.normalizeProfileKey(profileKey, category)
    local key = tostring(profileKey or category or "coffee")
    if key == "pill" or key == "coffee" or key == "tea" then
        return key
    end
    if key == "vitamins" then
        return "pill"
    end
    if key == "coffee_beans" then
        return "coffee"
    end
    return "coffee"
end

function Runtime.getWorldAgeMinutes()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    local hours = tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
    if hours == nil then
        return 0
    end
    return hours * 60.0
end

function Runtime.getOptions()
    local options = {}
    for key, value in pairs(DEFAULTS) do
        options[key] = value
    end
    if SandboxVars and SandboxVars.CaffeineMakesSense then
        for key, value in pairs(SandboxVars.CaffeineMakesSense) do
            local defaultValue = options[key]
            if defaultValue ~= nil then
                if type(defaultValue) == "boolean" then
                    options[key] = (tostring(value):lower() == "true" or value == true or value == 1)
                elseif type(defaultValue) == "number" then
                    local parsed = tonumber(value)
                    if parsed ~= nil then
                        options[key] = parsed
                    end
                end
            end
        end
    end
    return options
end

function Runtime.ensureStateTable(state, nowMinutes)
    local stateNow = tonumber(nowMinutes) or Runtime.getWorldAgeMinutes()
    state = type(state) == "table" and state or {}
    state.version = tonumber(state.version) or 3
    state.doses = type(state.doses) == "table" and state.doses or {}
    state.hiddenFatigue = tonumber(state.hiddenFatigue) or 0
    state.peakStimThisCycle = tonumber(state.peakStimThisCycle) or 0
    state.lastUpdateGameMinutes = tonumber(state.lastUpdateGameMinutes) or stateNow
    state.pendingCatchupMinutes = math.max(0, tonumber(state.pendingCatchupMinutes) or 0)
    state.realFatigue = tonumber(state.realFatigue) or nil
    state.lastSetFatigue = tonumber(state.lastSetFatigue) or nil
    state.wasSleeping = (state.wasSleeping == true)
    state.sleepStartMinute = tonumber(state.sleepStartMinute) or nil
    state.sleepLastAccumMinute = tonumber(state.sleepLastAccumMinute) or nil
    state.sleepWeightedDisruption = tonumber(state.sleepWeightedDisruption) or 0
    state.sleepWeightedMinutes = tonumber(state.sleepWeightedMinutes) or 0
    state.sleepPeakDisruption = tonumber(state.sleepPeakDisruption) or 0
    state.sleepDisruptionScore = tonumber(state.sleepDisruptionScore) or 0
    state.sleepDisruptionStrength = tonumber(state.sleepDisruptionStrength) or 0
    state.sleepPendingWakeFatigue = tonumber(state.sleepPendingWakeFatigue) or 0
    state.lastWakeFatiguePenalty = tonumber(state.lastWakeFatiguePenalty) or 0
    state.lastSleepDisruptionScore = tonumber(state.lastSleepDisruptionScore) or 0
    return state
end

function Runtime.ensureStateForPlayer(playerObj, nowMinutes)
    local modData = safeCall(playerObj, "getModData")
    if type(modData) ~= "table" then
        return nil
    end
    local key = getStateKey()
    modData[key] = Runtime.ensureStateTable(modData[key], nowMinutes)
    return modData[key]
end

function Runtime.addDose(state, doseLevel, nowMinutes, profileKey, category)
    if not state or doseLevel <= 0 then
        return
    end
    state.doses = state.doses or {}
    state.doses[#state.doses + 1] = {
        doseLevel = doseLevel,
        doseMinute = nowMinutes,
        profileKey = Runtime.normalizeProfileKey(profileKey, category),
        category = tostring(category or profileKey or "unknown"),
    }
end

function Runtime.getNewestDose(state)
    local newest = nil
    for i = 1, #(state and state.doses or {}) do
        local dose = state.doses[i]
        if dose and dose.doseMinute and (not newest or dose.doseMinute > newest.doseMinute) then
            newest = dose
        end
    end
    return newest
end

function Runtime.getDoseProfileKey(dose)
    if not dose then
        return "coffee"
    end
    return Runtime.normalizeProfileKey(dose.profileKey, dose.category)
end

function Runtime.getLoadTotals(state, nowMinutes, options)
    local Pharma = CaffeineMakesSense.Pharma
    if not Pharma or not state or not state.doses then
        return 0, 0
    end
    local rawStimLoad = 0
    local maskLoad = 0
    for i = 1, #state.doses do
        local dose = state.doses[i]
        if dose and dose.doseLevel and dose.doseMinute then
            local elapsed = nowMinutes - dose.doseMinute
            local profile = Pharma.getProfileOptions(options, Runtime.getDoseProfileKey(dose))
            local level = Pharma.caffeineAtTime(dose.doseLevel, elapsed, profile.onsetMinutes, profile.halfLifeMinutes)
            rawStimLoad = rawStimLoad + level
            maskLoad = maskLoad + (level * profile.maskScale)
        end
    end
    return rawStimLoad, maskLoad
end

function Runtime.getEffectiveCaffeine(state, nowMinutes, options)
    local rawStimLoad = Runtime.getLoadTotals(state, nowMinutes, options)
    return rawStimLoad
end

function Runtime.pruneDoses(state, nowMinutes, options)
    local Pharma = CaffeineMakesSense.Pharma
    if not state or not state.doses or not Pharma then
        return
    end
    local threshold = tonumber(options.NegligibleThreshold) or 0.05
    local pruned = {}
    for i = 1, #state.doses do
        local dose = state.doses[i]
        if dose and dose.doseLevel and dose.doseMinute then
            local elapsed = nowMinutes - dose.doseMinute
            local profile = Pharma.getProfileOptions(options, Runtime.getDoseProfileKey(dose))
            local level = Pharma.caffeineAtTime(dose.doseLevel, elapsed, profile.onsetMinutes, profile.halfLifeMinutes)
            -- Smooth onset starts near zero, so pruning only by current level can
            -- delete fresh doses before they ever reach their first meaningful rise.
            if elapsed < profile.onsetMinutes or level >= threshold * 0.1 then
                pruned[#pruned + 1] = dose
            end
        end
    end
    state.doses = pruned
end

function Runtime.getFatigue(playerObj)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return nil
    end
    if CharacterStat and CharacterStat.FATIGUE then
        return tonumber(safeCall(stats, "get", CharacterStat.FATIGUE))
    end
    return tonumber(safeCall(stats, "getFatigue"))
end

function Runtime.setFatigue(playerObj, value)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return
    end
    value = clamp(value, 0, 1)
    if CharacterStat and CharacterStat.FATIGUE then
        safeCall(stats, "set", CharacterStat.FATIGUE, value)
        return
    end
    safeCall(stats, "setFatigue", value)
end

function Runtime.isPlayerAsleep(playerObj)
    return safeCall(playerObj, "isAsleep") == true
end

function Runtime.resetState(state, restoredFatigue)
    if not state then
        return
    end
    local restored = clamp(tonumber(restoredFatigue) or 0, 0, 1)
    state.doses = {}
    state.hiddenFatigue = 0
    state.peakStimThisCycle = 0
    state.pendingCatchupMinutes = 0
    state.wasSleeping = false
    state.sleepStartMinute = nil
    state.sleepLastAccumMinute = nil
    state.sleepWeightedDisruption = 0
    state.sleepWeightedMinutes = 0
    state.sleepPeakDisruption = 0
    state.sleepDisruptionScore = 0
    state.sleepDisruptionStrength = 0
    state.sleepPendingWakeFatigue = 0
    state.lastWakeFatiguePenalty = 0
    state.lastSleepDisruptionScore = 0
    state.realFatigue = restored
    state.lastSetFatigue = restored
end

local function clearSleepSession(state)
    state.sleepStartMinute = nil
    state.sleepLastAccumMinute = nil
    state.sleepWeightedDisruption = 0
    state.sleepWeightedMinutes = 0
    state.sleepPeakDisruption = 0
    state.sleepDisruptionScore = 0
    state.sleepDisruptionStrength = 0
    state.sleepPendingWakeFatigue = 0
end

function Runtime.beginSleepSession(playerObj, state, nowMinutes)
    if not state then
        return
    end
    local now = tonumber(nowMinutes) or Runtime.getWorldAgeMinutes()
    clearSleepSession(state)
    state.wasSleeping = true
    state.sleepStartMinute = now
    state.sleepLastAccumMinute = now
end

function Runtime.accumulateSleepDisruption(playerObj, state, nowMinutes, dtMinutes, options)
    local Pharma = CaffeineMakesSense.Pharma
    if not state or not Pharma then
        return
    end
    local dt = math.max(0, tonumber(dtMinutes) or 0)
    local now = tonumber(nowMinutes) or Runtime.getWorldAgeMinutes()
    if dt <= 0 then
        state.sleepLastAccumMinute = now
        return
    end

    local maxCaffeine = tonumber(options.MaxCaffeineLevel) or 4.0
    local disruptionMax = tonumber(options.SleepDisruptionStrengthMax) or 0.60
    local rawStimLoad = Runtime.getLoadTotals(state, now, options)
    local instantDisruption = Pharma.sleepDisruptionStrength(rawStimLoad, disruptionMax, maxCaffeine)
    local sleepStart = tonumber(state.sleepStartMinute) or now
    local minutesAsleep = math.max(0, now - sleepStart)
    local earlyWeight = 0.35 + 0.65 * math.exp(-minutesAsleep / 180.0)

    state.sleepWeightedDisruption = (state.sleepWeightedDisruption or 0) + instantDisruption * earlyWeight * dt
    state.sleepWeightedMinutes = (state.sleepWeightedMinutes or 0) + earlyWeight * dt
    state.sleepPeakDisruption = math.max(tonumber(state.sleepPeakDisruption) or 0, instantDisruption)
    state.sleepDisruptionStrength = instantDisruption
    state.sleepDisruptionScore = (state.sleepWeightedDisruption or 0) / math.max(0.01, state.sleepWeightedMinutes or 0)
    local wakeFatigueMax = tonumber(options.SleepWakeFatigueMax) or 0.12
    state.sleepPendingWakeFatigue = clamp((state.sleepDisruptionScore or 0) * wakeFatigueMax, 0, wakeFatigueMax)
    state.sleepLastAccumMinute = now
end

function Runtime.accumulateSleepToTime(playerObj, state, nowMinutes, options)
    if not state then
        return
    end
    local now = tonumber(nowMinutes) or Runtime.getWorldAgeMinutes()
    local last = tonumber(state.sleepLastAccumMinute) or now
    local dt = math.max(0, now - last)
    Runtime.accumulateSleepDisruption(playerObj, state, now, dt, options)
end

function Runtime.finalizeSleepSession(playerObj, state, nowMinutes, options)
    if not state then
        return 0
    end
    local now = tonumber(nowMinutes) or Runtime.getWorldAgeMinutes()
    Runtime.accumulateSleepToTime(playerObj, state, now, options)
    local wakeFatigueMax = tonumber(options.SleepWakeFatigueMax) or 0.12
    state.lastSleepDisruptionScore = tonumber(state.sleepDisruptionScore) or 0
    local wakePenalty = clamp(tonumber(state.sleepPendingWakeFatigue) or 0, 0, wakeFatigueMax)
    state.lastWakeFatiguePenalty = wakePenalty
    if wakePenalty > 0 then
        state.realFatigue = clamp((state.realFatigue or 0) + wakePenalty, 0, 1)
    end
    clearSleepSession(state)
    state.wasSleeping = false
    return wakePenalty
end

function Runtime.onSleepingTick(playerObj)
    local Pharma = CaffeineMakesSense.Pharma
    if not playerObj or not Pharma then
        return
    end
    local nowMinutes = Runtime.getWorldAgeMinutes()
    local state = Runtime.ensureStateForPlayer(playerObj, nowMinutes)
    if not state then
        return
    end
    if not Runtime.isPlayerAsleep(playerObj) then
        return
    end
    if not state.wasSleeping or not state.sleepStartMinute then
        Runtime.beginSleepSession(playerObj, state, nowMinutes)
    end
    Runtime.accumulateSleepToTime(playerObj, state, nowMinutes, Runtime.getOptions())
end

function Runtime.tickPlayer(playerObj)
    local Pharma = CaffeineMakesSense.Pharma
    if not playerObj or not Pharma then
        return
    end

    local nowMinutes = Runtime.getWorldAgeMinutes()
    local state = Runtime.ensureStateForPlayer(playerObj, nowMinutes)
    if not state then
        return
    end
    local options = Runtime.getOptions()

    local elapsed = nowMinutes - state.lastUpdateGameMinutes
    state.lastUpdateGameMinutes = nowMinutes

    local pendingMinutes = math.max(0, state.pendingCatchupMinutes + elapsed)
    if pendingMinutes <= 0 then
        state.pendingCatchupMinutes = 0
        return
    end

    local dtCap = math.max(0.01, tonumber(options.DtMaxMinutes) or 3)
    local maxSlices = math.max(1, math.floor(tonumber(options.DtCatchupMaxSlices) or 240))
    local slices = 0
    local maxCaffeine = tonumber(options.MaxCaffeineLevel) or 4.0
    local peakMask = tonumber(options.PeakMaskStrength) or 0.85
    local negligible = tonumber(options.NegligibleThreshold) or 0.05
    local suppressionFrac = tonumber(options.SuppressionFraction) or 0.50
    local projectionShapeScale = tonumber(options.ProjectionShapeScale) or 3.0
    local wasSleeping = state.wasSleeping == true
    local sleeping = Runtime.isPlayerAsleep(playerObj)

    if sleeping and not wasSleeping then
        Runtime.beginSleepSession(playerObj, state, nowMinutes)
    end

    local displayedFatigue = Runtime.getFatigue(playerObj)
    if displayedFatigue == nil then
        return
    end
    local vanillaDelta = displayedFatigue - (state.lastSetFatigue or displayedFatigue)
    state.realFatigue = clamp(state.realFatigue or displayedFatigue, 0, 1)
    local totalPendingMinutes = pendingMinutes

    while pendingMinutes > 0 and slices < maxSlices do
        local dt = clamp(pendingMinutes, 0, dtCap)
        if dt <= 0 then
            break
        end
        pendingMinutes = pendingMinutes - dt
        slices = slices + 1

        local sliceMinute = nowMinutes - pendingMinutes
        local rawStimLoad, maskLoad = Runtime.getLoadTotals(state, sliceMinute, options)
        local sliceWeight = totalPendingMinutes > 0 and (dt / totalPendingMinutes) or 1.0
        local vanillaDeltaSlice = vanillaDelta * sliceWeight

        if sleeping then
            Runtime.accumulateSleepToTime(playerObj, state, sliceMinute, options)
        end

        state.realFatigue = clamp((state.realFatigue or displayedFatigue) + vanillaDeltaSlice, 0, 1)

        if rawStimLoad > (state.peakStimThisCycle or 0) then
            state.peakStimThisCycle = rawStimLoad
        end

        local targetDisplayed = state.realFatigue
        if not sleeping then
            local maskStr = Pharma.maskStrength(maskLoad, peakMask, maxCaffeine)
            targetDisplayed = Pharma.projectDisplayedFatigue(
                state.realFatigue,
                maskStr,
                suppressionFrac,
                projectionShapeScale
            )
            state.hiddenFatigue = math.max(0, state.realFatigue - targetDisplayed)
        else
            state.hiddenFatigue = 0
        end

        Runtime.setFatigue(playerObj, targetDisplayed)
        state.lastSetFatigue = targetDisplayed

        if rawStimLoad < negligible * 0.1 and (state.hiddenFatigue or 0) < 0.001 then
            state.hiddenFatigue = 0
            state.peakStimThisCycle = 0
            state.sleepDisruptionStrength = 0
            state.sleepDisruptionScore = 0
            state.sleepPendingWakeFatigue = 0
            local fatNow = Runtime.getFatigue(playerObj)
            if fatNow then
                state.realFatigue = fatNow
                state.lastSetFatigue = fatNow
            end
        end
    end

    if (not sleeping) and wasSleeping then
        Runtime.finalizeSleepSession(playerObj, state, nowMinutes, options)
        local rawStimLoad, maskLoad = Runtime.getLoadTotals(state, nowMinutes, options)
        local targetDisplayed = state.realFatigue or displayedFatigue
        if rawStimLoad > (state.peakStimThisCycle or 0) then
            state.peakStimThisCycle = rawStimLoad
        end
        local maskStr = Pharma.maskStrength(maskLoad, peakMask, maxCaffeine)
        targetDisplayed = Pharma.projectDisplayedFatigue(
            state.realFatigue,
            maskStr,
            suppressionFrac,
            projectionShapeScale
        )
        state.hiddenFatigue = math.max(0, (state.realFatigue or 0) - targetDisplayed)
        Runtime.setFatigue(playerObj, targetDisplayed)
        state.lastSetFatigue = targetDisplayed
    end

    state.wasSleeping = sleeping
    state.pendingCatchupMinutes = math.max(0, pendingMinutes)
    Runtime.pruneDoses(state, nowMinutes, options)
end

return Runtime
