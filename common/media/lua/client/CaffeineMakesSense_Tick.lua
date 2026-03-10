CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.Tick = CaffeineMakesSense.Tick or {}

require "CaffeineMakesSense_Runtime"

local Tick = CaffeineMakesSense.Tick
local Runtime = CaffeineMakesSense.Runtime

function Tick.tickPlayer(player)
    return Runtime.tickPlayer(player)
end

return Tick
