CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.MPClient = CaffeineMakesSense.MPClient or {}

local okMpCompat, mpCompatOrErr = pcall(require, "CaffeineMakesSense_MPCompat")
if not okMpCompat then
    print("[CaffeineMakesSense][MP][CLIENT][ERROR] MPCompat require failed: " .. tostring(mpCompatOrErr))
    return
end

local MP = (type(mpCompatOrErr) == "table" and mpCompatOrErr) or CaffeineMakesSense.MP
if type(MP) ~= "table" then
    print("[CaffeineMakesSense][MP][CLIENT][ERROR] MP compat constants unavailable")
    return
end

local MPClient = CaffeineMakesSense.MPClient
local latestSnapshot = nil
local lastRequestWallSecond = 0

local function getWallClockSeconds()
    if type(getTimestampMs) == "function" then
        local nowMs = tonumber(getTimestampMs())
        if nowMs ~= nil then
            return math.floor(nowMs / 1000)
        end
    end
    if type(getTimestamp) == "function" then
        local nowSecond = tonumber(getTimestamp())
        if nowSecond ~= nil then
            return math.floor(nowSecond)
        end
    end
    return 0
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

function MPClient.getSnapshot()
    return latestSnapshot
end

function MPClient.clearSnapshot()
    latestSnapshot = nil
end

function MPClient.requestSnapshot(reason, force)
    if type(isClient) ~= "function" or not isClient() then
        return false
    end
    if type(sendClientCommand) ~= "function" then
        return false
    end
    local nowSecond = getWallClockSeconds()
    if (not force) and (nowSecond - lastRequestWallSecond) < 1 then
        return false
    end
    lastRequestWallSecond = nowSecond
    local args = {
        reason = tostring(reason or "panel"),
        world_minute = math.floor(getWorldAgeMinutes()),
    }
    local ok = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REQUEST_SNAPSHOT_COMMAND), args)
    return ok
end

function MPClient.requestReset(reason)
    if type(isClient) ~= "function" or not isClient() then
        return false
    end
    if type(sendClientCommand) ~= "function" then
        return false
    end
    latestSnapshot = nil
    local args = {
        reason = tostring(reason or "panel_reset"),
        world_minute = math.floor(getWorldAgeMinutes()),
    }
    return pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.RESET_COMMAND), args)
end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.SNAPSHOT_COMMAND) then
        return
    end
    if type(args) ~= "table" then
        return
    end
    latestSnapshot = {
        rawStimLoad = tonumber(args.rawStimLoad) or 0,
        maskLoad = tonumber(args.maskLoad) or 0,
        maxCaffeine = tonumber(args.maxCaffeine) or 4.0,
        maskStrength = tonumber(args.maskStrength) or 0,
        stimFraction = tonumber(args.stimFraction) or 0,
        hiddenFatigue = tonumber(args.hiddenFatigue) or 0,
        totalStress = tonumber(args.totalStress) or 0,
        caffeineStress = tonumber(args.caffeineStress) or 0,
        caffeineStressTarget = tonumber(args.caffeineStressTarget) or 0,
        sleepDisruption = tonumber(args.sleepDisruption) or 0,
        sleepRecoveryPenaltyFraction = tonumber(args.sleepRecoveryPenaltyFraction) or 0,
        projectedSleepRecoveryPenaltyFraction = tonumber(args.projectedSleepRecoveryPenaltyFraction),
        sleepRecoveryFatigue = tonumber(args.sleepRecoveryFatigue) or 0,
        displayedFatigue = tonumber(args.displayedFatigue) or 0,
        realFatigue = tonumber(args.realFatigue) or 0,
        sleeping = args.sleeping == true,
        sleepSessionMinutes = tonumber(args.sleepSessionMinutes) or 0,
        stage = tostring(args.stage or "inactive"),
        doseCount = tonumber(args.doseCount) or 0,
        minutesSinceLastDose = tonumber(args.minutesSinceLastDose),
        timeToTailOnset = tonumber(args.timeToTailOnset),
        onsetMinutes = tonumber(args.onsetMinutes) or 0,
        halfLifeMinutes = tonumber(args.halfLifeMinutes) or 0,
        profileKey = tostring(args.profileKey or "coffee"),
        updatedMinute = tonumber(args.updatedMinute) or getWorldAgeMinutes(),
        reason = tostring(args.reason or "server"),
        source = "mp_server",
    }
end

if Events and Events.OnServerCommand and type(Events.OnServerCommand.Add) == "function" then
    Events.OnServerCommand.Add(onServerCommand)
end

return MPClient
