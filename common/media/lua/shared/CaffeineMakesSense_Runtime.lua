CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.Runtime = CaffeineMakesSense.Runtime or {}

require "CaffeineMakesSense_SleepPlanner"
require "CaffeineMakesSense_HealthStatus"
require "CaffeineMakesSense_Pharma"

local Runtime = CaffeineMakesSense.Runtime
local DEFAULTS = CaffeineMakesSense.DEFAULTS or {}
local HealthStatus = CaffeineMakesSense.HealthStatus or {}
local Planner = CaffeineMakesSense.SleepPlanner or {}
local PROTOCOL = "mscompat-v1"

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

local function getCompat()
    local compat = CaffeineMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or tostring(compat.protocol) ~= PROTOCOL then
        return nil
    end
    return compat
end

local function isAuthoritativeMpServer()
    return ((type(isServer) == "function" and isServer() == true)
        or (GameServer and GameServer.bServer == true))
end

local function buildTraceSnapshot(playerObj, _args)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return {}
    end
    local options = Runtime.getOptions()
    local sleepPenaltyEnabled = Runtime.isSleepPenaltyEnabled(options)

    return {
        real_fatigue = tonumber(state.realFatigue) or nil,
        hidden_fatigue = tonumber(state.hiddenFatigue) or 0,
        last_set_fatigue = tonumber(state.lastSetFatigue) or nil,
        last_nms_extra_fatigue = tonumber(state.lastCompatNmsExtraFatigue) or 0,
        last_ams_sleep_fatigue = tonumber(state.lastCompatAmsSleepFatigue) or 0,
        last_sleep_recovery_fatigue = sleepPenaltyEnabled and (tonumber(state.lastSleepRecoveryFatigue) or 0) or 0,
        peak_stim = tonumber(state.peakStimThisCycle) or 0,
        sleep_disruption_score = sleepPenaltyEnabled and (tonumber(state.sleepDisruptionScore) or 0) or 0,
        sleep_recovery_penalty_fraction = sleepPenaltyEnabled and (tonumber(state.lastSleepRecoveryPenaltyFraction)
            or tonumber(state.sleepRecoveryPenaltyFraction)
            or 0) or 0,
        sleep_wake_adjustment = tonumber(state.lastSleepWakeAdjustment) or 0,
        sleep_bed_type = tostring(state.sleepBedType or ""),
        caffeine_stress = tonumber(state.caffeineStressCurrent) or 0,
    }
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

do
    local compat = getCompat()
    if compat and type(compat.registerProvider) == "function" then
        compat:registerProvider("CaffeineMakesSense", {
            capabilities = {
                fatigue_coordinator = true,
                sleep_planner_coordinator = true,
                sleep_wake_adjustment_coordinator = true,
                sleep_planner_penalty_provider = true,
            },
            callbacks = {
                buildTraceSnapshot = buildTraceSnapshot,
                estimateSleepPlannerPenalty = function(playerObj, args)
                    return Runtime.computeSleepPlannerPenalty(playerObj, args)
                end,
            },
        })
    end
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

