CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.HealthPanelHook = CaffeineMakesSense.HealthPanelHook or {}

require "CaffeineMakesSense_Config"
require "CaffeineMakesSense_Runtime"
require "CaffeineMakesSense_HealthStatus"
pcall(require, "CaffeineMakesSense_MPClientRuntime")

local HealthPanelHook = CaffeineMakesSense.HealthPanelHook
local Runtime = CaffeineMakesSense.Runtime or {}
local HealthStatus = CaffeineMakesSense.HealthStatus or {}
local MPClient = CaffeineMakesSense.MPClient or {}
local DEFAULTS = CaffeineMakesSense.DEFAULTS or {}

local UI_BORDER_SPACING = 10
local FONT = UIFont.Small
local FONT_HGT = nil

local C_WHITE = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
local C_VALUE = { r = 0.75, g = 0.77, b = 0.80, a = 1.0 }
local C_WARN = { r = 0.90, g = 0.75, b = 0.30, a = 1.0 }
local C_BAD = { r = 0.90, g = 0.35, b = 0.30, a = 1.0 }

local originalRender = nil
local originalUpdate = nil

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function getWorldAgeMinutes()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    local hours = tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
    if hours == nil then
        return 0
    end
    return hours * 60.0
end

local function isMultiplayerClient()
    return type(isClient) == "function" and isClient() == true
end

local function getCompat()
    local compat = CaffeineMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" then
        return nil
    end
    if type(compat.hasCapability) ~= "function" then
        return nil
    end
    return compat
end

local function nmsOwnsHealthPanel()
    local compat = getCompat()
    return type(compat) == "table"
        and compat:hasCapability("NutritionMakesSense", "health_panel_coordinator")
end

local function buildOptions(snapshot)
    if type(snapshot) == "table" then
        return {
            MaxCaffeineLevel = HealthStatus.firstNumber(DEFAULTS.MaxCaffeineLevel or 4.0, snapshot.maxCaffeine),
            NegligibleThreshold = HealthStatus.firstNumber(DEFAULTS.NegligibleThreshold or 0.05, DEFAULTS.NegligibleThreshold),
        }
    end
    if type(Runtime.getOptions) == "function" then
        return Runtime.getOptions()
    end
    return DEFAULTS
end

local function getHealthLine(playerObj)
    if not playerObj or type(HealthStatus.buildHealthLine) ~= "function" then
        return nil
    end

    local nowMinutes = getWorldAgeMinutes()
    local snapshot = nil
    if isMultiplayerClient() and type(MPClient.requestSnapshot) == "function" and type(MPClient.getSnapshot) == "function" then
        pcall(MPClient.requestSnapshot, "health_panel", false)
        snapshot = MPClient.getSnapshot()
    end

    local options = buildOptions(snapshot)
    local localRawStimLoad = nil
    local localNewestDoseMinute = nil
    local state = type(Runtime.ensureStateForPlayer) == "function" and Runtime.ensureStateForPlayer(playerObj) or nil
    if state and type(Runtime.getLoadTotals) == "function" then
        localRawStimLoad = HealthStatus.firstNumber(nil, Runtime.getLoadTotals(state, nowMinutes, options))
        local newestDose = type(Runtime.getNewestDose) == "function" and Runtime.getNewestDose(state) or nil
        localNewestDoseMinute = HealthStatus.firstNumber(nil, newestDose and newestDose.doseMinute)
    end

    local chosenLoad = nil
    if type(HealthStatus.chooseDisplayLoad) == "function" then
        chosenLoad = HealthStatus.chooseDisplayLoad(snapshot, localRawStimLoad, localNewestDoseMinute, nowMinutes, options)
    elseif snapshot and snapshot.rawStimLoad ~= nil then
        chosenLoad = { rawStimLoad = HealthStatus.firstNumber(0, snapshot.rawStimLoad) }
    elseif localRawStimLoad ~= nil then
        chosenLoad = { rawStimLoad = HealthStatus.firstNumber(0, localRawStimLoad) }
    end
    if not chosenLoad then
        return nil
    end

    local line = HealthStatus.buildHealthLine(chosenLoad.rawStimLoad, options)
    if not line or line.visible ~= true then
        return nil
    end
    return line
