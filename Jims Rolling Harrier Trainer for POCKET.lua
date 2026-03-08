-- Rolling Harrier Trainer — Radiomaster Pocket Edition
-- place script into your SCRIPTS/TOOLS folder
-- If your active model has excessive trim it may cause an issue. If so make a new model with no trim.
-- My setup was AETR, you may have to invert a channel to make it work correctly
-- Designed for Radiomaster Pocket (128x64, monochrome)
-- ENTER = open settings (main) / confirm/toggle (settings)
-- EXIT  = back (settings)
-- Rotary or +/- = scroll params / adjust value when in adjust mode

----------------------------------------------------------
-- CONFIG
----------------------------------------------------------
local configOpen   = false
local allowOverlap = false

local configParams = {
    { label="Rudder",   key="rudder",         min=50, max=1024, step=10 },
    { label="Elevator", key="elevator",       min=50, max=1024, step=10 },
    { label="Deadband", key="centerDeadband", min=20, max=300,  step=10 },
}

----------------------------------------------------------
-- THRESHOLDS
----------------------------------------------------------
local thresholds = {
    rudder         = 300,
    elevator       = 180,
    centerDeadband = 120,
}

local defaults = { rudder=300, elevator=180, centerDeadband=120 }

local function resetDefaults()
    for k, v in pairs(defaults) do thresholds[k] = v end
end

local function T() return thresholds end

----------------------------------------------------------
-- GAME STATE
----------------------------------------------------------
local stepIndex      = 1
local stickWasActive = false
local waitForCenter  = false
local centerHintCh   = 4
local errorLatch     = false
local statusError    = false
local errorFrames    = 0
local errorDelay     = 3
local rollStreak     = 0

----------------------------------------------------------
-- HELPERS
----------------------------------------------------------

local function get(ch) return getValue("ch"..ch) end

local function centered()
    return math.abs(get(2)) < T().centerDeadband and
           math.abs(get(4)) < T().centerDeadband
end

local function rollingRight() return get(1) >  T().rudder end
local function rollingLeft()  return get(1) < -T().rudder end

-- Direction locked at sequence start so mid-roll aileron movement
-- doesn't corrupt step definitions
local lockedRight = false

----------------------------------------------------------
-- STEP BUILDER
----------------------------------------------------------

local function getStep(index)
    local right = lockedRight
    local r1 = right and -1 or 1
    local r2 = right and 1 or -1
    local steps = {
        { name=(right and "Left Rudder"  or "Right Rudder"), ch=4, dir=r1, thr=T().rudder },
        { name="Push Elevator",                               ch=2, dir= 1, thr=T().elevator },
        { name=(right and "Right Rudder" or "Left Rudder"),  ch=4, dir=r2, thr=T().rudder },
        { name="Pull Elevator",                               ch=2, dir=-1, thr=T().elevator },
    }
    return steps[index]
end

local function evalMove(step)
    local v = get(step.ch)
    local past = (step.dir == 1 and v > step.thr) or
                 (step.dir == -1 and v < -step.thr)
    if not past then return "wrong" end
    return "correct"
end

local function anyWrongMove(step)
    local wrongChannel = step.ch == 2 and math.abs(get(4)) > T().rudder
                                       or math.abs(get(2)) > T().elevator
    -- also flag if the correct channel is moving in the wrong direction
    local v = get(step.ch)
    local wrongDir = (step.dir == 1  and v < -T()[step.ch == 2 and "elevator" or "rudder"]) or
                     (step.dir == -1 and v >  T()[step.ch == 2 and "elevator" or "rudder"])
    return wrongChannel or wrongDir
end

----------------------------------------------------------
-- RESET
----------------------------------------------------------

local function resetState()
    stepIndex      = 1
    stickWasActive = false
    waitForCenter  = false
    centerHintCh   = 4
    errorLatch     = false
    statusError    = false
    errorFrames    = 0
    rollStreak     = 0
    lockedRight    = rollingRight()
end

----------------------------------------------------------
-- SETTINGS PAGE
----------------------------------------------------------
local pktConfigCursor = 1
local pktAdjusting    = false

