-- Jim's Rolling Harrier / Rifle Roll Trainer
-- place script into your SCRIPTS/TOOLS folder
-- Touching anywhere on your screen swaps between Rolling Harrier and Rifle Roll Mode
-- Rifle Roll mode has shorter throws for success and an overshoot means fail

----------------------------------------------------------
-- MODES
----------------------------------------------------------
local MODE_HARRIER = 1
local MODE_RIFLE   = 2
local mode = MODE_HARRIER

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

local function T()
    return thresholds[mode]
end

----------------------------------------------------------

local stepIndex = 1
local stickWasActive = false
local waitForCenter = false
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
        lcd.drawText(BOX_X + 4, BOX_Y + 4, tostring(rollStreak), SMLSIZE + BOLD + WHITE)
    end
end

----------------------------------------------------------
-- main
----------------------------------------------------------

local function run(event)

    lcd.clear()

    if event == EVT_TOUCH_FIRST then
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
    drawProgress()

    local stepColor = waitForCenter and ORANGE or BLACK

    if waitForCenter then
        if centered() then
            waitForCenter = false
            stepColor = BLACK
        end
        lcd.drawText(20, 88, step.name, DBLSIZE + stepColor)
        drawStatusBox(true)
        return 0
    end

    lcd.drawText(20, 88, step.name, DBLSIZE + BLACK)

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
    elseif anyWrongMove(step) then
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

    if active and not stickWasActive then
        stepIndex     = stepIndex + 1
        waitForCenter = true
        statusError   = false
        playTone(750, 80, 0, PLAY_NOW)

        if stepIndex > 4 then
            playTone(1200, 250, 0, PLAY_NOW)
            stepIndex  = 1
            rollStreak = rollStreak + 1
        end
    end

    stickWasActive = active

    return 0
end

return { run=run }