function Runtime.isSleepPenaltyEnabled(options)
    if type(options) ~= "table" then
        options = Runtime.getOptions()
    end
    return options.EnableSleepPenaltyModel ~= false
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
    state.pendingSleepSession = type(state.pendingSleepSession) == "table" and state.pendingSleepSession or nil
    state.realFatigue = tonumber(state.realFatigue) or nil
    state.lastSetFatigue = tonumber(state.lastSetFatigue) or nil
    state.wasSleeping = (state.wasSleeping == true)
    state.sleepStartMinute = tonumber(state.sleepStartMinute) or nil
    state.sleepBedType = tostring(state.sleepBedType or "")
    state.sleepLastAccumMinute = tonumber(state.sleepLastAccumMinute) or nil
    state.sleepWeightedDisruption = tonumber(state.sleepWeightedDisruption) or 0
    state.sleepWeightedMinutes = tonumber(state.sleepWeightedMinutes) or 0
    state.sleepPeakDisruption = tonumber(state.sleepPeakDisruption) or 0
    state.sleepDisruptionScore = tonumber(state.sleepDisruptionScore) or 0
    state.sleepDisruptionStrength = tonumber(state.sleepDisruptionStrength) or 0
    state.sleepRecoveryPenaltyFraction = clamp(tonumber(state.sleepRecoveryPenaltyFraction) or 0, 0, 0.95)
    state.lastSleepRecoveryPenaltyFraction = clamp(tonumber(state.lastSleepRecoveryPenaltyFraction) or 0, 0, 0.95)
    state.lastSleepRecoveryFatigue = tonumber(state.lastSleepRecoveryFatigue) or 0
    state.lastSleepDisruptionScore = tonumber(state.lastSleepDisruptionScore) or 0
    state.lastSleepWakeAdjustment = tonumber(state.lastSleepWakeAdjustment) or 0
    state.caffeineStressCurrent = clamp(tonumber(state.caffeineStressCurrent) or 0, 0, 1)
    state.caffeineStressTarget = clamp(tonumber(state.caffeineStressTarget) or 0, 0, 1)
    state.lastAppliedCaffeineStress = clamp(tonumber(state.lastAppliedCaffeineStress) or 0, 0, 1)
    state.lastCompatNmsExtraFatigue = tonumber(state.lastCompatNmsExtraFatigue) or 0
    state.lastCompatAmsSleepFatigue = tonumber(state.lastCompatAmsSleepFatigue) or 0
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

function Runtime.getStress(playerObj)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return nil
    end
    if CharacterStat and CharacterStat.STRESS then
        return tonumber(safeCall(stats, "get", CharacterStat.STRESS))
    end
    return tonumber(safeCall(stats, "getStress"))
end

function Runtime.setStress(playerObj, value)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return
    end
    value = clamp(value, 0, 1)
    if CharacterStat and CharacterStat.STRESS then
        safeCall(stats, "set", CharacterStat.STRESS, value)
        return
    end
    safeCall(stats, "setStress", value)
end

function Runtime.isPlayerAsleep(playerObj)
    return safeCall(playerObj, "isAsleep") == true
end

function Runtime.clearAppliedCaffeineStress(playerObj, state)
    if not state then
        return
    end
    local totalStress = Runtime.getStress(playerObj)
    if totalStress == nil then
        state.lastAppliedCaffeineStress = 0
        state.caffeineStressCurrent = 0
        state.caffeineStressTarget = 0
        return
    end
    local priorApplied = clamp(state.lastAppliedCaffeineStress or 0, 0, 1)
    Runtime.setStress(playerObj, clamp(totalStress - priorApplied, 0, 1))
    state.lastAppliedCaffeineStress = 0
    state.caffeineStressCurrent = 0
    state.caffeineStressTarget = 0
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
    state.pendingSleepSession = nil
    state.wasSleeping = false
    state.sleepStartMinute = nil
    state.sleepBedType = ""
    state.sleepLastAccumMinute = nil
    state.sleepWeightedDisruption = 0
    state.sleepWeightedMinutes = 0
    state.sleepPeakDisruption = 0
    state.sleepDisruptionScore = 0
    state.sleepDisruptionStrength = 0
    state.sleepRecoveryPenaltyFraction = 0
    state.lastSleepRecoveryPenaltyFraction = 0
    state.lastSleepRecoveryFatigue = 0
    state.lastSleepDisruptionScore = 0
    state.lastSleepWakeAdjustment = 0
    state.caffeineStressCurrent = 0
    state.caffeineStressTarget = 0
    state.lastAppliedCaffeineStress = 0
    state.realFatigue = restored
    state.lastSetFatigue = restored
end

