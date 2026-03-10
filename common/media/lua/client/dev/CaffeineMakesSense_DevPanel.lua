CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.DevPanel = CaffeineMakesSense.DevPanel or {}

local DevPanel = CaffeineMakesSense.DevPanel
local panelInstance = nil

local recording = false
local recordBuffer = {}
local recordStartMinute = nil
local recordLabel = nil
local lastSampleGameMinute = nil
local SAMPLE_INTERVAL_MINUTES = 5
local preFatigue = nil

local PANEL_W = 400
local PANEL_H = 420
local LINE_H = 22
local PAD = 14
local SECTION_GAP = 10
local FONT = UIFont.Medium
local FONT_SMALL = UIFont.Small
local BAR_H = 14

local COLOR_BG = { r = 0.06, g = 0.06, b = 0.09, a = 0.92 }
local COLOR_BORDER = { r = 0.30, g = 0.50, b = 0.60, a = 0.60 }
local COLOR_LABEL = { r = 0.55, g = 0.60, b = 0.65, a = 1.00 }
local COLOR_VALUE = { r = 0.92, g = 0.93, b = 0.95, a = 1.00 }
local COLOR_HEADER = { r = 0.40, g = 0.75, b = 0.90, a = 1.00 }
local COLOR_SECTION = { r = 0.35, g = 0.55, b = 0.65, a = 0.80 }
local COLOR_BAR_BG = { r = 0.12, g = 0.12, b = 0.16, a = 1.00 }
local COLOR_STIM = { r = 0.45, g = 0.78, b = 0.35, a = 1.00 }
local COLOR_MASK = { r = 0.25, g = 0.55, b = 0.85, a = 1.00 }
local COLOR_HIDDEN = { r = 0.88, g = 0.45, b = 0.20, a = 1.00 }
local COLOR_SLEEP = { r = 0.85, g = 0.22, b = 0.22, a = 1.00 }
local COLOR_DIM = { r = 0.40, g = 0.42, b = 0.45, a = 0.70 }

local function clamp(v, lo, hi)
    local val = tonumber(v) or lo
    if val < lo then return lo end
    if val > hi then return hi end
    return val
end

local function getWorldAgeMinutes()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if not gameTime then return 0 end
    local ok, hours = pcall(gameTime.getWorldAgeHours, gameTime)
    if not ok then return 0 end
    return (tonumber(hours) or 0) * 60
end

local function getFatigue(player)
    local ok, stats = pcall(player.getStats, player)
    if not ok or not stats then return nil end
    if CharacterStat and CharacterStat.FATIGUE then
        local ok2, val = pcall(stats.get, stats, CharacterStat.FATIGUE)
        if ok2 then return tonumber(val) end
    end
    if type(stats.getFatigue) == "function" then
        local ok2, val = pcall(stats.getFatigue, stats)
        if ok2 then return tonumber(val) end
    end
    return nil
end

local function getLocalPlayer()
    if type(getPlayer) ~= "function" then return nil end
    local ok, player = pcall(getPlayer)
    if not ok then return nil end
    return player
end

local function isPlayerAsleep(player)
    if not player or type(player.isAsleep) ~= "function" then
        return false
    end
    local ok, asleep = pcall(player.isAsleep, player)
    return ok and asleep == true
end

