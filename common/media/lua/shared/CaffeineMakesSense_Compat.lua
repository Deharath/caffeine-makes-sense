CaffeineMakesSense = CaffeineMakesSense or {}

local PROTOCOL = "mscompat-v1"

local function clamp(value, minimum, maximum)
    local v = tonumber(value)
    if v == nil then
        return minimum
    end
    if v < minimum then
        return minimum
    end
    if v > maximum then
        return maximum
    end
    return v
end

local function ensureCompatMethods(compat)
    if type(compat) ~= "table" then
        return compat
    end

    compat.combinePenaltyFractions = function(penalties)
        if type(penalties) ~= "table" then
            return 0
        end

        local remaining = 1.0
        for i = 1, #penalties do
            local penalty = clamp(penalties[i], 0, 0.95)
            remaining = remaining * (1.0 - penalty)
        end
        return clamp(1.0 - remaining, 0, 0.95)
    end

    compat.computePlannerExtraHours = function(baseHours, combinedPenalty)
        local base = clamp(baseHours, 0, 16)
        local penalty = clamp(combinedPenalty, 0, 0.95)
        if base <= 0 or penalty <= 0 then
            return 0
        end

        local effectivePenalty = penalty * (0.75 + (0.25 * penalty))
        return clamp(base * effectivePenalty, 0, 2.25)
    end

    compat.computeHoursUntilWake = function(timeOfDay, wakeHour)
        local now = tonumber(timeOfDay)
        local wake = tonumber(wakeHour)
        if now == nil or wake == nil then
            return nil
        end

        local delta = wake - now
        if delta < 0 then
            delta = delta + 24.0
        end
        return delta
    end

    compat.computeWakeHourFromNow = function(timeOfDay, hoursFromNow)
        local now = tonumber(timeOfDay)
        local delta = tonumber(hoursFromNow)
        if now == nil or delta == nil then
            return nil
        end

        local wake = now + delta
        while wake >= 24.0 do
            wake = wake - 24.0
        end
        while wake < 0 do
            wake = wake + 24.0
        end
        return wake
    end

    return compat
end

local function ensureCompat()
    local compat = rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table"
        or compat.protocol ~= PROTOCOL
        or type(compat.registerProvider) ~= "function"
        or type(compat.getCallback) ~= "function"
        or type(compat.hasCapability) ~= "function" then
        compat = {
            protocol = PROTOCOL,
            providers = {},
        }

        function compat:registerProvider(modKey, definition)
            local key = tostring(modKey or "")
            if key == "" or type(definition) ~= "table" then
                return nil
            end

            local entry = {
                protocol = PROTOCOL,
                capabilities = type(definition.capabilities) == "table" and definition.capabilities or {},
                callbacks = type(definition.callbacks) == "table" and definition.callbacks or {},
            }

            self.providers[key] = entry
            return entry
        end

        function compat:getProvider(modKey)
            local provider = self.providers[tostring(modKey or "")]
            if type(provider) ~= "table" or provider.protocol ~= self.protocol then
                return nil
            end
            return provider
        end

        function compat:hasCapability(modKey, capability)
            local provider = self:getProvider(modKey)
            return type(provider) == "table"
                and type(provider.capabilities) == "table"
                and provider.capabilities[tostring(capability or "")] == true
        end

        function compat:getCallback(modKey, callbackName)
            local provider = self:getProvider(modKey)
            if type(provider) ~= "table" or type(provider.callbacks) ~= "table" then
                return nil
            end

            local callback = provider.callbacks[tostring(callbackName or "")]
            if type(callback) ~= "function" then
                return nil
            end
            return callback
        end
    end

    compat.protocol = PROTOCOL
    compat.providers = type(compat.providers) == "table" and compat.providers or {}
    ensureCompatMethods(compat)
    rawset(_G, "MakesSenseCompat", compat)
    return compat
end

local Compat = ensureCompat()
CaffeineMakesSense.Compat = Compat

return Compat