function Runtime.applyCanonicalFatigueTarget(playerObj, state, targetFatigue)
    if not playerObj then
        return nil
    end

    local Pharma = CaffeineMakesSense.Pharma
    local runtimeState = state or Runtime.ensureStateForPlayer(playerObj, Runtime.getWorldAgeMinutes())
    if not runtimeState or type(Pharma) ~= "table" then
        return nil
    end

    local target = clamp(tonumber(targetFatigue) or 0, 0, 1)
    local nowMinutes = Runtime.getWorldAgeMinutes()
    local options = Runtime.getOptions()
    local sleeping = Runtime.isPlayerAsleep(playerObj)
    local rawStimLoad, maskLoad = Runtime.getLoadTotals(runtimeState, nowMinutes, options)
    local maxCaffeine = tonumber(options.MaxCaffeineLevel) or 4.0
    local peakMask = tonumber(options.PeakMaskStrength) or 0.85
    local suppressionFrac = tonumber(options.SuppressionFraction) or 0.50
    local projectionShapeScale = tonumber(options.ProjectionShapeScale) or 3.0

    local targetDisplayed = target
    runtimeState.realFatigue = target
    runtimeState.pendingCatchupMinutes = 0

    if sleeping then
        runtimeState.hiddenFatigue = 0
    else
        if type(Pharma.maskStrength) == "function" and type(Pharma.projectDisplayedFatigue) == "function" then
            local maskStr = Pharma.maskStrength(maskLoad, peakMask, maxCaffeine)
            targetDisplayed = Pharma.projectDisplayedFatigue(
                target,
                maskStr,
                suppressionFrac,
                projectionShapeScale
            )
            runtimeState.hiddenFatigue = math.max(0, target - targetDisplayed)
        else
            runtimeState.hiddenFatigue = 0
        end
    end

    Runtime.setFatigue(playerObj, targetDisplayed)
    runtimeState.lastSetFatigue = targetDisplayed

    return {
        realFatigue = target,
        displayedFatigue = targetDisplayed,
        sleeping = sleeping,
    }
end

local function clearSleepSession(state)
    state.sleepStartMinute = nil
    state.sleepBedType = ""
    state.sleepLastAccumMinute = nil
    state.sleepWeightedDisruption = 0
    state.sleepWeightedMinutes = 0
    state.sleepPeakDisruption = 0
    state.sleepDisruptionScore = 0
    state.sleepDisruptionStrength = 0
    state.sleepRecoveryPenaltyFraction = 0
end

local function resolveSleepBedType(playerObj, state)
    local bedType = tostring(safeCall(playerObj, "getBedType") or "")
    if bedType == "" and type(state) == "table" and type(state.pendingSleepSession) == "table" then
        bedType = tostring(state.pendingSleepSession.bedType or state.pendingSleepSession.bed_type or "")
    end
    return bedType
end

local function updateCaffeineStress(playerObj, state, rawStimLoad, dtMinutes, sleeping, options)
    local Pharma = CaffeineMakesSense.Pharma
    if not state or type(Pharma) ~= "table" then
        return
    end

    local target = 0
    if not sleeping then
        target = Pharma.caffeineStressTarget(rawStimLoad, state.hiddenFatigue or 0, options)
    end

    local tauMinutes
    if sleeping then
        tauMinutes = tonumber(options.StressSleepDecayTauMinutes) or 60
    elseif target > (state.caffeineStressCurrent or 0) then
        tauMinutes = tonumber(options.StressRiseTauMinutes) or 90
    else
        tauMinutes = tonumber(options.StressDecayTauMinutes) or 120
    end

    state.caffeineStressTarget = clamp(target, 0, 1)
    state.caffeineStressCurrent = clamp(
        Pharma.approachValue(state.caffeineStressCurrent or 0, state.caffeineStressTarget, dtMinutes, tauMinutes),
        0,
        1
    )

    local totalStress = Runtime.getStress(playerObj) or 0
    local priorApplied = clamp(state.lastAppliedCaffeineStress or 0, 0, 1)
    local baselineStress = clamp(totalStress - priorApplied, 0, 1)
    local newTotalStress = clamp(baselineStress + (state.caffeineStressCurrent or 0), 0, 1)
    Runtime.setStress(playerObj, newTotalStress)
    state.lastAppliedCaffeineStress = state.caffeineStressCurrent or 0
end

function Runtime.beginSleepSession(playerObj, state, nowMinutes)
    if not state then
        return
    end
    local now = tonumber(nowMinutes) or Runtime.getWorldAgeMinutes()
    clearSleepSession(state)
    state.wasSleeping = true
    state.sleepStartMinute = now
    state.sleepBedType = resolveSleepBedType(playerObj, state)
    state.pendingSleepSession = nil
    state.sleepLastAccumMinute = now
    state.lastSleepRecoveryFatigue = 0
    state.lastSleepWakeAdjustment = 0
end

