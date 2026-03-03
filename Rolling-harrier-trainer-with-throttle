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
-- THRESHOLDS (per mode)
----------------------------------------------------------
local thresholds = {
    [MODE_HARRIER] = {
        rudder         = 450,
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
-- BALL STATE (harrier mode only)
----------------------------------------------------------
local BALL_ZONE_X     = 270
local BALL_ZONE_W     = 80
local BALL_ZONE_TOP   = 40
local BALL_ZONE_BOT   = 260
local BALL_R          = 16

local ballX   = BALL_ZONE_X + BALL_ZONE_W / 2
local ballY   = (BALL_ZONE_TOP + BALL_ZONE_BOT) / 2
local ballVY  = 0
local GRAVITY = 0.6

local ballFloorFlash = 0

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
    ballX          = BALL_ZONE_X + BALL_ZONE_W / 2
    ballY          = (BALL_ZONE_TOP + BALL_ZONE_BOT) / 2
    ballVY         = 0
    ballFloorFlash = 0
end

----------------------------------------------------------
-- ball physics
----------------------------------------------------------

local function updateBall()
    local throttle = get(3)
    local tNorm = (throttle + 1024) / 2048

    -- more responsive lift: hover at 45% throttle at center rudder
    local lift = tNorm * GRAVITY / 0.45 * 1.4

    -- rudder gravity: quadratic curve, gentle at low deflection steep at high
    -- max gravity capped at 2.0x so full throttle can always win at full rudder
    local rudFactor = math.abs(get(4)) / 600
    if rudFactor > 1.0 then rudFactor = 1.0 end
    local rudCurve = rudFactor * rudFactor
    local activeGravity = GRAVITY * (1.0 + rudCurve * 1.0)

    ballVY = ballVY + activeGravity - lift
    ballVY = ballVY * 0.88   -- less damping for snappier feel
    if ballVY >  16 then ballVY =  16 end
    if ballVY < -16 then ballVY = -16 end

    ballY = ballY + ballVY

    -- ceiling
    if ballY - BALL_R < BALL_ZONE_TOP then
        ballY  = BALL_ZONE_TOP + BALL_R
        ballVY = math.abs(ballVY) * 0.4
    end

    -- floor hit
    if ballY + BALL_R > BALL_ZONE_BOT then
        ballY          = BALL_ZONE_BOT - BALL_R
        ballVY         = -math.abs(ballVY) * 0.4
        ballFloorFlash = 8
    end

    if ballFloorFlash > 0 then
        ballFloorFlash = ballFloorFlash - 1
    end
end

local function drawBall()
    local zoneH = BALL_ZONE_BOT - BALL_ZONE_TOP

    -- target line at 1/3 from top
    local targetY = BALL_ZONE_TOP + math.floor(zoneH / 3)
    lcd.drawFilledRectangle(BALL_ZONE_X, targetY, BALL_ZONE_W, 2, BLACK)

    -- throttle bar on left edge
    local throttle = get(3)
    local tNorm    = (throttle + 1024) / 2048
    local tBarH    = math.floor(tNorm * zoneH)
    lcd.drawFilledRectangle(BALL_ZONE_X, BALL_ZONE_BOT - tBarH, 4, tBarH, BLUE)

    -- ball color gradient: green at target, red at edges
    local posNorm   = (ballY - BALL_ZONE_TOP) / zoneH
    local targetPos = 1.0 / 3.0
    local dist      = math.abs(posNorm - targetPos) / targetPos
    if dist > 1.0 then dist = 1.0 end
    local r = math.floor(dist * 255)
    local g = math.floor((1.0 - dist) * 255)
    local ballColor = lcd.RGB(r, g, 0)

    if ballFloorFlash > 0 then
        ballColor = RED
    end

    lcd.drawFilledCircle(math.floor(ballX), math.floor(ballY), BALL_R, ballColor)
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

    if mode == MODE_HARRIER then
        updateBall()
        drawBall()
    end

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
