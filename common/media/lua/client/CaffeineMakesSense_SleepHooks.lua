CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.SleepHooks = CaffeineMakesSense.SleepHooks or {}

require "CaffeineMakesSense_Runtime"
require "CaffeineMakesSense_SleepPlanner"

local SleepHooks = CaffeineMakesSense.SleepHooks
local Runtime = CaffeineMakesSense.Runtime or {}
local Planner = CaffeineMakesSense.SleepPlanner or {}

local function log(msg)
    print("[CaffeineMakesSense] " .. tostring(msg))
end

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

local function isMultiplayerSession()
    return (type(isClient) == "function" and isClient() == true)
        or (type(isServer) == "function" and isServer() == true)
end

local function getCompat()
    local compat = CaffeineMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" then
        return nil
    end
    if type(compat.getCallback) ~= "function" or type(compat.computePlannerExtraHours) ~= "function" then
        return nil
    end
    return compat
end

local function getPlayerFromIndex(playerIndex)
    if type(getSpecificPlayer) == "function" then
        local ok, playerObj = pcall(getSpecificPlayer, playerIndex)
        if ok and playerObj then
            return playerObj
        end
    end
    if type(getPlayer) == "function" then
        local ok, playerObj = pcall(getPlayer)
        if ok and playerObj then
            return playerObj
        end
    end
    return nil
end

local function stringContains(value, needle)
    local text = tostring(value or "")
    if type(text.contains) == "function" then
        return text:contains(needle)
    end
    return string.find(text, needle, 1, true) ~= nil
end

local function hasTrait(playerObj, enumKey, legacyKey)
    if not playerObj then
        return false
    end
    if CharacterTrait and CharacterTrait[enumKey] then
        return safeCall(playerObj, "hasTrait", CharacterTrait[enumKey]) == true
    end
    return safeCall(playerObj, "hasTrait", legacyKey) == true or safeCall(playerObj, "HasTrait", legacyKey) == true
end

local function collectTraitFlags(playerObj)
    return {
        insomniac = hasTrait(playerObj, "INSOMNIAC", "Insomniac"),
        needs_less_sleep = hasTrait(playerObj, "NEEDS_LESS_SLEEP", "NeedsLessSleep"),
        needs_more_sleep = hasTrait(playerObj, "NEEDS_MORE_SLEEP", "NeedsMoreSleep"),
    }
end

local function getPlannerFatigues(playerObj)
    if not playerObj then
        return nil, nil
    end

    if type(isClient) == "function" and isClient() == true then
        local MPClient = CaffeineMakesSense.MPClient
        if type(MPClient) == "table" then
            if type(MPClient.requestSnapshot) == "function" then
                pcall(MPClient.requestSnapshot, "sleep_planner", false)
            end
            if type(MPClient.getSnapshot) == "function" then
                local snapshot = MPClient.getSnapshot()
                local displayedFatigue = tonumber(snapshot and snapshot.displayedFatigue)
                local realFatigue = tonumber(snapshot and snapshot.realFatigue)
                if displayedFatigue ~= nil or realFatigue ~= nil then
                    return displayedFatigue or realFatigue, realFatigue or displayedFatigue
                end
            end
        end
    end

    local displayedFatigue = type(Runtime.getFatigue) == "function" and tonumber(Runtime.getFatigue(playerObj)) or nil
    local nowMinutes = type(Runtime.getWorldAgeMinutes) == "function" and Runtime.getWorldAgeMinutes() or nil
    local state = type(Runtime.ensureStateForPlayer) == "function" and Runtime.ensureStateForPlayer(playerObj, nowMinutes) or nil
    local realFatigue = tonumber(state and state.realFatigue) or displayedFatigue
    displayedFatigue = displayedFatigue or tonumber(state and state.lastSetFatigue) or realFatigue

    return displayedFatigue, realFatigue
end

local function getBedType(playerObj, bed)
    if type(ISWorldObjectContextMenu) == "table" and type(ISWorldObjectContextMenu.getBedQuality) == "function" and playerObj and bed then
        local ok, bedType = pcall(ISWorldObjectContextMenu.getBedQuality, playerObj, bed)
        if ok and bedType ~= nil then
            return tostring(bedType)
        end
    end
    return tostring(safeCall(playerObj, "getBedType") or "")