function Runtime.applySleepWakeFatigueAdjustment(playerObj, state, nowMinutes)
    if not playerObj or type(state) ~= "table" then
        return 0
    end

    local compat = getCompat()
    if type(compat) ~= "table" or type(compat.computeSleepWakeFatigueDelta) ~= "function" then
        state.lastSleepWakeAdjustment = 0
        return 0
    end

    local sleepStartMinute = tonumber(state.sleepStartMinute)
    if sleepStartMinute == nil then
        state.lastSleepWakeAdjustment = 0
        return 0
    end

    local sleptHours = math.max(0, ((tonumber(nowMinutes) or Runtime.getWorldAgeMinutes()) - sleepStartMinute) / 60.0)
    local referenceFatigue = tonumber(state.realFatigue)
    if referenceFatigue == nil then
        referenceFatigue = Runtime.getFatigue(playerObj)
    end
    local expectedWakeAdjustment = tonumber(compat.computeSleepWakeFatigueDelta(state.sleepBedType, sleptHours)) or 0

    local observedFatigue = Runtime.getFatigue(playerObj)
    if observedFatigue ~= nil and referenceFatigue ~= nil then
        local observedAdjustment = clamp(observedFatigue, 0, 1) - referenceFatigue
        if math.abs(observedAdjustment) > 0.002 then
            local trustObserved = true
            if isAuthoritativeMpServer() and expectedWakeAdjustment ~= 0 then
                trustObserved = (observedAdjustment < 0 and expectedWakeAdjustment < 0)
                    or (observedAdjustment > 0 and expectedWakeAdjustment > 0)
            end
            if trustObserved then
                state.lastSleepWakeAdjustment = observedAdjustment
                state.realFatigue = clamp(observedFatigue, 0, 1)
                return observedAdjustment
            end
        end
    end

    if not isAuthoritativeMpServer() then
        state.lastSleepWakeAdjustment = 0
        if observedFatigue ~= nil then
            state.realFatigue = clamp(observedFatigue, 0, 1)
        end
        return 0
    end

    local wakeAdjustment = expectedWakeAdjustment
    state.lastSleepWakeAdjustment = wakeAdjustment

    if wakeAdjustment == 0 then
        return 0
    end

    if referenceFatigue == nil then
        return wakeAdjustment
    end

    state.realFatigue = clamp(referenceFatigue + wakeAdjustment, 0, 1)
    return wakeAdjustment
end

function Runtime.computeSleepDisruptionStrength(rawStimLoad, options)
    if not Runtime.isSleepPenaltyEnabled(options) then
        return 0
    end
    local Pharma = CaffeineMakesSense.Pharma
    if not Pharma then
        return 0
    end
    local maxCaffeine = tonumber(options and options.MaxCaffeineLevel) or 4.0
    local disruptionMax = tonumber(options and options.SleepDisruptionStrengthMax) or 0.60
    return Pharma.sleepDisruptionStrength(rawStimLoad, disruptionMax, maxCaffeine)
end

function Runtime.computeSleepRecoveryPenaltyFraction(rawStimLoad, options)
    if not Runtime.isSleepPenaltyEnabled(options) then
        return 0
    end
    local Pharma = CaffeineMakesSense.Pharma
    if not Pharma then
        return 0
    end
    local meaningfulThreshold = type(HealthStatus.getMeaningfulLoadThreshold) == "function"
        and tonumber(HealthStatus.getMeaningfulLoadThreshold(options))
        or nil
    if meaningfulThreshold ~= nil and rawStimLoad < meaningfulThreshold then
        return 0
    end
    local maxCaffeine = tonumber(options and options.MaxCaffeineLevel) or 4.0
    local penaltyMax = tonumber(options and options.SleepRecoveryPenaltyMaxFrac) or 0.20
    return Pharma.sleepDisruptionStrength(rawStimLoad, penaltyMax, maxCaffeine)
end

