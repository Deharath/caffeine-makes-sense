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

function Hooks.onCaffeineConsumed(player, doseKey, category, profileKey, percentage)
    local State = CaffeineMakesSense.State
    if not State then
        return
    end
    local state = State.ensureState(player)
    if not state then
        return
    end
    local options = State.getOptions()
    local doseLevel = (tonumber(options[doseKey]) or 1.0) * (tonumber(percentage) or 1.0)
    local maxCaffeine = tonumber(options.MaxCaffeineLevel) or 3.0

    local nowMinutes = getWorldAgeMinutes()
    local currentTotal = State.getEffectiveCaffeine(state, nowMinutes, options)

    if currentTotal + doseLevel > maxCaffeine then
        doseLevel = math.max(0, maxCaffeine - currentTotal)
    end
    if doseLevel <= 0.001 then
        log(string.format("dose capped: category=%s current=%.2f max=%.2f", tostring(category), currentTotal, maxCaffeine))
        return
    end

    State.addDose(state, doseLevel, nowMinutes, profileKey, category)
    log(string.format("dose added: category=%s profile=%s dose=%.2f total=%.2f", tostring(category), tostring(profileKey), doseLevel, currentTotal + doseLevel))

    local DevPanel = CaffeineMakesSense.DevPanel
    if DevPanel and DevPanel.isRecording and DevPanel.isRecording() then
        pcall(DevPanel.sampleEvent, "dose:" .. tostring(category), tostring(profileKey))
    end

    if isMultiplayer() and type(sendClientCommand) == "function" then
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
        local fullType = nil
        if type(food.getFullType) == "function" then
            local ok2, ft = pcall(food.getFullType, food)
            if ok2 then fullType = tostring(ft) end
        end

        local ItemDefs = CaffeineMakesSense.ItemDefs
        if not ItemDefs then
            return
        end

        local def = fullType and ItemDefs.CAFFEINE_ITEMS[fullType]
        if def then
            Hooks.onCaffeineConsumed(character, def.dose, def.category, def.profile, percentage)
            return
        end

        local itemType = nil
        if type(food.getType) == "function" then
            local ok2, itemTypeValue = pcall(food.getType, food)
            if ok2 then itemType = tostring(itemTypeValue) end
        end
        local pillDef = itemType and ItemDefs.CAFFEINE_PILLS[itemType]
        if pillDef then
            Hooks.onCaffeineConsumed(character, pillDef.dose, pillDef.category, pillDef.profile, percentage)
        end
    end)
    if not ok then
        log("[ERROR] CMS_OnEatCaffeine: " .. tostring(err))
    end
end

return Hooks
