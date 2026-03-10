CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.Hooks = CaffeineMakesSense.Hooks or {}

local Hooks = CaffeineMakesSense.Hooks

local function log(msg)
    print("[CaffeineMakesSense] " .. tostring(msg))
end

local function getWorldAgeMinutes()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if not gameTime then
        return 0
    end
    local ok, hours = pcall(gameTime.getWorldAgeHours, gameTime)
    if not ok then
        return 0
    end
    return (tonumber(hours) or 0) * 60
end

local function isMultiplayer()
    if type(isClient) == "function" and isClient() then
        return true
    end
    if type(isServer) == "function" and isServer() then
        return true
    end
    return false
end

local function isServerRuntime()
    return type(isServer) == "function" and isServer() == true
end

local function getItemFullType(item)
    if not item or type(item.getFullType) ~= "function" then
        return nil
    end
    local ok, fullType = pcall(item.getFullType, item)
    if not ok or fullType == nil then
        return nil
    end
    return tostring(fullType)
end

local function getItemType(item)
    if not item or type(item.getType) ~= "function" then
        return nil
    end
    local ok, itemType = pcall(item.getType, item)
    if not ok or itemType == nil then
        return nil
    end
    return tostring(itemType)
end

local function getDrinkDef(item)
    local ItemDefs = CaffeineMakesSense.ItemDefs
    if not ItemDefs or not item then
        return nil
    end

    local fullType = getItemFullType(item)
    local byFullType = fullType and ItemDefs.CAFFEINE_ITEMS[fullType]
    if byFullType then
        return byFullType
    end

    local fluidContainer = type(item.getFluidContainer) == "function" and item:getFluidContainer() or nil
    local primaryFluid = fluidContainer and type(fluidContainer.getPrimaryFluid) == "function" and fluidContainer:getPrimaryFluid() or nil
    if not primaryFluid then
        return nil
    end

    local fluidName = nil
    if type(primaryFluid.getFluidTypeString) == "function" then
        local ok, value = pcall(primaryFluid.getFluidTypeString, primaryFluid)
        if ok and value ~= nil then
            fluidName = tostring(value)
        end
    end
    if (not fluidName or fluidName == "") and type(primaryFluid.getName) == "function" then
        local ok, value = pcall(primaryFluid.getName, primaryFluid)
        if ok and value ~= nil then
            fluidName = tostring(value)
        end
    end

    return fluidName and ItemDefs.CAFFEINE_FLUIDS[fluidName] or nil
end

local function getCaffeineItemDef(item)
    local ItemDefs = CaffeineMakesSense.ItemDefs
    if not ItemDefs or not item then
        return nil
    end
    local fullType = getItemFullType(item)
    if fullType and ItemDefs.CAFFEINE_ITEMS[fullType] then
        return ItemDefs.CAFFEINE_ITEMS[fullType]
    end
    local itemType = getItemType(item)
    if itemType and ItemDefs.CAFFEINE_PILLS[itemType] then
        return ItemDefs.CAFFEINE_PILLS[itemType]
    end
    return nil
end

local function applyFatigueOffset(player, delta)
    local Runtime = CaffeineMakesSense.Runtime
    if not Runtime or not player or not delta or math.abs(delta) <= 0.000001 then
        return
    end
    local current = Runtime.getFatigue(player)
    if current == nil then
        return
    end
    Runtime.setFatigue(player, current + delta)
end

function Hooks.onCaffeineConsumed(player, doseKey, category, profileKey, percentage)
    local Runtime = CaffeineMakesSense.Runtime
    local State = CaffeineMakesSense.State
    local state = nil
    local options = nil

    if isServerRuntime() then
        if not Runtime then
            return
        end
        local nowMinutes = getWorldAgeMinutes()
        state = Runtime.ensureStateForPlayer(player, nowMinutes)
        options = Runtime.getOptions()
    else
        if not State then
            return
        end
        state = State.ensureState(player)
        options = State.getOptions()
    end

    if not state or not options then
        return
    end

    local doseLevel = (tonumber(options[doseKey]) or 1.0) * (tonumber(percentage) or 1.0)
    local maxCaffeine = tonumber(options.MaxCaffeineLevel) or 3.0

    local nowMinutes = getWorldAgeMinutes()
    local currentTotal = Runtime and Runtime.getEffectiveCaffeine(state, nowMinutes, options) or 0

    if currentTotal + doseLevel > maxCaffeine then
        doseLevel = math.max(0, maxCaffeine - currentTotal)
    end
    if doseLevel <= 0.001 then
        log(string.format("dose capped: category=%s current=%.2f max=%.2f", tostring(category), currentTotal, maxCaffeine))
        return
    end

    if Runtime and type(Runtime.addDose) == "function" then
        Runtime.addDose(state, doseLevel, nowMinutes, profileKey, category)
    elseif State and type(State.addDose) == "function" then
        State.addDose(state, doseLevel, nowMinutes, profileKey, category)
    else
        return
    end
    log(string.format("dose added: category=%s profile=%s dose=%.2f total=%.2f", tostring(category), tostring(profileKey), doseLevel, currentTotal + doseLevel))

    local DevPanel = CaffeineMakesSense.DevPanel
    if DevPanel and DevPanel.isRecording and DevPanel.isRecording() then
        pcall(DevPanel.sampleEvent, "dose:" .. tostring(category), tostring(profileKey))
    end

    if (not isServerRuntime()) and isMultiplayer() and type(sendClientCommand) == "function" then
        local MP = CaffeineMakesSense.MP
        if MP then
            pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.CAFFEINE_DOSE_COMMAND), {
                dose_key = tostring(doseKey),
                dose_level = doseLevel,
                category = tostring(category),
                profile_key = tostring(profileKey),
                minute = nowMinutes,
            })
        end
    end
