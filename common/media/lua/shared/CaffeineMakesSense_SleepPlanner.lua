CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.SleepPlanner = CaffeineMakesSense.SleepPlanner or {}

local Planner = CaffeineMakesSense.SleepPlanner

local function clamp(value, minimum, maximum)
    local v = tonumber(value) or minimum
    if v < minimum then
        return minimum
    end
    if v > maximum then
        return maximum
    end
    return v
end

local function contains(text, needle)
    return type(text) == "string" and string.find(text, needle, 1, true) ~= nil
end

local function isTruthy(value)
    return value == true
end

local function applyAutoSleepModifiers(hours, bedType, traits)
    local sleepFor = tonumber(hours) or 0
    local bed = tostring(bedType or "")
    local flags = type(traits) == "table" and traits or {}

    if bed == "goodBed" or contains(bed, "goodBedPillow") then
        sleepFor = sleepFor - 1
    end
    if bed == "badBed" or contains(bed, "badBedPillow") then
        sleepFor = sleepFor + 1
    end
    if bed == "floor" or contains(bed, "floorPillow") then
        sleepFor = sleepFor * 0.7
    end
    if isTruthy(flags.insomniac) then
        sleepFor = sleepFor * 0.5
    end
    if isTruthy(flags.needs_less_sleep) then
        sleepFor = sleepFor * 0.75
    end
    if isTruthy(flags.needs_more_sleep) then
        sleepFor = sleepFor * 1.18
    end

    return clamp(sleepFor, 3, 16)
end

function Planner.computeDialogHoursFromFatigue(fatigue)
    local value = clamp(fatigue or 0, 0, 1)
    local hours = 7
    if value > 0.3 then
        hours = hours + (5 * ((value - 0.3) / 0.7))
    end
    return math.ceil(hours)
end

function Planner.computeAutoExpectedHoursFromFatigue(fatigue, bedType, traits)
    local value = clamp(fatigue or 0, 0, 1)
    local midpointHours = 1 + (11.5 * value)
    return applyAutoSleepModifiers(midpointHours, bedType, traits)
end

function Planner.computeDialogRebaseDelta(displayedFatigue, realFatigue)
    local displayedHours = Planner.computeDialogHoursFromFatigue(displayedFatigue)
    local realHours = Planner.computeDialogHoursFromFatigue(realFatigue)
    return math.max(0, realHours - displayedHours)
end

function Planner.computeAutoRebaseDelta(displayedFatigue, realFatigue, bedType, traits)
    local displayedHours = Planner.computeAutoExpectedHoursFromFatigue(displayedFatigue, bedType, traits)
    local realHours = Planner.computeAutoExpectedHoursFromFatigue(realFatigue, bedType, traits)
    return math.max(0, realHours - displayedHours)
end

function Planner.computePlannerPenaltyFraction(_recoveryPenaltyFraction)
    -- CMS sleep cost should make sleep less restorative, not ask the planner to
    -- bluntly schedule extra hours on top of the real-fatigue baseline.
    return 0
end

return Planner
