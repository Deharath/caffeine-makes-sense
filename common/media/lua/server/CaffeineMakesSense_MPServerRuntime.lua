CaffeineMakesSense = CaffeineMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

pcall(require, "CaffeineMakesSense_Config")
local okMpCompat, mpCompatOrErr = pcall(require, "CaffeineMakesSense_MPCompat")
if not okMpCompat then
    print("[CaffeineMakesSense][MP][SERVER][ERROR] MPCompat require failed: " .. tostring(mpCompatOrErr))
    return
end
pcall(require, "CaffeineMakesSense_Compat")
pcall(require, "CaffeineMakesSense_Pharma")
pcall(require, "CaffeineMakesSense_Runtime")
pcall(require, "CaffeineMakesSense_ItemDefs")
pcall(require, "CaffeineMakesSense_Hooks")

local MP = (type(mpCompatOrErr) == "table" and mpCompatOrErr) or CaffeineMakesSense.MP
local Runtime = CaffeineMakesSense.Runtime
local Pharma = CaffeineMakesSense.Pharma
if type(MP) ~= "table" then
    print("[CaffeineMakesSense][MP][SERVER][ERROR] MP compat constants unavailable")
    return
end
if type(Runtime) ~= "table" then
    print("[CaffeineMakesSense][MP][SERVER][ERROR] shared runtime unavailable")
    return
end

local function log(msg)
    print("[CaffeineMakesSense][MP][SERVER] " .. tostring(msg))
end

local function buildSnapshot(playerObj)
    if type(Pharma) ~= "table" then
        return nil
    end

    local nowMinutes = Runtime.getWorldAgeMinutes()
    local state = Runtime.ensureStateForPlayer(playerObj, nowMinutes)
    if not state then
        return nil
    end

    local options = Runtime.getOptions()
    local rawStimLoad, maskLoad = Runtime.getLoadTotals(state, nowMinutes, options)
    local maxCaffeine = tonumber(options.MaxCaffeineLevel) or 4.0
    local peakMask = tonumber(options.PeakMaskStrength) or 0.85
    local maskStrength = Pharma.maskStrength(maskLoad, peakMask, maxCaffeine)
    local negligible = tonumber(options.NegligibleThreshold) or 0.05
    local peakStim = tonumber(state.peakStimThisCycle) or 0
    local stimFraction = peakStim > 0 and (rawStimLoad / peakStim) or 0
    local newestDose = Runtime.getNewestDose(state)
    local newestProfileKey = Runtime.getDoseProfileKey(newestDose)
    local newestProfile = Pharma.getProfileOptions(options, newestProfileKey)
    local onsetMin = tonumber(newestProfile.onsetMinutes) or 0
    local halfLifeMin = tonumber(newestProfile.halfLifeMinutes) or 0
    local sleepDebug = type(Runtime.buildSleepDebugMetrics) == "function"
        and Runtime.buildSleepDebugMetrics(state, rawStimLoad, options)
        or nil
    local displayedFatigue = Runtime.getFatigue(playerObj) or 0
    local realFatigue = tonumber(state.realFatigue) or displayedFatigue
    local hiddenFatigue = math.max(0, tonumber(state.hiddenFatigue) or (realFatigue - displayedFatigue))
    local totalStress = Runtime.getStress(playerObj) or 0
    local stage = "inactive"
    if rawStimLoad >= negligible then
        if newestDose and (nowMinutes - newestDose.doseMinute) < onsetMin then
            stage = "onset"
        elseif stimFraction >= 0.90 then
            stage = "peak"
        elseif stimFraction >= 0.30 then
            stage = "decay"
        else
            stage = "tail"
        end
    end

    local minutesSinceLastDose = newestDose and newestDose.doseMinute and (nowMinutes - newestDose.doseMinute) or nil
    local timeToTailOnset = nil
    if newestDose and stimFraction >= 0.30 and rawStimLoad >= negligible then
        local minutesPastPeak = math.max(0, (nowMinutes - newestDose.doseMinute) - onsetMin)
        local totalDecayToThreshold = halfLifeMin * (math.log(1 / 0.30) / math.log(2))
        timeToTailOnset = math.max(0, totalDecayToThreshold - minutesPastPeak)
    end

    return {
        rawStimLoad = rawStimLoad,
        maskLoad = maskLoad,
        maxCaffeine = maxCaffeine,
        maskStrength = maskStrength,
        stimFraction = stimFraction,
        hiddenFatigue = hiddenFatigue,
        totalStress = totalStress,
        caffeineStress = tonumber(state.caffeineStressCurrent) or 0,
        caffeineStressTarget = tonumber(state.caffeineStressTarget) or 0,
        sleepDisruption = math.max(tonumber(state.sleepDisruptionScore) or 0, tonumber(state.lastSleepDisruptionScore) or 0),
        sleepRecoveryPenaltyFraction = sleepDebug and sleepDebug.activePenaltyFraction
            or tonumber(state.lastSleepRecoveryPenaltyFraction)
            or tonumber(state.sleepRecoveryPenaltyFraction)
            or 0,
        projectedSleepRecoveryPenaltyFraction = sleepDebug and sleepDebug.projectedPenaltyFraction
            or (type(Runtime.computeSleepRecoveryPenaltyFraction) == "function"
                and Runtime.computeSleepRecoveryPenaltyFraction(rawStimLoad, options))
            or 0,
        sleepRecoveryFatigue = sleepDebug and sleepDebug.lastRecoveryFatigue
            or tonumber(state.lastSleepRecoveryFatigue)
            or 0,
        displayedFatigue = displayedFatigue,
        realFatigue = realFatigue,
        sleeping = Runtime.isPlayerAsleep(playerObj),
        sleepSessionMinutes = math.max(0, nowMinutes - (tonumber(state.sleepStartMinute) or nowMinutes)),
        stage = stage,
        doseCount = #(state.doses or {}),
        minutesSinceLastDose = minutesSinceLastDose,
        timeToTailOnset = timeToTailOnset,
        onsetMinutes = onsetMin,
        halfLifeMinutes = halfLifeMin,
        profileKey = newestProfileKey,
        updatedMinute = nowMinutes,
    }