end

function CMS_OnEatCaffeine(food, character, percentage)
    local ok, err = pcall(function()
        if not food or not character then
            return
        end

        local ItemDefs = CaffeineMakesSense.ItemDefs
        if not ItemDefs then
            return
        end

        local fullType = getItemFullType(food)
        local def = fullType and ItemDefs.CAFFEINE_ITEMS[fullType]
        if def then
            Hooks.onCaffeineConsumed(character, def.dose, def.category, def.profile, percentage)
            return
        end

        local itemType = getItemType(food)
        local pillDef = itemType and ItemDefs.CAFFEINE_PILLS[itemType]
        if pillDef then
            Hooks.onCaffeineConsumed(character, pillDef.dose, pillDef.category, pillDef.profile, percentage)
        end
    end)
    if not ok then
        log("[ERROR] CMS_OnEatCaffeine: " .. tostring(err))
    end
end

function Hooks.wrapDrinkFluidAction()
    if CaffeineMakesSense._drinkFluidWrapped then
        return
    end

    pcall(require, "TimedActions/ISDrinkFluidAction")
    if type(ISDrinkFluidAction) ~= "table" or type(ISDrinkFluidAction.updateEat) ~= "function" then
        return
    end

    local originalUpdateEat = ISDrinkFluidAction.updateEat
    ISDrinkFluidAction.updateEat = function(self, delta)
        local item = self and self.item or nil
        local character = self and self.character or nil
        local fluidContainer = item and type(item.getFluidContainer) == "function" and item:getFluidContainer() or nil
        local beforeRatio = fluidContainer and type(fluidContainer.getFilledRatio) == "function" and fluidContainer:getFilledRatio() or nil
        local beforeFatigue = character and Runtime and Runtime.getFatigue(character) or nil

        originalUpdateEat(self, delta)

        local afterRatio = fluidContainer and type(fluidContainer.getFilledRatio) == "function" and fluidContainer:getFilledRatio() or nil
        local afterFatigue = character and Runtime and Runtime.getFatigue(character) or nil
        local consumedFraction = nil
        if beforeRatio ~= nil and afterRatio ~= nil then
            consumedFraction = math.max(0, (tonumber(beforeRatio) or 0) - (tonumber(afterRatio) or 0))
        end
        if not consumedFraction or consumedFraction <= 0.0001 then
            return
        end

        local def = getDrinkDef(item)
        if not def then
            return
        end

        if beforeFatigue ~= nil and afterFatigue ~= nil and afterFatigue < beforeFatigue then
            applyFatigueOffset(character, beforeFatigue - afterFatigue)
        end

        Hooks.onCaffeineConsumed(character, def.dose, def.category, def.profile, consumedFraction)
    end

    CaffeineMakesSense._drinkFluidWrapped = true
    log("wrapped ISDrinkFluidAction.updateEat for fluid caffeine dosing")
end

function Hooks.wrapEatFoodAction()
    if CaffeineMakesSense._eatFoodWrapped then
        return
    end

    pcall(require, "TimedActions/ISEatFoodAction")
    if type(ISEatFoodAction) ~= "table" or type(ISEatFoodAction.complete) ~= "function" then
        return
    end

    local originalComplete = ISEatFoodAction.complete
    ISEatFoodAction.complete = function(self)
        local item = self and self.item or nil
        local character = self and self.character or nil
        local def = getCaffeineItemDef(item)
        local beforeFatigue = character and CaffeineMakesSense.Runtime and CaffeineMakesSense.Runtime.getFatigue(character) or nil

        local result = originalComplete(self)

        local afterFatigue = character and CaffeineMakesSense.Runtime and CaffeineMakesSense.Runtime.getFatigue(character) or nil
        if def and beforeFatigue ~= nil and afterFatigue ~= nil and afterFatigue < beforeFatigue then
            applyFatigueOffset(character, beforeFatigue - afterFatigue)
        end

        return result
    end

    CaffeineMakesSense._eatFoodWrapped = true
    log("wrapped ISEatFoodAction.complete for caffeine fatigue reversal")
end

return Hooks
