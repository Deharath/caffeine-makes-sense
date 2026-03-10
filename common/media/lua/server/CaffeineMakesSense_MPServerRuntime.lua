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
pcall(require, "CaffeineMakesSense_Pharma")
pcall(require, "CaffeineMakesSense_Runtime")

local MP = (type(mpCompatOrErr) == "table" and mpCompatOrErr) or CaffeineMakesSense.MP
local Runtime = CaffeineMakesSense.Runtime
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

local function onClientCommand(module, command, playerObj, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    local ok, err = pcall(function()
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
            end
        end
    end
end

local function registerEvents()
    if CaffeineMakesSense._mpServerRegistered then
        return
    end
    CaffeineMakesSense._mpServerRegistered = true

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