end

local function sendSnapshot(playerObj, reason)
    if type(sendServerCommand) ~= "function" then
        return
    end
    local snapshot = buildSnapshot(playerObj)
    if type(snapshot) ~= "table" then
        return
    end
    snapshot.reason = tostring(reason or "server")
    local ok, err = pcall(sendServerCommand, playerObj, tostring(MP.NET_MODULE), tostring(MP.SNAPSHOT_COMMAND), snapshot)
    if not ok then
        log("snapshot send failed err=" .. tostring(err))
    end
end

local function resetPlayerState(playerObj)
    local nowMinutes = Runtime.getWorldAgeMinutes()
    local state = Runtime.ensureStateForPlayer(playerObj, nowMinutes)
    if not state then
        return false
    end
    local restored = Runtime.getFatigue(playerObj) or tonumber(state.realFatigue) or 0
    Runtime.clearAppliedCaffeineStress(playerObj, state)
    Runtime.resetState(state, restored)
    Runtime.setFatigue(playerObj, restored)
    return true
end

local function registerOnEatCallbacks()
    local sm = ScriptManager and ScriptManager.instance
    local ItemDefs = CaffeineMakesSense.ItemDefs or {}
    if not sm or type(ItemDefs) ~= "table" then
        return
    end
    local count = 0
    for fullType, _ in pairs(ItemDefs.CAFFEINE_ITEMS or {}) do
        local item = sm:getItem(fullType)
        if item and type(item.DoParam) == "function" then
            local ok = pcall(item.DoParam, item, "OnEat = CMS_OnEatCaffeine")
            if ok then
                count = count + 1
            end
        end
    end
    for itemType, _ in pairs(ItemDefs.CAFFEINE_PILLS or {}) do
        local item = sm:getItem("Base." .. itemType)
        if item and type(item.DoParam) == "function" then
            local ok = pcall(item.DoParam, item, "OnEat = CMS_OnEatCaffeine")
            if ok then
                count = count + 1
            end
        end
    end
    log(string.format("registered OnEat callback on %d items", count))