local function computeSnapshot()
    local player = getLocalPlayer()
    if not player then return nil end

    local State = CaffeineMakesSense.State
    local Pharma = CaffeineMakesSense.Pharma
    if not State or not Pharma then return nil end

    local state = State.ensureState(player)
    if not state then return nil end
    local options = State.getOptions()
    local now = getWorldAgeMinutes()

    local rawStimLoad, maskLoad = State.getLoadTotals(state, now, options)
    local maxCaffeine = tonumber(options.MaxCaffeineLevel) or 4.0
    local peakMask = tonumber(options.PeakMaskStrength) or 0.85
    local maskStr = Pharma.maskStrength(maskLoad, peakMask, maxCaffeine)
    local negligible = tonumber(options.NegligibleThreshold) or 0.05

    local stimFraction = 0
    local peakStim = state.peakStimThisCycle or 0
    if peakStim > 0 then
        stimFraction = rawStimLoad / peakStim
    end

    local newestDose = State.getNewestDose(state)
    local newestProfileKey = State.getDoseProfileKey(newestDose)
    local newestProfile = Pharma.getProfileOptions(options, newestProfileKey)
    local onsetMin = newestProfile.onsetMinutes
    local halfLifeMin = newestProfile.halfLifeMinutes
    local hiddenFatigue = state.hiddenFatigue or 0

    local stage = "inactive"
    if rawStimLoad >= negligible then
        if newestDose and (now - newestDose.doseMinute) < onsetMin then
            stage = "onset"
        elseif stimFraction >= 0.90 then
            stage = "peak"
        elseif stimFraction >= 0.30 then
            stage = "decay"
        else
            stage = "tail"
        end
    end

    local minutesSinceLastDose = newestDose and newestDose.doseMinute and (now - newestDose.doseMinute) or nil
    local timeToTailOnset = nil
    if newestDose and stimFraction >= 0.30 and rawStimLoad >= negligible then
        local minutesPastPeak = math.max(0, (now - newestDose.doseMinute) - onsetMin)
        local totalDecayToThreshold = halfLifeMin * (math.log(1 / 0.30) / math.log(2))
        timeToTailOnset = math.max(0, totalDecayToThreshold - minutesPastPeak)
    end

    return {
        rawStimLoad = rawStimLoad,
        maskLoad = maskLoad,
        maxCaffeine = maxCaffeine,
        maskStrength = maskStr,
        stimFraction = stimFraction,
        hiddenFatigue = hiddenFatigue,
        sleepDisruption = math.max(tonumber(state.sleepDisruptionScore) or 0, tonumber(state.lastSleepDisruptionScore) or 0),
        wakeFatiguePenalty = tonumber(state.lastWakeFatiguePenalty) or 0,
        displayedFatigue = getFatigue(player) or 0,
        realFatigue = state.realFatigue or (getFatigue(player) or 0),
        sleeping = isPlayerAsleep(player),
        sleepSessionMinutes = math.max(0, now - (tonumber(state.sleepStartMinute) or now)),
        stage = stage,
        doseCount = #(state.doses or {}),
        minutesSinceLastDose = minutesSinceLastDose,
        timeToTailOnset = timeToTailOnset,
        onsetMinutes = onsetMin,
        halfLifeMinutes = halfLifeMin,
        profileKey = newestProfileKey,
    }
end

local CSV_HEADER = table.concat({
    "elapsed_min",
    "game_min",
    "game_speed",
    "stage",
    "raw_stim_load",
    "mask_load",
    "caffeine_max",
    "mask_pct",
    "frac_of_peak_pct",
    "fatigue_pre",
    "fatigue_post",
    "real_fatigue_est",
    "hidden_debt",
    "sleep_disruption_pct",
    "wake_fatigue_penalty",
    "sleep_session_min",
    "dose_count",
    "sleeping",
    "event",
    "event_profile",
}, ",")

local function getGameSpeed()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if not gameTime then return 1 end
    local ok, mult = pcall(gameTime.getMultiplier, gameTime)
    if not ok then return 1 end
    return tonumber(mult) or 1
end

local function recordSample(snap, eventTag, eventProfile)
    if not recording or not snap then return end
    local now = getWorldAgeMinutes()
    local elapsed = now - (recordStartMinute or now)
    local pre = preFatigue or snap.displayedFatigue
    recordBuffer[#recordBuffer + 1] = string.format(
        "%.1f,%.1f,%.0f,%s,%.4f,%.4f,%.1f,%.2f,%.2f,%.5f,%.5f,%.5f,%.5f,%.2f,%.5f,%.1f,%d,%s,%s,%s",
        elapsed,
        now,
        getGameSpeed(),
        snap.stage,
        snap.rawStimLoad,
        snap.maskLoad,
        snap.maxCaffeine,
        snap.maskStrength * 100,
        snap.stimFraction * 100,
        pre,
        snap.displayedFatigue,
        snap.realFatigue,
        snap.hiddenFatigue,
        snap.sleepDisruption * 100,
        snap.wakeFatiguePenalty,
        snap.sleepSessionMinutes,
        snap.doseCount,
        tostring(snap.sleeping),
        eventTag or "",
        eventProfile or ""
    )
