-- ============================================================
-- CRANK RUNNER - A Chrome Dino-style game for Playdate
-- Crank to run, buttons to jump and duck!
-- ============================================================

-- ===========================================
-- SECTION 1: Imports & Constants
-- ===========================================
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/crank"
import "CoreLibs/ui"

local pd <const> = playdate
local gfx <const> = playdate.graphics

-- Screen
local SCREEN_W <const> = 400
local SCREEN_H <const> = 240
local GROUND_Y <const> = 200

-- Physics
local GRAVITY <const> = 1.2
local JUMP_VELOCITY <const> = -13
local FAST_FALL_GRAVITY <const> = 2.4

-- Crank / Speed
local MIN_CRANK_SPEED <const> = 3
local BASE_GAME_SPEED <const> = 3
local MAX_GAME_SPEED <const> = 12
local CRANK_SPEED_SCALE <const> = 0.12
local SPEED_SMOOTHING <const> = 0.15
local FRICTION <const> = 0.92

-- Dino position
local DINO_X <const> = 60

-- Scoring
local SCORE_MILESTONE <const> = 100

-- Day/Night
local DAY_NIGHT_INTERVAL <const> = 600

-- Obstacle spawning
local BASE_OBSTACLE_GAP <const> = 60

-- ===========================================
-- SECTION 2: Game State Variables
-- ===========================================
local game = {
    state = "title",
    speed = 0,
    rawCrankSpeed = 0,
    score = 0,
    highScore = 0,
    lastMilestone = 0,
    milestoneFlash = 0,
    isNight = false,
    nightTimer = DAY_NIGHT_INTERVAL,
    groundOffset = 0,
    shakeFrames = 0,
    restartDebounce = 0,
    obstacleTimer = 0,
    difficultyLevel = 0,
}

local dino = {
    sprite = nil,
    y = GROUND_Y,
    velocityY = 0,
    isJumping = false,
    isDucking = false,
    isDead = false,
    animFrame = 1,
    animCounter = 0,
}

local obstacles = {}
local clouds = {}

-- ===========================================
-- SECTION 3: Procedural Graphics
-- ===========================================

-- Dino images
local dinoRunImages = {}
local dinoDuckImages = {}
local dinoJumpImage = nil
local dinoDeadImage = nil
local dinoStandImage = nil

-- Dino dimensions
local DINO_W, DINO_H = 40, 44
local DUCK_W, DUCK_H = 56, 26