local function pktDrawConfig()
    lcd.drawText(0, 0, "Harrier Settings", SMLSIZE + BOLD)

    local totalItems = #configParams + 2  -- params + overlap + exit

    -- Show up to 3 params at a time, scrolling window around cursor
    local startI = math.max(1, math.min(pktConfigCursor - 1, #configParams - 2))
    local endI   = math.min(startI + 2, #configParams)

    for i = startI, endI do
        local p = configParams[i]
        local val = thresholds[p.key]
        local y = 12 + (i - startI) * 12
        local flags = (i == pktConfigCursor) and (SMLSIZE + INVERS) or SMLSIZE
        lcd.drawText(0, y, p.label, flags)
        local valStr = (pktAdjusting and i == pktConfigCursor)
            and ("<"..tostring(val)..">") or tostring(val)
        lcd.drawText(80, y, valStr, flags)
    end

    -- Overlap toggle
    local ovlFlags = (pktConfigCursor == #configParams + 1) and (SMLSIZE + INVERS) or SMLSIZE
    lcd.drawText(0, 48, allowOverlap and "Allow Overlap: ON" or "Allow Overlap: OFF", ovlFlags)

    -- Exit button
    local exitFlags = (pktConfigCursor == totalItems) and (SMLSIZE + INVERS) or SMLSIZE
    lcd.drawText(0, 56, "[ Exit ]", exitFlags)
end

local function pktHandleConfig(event)
    local totalItems = #configParams + 2

    if event == EVT_ROT_RIGHT or event == EVT_PLUS_FIRST then
        if pktAdjusting then
            local p = configParams[pktConfigCursor]
            thresholds[p.key] = math.min(p.max, thresholds[p.key] + p.step)
            playTone(700, 50, 0, PLAY_NOW)
        else
            pktConfigCursor = math.min(totalItems, pktConfigCursor + 1)
        end

    elseif event == EVT_ROT_LEFT or event == EVT_MINUS_FIRST then
        if pktAdjusting then
            local p = configParams[pktConfigCursor]
            thresholds[p.key] = math.max(p.min, thresholds[p.key] - p.step)
            playTone(500, 50, 0, PLAY_NOW)
        else
            pktConfigCursor = math.max(1, pktConfigCursor - 1)
        end

    elseif event == EVT_ENTER_FIRST then
        if pktConfigCursor == totalItems then
            configOpen = false
            pktConfigCursor = 1
            pktAdjusting = false
        elseif pktConfigCursor == #configParams + 1 then
            allowOverlap = not allowOverlap
            playTone(600, 80, 0, PLAY_NOW)
        else
            pktAdjusting = not pktAdjusting
            playTone(pktAdjusting and 700 or 500, 80, 0, PLAY_NOW)
        end

    elseif event == EVT_EXIT_FIRST then
        if pktAdjusting then
            pktAdjusting = false
        else
            configOpen = false
            pktConfigCursor = 1
        end
    end
end

----------------------------------------------------------
-- MAIN SCREEN
----------------------------------------------------------

local function pktDrawProgress()
    local size   = 8
    local gap    = 4
    local startX = 4
    local y      = 54

    for i = 1, 4 do
        local drawIndex = lockedRight and i or (5 - i)
        local x = startX + (drawIndex - 1) * (size + gap)
        if i < stepIndex then
            lcd.drawFilledRectangle(x, y, size, size, SOLID)
        elseif i == stepIndex then
            lcd.drawFilledRectangle(x, y, size, size, SOLID)
            lcd.drawRectangle(x + 1, y + 1, size - 2, size - 2, ERASE)
        else
            lcd.drawRectangle(x, y, size, size, SOLID)
        end
    end
end

local function pktDrawMain(step, showHint)
    -- Row 0: title
    lcd.drawText(0, 0, "Jims Rolling Harrier Trainer", SMLSIZE)

    -- Row 1: aileron state + status
    if rollingRight() then
        lcd.drawText(0, 12, ">> Right", SMLSIZE)
    elseif rollingLeft() then
        lcd.drawText(0, 12, "<< Left", SMLSIZE)
    else
        lcd.drawText(0, 12, "Centered", SMLSIZE + INVERS)
    end
    if statusError then
        lcd.drawText(90, 12, "ERR", SMLSIZE + INVERS)
    else
        lcd.drawText(90, 12, "OK", SMLSIZE)
    end

    -- Row 2: streak counter (below ERR/OK) + current step
    if rollStreak > 0 then
        lcd.drawText(90, 24, "x"..tostring(rollStreak), SMLSIZE + BOLD)
    end
    local stepFlags = waitForCenter and (SMLSIZE + INVERS) or SMLSIZE
    lcd.drawText(0, 24, step.name, stepFlags)

    -- Row 3: center hint
    if showHint then
        if centerHintCh == 2 then
            lcd.drawText(0, 36, "Center Elevator", SMLSIZE)
        else
            lcd.drawText(0, 36, "Center Rudder", SMLSIZE)
        end
    end

    -- Bottom right: settings hint
    lcd.drawText(61, 55, "ENTER=Settings", SMLSIZE)

    pktDrawProgress()
end

local function pktHandleMain(event)
    if event == EVT_ENTER_FIRST then
        configOpen = true
        pktConfigCursor = 1
        pktAdjusting = false
    end
end

----------------------------------------------------------
-- GAME LOGIC
----------------------------------------------------------

local function runGameLogic(step, result, active)
    if active then
        statusError = false
        errorLatch  = false
        errorFrames = 0
    elseif anyWrongMove(step) and not waitForCenter then
        errorFrames = errorFrames + 1
        if errorFrames >= errorDelay then
            if not errorLatch then
                playTone(300, 150, 0, PLAY_NOW)
                errorLatch = true
            end
            statusError = true
            rollStreak  = 0
        end
    else
        errorFrames = 0
        errorLatch  = false
    end

    if active and not stickWasActive then
        centerHintCh  = step.ch
        stepIndex     = stepIndex + 1
        waitForCenter = true
        statusError   = false

        if stepIndex > 4 then
            playTone(760, 90, 0, PLAY_NOW)
            stepIndex   = 1
            rollStreak  = rollStreak + 1
            lockedRight = rollingRight()
        else
            playTone(750, 80, 0, PLAY_NOW)
        end
    end

    stickWasActive = active
end

----------------------------------------------------------
-- MAIN RUN
----------------------------------------------------------

local function run(event, touchState)
    lcd.clear()

    if configOpen then
        pktDrawConfig()
        pktHandleConfig(event)
        return 0
    end

    if waitForCenter and centered() then
        waitForCenter = false
    end

    -- Lock roll direction at the start of each new sequence
    if stepIndex == 1 and not waitForCenter then
        lockedRight = rollingRight()
    end

    -- If aileron flips mid-sequence, restart cleanly in the new direction
    if stepIndex > 1 and rollingRight() ~= lockedRight and
       (rollingRight() or rollingLeft()) then
        resetState()
        lockedRight = rollingRight()
    end

    local step   = getStep(stepIndex)
    local result = evalMove(step)
    local active = (result == "correct")
    local showHint = waitForCenter

    pktHandleMain(event)

    if waitForCenter and not allowOverlap then
        pktDrawMain(step, showHint)
        return 0
    end

    runGameLogic(step, result, active)
    pktDrawMain(step, showHint)
    return 0
end

return { run=run }