end

local function writeRecordingToFile()
    if #recordBuffer == 0 then
        print("[CaffeineMakesSense] recording empty, nothing to write")
        return nil
    end
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local label = recordLabel or "session"
    local filename = "cms_recording_" .. label .. "_" .. timestamp .. ".csv"
    local relPath = "cmslogs/" .. filename

    local writer = nil
    if type(getFileWriter) == "function" then
        local ok, w = pcall(getFileWriter, relPath, true, false)
        if ok and w then writer = w end
    end
    if not writer and type(getSandboxFileWriter) == "function" then
        local ok, w = pcall(getSandboxFileWriter, relPath, true, false)
        if ok and w then writer = w end
    end
    if not writer then
        print("[CaffeineMakesSense] failed to open file writer for " .. relPath)
        return nil
    end

    writer:writeln(CSV_HEADER)
    for i = 1, #recordBuffer do
        writer:writeln(recordBuffer[i])
    end
    writer:close()

    print(string.format("[CaffeineMakesSense] recording saved: %s (%d samples)", relPath, #recordBuffer))
    return relPath
end

function DevPanel.startRecording(label)
    if recording then
        DevPanel.stopRecording()
    end
    recordBuffer = {}
    recordStartMinute = getWorldAgeMinutes()
    lastSampleGameMinute = recordStartMinute
    preFatigue = nil
    recordLabel = label or "session"
    recording = true
    print(string.format("[CaffeineMakesSense] recording started (label=%s, interval=%dmin)", recordLabel, SAMPLE_INTERVAL_MINUTES))
end

function DevPanel.stopRecording()
    if not recording then return nil end
    recording = false
    local path = writeRecordingToFile()
    local count = #recordBuffer
    recordBuffer = {}
    recordStartMinute = nil
    recordLabel = nil
    return path, count
end

function DevPanel.isRecording()
    return recording
end

function DevPanel.capturePreTick()
    if not recording then return end
    local player = getLocalPlayer()
    if player then
        preFatigue = getFatigue(player)
    end
end

function DevPanel.sampleTick()
    if not recording then return end
    local snap = computeSnapshot()
    recordSample(snap, "")
    preFatigue = nil
    lastSampleGameMinute = getWorldAgeMinutes()
end

function DevPanel.sampleHighFreq()
    if not recording then return end
    local now = getWorldAgeMinutes()
    local last = lastSampleGameMinute or now
    if (now - last) < SAMPLE_INTERVAL_MINUTES then return end
    local player = getLocalPlayer()
    if player then
        preFatigue = getFatigue(player)
    end
    local snap = computeSnapshot()
    recordSample(snap, "interp")
    preFatigue = nil
    lastSampleGameMinute = now
end

function DevPanel.sampleEvent(eventTag, eventProfile)
    if not recording then return end
    local player = getLocalPlayer()
    if player then
        preFatigue = getFatigue(player)
    end
    local snap = computeSnapshot()
    recordSample(snap, eventTag or "event", eventProfile or "")
    preFatigue = nil
end

function DevPanel.reset()
    local player = getLocalPlayer()
    if not player then
        print("[CaffeineMakesSense] reset: no player")
        return
    end
    local State = CaffeineMakesSense.State
    if not State then return end

    local state = State.ensureState(player)
    if not state then return end

    local fatNow = getFatigue(player)
    local restored = clamp(state.realFatigue or fatNow or 0, 0, 1)
    if fatNow ~= nil and math.abs(restored - fatNow) > 0.0001 then
        local ok, stats = pcall(player.getStats, player)
        if ok and stats then
            if CharacterStat and CharacterStat.FATIGUE then
                pcall(stats.set, stats, CharacterStat.FATIGUE, restored)
            elseif type(stats.setFatigue) == "function" then
                pcall(stats.setFatigue, stats, restored)
            end
        end
        print(string.format("[CaffeineMakesSense] reset: restored fatigue %.1f%% -> %.1f%%", (fatNow or 0) * 100, restored * 100))
    end

    state.doses = {}
    state.hiddenFatigue = 0
    state.peakStimThisCycle = 0
    state.pendingCatchupMinutes = 0
    state.wasSleeping = false
    state.sleepStartMinute = nil
    state.sleepLastAccumMinute = nil
    state.sleepWeightedDisruption = 0
    state.sleepWeightedMinutes = 0
    state.sleepPeakDisruption = 0
    state.sleepDisruptionScore = 0
    state.sleepDisruptionStrength = 0
    state.sleepPendingWakeFatigue = 0
    state.lastWakeFatiguePenalty = 0
    state.lastSleepDisruptionScore = 0
    state.realFatigue = restored
    state.lastSetFatigue = restored

    if recording then
        pcall(DevPanel.sampleEvent, "reset", "")
    end

    print("[CaffeineMakesSense] reset: all caffeine state cleared")
end

local CMS_DevOverlay = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("CMS_DevOverlay")
    or nil

if not CMS_DevOverlay then
    print("[CaffeineMakesSense][WARN] ISPanel not available at load time; dev panel will initialize on first use")
    CMS_DevOverlay = {}
end

function CMS_DevOverlay:new(x, y)
    local panel = ISPanel:new(x, y, PANEL_W, PANEL_H)
    setmetatable(panel, self)
    self.__index = self
    panel.moveWithMouse = true
    panel.backgroundColor = COLOR_BG
    panel.borderColor = COLOR_BORDER
    return panel
end

function CMS_DevOverlay:initialise()
    ISPanel.initialise(self)
end

function CMS_DevOverlay:createChildren()
    ISPanel.createChildren(self)
    self.closeBtn = ISButton:new(PANEL_W - 28, 4, 22, 22, "X", self, CMS_DevOverlay.onClose)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)

    self.recordBtn = ISButton:new(PAD, 4, 80, 22, "Record", self, CMS_DevOverlay.onToggleRecord)
    self.recordBtn:initialise()
    self:addChild(self.recordBtn)
    self:updateRecordButton()

    self.resetBtn = ISButton:new(PAD + 86, 4, 60, 22, "Reset", self, CMS_DevOverlay.onReset)
    self.resetBtn:initialise()
    self.resetBtn.backgroundColor = { r = 0.15, g = 0.15, b = 0.20, a = 0.9 }
    self.resetBtn.textColor = { r = 0.8, g = 0.8, b = 0.8, a = 1 }
    self:addChild(self.resetBtn)
end

function CMS_DevOverlay:updateRecordButton()
    if not self.recordBtn then return end
    if recording then
        self.recordBtn:setTitle("Stop (" .. tostring(#recordBuffer) .. ")")
        self.recordBtn.backgroundColor = { r = 0.6, g = 0.15, b = 0.15, a = 0.9 }
        self.recordBtn.textColor = { r = 1, g = 1, b = 1, a = 1 }
    else
        self.recordBtn:setTitle("Record")
        self.recordBtn.backgroundColor = { r = 0.15, g = 0.15, b = 0.20, a = 0.9 }
        self.recordBtn.textColor = { r = 0.8, g = 0.8, b = 0.8, a = 1 }
    end
end

function CMS_DevOverlay:onToggleRecord()
    if recording then
        local path, count = DevPanel.stopRecording()
        if path then
            print(string.format("[CaffeineMakesSense] saved %d samples -> %s", count or 0, path))
        end
    else
        DevPanel.startRecording("dev")
    end
    self:updateRecordButton()
end

function CMS_DevOverlay:onReset()
    DevPanel.reset()
end

function CMS_DevOverlay:onClose()
    if recording then
        DevPanel.stopRecording()
    end
    DevPanel.hide()
end

function CMS_DevOverlay:prerender()
    ISPanel.prerender(self)
end

local function drawBar(self, y, fraction, color)
    local x = PAD
    local w = PANEL_W - PAD * 2
    self:drawRect(x, y, w, BAR_H, COLOR_BAR_BG.a, COLOR_BAR_BG.r, COLOR_BAR_BG.g, COLOR_BAR_BG.b)
    local fillW = math.max(0, math.floor(w * clamp(fraction, 0, 1)))
    if fillW > 0 then
        self:drawRect(x, y, fillW, BAR_H, color.a, color.r, color.g, color.b)
    end
    return y + BAR_H + 6
end

local function drawRow(self, y, label, value, valueColor)
    valueColor = valueColor or COLOR_VALUE
    self:drawText(label, PAD, y, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT_SMALL)
    self:drawTextRight(tostring(value), PANEL_W - PAD, y, valueColor.r, valueColor.g, valueColor.b, valueColor.a, FONT_SMALL)
    return y + LINE_H
end

local function drawSectionHeader(self, y, title)
    y = y + 2
    local lineY = y + 8
    self:drawRect(PAD, lineY, PANEL_W - PAD * 2, 1, COLOR_SECTION.a * 0.4, COLOR_SECTION.r, COLOR_SECTION.g, COLOR_SECTION.b)
    self:drawText(title, PAD, y, COLOR_SECTION.r, COLOR_SECTION.g, COLOR_SECTION.b, COLOR_SECTION.a, FONT_SMALL)
    return y + LINE_H + 2
end

local function fmtMinutes(minutes)
    if not minutes then return "--" end
    if minutes < 60 then
        return string.format("%.0f min", minutes)
    end
    return string.format("%.1f hr", minutes / 60)
end

local STAGE_COLORS = {
    inactive = COLOR_DIM,
    onset = { r = 0.92, g = 0.85, b = 0.25, a = 1.0 },
    peak = COLOR_STIM,
    decay = COLOR_MASK,
    tail = { r = 0.5, g = 0.5, b = 0.6, a = 1.0 },
}

function CMS_DevOverlay:render()
    ISPanel.render(self)

    local snap = computeSnapshot()
    local y = PAD

    self:drawText("Caffeine Makes Sense", PAD + 90, y, COLOR_HEADER.r, COLOR_HEADER.g, COLOR_HEADER.b, COLOR_HEADER.a, FONT)
    self:drawTextRight("dev", PANEL_W - PAD - 30, y + 2, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, FONT_SMALL)
    y = y + LINE_H

    if recording then
        local elapsed = getWorldAgeMinutes() - (recordStartMinute or 0)
        local recText = string.format("REC  %d samples  %.0f min", #recordBuffer, elapsed)
        self:drawText(recText, PAD + 90, y, COLOR_SLEEP.r, COLOR_SLEEP.g, COLOR_SLEEP.b, COLOR_SLEEP.a, FONT_SMALL)
    end
    y = y + SECTION_GAP

    if not snap then
        self:drawText("Waiting for player...", PAD, y, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, FONT_SMALL)
        return
    end

    local stageColor = STAGE_COLORS[snap.stage] or COLOR_DIM
    y = drawRow(self, y, "Stage", string.upper(snap.stage), stageColor)
    y = drawRow(self, y, "Latest Profile", string.upper(tostring(snap.profileKey or "coffee")), COLOR_DIM)
    y = y + 2

    y = drawSectionHeader(self, y, "Pharmacokinetics")
    y = drawRow(self, y, "Raw Stim Load", string.format("%.3f / %.1f", snap.rawStimLoad, snap.maxCaffeine))
    y = drawBar(self, y, snap.rawStimLoad / snap.maxCaffeine, COLOR_STIM)
    y = drawRow(self, y, "Mask Load", string.format("%.3f / %.1f", snap.maskLoad, snap.maxCaffeine))
    y = drawBar(self, y, snap.maskLoad / snap.maxCaffeine, COLOR_MASK)
    y = drawRow(self, y, "Mask Strength", string.format("%.1f%%", snap.maskStrength * 100))
    y = drawBar(self, y, snap.maskStrength, COLOR_MASK)
    y = drawRow(self, y, "Frac of Peak", string.format("%.1f%%", snap.stimFraction * 100), COLOR_DIM)

    y = drawSectionHeader(self, y, "Fatigue")
    y = drawRow(self, y, "Displayed", string.format("%.1f%%", snap.displayedFatigue * 100))
    y = drawRow(self, y, "Real (estimated)", string.format("%.1f%%", snap.realFatigue * 100), COLOR_DIM)
    y = drawRow(self, y, "Hidden Debt", string.format("%.4f", snap.hiddenFatigue))
    y = drawBar(self, y, snap.hiddenFatigue, COLOR_HIDDEN)

    y = drawSectionHeader(self, y, "Sleep")
    y = drawRow(self, y, "Sleeping", snap.sleeping and "YES" or "NO", snap.sleeping and COLOR_SLEEP or COLOR_DIM)
    y = drawRow(self, y, "Disruption Score", string.format("%.1f%%", snap.sleepDisruption * 100), snap.sleepDisruption > 0 and COLOR_SLEEP or COLOR_DIM)
    y = drawBar(self, y, snap.sleepDisruption, COLOR_SLEEP)
    y = drawRow(self, y, "Wake Penalty", string.format("%.3f", snap.wakeFatiguePenalty), snap.wakeFatiguePenalty > 0 and COLOR_SLEEP or COLOR_DIM)
    y = drawRow(self, y, "Sleep Session", fmtMinutes(snap.sleepSessionMinutes), COLOR_DIM)

    y = drawSectionHeader(self, y, "Timing")
    y = drawRow(self, y, "Active Doses", tostring(snap.doseCount))
    y = drawRow(self, y, "Since Last Dose", fmtMinutes(snap.minutesSinceLastDose))
    y = drawRow(self, y, "Est. Time to Tail", fmtMinutes(snap.timeToTailOnset))

    local neededH = y + PAD
    if math.abs(neededH - self.height) > 2 then
        self:setHeight(neededH)
    end
end

function CMS_DevOverlay:update()
    ISPanel.update(self)
    self:updateRecordButton()
end

function CMS_DevOverlay:onMouseDown(x, y)
    self.moving = true
    self.moveOffsetX = x
    self.moveOffsetY = y
    return true
end

function CMS_DevOverlay:onMouseUp(x, y)
    self.moving = false
    return true
end

function CMS_DevOverlay:onMouseMove(dx, dy)
    if self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
    return true
end

function CMS_DevOverlay:onMouseMoveOutside(dx, dy)
    if self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
    return true
end

function DevPanel.show()
    if panelInstance and panelInstance:isVisible() then
        return
    end
    if not CMS_DevOverlay.__index and ISPanel and type(ISPanel.derive) == "function" then
        local methods = {}
        for key, value in pairs(CMS_DevOverlay) do methods[key] = value end
        CMS_DevOverlay = ISPanel:derive("CMS_DevOverlay")
        for key, value in pairs(methods) do CMS_DevOverlay[key] = value end
    end
    if not ISPanel or not CMS_DevOverlay.new then
        print("[CaffeineMakesSense][ERROR] Cannot open dev panel: ISPanel not available")
        return
    end
    local x = getCore():getScreenWidth() - PANEL_W - 30
    local y = 80
    panelInstance = CMS_DevOverlay:new(x, y)
    panelInstance:initialise()
    panelInstance:addToUIManager()
    panelInstance:setVisible(true)
    print("[CaffeineMakesSense] dev panel opened")
end

function DevPanel.hide()
    if panelInstance then
        panelInstance:setVisible(false)
        panelInstance:removeFromUIManager()
        panelInstance = nil
        print("[CaffeineMakesSense] dev panel closed")
    end
end

function DevPanel.toggle()
    if panelInstance and panelInstance:isVisible() then
        DevPanel.hide()
    else
        DevPanel.show()
    end
end

function DevPanel.isVisible()
    return panelInstance ~= nil and panelInstance:isVisible()
end

function CMS_DevPanel()
    local ok, err = pcall(DevPanel.toggle)
    if not ok then
        print("[CaffeineMakesSense][ERROR] CMS_DevPanel: " .. tostring(err))
    end
end

return DevPanel
