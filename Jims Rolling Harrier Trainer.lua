-- Jim's Rolling Harrier / Rifle Roll Trainer
-- place script into your SCRIPTS/TOOLS folder
-- Touching anywhere on your screen swaps between Rolling Harrier and Rifle Roll Mode
-- Rifle Roll mode has shorter throws for success and an overshoot means fail
-- If your active model has excessive trim it may cause an issue. If so make a new model with no trim. 
-- My setup was AETR, you may have to invert a channel to make it work correctly

----------------------------------------------------------
-- MODES
----------------------------------------------------------
local MODE_HARRIER = 1
local MODE_RIFLE   = 2
local mode = MODE_HARRIER

----------------------------------------------------------
-- CONFIG PAGE
----------------------------------------------------------
local configOpen      = false
local configSelected  = 1   -- which param row is selected (1-3)
local allowOverlap    = false  -- if true, don't block on waitForCenter

-- Configure button: same X/W as status box (BOX_X=359, BOX_W=110, BOX_Y=150)
local GEAR_X = 359
local GEAR_W = 110
local GEAR_H = 36
local GEAR_Y = 108  -- BOX_Y(150) - GEAR_H(36) - gap(6)

-- Config param descriptors for Harrier mode
-- Each entry: { label, key, min, max, step }
local configParams = {
    { label="Rudder Threshold",   key="rudder",         min=50,  max=1024, step=10 },
    { label="Elevator Threshold", key="elevator",       min=50,  max=1024, step=10 },
    { label="Center Deadband",    key="centerDeadband", min=20,  max=300,  step=10 },
}

----------------------------------------------------------
-- THRESHOLDS (per mode)
----------------------------------------------------------
local thresholds = {
    [MODE_HARRIER] = {
        rudder         = 300,
        elevator       = 180,
        centerDeadband = 120,
        overshoot      = nil,
    },
    [MODE_RIFLE] = {
        rudder         = 100,
        elevator       = 80,
        centerDeadband = 80,
        overshoot      = 250,
    },
}

-- Default values for reset
local harrierDefaults = {
    rudder         = 300,
    elevator       = 180,
    centerDeadband = 120,
}

local function resetHarrierDefaults()
    for k, v in pairs(harrierDefaults) do
        thresholds[MODE_HARRIER][k] = v
    end
end

local function T()
    return thresholds[mode]
end

----------------------------------------------------------

local stepIndex = 1
local stickWasActive = false
local waitForCenter = false
local centerHintCh  = 4  -- channel that needs to return to center (2=elevator, 4=rudder)
local errorLatch = false
local statusError = false
local errorFrames = 0
local errorDelay = 3
local rollStreak = 0

----------------------------------------------------------
-- helpers
----------------------------------------------------------

local function get(ch)
    return getValue("ch"..ch)
end

local function centered()
    return math.abs(get(2)) < T().centerDeadband and
           math.abs(get(4)) < T().centerDeadband
end

local function rollingRight()
    return get(1) > T().rudder
end

local function rollingLeft()
    return get(1) < -T().rudder
end

----------------------------------------------------------
-- dynamic step builder
----------------------------------------------------------

local function getStep(index)
    local right = rollingRight()
    local r1 = right and -1 or 1
    local r2 = right and 1 or -1

    local steps = {
        { name=(right and "Left Rudder" or "Right Rudder"), ch=4, dir=r1, thr=T().rudder },
        { name="Push Elevator",                              ch=2, dir= 1, thr=T().elevator },
        { name=(right and "Right Rudder" or "Left Rudder"), ch=4, dir=r2, thr=T().rudder },
        { name="Pull Elevator",                              ch=2, dir=-1, thr=T().elevator }
    }

    return steps[index]
end

-- returns "correct", "overshoot", or "wrong"
local function evalMove(step)
    local v = get(step.ch)
    local past = (step.dir == 1 and v > step.thr) or
                 (step.dir == -1 and v < -step.thr)

    if not past then return "wrong" end

    if T().overshoot and math.abs(v) > T().overshoot then
        return "overshoot"
    end

    return "correct"
end

local function anyWrongMove(step)
    local v2 = math.abs(get(2))
    local v4 = math.abs(get(4))
    if step.ch == 2 then
        return v4 > T().rudder
    else
        return v2 > T().elevator
    end
end

local function anyMove()
    return math.abs(get(2)) > T().elevator or
           math.abs(get(4)) > T().rudder
end

----------------------------------------------------------
-- reset on mode switch
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
end

----------------------------------------------------------
-- drawing
----------------------------------------------------------

local function drawProgress()
    local size   = 42
    local gap    = 18
    local startX = 20
    local y      = 215
    local right  = rollingRight()

    for i = 1, 4 do
        local drawIndex = right and i or (5 - i)
        local x = startX + (drawIndex - 1) * (size + gap)

        if i < stepIndex then
            lcd.drawFilledRectangle(x, y, size, size, GREEN)
        elseif i == stepIndex then
            lcd.drawFilledRectangle(x, y, size, size, YELLOW)
        else
            lcd.drawRectangle(x, y, size, size)
        end
    end
