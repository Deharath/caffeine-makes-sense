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

local function getTimeOfDay()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if not gameTime then
        return nil
    end
    local ok, value = pcall(gameTime.getTimeOfDay, gameTime)
    if not ok then
        return nil
    end
    return tonumber(value)
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

local function adjustForceWakeTime(playerObj, bed)
    if not playerObj or type(playerObj.isAsleep) ~= "function" or playerObj:isAsleep() ~= true then
        return
    end

    local compat = getCompat()
    local timeOfDay = getTimeOfDay()
    local wakeHour = type(playerObj.getForceWakeUpTime) == "function" and playerObj:getForceWakeUpTime() or nil
    local baseHours = compat and compat.computeHoursUntilWake(timeOfDay, wakeHour) or nil
    if baseHours == nil or baseHours <= 0 then
        return
    end

    local adjustedHours = computeAdjustedHours(playerObj, baseHours, "auto", bed)
    if adjustedHours <= (baseHours + 0.01) then
        return
    end

    local adjustedWakeHour = compat.computeWakeHourFromNow(timeOfDay, adjustedHours)
    if adjustedWakeHour ~= nil and type(playerObj.setForceWakeUpTime) == "function" then
        playerObj:setForceWakeUpTime(adjustedWakeHour)
    end
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

    local originalOnSleepWalkToComplete = ISWorldObjectContextMenu.onSleepWalkToComplete
    ISWorldObjectContextMenu.onSleepWalkToComplete = function(playerIndex, bed)
        originalOnSleepWalkToComplete(playerIndex, bed)
        local playerObj = getPlayerFromIndex(playerIndex)
        if playerObj then
            adjustForceWakeTime(playerObj, bed)
        end
    end

    CaffeineMakesSense._autoSleepPlannerWrapped = true
end

function SleepHooks.wrapSleepPlanning()
    wrapSleepDialog()
    wrapAutoSleep()
    if CaffeineMakesSense._sleepPlannerHooksLogged ~= true then
        CaffeineMakesSense._sleepPlannerHooksLogged = true
        log("wrapped sleep planner hooks")
    end
end

return SleepHooks
