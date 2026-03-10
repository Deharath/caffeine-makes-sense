CaffeineMakesSense = CaffeineMakesSense or {}

if CaffeineMakesSense._bootDone then
    return
end
CaffeineMakesSense._bootDone = true

require "CaffeineMakesSense_Config"
require "CaffeineMakesSense_ItemDefs"

local ItemDefs = CaffeineMakesSense.ItemDefs

local function log(msg)
    print("[CaffeineMakesSense] " .. tostring(msg))
end

local function safeDoParam(scriptItem, paramStr)
    if not scriptItem or type(scriptItem.DoParam) ~= "function" then
        return false
    end
    local ok, err = pcall(scriptItem.DoParam, scriptItem, paramStr)
    if not ok then
        log("DoParam failed: " .. tostring(err))
        return false
    end
    return true
end

-- Cache original fatigueChange values before zeroing, so we know what vanilla
-- would have applied (useful for reversing fluid consumption).
CaffeineMakesSense._originalFatigueChange = CaffeineMakesSense._originalFatigueChange or {}

local function cacheAndZeroFatigue(scriptItem, fullType)
    if not scriptItem then
        return false
    end
    local getFn = scriptItem.getFatigueChange or scriptItem.getfatigueChange
    if type(getFn) == "function" then
        local ok, val = pcall(getFn, scriptItem)
        if ok and val then
            CaffeineMakesSense._originalFatigueChange[fullType] = tonumber(val) or 0
        end
    end
    return safeDoParam(scriptItem, "fatigueChange = 0")
end

local function applyBootOverrides()
    local sm = ScriptManager and ScriptManager.instance
    if not sm then
        log("ScriptManager not available; boot overrides skipped")
        return
    end

    local changed = 0
    local missing = 0

    -- Zero fatigueChange on known caffeine food items.
    for fullType, _ in pairs(ItemDefs.CAFFEINE_ITEMS) do
        local item = sm:getItem(fullType)
        if item then
            if cacheAndZeroFatigue(item, fullType) then
                changed = changed + 1
            end
        else
            missing = missing + 1
        end
    end

    -- Zero fatigueChange on caffeine pills (drainable items).
    -- Pills go through BodyDamage.JustTookPill() which applies fatigueChange
    -- via stats.set (vitamins) -- we zero it here and handle dosing via OnEat.
    local pillChanged = 0
    for itemType, _ in pairs(ItemDefs.CAFFEINE_PILLS) do
        local item = sm:getItem("Base." .. itemType)
        if item then
            if cacheAndZeroFatigue(item, "Base." .. itemType) then
                pillChanged = pillChanged + 1
            end
        end
    end

    log(string.format("boot: zeroed fatigueChange on %d caffeine items + %d pills (%d missing)", changed, pillChanged, missing))
end

if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(function()
        local ok, err = pcall(applyBootOverrides)
        if not ok then
            log("[ERROR] applyBootOverrides: " .. tostring(err))
        end
        log(string.format("[BOOT] version=%s", tostring(CaffeineMakesSense.MP and CaffeineMakesSense.MP.SCRIPT_VERSION or "0.1.0")))
    end)
else
    log("Events.OnGameBoot.Add unavailable; boot overrides not registered")
end