end

local function drawRollText()
    if rollingRight() then
        lcd.drawText(20, 55, "Rolling Right", DBLSIZE)
    elseif rollingLeft() then
        lcd.drawText(20, 55, "Rolling Left", DBLSIZE)
    else
        lcd.drawText(20, 55, "Aileron Centered", DBLSIZE + ORANGE)
    end
end

-- status box:
local BOX_X = 359
local BOX_Y = 150
local BOX_W = 110
local BOX_H = 110

local function drawStatusBox(green)
    if green then
        lcd.drawFilledRectangle(BOX_X, BOX_Y, BOX_W, BOX_H, GREEN)
    else
        lcd.drawFilledRectangle(BOX_X, BOX_Y, BOX_W, BOX_H, RED)
    end
    if rollStreak > 0 then
        lcd.drawText(BOX_X + 7, BOX_Y + 4, tostring(rollStreak), DBLSIZE + WHITE)
    end
end

----------------------------------------------------------
-- gear button
----------------------------------------------------------

local function drawGearButton()
    lcd.drawFilledRectangle(GEAR_X, GEAR_Y, GEAR_W, GEAR_H, LIGHTGREY)
    lcd.drawText(GEAR_X + 25, GEAR_Y + 11, "Configure", SMLSIZE + WHITE)
end

local function touchInGear(tx, ty)
    return tx >= GEAR_X and tx <= GEAR_X + GEAR_W and
           ty >= GEAR_Y and ty <= GEAR_Y + GEAR_H
end

----------------------------------------------------------
-- config page drawing & interaction
----------------------------------------------------------

local CFG_ROW_H   = 52
local CFG_START_Y = 50
local CFG_LABEL_X = 18
local CFG_VAL_X   = 298
local CFG_BTN_W   = 50
local CFG_BTN_H   = 40
local CFG_MINUS_X = 358
local CFG_PLUS_X  = 418
local CFG_BACK_Y   = 240
local CFG_BACK_X   = 20
local CFG_BACK_W   = 160
local CFG_BACK_H   = 42
local CFG_RESET_X  = 300
local CFG_RESET_W  = 160
local CFG_RESET_H  = 42

local function drawConfigPage()
    lcd.drawText(LCD_W/2, 2, "Harrier Settings", DBLSIZE + CENTER)

    for i, p in ipairs(configParams) do
        local y = CFG_START_Y + (i - 1) * CFG_ROW_H
        local val = thresholds[MODE_HARRIER][p.key]
        local selected = (i == configSelected)

        -- Highlight: extended 2px left of label
        if selected then
            lcd.drawFilledRectangle(CFG_LABEL_X - 6, y - 6, 460, CFG_ROW_H + 1, DARKBLUE)
        end

        -- Label: white when selected, dark blue when not
        local labelColor = selected and WHITE or DARKBLUE
        lcd.drawText(CFG_LABEL_X, y + 4, p.label, MIDSIZE + labelColor)
        lcd.drawText(CFG_VAL_X, y + 4, tostring(val), MIDSIZE + BOLD + labelColor)

        -- Minus button
        lcd.drawFilledRectangle(CFG_MINUS_X, y, CFG_BTN_W, CFG_BTN_H, DARKGREY)
        lcd.drawText(CFG_MINUS_X + 18, y + 2, "-", MIDSIZE + BOLD + WHITE)

        -- Plus button
        lcd.drawFilledRectangle(CFG_PLUS_X, y, CFG_BTN_W, CFG_BTN_H, DARKGREY)
        lcd.drawText(CFG_PLUS_X + 15, y + 2, "+", MIDSIZE + BOLD + WHITE)
    end

    -- Back button: aligned with highlight left edge (x=14)
    lcd.drawFilledRectangle(14, CFG_BACK_Y - 17, 120, CFG_BACK_H, DARKGREY)
    lcd.drawText(34, CFG_BACK_Y - 10, "< Back", MIDSIZE + WHITE)

    -- Allow Input Overlap toggle: sits between Back and Reset
    local OVL_X = 148
    local OVL_W = 196
    local OVL_Y = CFG_BACK_Y - 17
    local OVL_H = CFG_BACK_H
    local ovlColor = allowOverlap and ORANGE or DARKBLUE
    lcd.drawFilledRectangle(OVL_X, OVL_Y, OVL_W, OVL_H, ovlColor)
    if allowOverlap then
        lcd.drawText(OVL_X + 35, CFG_BACK_Y - 5, "Input Overlap Allowed", SMLSIZE + WHITE)
    else
        lcd.drawText(OVL_X + 50, CFG_BACK_Y - 5, "No Input Overlap", SMLSIZE + WHITE)
    end

    -- Reset button
    lcd.drawFilledRectangle(358, CFG_BACK_Y - 17, 110, CFG_RESET_H, RED)
    lcd.drawText(373, CFG_BACK_Y - 5, "Reset Defaults", SMLSIZE + WHITE)