end

local function computeRebasedBaseHours(playerObj, baseHours, plannerKind, bed)
    local base = tonumber(baseHours) or 0
    if base <= 0 then
        return 0
    end

    local displayedFatigue, realFatigue = getPlannerFatigues(playerObj)
    if displayedFatigue == nil or realFatigue == nil or realFatigue <= (displayedFatigue + 0.001) then
        return base
    end

    local delta = 0
    if plannerKind == "dialog" and type(Planner.computeDialogRebaseDelta) == "function" then
        delta = tonumber(Planner.computeDialogRebaseDelta(displayedFatigue, realFatigue)) or 0
    elseif plannerKind == "auto" and type(Planner.computeAutoRebaseDelta) == "function" then
        delta = tonumber(Planner.computeAutoRebaseDelta(
            displayedFatigue,
            realFatigue,
            getBedType(playerObj, bed),
            collectTraitFlags(playerObj)
        )) or 0
    end

    return base + math.max(0, delta)
end

local function collectPenaltyFractions(playerObj, baseHours)
    local compat = getCompat()
    if not compat then
        return nil, {}
    end

    local penalties = {}
    local callbacks = {
        compat:getCallback("CaffeineMakesSense", "estimateSleepPlannerPenalty"),
        compat:getCallback("ArmorMakesSense", "estimateSleepPlannerPenalty"),
    }

    for i = 1, #callbacks do
        local callback = callbacks[i]
        if type(callback) == "function" then
            local ok, result = pcall(callback, playerObj, { baseHours = baseHours })
            if ok and type(result) == "table" then
                local penalty = tonumber(result.penaltyFraction) or 0
                if penalty > 0 then
                    penalties[#penalties + 1] = penalty
                end
            end
        end
    end

    return compat, penalties
end

local function computeAdjustedHours(playerObj, baseHours, plannerKind, bed)
    local rebasedHours = computeRebasedBaseHours(playerObj, baseHours, plannerKind, bed)
    local compat, penalties = collectPenaltyFractions(playerObj, rebasedHours)
    if not compat or #penalties == 0 then
        return rebasedHours
    end

    local combinedPenalty = compat.combinePenaltyFractions(penalties)
    local extraHours = compat.computePlannerExtraHours(rebasedHours, combinedPenalty)
    return rebasedHours + extraHours
end

local function wrapSleepDialog()
    if CaffeineMakesSense._sleepDialogPlannerWrapped then
        return
    end

    pcall(require, "ISUI/ISSleepDialog")
    if type(ISSleepDialog) ~= "table" or type(ISSleepDialog.initialise) ~= "function" then
        return
    end

    local originalInitialise = ISSleepDialog.initialise
    ISSleepDialog.initialise = function(self)
        originalInitialise(self)

        local playerObj = self and self.player or nil
        local spinBox = self and self.spinBox or nil
        local baseHours = tonumber(spinBox and spinBox.selected) or nil
        if not playerObj or not spinBox or baseHours == nil or baseHours <= 0 then
            return
        end

        local adjustedHours = computeAdjustedHours(playerObj, baseHours, "dialog")
        local roundedHours = math.max(baseHours, math.floor(adjustedHours + 0.5))
        for hour = baseHours + 1, roundedHours do
            spinBox:addOption(getText("IGUI_Sleep_NHours", hour))
        end
        spinBox.selected = roundedHours
    end

    CaffeineMakesSense._sleepDialogPlannerWrapped = true
end

local function wrapAutoSleep()
    if CaffeineMakesSense._autoSleepPlannerWrapped then
        return
    end

    pcall(require, "ISUI/ISWorldObjectContextMenu")
    if type(ISWorldObjectContextMenu) ~= "table" or type(ISWorldObjectContextMenu.onSleepWalkToComplete) ~= "function" then
        return
    end

    ISWorldObjectContextMenu.onSleepWalkToComplete = function(playerIndex, bed)
        local playerObj = getPlayerFromIndex(playerIndex)
        if not playerObj then
            return
        end

        local stats = type(playerObj.getStats) == "function" and playerObj:getStats() or nil
        local moodles = type(playerObj.getMoodles) == "function" and playerObj:getMoodles() or nil
        local isZombies = stats and (
            (tonumber(stats:getNumVisibleZombies()) or 0) > 0
            or (tonumber(stats:getNumChasingZombies()) or 0) > 0
            or (tonumber(stats:getNumVeryCloseZombies()) or 0) > 0
        ) or false
        if isZombies then
            HaloTextHelper.addBadText(playerObj, getText("IGUI_Sleep_NotSafe"))
            return
        end

        if (tonumber(playerObj:getSleepingTabletEffect()) or 0) < 2000 then
            local fatigue = stats and stats:get(CharacterStat.FATIGUE) or 0
            if moodles and moodles:getMoodleLevel(MoodleType.PAIN) >= 2 and fatigue <= 0.85 then
                HaloTextHelper.addBadText(playerObj, getText("ContextMenu_PainNoSleep"))
                return
            end
            if moodles and moodles:getMoodleLevel(MoodleType.PANIC) >= 1 then
                HaloTextHelper.addBadText(playerObj, getText("ContextMenu_PanicNoSleep"))
                return
            end
        end

        if playerObj:getVariableBoolean("ExerciseEnded") == false then
            return
        end

        ISTimedActionQueue.clear(playerObj)

        local fatigue = tonumber(stats and stats:get(CharacterStat.FATIGUE)) or 0
        local sleepFor = ZombRand(fatigue * 10, fatigue * 13) + 1
        local bedType = ISWorldObjectContextMenu.getBedQuality(playerObj, bed)
        if bedType == "goodBed" or stringContains(bedType, "goodBedPillow") then
            sleepFor = sleepFor - 1
        end
        if bedType == "badBed" or stringContains(bedType, "badBedPillow") then
            sleepFor = sleepFor + 1
        end
        if bedType == "floor" or stringContains(bedType, "floorPillow") then
            sleepFor = sleepFor * 0.7
        end
        if playerObj:hasTrait(CharacterTrait.INSOMNIAC) then
            sleepFor = sleepFor * 0.5
        end
        if playerObj:hasTrait(CharacterTrait.NEEDS_LESS_SLEEP) then
            sleepFor = sleepFor * 0.75
        end
        if playerObj:hasTrait(CharacterTrait.NEEDS_MORE_SLEEP) then
            sleepFor = sleepFor * 1.18
        end
        if sleepFor > 16 then
            sleepFor = 16
        end
        if sleepFor < 3 then
            sleepFor = 3
        end

        sleepFor = computeAdjustedHours(playerObj, sleepFor, "auto", bed)

        local gameTime = GameTime.getInstance()
        local sleepHours = sleepFor + gameTime:getTimeOfDay()
        if sleepHours >= 24 then
            sleepHours = sleepHours - 24
        end

        playerObj:setBed(bed)
        playerObj:setBedType(bedType)
        playerObj:setForceWakeUpTime(tonumber(sleepHours))
        playerObj:setAsleepTime(0.0)
        playerObj:setAsleep(true)

        if playerObj:getVehicle() then
            playerObj:playSound("VehicleGoToSleep")
        end

        if isClient() and getServerOptions():getBoolean("SleepAllowed") then
            UIManager.setFadeBeforeUI(playerIndex, true)
            UIManager.FadeOut(playerIndex, 1)
            if playerObj:getVehicle() then
                sendClientCommand(playerObj, "player", "onVehicleSleep", { id = playerObj:getOnlineID(), isAsleep = true })
            end
            return
        end

        getSleepingEvent():setPlayerFallAsleep(playerObj, sleepFor)
        UIManager.setFadeBeforeUI(playerObj:getPlayerNum(), true)
        UIManager.FadeOut(playerObj:getPlayerNum(), 1)

        if IsoPlayer.allPlayersAsleep() then
            UIManager.getSpeedControls():SetCurrentGameSpeed(3)
            save(true)
        end
    end

    CaffeineMakesSense._autoSleepPlannerWrapped = true
end

function SleepHooks.wrapSleepPlanning()
    if isMultiplayerSession() then
        return
    end
    wrapSleepDialog()
    wrapAutoSleep()
    if CaffeineMakesSense._sleepPlannerHooksLogged ~= true then
        CaffeineMakesSense._sleepPlannerHooksLogged = true
        log("wrapped sleep planner hooks")
    end
end

return SleepHooks
