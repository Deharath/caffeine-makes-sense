CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.State = CaffeineMakesSense.State or {}

require "CaffeineMakesSense_Runtime"

local State = CaffeineMakesSense.State
local Runtime = CaffeineMakesSense.Runtime

function State.ensureState(player)
    return Runtime.ensureStateForPlayer(player)
end

function State.addDose(state, doseLevel, nowMinutes, profileKey, category)
    return Runtime.addDose(state, doseLevel, nowMinutes, profileKey, category)
end

function State.getNewestDose(state)
    return Runtime.getNewestDose(state)
end

function State.getDoseProfileKey(dose)
    return Runtime.getDoseProfileKey(dose)
end

function State.getLoadTotals(state, nowMinutes, options)
    return Runtime.getLoadTotals(state, nowMinutes, options)
end

function State.getEffectiveCaffeine(state, nowMinutes, options)
    return Runtime.getEffectiveCaffeine(state, nowMinutes, options)
end

function State.pruneDoses(state, nowMinutes, options)
    return Runtime.pruneDoses(state, nowMinutes, options)
end

function State.getOptions()
    return Runtime.getOptions()
end

return State