end

local function handleConfigTouch(tx, ty)
    -- Check Allow Input Overlap toggle (x=148, w=196)
    if tx >= 148 and tx <= 344 and
       ty >= CFG_BACK_Y - 17 and ty <= CFG_BACK_Y - 17 + CFG_BACK_H then
        allowOverlap = not allowOverlap
        playTone(600, 80, 0, PLAY_NOW)
        return
    end

    -- Check Back button (x=14, w=120, h=CFG_BACK_H)
    if tx >= 14 and tx <= 134 and
       ty >= CFG_BACK_Y - 17 and ty <= CFG_BACK_Y - 17 + CFG_BACK_H then
        configOpen = false
        return
    end

    -- Check Reset button (x=358, w=110)
    if tx >= 358 and tx <= 468 and
       ty >= CFG_BACK_Y - 17 and ty <= CFG_BACK_Y - 17 + CFG_RESET_H then
        resetHarrierDefaults()
        playTone(440, 200, 0, PLAY_NOW)
        return
    end

    -- Check +/- buttons for each row
    for i, p in ipairs(configParams) do
        local y = CFG_START_Y + (i - 1) * CFG_ROW_H
        local inRow = ty >= y and ty <= y + CFG_BTN_H

        if inRow then
            configSelected = i
            local val = thresholds[MODE_HARRIER][p.key]

            -- Minus
            if tx >= CFG_MINUS_X and tx <= CFG_MINUS_X + CFG_BTN_W then
                thresholds[MODE_HARRIER][p.key] = math.max(p.min, val - p.step)
                playTone(500, 50, 0, PLAY_NOW)
            end

            -- Plus
            if tx >= CFG_PLUS_X and tx <= CFG_PLUS_X + CFG_BTN_W then
                thresholds[MODE_HARRIER][p.key] = math.min(p.max, val + p.step)
                playTone(700, 50, 0, PLAY_NOW)
            end
        end
    end
end

----------------------------------------------------------
-- main
----------------------------------------------------------

local function run(event, touchState)

    lcd.clear()

    -- Config page (Harrier only)
    if configOpen then
        drawConfigPage()
        if event == EVT_TOUCH_FIRST and touchState then
            handleConfigTouch(touchState.x, touchState.y)
        end
        return 0
    end

    -- Mode toggle on touch (excluding Configure button area)
    if event == EVT_TOUCH_FIRST and touchState then
        local tx = touchState.x
        local ty = touchState.y
        if mode == MODE_HARRIER and touchInGear(tx, ty) then
            configOpen = true
            return 0
        end
        mode = (mode == MODE_HARRIER) and MODE_RIFLE or MODE_HARRIER
        resetState()
    end

    local step   = getStep(stepIndex)
    local result = evalMove(step)
    local active = (result == "correct")

    if mode == MODE_HARRIER then
        lcd.drawText(LCD_W/2, 2, "Jim's Rolling Harrier Trainer", DBLSIZE + CENTER)
    else
        lcd.drawText(LCD_W/2, 2, "Jim's Rifle Roll Trainer", DBLSIZE + CENTER)
    end

    drawRollText()

    local stepColor = waitForCenter and ORANGE or BLACK

    if waitForCenter then
        if centered() then
            waitForCenter = false
            stepColor = BLACK
        end
    end

    -- Draw step name: orange if waiting for center
    lcd.drawText(20, 88, step.name, DBLSIZE + stepColor)

    -- Show return-to-center hint while stick not yet centered
    if waitForCenter then
        local centerHint
        if centerHintCh == 2 then
            centerHint = "Return Elevator to Center"
        else
            centerHint = "Return Rudder to Center"
        end
        lcd.drawText(20, 128, centerHint, SMLSIZE + ORANGE)
    end

    -- If overlap not allowed and still waiting, block here
    if waitForCenter and not allowOverlap then
        if mode == MODE_HARRIER then drawGearButton() end
        drawProgress()
        drawStatusBox(true)
        return 0
    end

    if active then
        statusError = false
        errorLatch  = false
        errorFrames = 0
    elseif result == "overshoot" then
        if not errorLatch then
            playTone(300, 150, 0, PLAY_NOW)
            errorLatch = true
        end
        statusError = true
        rollStreak  = 0
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

    drawStatusBox(not statusError)

    if mode == MODE_HARRIER then drawGearButton() end
    drawProgress()

    if active and not stickWasActive then
        centerHintCh  = step.ch
        stepIndex     = stepIndex + 1
        waitForCenter = true
        statusError   = false

        if stepIndex > 4 then
            playTone(760, 85, 0, PLAY_NOW)
            stepIndex  = 1
            rollStreak = rollStreak + 1
        else
            playTone(750, 80, 0, PLAY_NOW)
        end
    end

    stickWasActive = active

    return 0
end

return { run=run }