local function createDinoImages()
    -- Helper: draw the dino body (shared between frames)
    local function drawDinoBody(img, legOffset1, legOffset2)
        gfx.pushContext(img)
        gfx.setColor(gfx.kColorBlack)
        -- Body
        gfx.fillRect(8, 10, 22, 20)
        -- Head
        gfx.fillRect(18, 0, 20, 16)
        -- Eye (white dot)
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(30, 4, 4, 4)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(32, 4, 2, 2)
        -- Mouth
        gfx.drawLine(26, 12, 38, 12)
        -- Tail
        gfx.fillRect(2, 12, 8, 4)
        gfx.fillRect(0, 10, 4, 4)
        -- Arm
        gfx.fillRect(26, 22, 3, 8)
        gfx.fillRect(26, 28, 5, 2)
        -- Leg 1
        gfx.fillRect(12, 28, 4, legOffset1)
        gfx.fillRect(12, 28 + legOffset1 - 2, 6, 2)
        -- Leg 2
        gfx.fillRect(22, 28, 4, legOffset2)
        gfx.fillRect(22, 28 + legOffset2 - 2, 6, 2)
        gfx.popContext()
    end

    -- Running frame 1: left leg forward, right leg back
    dinoRunImages[1] = gfx.image.new(DINO_W, DINO_H, gfx.kColorClear)
    drawDinoBody(dinoRunImages[1], 16, 10)

    -- Running frame 2: opposite legs
    dinoRunImages[2] = gfx.image.new(DINO_W, DINO_H, gfx.kColorClear)
    drawDinoBody(dinoRunImages[2], 10, 16)

    -- Jump image: legs together, tucked
    dinoJumpImage = gfx.image.new(DINO_W, DINO_H, gfx.kColorClear)
    gfx.pushContext(dinoJumpImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(8, 10, 22, 20)
    gfx.fillRect(18, 0, 20, 16)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(30, 4, 4, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(32, 4, 2, 2)
    gfx.drawLine(26, 12, 38, 12)
    gfx.fillRect(2, 12, 8, 4)
    gfx.fillRect(0, 10, 4, 4)
    gfx.fillRect(26, 22, 3, 8)
    gfx.fillRect(26, 28, 5, 2)
    -- Both legs together, straight down
    gfx.fillRect(14, 28, 4, 14)
    gfx.fillRect(14, 40, 6, 2)
    gfx.fillRect(22, 28, 4, 14)
    gfx.fillRect(22, 40, 6, 2)
    gfx.popContext()

    -- Dead image: X eyes
    dinoDeadImage = gfx.image.new(DINO_W, DINO_H, gfx.kColorClear)
    gfx.pushContext(dinoDeadImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(8, 10, 22, 20)
    gfx.fillRect(18, 0, 20, 16)
    -- X for eye
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(29, 3, 6, 6)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(30, 4, 34, 8)
    gfx.drawLine(34, 4, 30, 8)
    -- Mouth open
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(26, 11, 12, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(26, 11, 12, 4)
    -- Tail
    gfx.fillRect(2, 12, 8, 4)
    gfx.fillRect(0, 10, 4, 4)
    -- Arm
    gfx.fillRect(26, 22, 3, 8)
    gfx.fillRect(26, 28, 5, 2)
    -- Legs straight
    gfx.fillRect(14, 28, 4, 14)
    gfx.fillRect(14, 40, 6, 2)
    gfx.fillRect(22, 28, 4, 14)
    gfx.fillRect(22, 40, 6, 2)
    gfx.popContext()

    -- Standing image (for title screen) — same as run frame 1
    dinoStandImage = dinoRunImages[1]

    -- Ducking frames
    for i = 1, 2 do
        dinoDuckImages[i] = gfx.image.new(DUCK_W, DUCK_H, gfx.kColorClear)
        gfx.pushContext(dinoDuckImages[i])
        gfx.setColor(gfx.kColorBlack)
        -- Flattened body
        gfx.fillRect(8, 2, 30, 14)
        -- Head stretched forward
        gfx.fillRect(36, 0, 18, 12)
        -- Eye
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(46, 2, 4, 4)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(48, 2, 2, 2)
        -- Mouth
        gfx.drawLine(42, 8, 54, 8)
        -- Tail
        gfx.fillRect(0, 4, 10, 4)
        -- Legs
        if i == 1 then
            gfx.fillRect(14, 14, 4, 12)
            gfx.fillRect(14, 24, 6, 2)
            gfx.fillRect(26, 14, 4, 8)
            gfx.fillRect(26, 20, 6, 2)
        else
            gfx.fillRect(14, 14, 4, 8)
            gfx.fillRect(14, 20, 6, 2)
            gfx.fillRect(26, 14, 4, 12)
            gfx.fillRect(26, 24, 6, 2)
        end
        gfx.popContext()
    end
end

-- Obstacle images
local smallCactusImage = nil
local mediumCactusImage = nil
local cactusClusterImage = nil
local pteroImages = {}

local SMALL_CACTUS_W, SMALL_CACTUS_H = 14, 28
local MEDIUM_CACTUS_W, MEDIUM_CACTUS_H = 18, 40
local CLUSTER_W, CLUSTER_H = 38, 28
local PTERO_W, PTERO_H = 38, 30

local function createObstacleImages()
    -- Small cactus
    smallCactusImage = gfx.image.new(SMALL_CACTUS_W, SMALL_CACTUS_H, gfx.kColorClear)
    gfx.pushContext(smallCactusImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(5, 0, 4, 28)
    -- Branches
    gfx.fillRect(0, 8, 5, 4)
    gfx.fillRect(0, 8, 4, 10)
    gfx.fillRect(9, 14, 5, 4)
    gfx.fillRect(10, 14, 4, 8)
    gfx.popContext()

    -- Medium cactus
    mediumCactusImage = gfx.image.new(MEDIUM_CACTUS_W, MEDIUM_CACTUS_H, gfx.kColorClear)
    gfx.pushContext(mediumCactusImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(7, 0, 5, 40)
    gfx.fillRect(0, 10, 7, 4)
    gfx.fillRect(0, 10, 4, 14)
    gfx.fillRect(12, 18, 6, 4)
    gfx.fillRect(14, 18, 4, 12)
    gfx.popContext()

    -- Cactus cluster
    cactusClusterImage = gfx.image.new(CLUSTER_W, CLUSTER_H, gfx.kColorClear)
    gfx.pushContext(cactusClusterImage)
    gfx.setColor(gfx.kColorBlack)
    -- Three cacti side by side
    for _, ox in ipairs({0, 12, 24}) do
        gfx.fillRect(ox + 5, 2, 4, 26)
        gfx.fillRect(ox, 10, 5, 3)
        gfx.fillRect(ox, 10, 3, 8)
        gfx.fillRect(ox + 9, 14, 5, 3)
        gfx.fillRect(ox + 10, 14, 3, 7)
    end
    gfx.popContext()

    -- Pterodactyl frames
    -- Body is centered at y=13 (middle of 30px height)
    -- Both frames share the same body; only wing position changes
    for i = 1, 2 do
        pteroImages[i] = gfx.image.new(PTERO_W, PTERO_H, gfx.kColorClear)
        gfx.pushContext(pteroImages[i])
        gfx.setColor(gfx.kColorBlack)
        -- Body (centered vertically at y=11, height=8)
        gfx.fillRect(4, 11, 28, 8)
        -- Head
        gfx.fillRect(2, 9, 8, 6)
        -- Beak
        gfx.fillRect(0, 12, 6, 3)
        -- Eye
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(4, 10, 2, 2)
        gfx.setColor(gfx.kColorBlack)
        -- Tail
        gfx.fillRect(30, 13, 8, 4)
        -- Wings
        if i == 1 then
            -- Wings up: extend above body
            gfx.fillRect(10, 4, 20, 3)
            gfx.fillRect(14, 1, 12, 3)
            -- Connect wing to body
            gfx.fillRect(12, 7, 18, 4)
        else
            -- Wings down: extend below body
            gfx.fillRect(10, 19, 20, 3)
            gfx.fillRect(14, 22, 12, 3)
            -- Connect wing to body
            gfx.fillRect(12, 19, 18, 2)
        end
        gfx.popContext()
    end
end

-- Cloud image
local cloudImage = nil

local function createCloudImage()
    cloudImage = gfx.image.new(36, 14, gfx.kColorClear)
    gfx.pushContext(cloudImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(0, 4, 36, 10, 4)
    gfx.fillRoundRect(8, 0, 20, 10, 4)
    gfx.popContext()
end

-- ===========================================
-- SECTION 4: Sound System
-- ===========================================
local jumpSynth = nil
local milestoneSynth1 = nil
local milestoneSynth2 = nil
local gameOverSynth = nil
local gameOverSynth2 = nil
local footstepSynth = nil

local function createSounds()
    jumpSynth = pd.sound.synth.new(pd.sound.kWaveSquare)
    jumpSynth:setADSR(0, 0.05, 0.3, 0.05)
    jumpSynth:setVolume(0.3)

    milestoneSynth1 = pd.sound.synth.new(pd.sound.kWaveTriangle)
    milestoneSynth1:setADSR(0, 0.02, 0.5, 0.05)
    milestoneSynth1:setVolume(0.3)

    milestoneSynth2 = pd.sound.synth.new(pd.sound.kWaveTriangle)
    milestoneSynth2:setADSR(0, 0.02, 0.5, 0.05)
    milestoneSynth2:setVolume(0.3)

    gameOverSynth = pd.sound.synth.new(pd.sound.kWaveNoise)
    gameOverSynth:setADSR(0, 0.15, 0.1, 0.2)
    gameOverSynth:setVolume(0.4)

    gameOverSynth2 = pd.sound.synth.new(pd.sound.kWaveSquare)
    gameOverSynth2:setADSR(0, 0.1, 0.2, 0.15)
    gameOverSynth2:setVolume(0.3)

    footstepSynth = pd.sound.synth.new(pd.sound.kWaveNoise)
    footstepSynth:setADSR(0, 0.01, 0, 0.01)
    footstepSynth:setVolume(0.1)
end

local function playJumpSound()
    jumpSynth:playNote(500, 0.3, 0.15)
end

local function playMilestoneSound()
    milestoneSynth1:playNote(800, 0.3, 0.08)
    pd.timer.new(80, function()
        milestoneSynth2:playNote(1200, 0.3, 0.12)
    end)
end

local function playGameOverSound()
    gameOverSynth:playNote(200, 0.4, 0.3)
    pd.timer.new(100, function()
        gameOverSynth2:playNote(300, 0.3, 0.15)
    end)
    pd.timer.new(250, function()
        gameOverSynth2:playNote(150, 0.3, 0.25)
    end)
end

local function playFootstep()
    footstepSynth:playNote(800, 0.1, 0.02)
end

-- ===========================================
-- SECTION 5: Player / Dino Logic
-- ===========================================

local function initDino()
    dino.sprite = gfx.sprite.new(dinoStandImage)
    dino.sprite:setCenter(0.5, 1.0) -- anchor at bottom center
    dino.sprite:moveTo(DINO_X, GROUND_Y)
    dino.sprite:setCollideRect(4, 4, DINO_W - 8, DINO_H - 6)
    dino.sprite:setZIndex(100)
    dino.sprite:add()
    dino.y = GROUND_Y
    dino.velocityY = 0
    dino.isJumping = false
    dino.isDucking = false
    dino.isDead = false
    dino.animFrame = 1
    dino.animCounter = 0
end

local function updateDinoAnimation()
    if dino.isDead or dino.isJumping or game.speed < 0.5 then
        return
    end

    dino.animCounter = dino.animCounter + 1
    local threshold = math.max(2, math.floor(10 / math.max(1, game.speed)))

    if dino.animCounter >= threshold then
        dino.animCounter = 0
        dino.animFrame = dino.animFrame == 1 and 2 or 1
        if dino.isDucking then
            dino.sprite:setImage(dinoDuckImages[dino.animFrame])
        else
            dino.sprite:setImage(dinoRunImages[dino.animFrame])
        end
    end
end

local function handleJump()
    if dino.isDead then return end

    -- Jump input
    if (pd.buttonJustPressed(pd.kButtonA) or pd.buttonJustPressed(pd.kButtonUp))
        and not dino.isJumping and not dino.isDucking then
        dino.velocityY = JUMP_VELOCITY
        dino.isJumping = true
        dino.sprite:setImage(dinoJumpImage)
        dino.sprite:setCollideRect(4, 4, DINO_W - 8, DINO_H - 6)
        playJumpSound()
    end

    -- Fast fall
    if dino.isJumping and (pd.buttonIsPressed(pd.kButtonB) or pd.buttonIsPressed(pd.kButtonDown)) then
        dino.velocityY = dino.velocityY + FAST_FALL_GRAVITY
    end

    -- Apply gravity
    if dino.isJumping then
        dino.velocityY = dino.velocityY + GRAVITY
        dino.y = dino.y + dino.velocityY

        if dino.y >= GROUND_Y then
            dino.y = GROUND_Y
            dino.velocityY = 0
            dino.isJumping = false
            dino.animFrame = 1
            dino.sprite:setImage(dinoRunImages[1])
            dino.sprite:setCollideRect(4, 4, DINO_W - 8, DINO_H - 6)
        end
    end

    dino.sprite:moveTo(DINO_X, dino.y)
end

local function handleDuck()
    if dino.isDead or dino.isJumping then return end

    local wantsDuck = pd.buttonIsPressed(pd.kButtonB) or pd.buttonIsPressed(pd.kButtonDown)

    if wantsDuck and not dino.isDucking then
        -- Start ducking
        dino.isDucking = true
        dino.animFrame = 1
        dino.sprite:setImage(dinoDuckImages[1])
        dino.sprite:setCollideRect(2, 2, DUCK_W - 4, DUCK_H - 4)
    elseif not wantsDuck and dino.isDucking then
        -- Stop ducking
        dino.isDucking = false
        dino.animFrame = 1
        dino.sprite:setImage(dinoRunImages[1])
        dino.sprite:setCollideRect(4, 4, DINO_W - 8, DINO_H - 6)
    end
end

-- ===========================================
-- SECTION 6: Obstacle System
-- ===========================================

local obstacleTypes = {
    {name = "small_cactus", image = nil, w = SMALL_CACTUS_W, h = SMALL_CACTUS_H, ground = true},
    {name = "medium_cactus", image = nil, w = MEDIUM_CACTUS_W, h = MEDIUM_CACTUS_H, ground = true},
    {name = "cactus_cluster", image = nil, w = CLUSTER_W, h = CLUSTER_H, ground = true},
    {name = "pterodactyl", image = nil, w = PTERO_W, h = PTERO_H, ground = false},
}

local function initObstacleTypes()
    obstacleTypes[1].image = smallCactusImage
    obstacleTypes[2].image = mediumCactusImage
    obstacleTypes[3].image = cactusClusterImage
    obstacleTypes[4].image = pteroImages[1]
end

local function spawnObstacle()
    -- Pick type based on difficulty
    local roll = math.random(100)
    local typeIndex
    local pteroChance = 0
    if game.score > 200 then
        pteroChance = math.min(25, 15 + game.difficultyLevel * 2)
    end

    if roll <= 40 - pteroChance / 3 then
        typeIndex = 1 -- small cactus
    elseif roll <= 65 - pteroChance / 3 then
        typeIndex = 2 -- medium cactus
    elseif roll <= 100 - pteroChance then
        typeIndex = 3 -- cluster
    else
        typeIndex = 4 -- pterodactyl
    end

    local otype = obstacleTypes[typeIndex]
    local sprite = gfx.sprite.new(otype.image)
    sprite:setCenter(0.5, 1.0)

    local yPos
    if otype.ground then
        yPos = GROUND_Y
    else
        -- Pterodactyl at two possible heights
        if math.random(2) == 1 then
            yPos = GROUND_Y - 30 -- low: must duck
        else
            yPos = GROUND_Y - 60 -- high: can run under
        end
    end

    sprite:moveTo(SCREEN_W + otype.w, yPos)
    sprite:setCollideRect(2, 2, otype.w - 4, otype.h - 4)
    sprite:setZIndex(50)
    sprite:add()

    table.insert(obstacles, {
        sprite = sprite,
        typeIndex = typeIndex,
        animFrame = 1,
        animCounter = 0,
    })
end

local function updateObstacles()
    if game.speed < 0.5 then return end

    -- Spawning
    game.obstacleTimer = game.obstacleTimer - 1
    if game.obstacleTimer <= 0 then
        spawnObstacle()
        local diffReduction = math.min(30, game.difficultyLevel * 5)
        local minGap = math.max(20, BASE_OBSTACLE_GAP - diffReduction)
        local maxGap = minGap + 30
        game.obstacleTimer = math.random(minGap, maxGap)
    end

    -- Move and animate
    local i = 1
    while i <= #obstacles do
        local obs = obstacles[i]
        local x, y = obs.sprite:getPosition()
        obs.sprite:moveBy(-game.speed, 0)

        -- Animate pterodactyl wings
        if obs.typeIndex == 4 then
            obs.animCounter = obs.animCounter + 1
            if obs.animCounter >= 8 then
                obs.animCounter = 0
                obs.animFrame = obs.animFrame == 1 and 2 or 1
                obs.sprite:setImage(pteroImages[obs.animFrame])
            end
        end

        -- Recycle off-screen
        if x < -50 then
            obs.sprite:remove()
            table.remove(obstacles, i)
        else
            i = i + 1
        end
    end
end

local function clearObstacles()
    for _, obs in ipairs(obstacles) do
        obs.sprite:remove()
    end
    obstacles = {}
end

-- ===========================================
-- SECTION 7: Ground / Terrain
-- ===========================================

local function initClouds()
    clouds = {
        {x = 50, y = 40},
        {x = 180, y = 60},
        {x = 320, y = 35},
    }
end

local function updateClouds()
    if game.speed < 0.5 then return end
    for _, c in ipairs(clouds) do
        c.x = c.x - game.speed * 0.3
        if c.x < -40 then
            c.x = SCREEN_W + math.random(20, 80)
            c.y = math.random(30, 70)
        end
    end
end

local groundPattern = {}
local function initGroundPattern()
    -- Pre-generate random-looking ground marks
    math.randomseed(42) -- deterministic so it looks consistent
    for i = 1, 20 do
        groundPattern[i] = {
            x = (i - 1) * 20 + math.random(0, 10),
            w = math.random(2, 6),
        }
    end
    math.randomseed(pd.getSecondsSinceEpoch())
end

local function setupBackground()
    gfx.sprite.setBackgroundDrawingCallback(function(x, y, w, h)
        gfx.setColor(gfx.kColorBlack)

        -- Ground line
        gfx.drawLine(0, GROUND_Y, SCREEN_W, GROUND_Y)

        -- Scrolling ground texture
        local offset = game.groundOffset % 400
        for _, mark in ipairs(groundPattern) do
            local mx = mark.x - offset
            if mx < -20 then mx = mx + 400 end
            if mx >= -10 and mx <= SCREEN_W + 10 then
                gfx.fillRect(mx, GROUND_Y + 4, mark.w, 1)
            end
            -- Second copy for seamless scrolling
            local mx2 = mx + 400
            if mx2 >= -10 and mx2 <= SCREEN_W + 10 then
                gfx.fillRect(mx2, GROUND_Y + 4, mark.w, 1)
            end
        end

        -- Ground detail bumps
        for i = 0, SCREEN_W, 30 do
            local bx = (i - offset % 30)
            if bx < 0 then bx = bx + SCREEN_W + 30 end
            if bx <= SCREEN_W then
                gfx.fillRect(bx, GROUND_Y + 2, 1, 1)
            end
        end

        -- Clouds
        for _, c in ipairs(clouds) do
            if cloudImage then
                cloudImage:draw(c.x, c.y)
            end
        end
    end)
end

-- ===========================================
-- SECTION 8: Scoring & Persistence
-- ===========================================

local function loadHighScore()
    local data = pd.datastore.read("highscore")
    if data and data.highScore then
        game.highScore = data.highScore
    end
end

local function saveHighScore()
    if game.score > game.highScore then
        game.highScore = math.floor(game.score)
        pd.datastore.write({highScore = game.highScore}, "highscore")
    end
end

local function formatScore(s)
    local n = math.floor(s)
    return string.format("%05d", n)
end

-- ===========================================
-- SECTION 9: Day/Night Cycle
-- ===========================================

local function updateDayNight()
    if game.speed < 0.5 then return end
    game.nightTimer = game.nightTimer - 1
    if game.nightTimer <= 0 then
        game.isNight = not game.isNight
        pd.display.setInverted(game.isNight)
        game.nightTimer = DAY_NIGHT_INTERVAL
    end
end

-- ===========================================
-- SECTION 10: Game State Management
-- ===========================================

local function resetGame()
    clearObstacles()
    if dino.sprite then
        dino.sprite:remove()
    end

    game.speed = 0
    game.rawCrankSpeed = 0
    game.score = 0
    game.lastMilestone = 0
    game.milestoneFlash = 0
    game.isNight = false
    game.nightTimer = DAY_NIGHT_INTERVAL
    game.groundOffset = 0
    game.shakeFrames = 0
    game.restartDebounce = 0
    game.obstacleTimer = BASE_OBSTACLE_GAP
    game.difficultyLevel = 0

    pd.display.setInverted(false)
    pd.display.setOffset(0, 0)

    initDino()
    initClouds()
end

local function triggerGameOver()
    game.state = "gameover"
    dino.isDead = true
    dino.sprite:setImage(dinoDeadImage)
    game.shakeFrames = 15
    game.restartDebounce = 30
    saveHighScore()
    playGameOverSound()
end

local function checkCollisions()
    local collisions = dino.sprite:overlappingSprites()
    if #collisions > 0 then
        triggerGameOver()
    end
end

-- Crank mechanic
local function updateCrankSpeed()
    local crankChange = pd.getCrankChange()
    local rawSpeed = math.abs(crankChange)

    game.rawCrankSpeed = game.rawCrankSpeed * (1 - SPEED_SMOOTHING) + rawSpeed * SPEED_SMOOTHING

    if game.rawCrankSpeed < MIN_CRANK_SPEED then
        game.speed = game.speed * FRICTION
        if game.speed < 0.5 then
            game.speed = 0
        end
    else
        local difficultyBonus = math.min(4, game.score / 500)
        local maxSpeed = MAX_GAME_SPEED + difficultyBonus
        local targetSpeed = BASE_GAME_SPEED + game.rawCrankSpeed * CRANK_SPEED_SCALE
        if targetSpeed > maxSpeed then targetSpeed = maxSpeed end
        game.speed = game.speed + (targetSpeed - game.speed) * 0.2
    end

    -- Footstep audio
    if game.speed > 0.5 and not dino.isJumping then
        local ticks = pd.getCrankTicks(8)
        if ticks ~= 0 then
            playFootstep()
        end
    end
end

-- Title state
local function updateTitle()
    gfx.sprite.update()

    -- Draw title
    gfx.drawTextAligned("*CRANK RUNNER*", SCREEN_W / 2, 50, kTextAlignment.center)
    gfx.drawTextAligned("Crank to run!", SCREEN_W / 2, 80, kTextAlignment.center)
    gfx.drawTextAligned("A/Up = Jump   B/Down = Duck", SCREEN_W / 2, 100, kTextAlignment.center)

    if game.highScore > 0 then
        gfx.drawTextAligned("HI " .. formatScore(game.highScore), SCREEN_W / 2, 130, kTextAlignment.center)
    end

    -- Crank indicator
    if pd.isCrankDocked() then
        pd.ui.crankIndicator:draw()
    end

    -- Start game on crank or A button
    local crankChange = math.abs(pd.getCrankChange())
    if crankChange > MIN_CRANK_SPEED or pd.buttonJustPressed(pd.kButtonA) then
        game.state = "playing"
        resetGame()
    end
end

-- Playing state
local function updatePlaying()
    updateCrankSpeed()
    handleJump()
    handleDuck()
    updateDinoAnimation()
    updateObstacles()
    updateClouds()

    -- Update ground scroll
    game.groundOffset = game.groundOffset + game.speed
    gfx.sprite.update()

    -- Check collisions after sprite update
    if not dino.isDead then
        checkCollisions()
    end

    -- Score
    if game.speed > 0.5 and not dino.isDead then
        local multiplier = math.max(1, game.speed / BASE_GAME_SPEED)
        game.score = game.score + game.speed * 0.05 * multiplier
        game.difficultyLevel = math.floor(game.score / 200)

        -- Milestones
        local currentMilestone = math.floor(game.score / SCORE_MILESTONE)
        if currentMilestone > game.lastMilestone then
            game.lastMilestone = currentMilestone
            game.milestoneFlash = 20
            playMilestoneSound()
        end
    end

    -- Day/night
    updateDayNight()

    -- Crank indicator when stopped
    if game.speed < 0.5 and pd.isCrankDocked() then
        pd.ui.crankIndicator:draw()
    end
end

-- Game over state
local function updateGameOver()
    -- Screen shake
    if game.shakeFrames > 0 then
        game.shakeFrames = game.shakeFrames - 1
        pd.display.setOffset(math.random(-3, 3), math.random(-2, 2))
        if game.shakeFrames == 0 then
            pd.display.setOffset(0, 0)
        end
    end

    gfx.sprite.update()

    -- Game over text
    gfx.drawTextAligned("*GAME OVER*", SCREEN_W / 2, 70, kTextAlignment.center)
    gfx.drawTextAligned("Score: " .. formatScore(game.score), SCREEN_W / 2, 95, kTextAlignment.center)
    if math.floor(game.score) >= game.highScore and game.highScore > 0 then
        gfx.drawTextAligned("NEW HIGH SCORE!", SCREEN_W / 2, 115, kTextAlignment.center)
    else
        gfx.drawTextAligned("HI " .. formatScore(game.highScore), SCREEN_W / 2, 115, kTextAlignment.center)
    end

    -- Restart prompt after debounce
    game.restartDebounce = game.restartDebounce - 1
    if game.restartDebounce <= 0 then
        gfx.drawTextAligned("Press A to restart", SCREEN_W / 2, 145, kTextAlignment.center)
        if pd.buttonJustPressed(pd.kButtonA) then
            game.state = "playing"
            resetGame()
        end
    end
end

-- ===========================================
-- SECTION 11: Draw UI Overlay
-- ===========================================

local function drawUI()
    if game.state == "playing" or game.state == "gameover" then
        -- Score display (top right)
        local showScore = true
        if game.milestoneFlash > 0 then
            game.milestoneFlash = game.milestoneFlash - 1
            -- Flash: hide score every other 4 frames
            if math.floor(game.milestoneFlash / 4) % 2 == 0 then
                showScore = false
            end
        end

        local scoreStr = formatScore(game.score)
        local hiStr = "HI " .. formatScore(game.highScore) .. "  "

        gfx.drawTextAligned(hiStr, SCREEN_W - 80, 10, kTextAlignment.right)
        if showScore then
            gfx.drawTextAligned(scoreStr, SCREEN_W - 10, 10, kTextAlignment.right)
        end

        -- Speed indicator (small bar, bottom left)
        if game.state == "playing" then
            local barW = math.floor(game.speed / (MAX_GAME_SPEED + 4) * 60)
            if barW > 0 then
                gfx.drawRect(10, SCREEN_H - 16, 62, 6)
                gfx.fillRect(11, SCREEN_H - 15, barW, 4)
            end
        end
    end
end

-- ===========================================
-- SECTION 12: Main Update Loop
-- ===========================================

function playdate.update()
    if game.state == "title" then
        updateTitle()
    elseif game.state == "playing" then
        updatePlaying()
    elseif game.state == "gameover" then
        updateGameOver()
    end

    -- UI overlay
    drawUI()

    -- Timers
    pd.timer.updateTimers()
end

-- ===========================================
-- Initialization
-- ===========================================

local function init()
    pd.display.setRefreshRate(30)
    createDinoImages()
    createObstacleImages()
    createCloudImage()
    createSounds()
    initObstacleTypes()
    initGroundPattern()
    initClouds()
    setupBackground()
    loadHighScore()

    -- Set up dino for title screen
    initDino()
end

init()
