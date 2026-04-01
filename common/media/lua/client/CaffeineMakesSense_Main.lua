CaffeineMakesSense = CaffeineMakesSense or {}

require "CaffeineMakesSense_Config"
pcall(require, "CaffeineMakesSense_MPCompat")
pcall(require, "CaffeineMakesSense_Compat")
pcall(require, "CaffeineMakesSense_ItemDefs")
require "CaffeineMakesSense_Pharma"
require "CaffeineMakesSense_Boot"
require "CaffeineMakesSense_State"
require "CaffeineMakesSense_Tick"
require "CaffeineMakesSense_Hooks"
require "CaffeineMakesSense_SleepHooks"
require "CaffeineMakesSense_HealthPanelHook"
pcall(require, "CaffeineMakesSense_MPClientRuntime")

local State = CaffeineMakesSense.State
local Tick = CaffeineMakesSense.Tick
local Hooks = CaffeineMakesSense.Hooks
local SleepHooks = CaffeineMakesSense.SleepHooks
local HealthPanelHook = CaffeineMakesSense.HealthPanelHook
local MP = CaffeineMakesSense.MP or {}
local ItemDefs = CaffeineMakesSense.ItemDefs or {}
local Runtime = CaffeineMakesSense.Runtime

local runtimeDisabled = false
local bootLogged = false

local TAG = "[CaffeineMakesSense]"
local DEV_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD6 or nil

local function log(msg)
    print(TAG .. " " .. tostring(msg))
end

local function logError(where, err)
    print(TAG .. "[ERROR] " .. tostring(where) .. ": " .. tostring(err))
end

local function tryLoadDevPanel()
    if CaffeineMakesSense.DevPanel then
        return true
    end
    local ok, result = pcall(require, "dev/CaffeineMakesSense_DevPanel")
    if ok then
        return true
    end
    local err = tostring(result)
    if string.find(string.lower(err), "not found", 1, true) then
        return false
    end
    logError("require DevPanel", err)
    return false
end

local function getLocalPlayer()
    if type(getPlayer) ~= "function" then
        return nil
    end
    local ok, player = pcall(getPlayer)
    if not ok then
        return nil
    end
    return player
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

-- Register OnEat callbacks on caffeine items at boot.
-- This sets the Lua callback name so PZ calls CMS_OnEatCaffeine when the item is consumed.
local function registerOnEatCallbacks()
    local sm = ScriptManager and ScriptManager.instance
    if not sm then
        return
    end
    local count = 0
    for fullType, def in pairs(ItemDefs.CAFFEINE_ITEMS) do
        local item = sm:getItem(fullType)
        if item and type(item.DoParam) == "function" then
            local ok = pcall(item.DoParam, item, "OnEat = CMS_OnEatCaffeine")
            if ok then
                count = count + 1
            end
        end
    end
    -- Pills (drainable items) also support OnEat -- JustTookPill calls it after
    -- applying the pill effect, so our callback fires post-consumption.
    for itemType, def in pairs(ItemDefs.CAFFEINE_PILLS) do
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

local function onGameBoot()
    local ok, err = pcall(function()
        registerOnEatCallbacks()
        Hooks.wrapDrinkFluidAction()
        Hooks.wrapEatFoodAction()
        if SleepHooks and type(SleepHooks.wrapSleepPlanning) == "function" then
            SleepHooks.wrapSleepPlanning()
        end
        if HealthPanelHook and type(HealthPanelHook.install) == "function" then
            HealthPanelHook.install()
        end
        tryLoadDevPanel()
    end)
    if not ok then
        logError("onGameBoot/registerOnEatCallbacks", err)
    end
    if DEV_PANEL_HOTKEY and CaffeineMakesSense.DevPanel then
        log("dev panel hotkey available: Numpad 6")
    end
end