end

local function onClientCommand(module, command, playerObj, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    local ok, err = pcall(function()
        if tostring(command) == tostring(MP.REQUEST_SNAPSHOT_COMMAND) then
            sendSnapshot(playerObj, args and args.reason or "request")
            return
        end
        if tostring(command) == tostring(MP.RESET_COMMAND) then
            if resetPlayerState(playerObj) then
                log(string.format("reset from client: player=%s",
                    tostring(Runtime.safeCall(playerObj, "getUsername") or "unknown")))
                sendSnapshot(playerObj, "reset")
            end
            return
        end
        if tostring(command) ~= tostring(MP.CAFFEINE_DOSE_COMMAND) then
            return
        end
        local nowMinutes = tonumber(args and args.minute) or Runtime.getWorldAgeMinutes()
        local state = Runtime.ensureStateForPlayer(playerObj, nowMinutes)
        if not state then
            return
        end

        local doseLevel = tonumber(args and args.dose_level) or 0
        if doseLevel <= 0 then
            return
        end

        local options = Runtime.getOptions()
        local maxCaffeine = tonumber(options.MaxCaffeineLevel) or 3.0
        local current = Runtime.getEffectiveCaffeine(state, nowMinutes, options)
        if current + doseLevel > maxCaffeine then
            doseLevel = math.max(0, maxCaffeine - current)
        end
        if doseLevel <= 0.001 then
            return
        end

        Runtime.addDose(state, doseLevel, nowMinutes, args and args.profile_key, args and args.category)
        log(string.format("dose from client: player=%s dose=%.2f category=%s profile=%s",
            tostring(Runtime.safeCall(playerObj, "getUsername") or "unknown"),
            doseLevel,
            tostring(args and args.category or "unknown"),
            tostring(args and args.profile_key or "unknown")))
        sendSnapshot(playerObj, "client_dose")
    end)
    if not ok then
        log("[ERROR] onClientCommand: " .. tostring(err))
    end
end

local function onEveryOneMinute()
    local onlinePlayers = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    local count = tonumber(onlinePlayers and Runtime.safeCall(onlinePlayers, "size")) or 0
    for i = 0, count - 1 do
        local playerObj = Runtime.safeCall(onlinePlayers, "get", i)
        if playerObj then
            local ok, err = pcall(Runtime.tickPlayer, playerObj)
            if not ok then
                log("[ERROR] tickPlayer: " .. tostring(err))
            else
                sendSnapshot(playerObj, "minute")
            end
        end
    end
end

local function registerEvents()
    if CaffeineMakesSense._mpServerRegistered then
        return
    end
    CaffeineMakesSense._mpServerRegistered = true

    registerOnEatCallbacks()
    if CaffeineMakesSense.Hooks and type(CaffeineMakesSense.Hooks.wrapDrinkFluidAction) == "function" then
        CaffeineMakesSense.Hooks.wrapDrinkFluidAction()
    end
    if CaffeineMakesSense.Hooks and type(CaffeineMakesSense.Hooks.wrapEatFoodAction) == "function" then
        CaffeineMakesSense.Hooks.wrapEatFoodAction()
    end

    if Events and Events.OnClientCommand and type(Events.OnClientCommand.Add) == "function" then
        Events.OnClientCommand.Add(onClientCommand)
        log("OnClientCommand handler registered")
    end
    if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(onEveryOneMinute)
        log("EveryOneMinute tick registered")
    end
end

registerEvents()
log(string.format("[BOOT] version=%s", tostring(MP.SCRIPT_VERSION or "0.1.0")))