end

local function getLineColor(line)
    local key = tostring(line and line.colorKey or "neutral")
    if key == "warn" then
        return C_WARN
    end
    if key == "bad" then
        return C_BAD
    end
    return C_VALUE
end

local function buildHostedLine(line)
    if not line or type(line.label) ~= "string" then
        return nil
    end
    return {
        text = "Caffeine: ",
        color = C_WHITE,
        valueText = line.label,
        valueColor = getLineColor(line),
    }
end

local function registerCompatProvider()
    local compat = getCompat()
    if not compat or type(compat.registerProvider) ~= "function" then
        return
    end

    compat:registerProvider("CaffeineMakesSense", {
        capabilities = {
            health_panel_line_provider = true,
        },
        callbacks = {
            collectHealthPanelLines = function(playerObj, _args)
                local line = getHealthLine(playerObj)
                local hosted = buildHostedLine(line)
                if not hosted then
                    return {}
                end
                return { hosted }
            end,
        },
    })
end

local function hookedUpdate(self)
    if not FONT_HGT then
        FONT_HGT = getTextManager():getFontHeight(FONT)
    end

    local patient = self.getPatient and self:getPatient() or nil
    if not patient or (self.otherPlayer and self.otherPlayer ~= patient) then
        originalUpdate(self)
        return
    end

    if nmsOwnsHealthPanel() then
        originalUpdate(self)
        return
    end

    local line = getHealthLine(patient)
    if not line then
        originalUpdate(self)
        return
    end

    local blockHeight = FONT_HGT + 2
    local previousAllTextHeight = self.allTextHeight
    if previousAllTextHeight ~= nil then
        self.allTextHeight = previousAllTextHeight + blockHeight
    end

    originalUpdate(self)
    self.allTextHeight = previousAllTextHeight
end

local function hookedRender(self)
    if not FONT_HGT then
        FONT_HGT = getTextManager():getFontHeight(FONT)
    end

    originalRender(self)

    local patient = self:getPatient()
    if not patient or (self.otherPlayer and self.otherPlayer ~= patient) then
        return
    end

    if nmsOwnsHealthPanel() then
        return
    end

    local line = getHealthLine(patient)
    if not line then
        return
    end

    local x = self.healthPanel:getRight() + UI_BORDER_SPACING
    local y = self.listbox:getY()
    local labelText = "Caffeine: "
    local valueText = line.label or "?"
    local valueColor = getLineColor(line)

    self:drawText(labelText, x, y, C_WHITE.r, C_WHITE.g, C_WHITE.b, C_WHITE.a, FONT)
    local vx = x + getTextManager():MeasureStringX(FONT, labelText)
    self:drawText(valueText, vx, y, valueColor.r, valueColor.g, valueColor.b, valueColor.a, FONT)
    self.listbox:setY(y + FONT_HGT + 2)
    self.listbox.vscroll:setHeight(self.listbox:getHeight())
end

local function installHook()
    if not ISHealthPanel or type(ISHealthPanel.render) ~= "function" or type(ISHealthPanel.update) ~= "function" then
        return
    end
    if originalRender or originalUpdate then
        return
    end

    originalUpdate = ISHealthPanel.update
    originalRender = ISHealthPanel.render
    ISHealthPanel.update = hookedUpdate
    ISHealthPanel.render = hookedRender
end

function HealthPanelHook.install()
    if HealthPanelHook._installed then
        return HealthPanelHook
    end
    HealthPanelHook._installed = true
    registerCompatProvider()

    if Events and Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(installHook)
    end
    installHook()

    return HealthPanelHook
end

return HealthPanelHook