function Runtime.buildSleepDebugMetrics(state, rawStimLoad, options)
    if not Runtime.isSleepPenaltyEnabled(options) then
        return {
            disruptionScore = 0,
            projectedPenaltyFraction = 0,
            activePenaltyFraction = 0,
            lastRecoveryFatigue = 0,
        }
    end
    local resolvedState = type(state) == "table" and state or {}
    return {
        disruptionScore = math.max(
            tonumber(resolvedState.sleepDisruptionScore) or 0,
            tonumber(resolvedState.lastSleepDisruptionScore) or 0
        ),
        projectedPenaltyFraction = Runtime.computeSleepRecoveryPenaltyFraction(rawStimLoad, options),
        activePenaltyFraction = clamp(tonumber(resolvedState.sleepRecoveryPenaltyFraction) or 0, 0, 0.95),
        lastRecoveryFatigue = tonumber(resolvedState.lastSleepRecoveryFatigue) or 0,
    }
end

function Runtime.computeSleepPlannerPenalty(playerObj, _args)
    if not playerObj then
        return { penaltyFraction = 0 }
    end

    local nowMinutes = Runtime.getWorldAgeMinutes()
    local state = Runtime.ensureStateForPlayer(playerObj, nowMinutes)
    if not state then
        return { penaltyFraction = 0 }
    end

    local options = Runtime.getOptions()
    if not Runtime.isSleepPenaltyEnabled(options) then
        return {
            penaltyFraction = 0,
            recoveryPenaltyFraction = 0,
            rawStimLoad = Runtime.getLoadTotals(state, nowMinutes, options),
        }
    end
    local rawStimLoad = Runtime.getLoadTotals(state, nowMinutes, options)
    local recoveryPenalty = Runtime.computeSleepRecoveryPenaltyFraction(rawStimLoad, options)
    local plannerPenalty = recoveryPenalty
    if type(Planner.computePlannerPenaltyFraction) == "function" then
        plannerPenalty = tonumber(Planner.computePlannerPenaltyFraction(recoveryPenalty, rawStimLoad, options)) or 0
    end

    return {
        penaltyFraction = clamp(plannerPenalty, 0, 0.95),
        recoveryPenaltyFraction = clamp(recoveryPenalty, 0, 0.95),
        rawStimLoad = rawStimLoad,
    }
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

    if not Runtime.isSleepPenaltyEnabled(options) then
        state.sleepWeightedDisruption = 0
        state.sleepWeightedMinutes = 0
        state.sleepPeakDisruption = 0
        state.sleepDisruptionStrength = 0
        state.sleepDisruptionScore = 0
        state.sleepRecoveryPenaltyFraction = 0
        state.sleepLastAccumMinute = now
        return
    end

    local rawStimLoad = Runtime.getLoadTotals(state, now, options)
    local instantDisruption = Runtime.computeSleepDisruptionStrength(rawStimLoad, options)
    local sleepStart = tonumber(state.sleepStartMinute) or now
    local minutesAsleep = math.max(0, now - sleepStart)
    local earlyWeight = 0.35 + 0.65 * math.exp(-minutesAsleep / 180.0)

    state.sleepWeightedDisruption = (state.sleepWeightedDisruption or 0) + instantDisruption * earlyWeight * dt
    state.sleepWeightedMinutes = (state.sleepWeightedMinutes or 0) + earlyWeight * dt
    state.sleepPeakDisruption = math.max(tonumber(state.sleepPeakDisruption) or 0, instantDisruption)
    state.sleepDisruptionStrength = instantDisruption
    state.sleepDisruptionScore = (state.sleepWeightedDisruption or 0) / math.max(0.01, state.sleepWeightedMinutes or 0)
    state.sleepRecoveryPenaltyFraction = Runtime.computeSleepRecoveryPenaltyFraction(rawStimLoad, options)
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
    state.lastSleepDisruptionScore = tonumber(state.sleepDisruptionScore) or 0
    state.lastSleepRecoveryPenaltyFraction = clamp(tonumber(state.sleepRecoveryPenaltyFraction) or 0, 0, 0.95)
    clearSleepSession(state)
    state.wasSleeping = false
    return 0
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
    local compat = getCompat()
    local nmsFatigueCallback = compat and compat.getCallback and compat:getCallback("NutritionMakesSense", "computeFatigueContribution") or nil
    local amsSleepPenaltyCallback = compat and compat.getCallback and compat:getCallback("ArmorMakesSense", "computeSleepPenaltyContribution") or nil
    local cycleNmsExtraFatigue = 0
    local cycleAmsSleepFatigue = 0
    local cycleSleepRecoveryFatigue = 0

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
        if (not sleeping) and type(nmsFatigueCallback) == "function" then
            local okCompat, fatigueContribution = pcall(nmsFatigueCallback, playerObj, {
                dtMinutes = dt,
                dtHours = dt / 60.0,
                sleeping = false,
                currentFatigue = state.realFatigue,
            })
            if okCompat and type(fatigueContribution) == "table" then
                local compatExtraFatigue = math.max(0, tonumber(fatigueContribution.extraFatigue) or 0)
                if compatExtraFatigue > 0 then
                    cycleNmsExtraFatigue = cycleNmsExtraFatigue + compatExtraFatigue
                    state.realFatigue = clamp((state.realFatigue or displayedFatigue) + compatExtraFatigue, 0, 0.95)
                end
            end
        end
        if sleeping then
            local recoveredFatigue = math.max(0, -vanillaDeltaSlice)
            local cmsPenaltyFraction = clamp(tonumber(state.sleepRecoveryPenaltyFraction) or 0, 0, 0.95)
            local amsPenaltyFraction = 0

            if type(amsSleepPenaltyCallback) == "function" then
                local okCompat, sleepContribution = pcall(amsSleepPenaltyCallback, playerObj, {
                    dtMinutes = dt,
                    currentFatigue = state.realFatigue,
                    recoveredFatigue = recoveredFatigue,
                })
                if okCompat and type(sleepContribution) == "table" then
                    amsPenaltyFraction = clamp(tonumber(sleepContribution.penaltyFraction) or 0, 0, 0.95)
                end
            end

            if recoveredFatigue > 0 then
                local combinedPenalty = 0
                if compat and type(compat.combinePenaltyFractions) == "function" then
                    combinedPenalty = compat.combinePenaltyFractions({
                        cmsPenaltyFraction,
                        amsPenaltyFraction,
                    })
                else
                    combinedPenalty = clamp(cmsPenaltyFraction + amsPenaltyFraction, 0, 0.95)
                end

                if combinedPenalty > 0 then
                    local compatExtraFatigue = recoveredFatigue * combinedPenalty
                    local rawPenaltyTotal = cmsPenaltyFraction + amsPenaltyFraction
                    if rawPenaltyTotal > 0 then
                        cycleSleepRecoveryFatigue = cycleSleepRecoveryFatigue
                            + (compatExtraFatigue * (cmsPenaltyFraction / rawPenaltyTotal))
                        cycleAmsSleepFatigue = cycleAmsSleepFatigue
                            + (compatExtraFatigue * (amsPenaltyFraction / rawPenaltyTotal))
                    end
                    state.realFatigue = clamp((state.realFatigue or displayedFatigue) + compatExtraFatigue, 0, 0.95)
                end
            end
        end

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

        updateCaffeineStress(playerObj, state, rawStimLoad, dt, sleeping, options)

        Runtime.setFatigue(playerObj, targetDisplayed)
        state.lastSetFatigue = targetDisplayed

        if rawStimLoad < negligible * 0.1 and (state.hiddenFatigue or 0) < 0.001 then
            state.hiddenFatigue = 0
            state.peakStimThisCycle = 0
            state.sleepDisruptionStrength = 0
            state.sleepDisruptionScore = 0
            state.sleepRecoveryPenaltyFraction = 0
            state.caffeineStressTarget = 0
            local fatNow = Runtime.getFatigue(playerObj)
            if fatNow then
                state.realFatigue = fatNow
                state.lastSetFatigue = fatNow
            end
        end
    end

    if (not sleeping) and wasSleeping then
        Runtime.applySleepWakeFatigueAdjustment(playerObj, state, nowMinutes)
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
        updateCaffeineStress(playerObj, state, rawStimLoad, dtCap, sleeping, options)
        Runtime.setFatigue(playerObj, targetDisplayed)
        state.lastSetFatigue = targetDisplayed
    end

    state.wasSleeping = sleeping
    state.pendingCatchupMinutes = math.max(0, pendingMinutes)
    state.lastCompatNmsExtraFatigue = cycleNmsExtraFatigue
    state.lastCompatAmsSleepFatigue = cycleAmsSleepFatigue
    state.lastSleepRecoveryFatigue = cycleSleepRecoveryFatigue
    Runtime.pruneDoses(state, nowMinutes, options)
end

return Runtime