local function onEveryOneMinute()
    if runtimeDisabled then
        return
    end
    local ok, err = pcall(function()
        local player = getLocalPlayer()
        if not player then
            return
        end
        local DevPanel = CaffeineMakesSense.DevPanel
        local isRec = DevPanel and DevPanel.isRecording and DevPanel.isRecording()
        if isMultiplayer() then
            if isRec then
                DevPanel.sampleTick()
            end
            return
        end
        if isRec then
            DevPanel.capturePreTick()
        end

        Tick.tickPlayer(player)

        if isRec then
            DevPanel.sampleTick()
        end
    end)
    if not ok then
        runtimeDisabled = true
        logError("onEveryOneMinute", err)
    end
end

local function onCreatePlayer(playerIndex, playerObj)
    local ok, err = pcall(function()
        local player = playerObj or getLocalPlayer()
        if not player then
            return
        end
        local state = State.ensureState(player)
        if not bootLogged and state then
            bootLogged = true
            log(string.format("[RUNTIME] version=%s doses=%d mp=%s",
                tostring(MP.SCRIPT_VERSION or "0.1.0"),
                #(state.doses or {}),
                tostring(isMultiplayer())))
        end
    end)
    if not ok then
        logError("onCreatePlayer", err)
    end
end

local function onPlayerUpdate(playerObj)
    if runtimeDisabled then return end
    local ok, err = pcall(function()
        local DevPanel = CaffeineMakesSense.DevPanel
        if DevPanel and DevPanel.isRecording and DevPanel.isRecording() then
            DevPanel.sampleHighFreq()
        end
    end)
    if not ok then
        logError("onPlayerUpdate", err)
    end
end

local function onSleepingTick(playerIndex, hourOfDay)
    if runtimeDisabled then return end
    local ok, err = pcall(function()
        if isMultiplayer() then
            return
        end
        local player = getLocalPlayer()
        if not player or not Runtime or type(Runtime.onSleepingTick) ~= "function" then
            return
        end
        Runtime.onSleepingTick(player)
    end)
    if not ok then
        logError("onSleepingTick", err)
    end
end

local function canUseDevPanel()
    if not tryLoadDevPanel() then
        return false
    end
    if type(isDebugEnabled) == "function" and isDebugEnabled() then
        return true
    end
    local core = type(getCore) == "function" and getCore() or nil
    if core and type(core.getDebug) == "function" then
        local ok, debugEnabled = pcall(core.getDebug, core)
        if ok and debugEnabled then
            return true
        end
    end
    if type(isClient) == "function" and isClient() and type(getAccessLevel) == "function" then
        local ok, accessLevel = pcall(getAccessLevel)
        if ok and (accessLevel == "admin" or accessLevel == "moderator") then
            return true
        end
    end
    return false
end

local function toggleDevPanel()
    tryLoadDevPanel()
    local DevPanel = CaffeineMakesSense.DevPanel
    if not DevPanel or type(DevPanel.toggle) ~= "function" then
        log("dev panel unavailable")
        return
    end
    local ok, err = pcall(DevPanel.toggle)
    if not ok then
        logError("toggleDevPanel", err)
    end
end

local function onKeyPressed(key)
    if runtimeDisabled or not DEV_PANEL_HOTKEY or key ~= DEV_PANEL_HOTKEY then
        return
    end
    if not canUseDevPanel() then
        return
    end
    toggleDevPanel()
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if not canUseDevPanel() then
        return
    end
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.Test then
        return true
    end
    context:addDebugOption("CMS Dev Panel", nil, toggleDevPanel)
end

-- Register events.
if Events then
    if Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
        Events.OnGameBoot.Add(onGameBoot)
    end
    if Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(onEveryOneMinute)
    end
    if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
        Events.OnCreatePlayer.Add(onCreatePlayer)
    end
    if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(onPlayerUpdate)
    end
    if Events.OnSleepingTick and type(Events.OnSleepingTick.Add) == "function" then
        Events.OnSleepingTick.Add(onSleepingTick)
    end
    if Events.OnKeyPressed and type(Events.OnKeyPressed.Add) == "function" then
        Events.OnKeyPressed.Add(onKeyPressed)
    end
    if Events.OnFillWorldObjectContextMenu and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
        Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
    end
else
    log("Events table not available; runtime events not registered")
end
