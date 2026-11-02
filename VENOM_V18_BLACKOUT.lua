-- VENOM V18 | BLACKOUT | ALL-WORLD COMBAT | SHIELD OBJECTIVES | NATIVE TOOL CONTROL
-- V16: Halloween Tower / alternate combat mode uses a dedicated attack scheduler.
-- Some tower floors do NOT use EncounterController.StageState, so stage-only logic would pause.
-- Input fallback is local/client-side, rate limited, and may be blocked by the executor.
-- Attack outcomes remain controlled by the game server.
-- Fix: preserve both CFrame and Vector3 return values when detecting arena NPCs.
-- V10 occasionally crashed with "attempt to index nil with X" during enemy scan.
-- The server still controls damage and combat outcomes.
-- V13 FIRST STRIKE: proactive boss approach and faster opening attack attempts.
-- This does not bypass cooldown, prevent all hits, or change server-side damage.
-- V12 OVERDRIVE: frequent server-permitted strikes; adaptive range-aware evasions.
-- Target: https://www.roblox.com/games/116448925875915/1-Venom-Evolution
-- Copy this ENTIRE file into your client Lua runner while inside the game.
-- No downloads, keys, remote loaders, fake Wins, or invented server remotes.
-- Not tested in the live game. Server checks may reject movement/interactions.
-- V9 ARENA STABILITY: combat has priority over routine strafing in melee range.
-- V9 RANGED TARGETS: unknown fast small projectiles can be tracked cautiously.
-- V9 MOVEMENT: avoid rapid dodge/chase position tug-of-war with a short cooldown.
-- Game server still controls damage and attack validation.
--
-- AUTO TRAIN: finds SoundChamber models and their Pad parts in the live map.
-- Uses the player's Chambers ownership attribute and actual chamber multipliers.
-- Rechecks unlocks automatically. It never uses a manual bookmark for training.
-- Runtime interfaces are validated; live-game compatibility is still unverified.
-- AUTO FIGHTS: uses EncounterController/CombatController for repeat fights.
-- QUICK STRIKE: checks native cooldown frequently and prioritizes wounded enemies.
-- V6/V7 AUTO DODGE: earlier shot tracking, measured-tween projectiles, predictive evasive paths,
-- readable enemy attack wind-ups, evasive flanks, and low health retreat.
-- V6/V7 BOSS OFFENSE: finds untagged gun-boss rigs and advances during lateral evasion.
-- V9 ASCENSION STABILITY: progression tracker, level/Wins goals, fight/train scheduler,
-- adaptive repeat stages, evolution-ready UI button assistance and live diagnostics.
-- V7 FROST UI: brighter daylight blue/white palette, legible dark text, active tabs and toggles.
-- Client movement may be corrected by the server; there is no guaranteed immunity.
-- BOSS HUNTER: prioritizes stage bosses; recognizes tagged and model-based bosses.
-- No godmode/invulnerability: all player/enemy damage is server-authoritative.
-- Pauses speaker training, follows eligible stage enemies, and uses free Win pads.
-- ANTI-AFK: uses VirtualUser on idle; unavailable input permissions are reported.
-- PROMPTS: select the closest prompt while beside the exact one you want.
-- Repeat only works with enabled, nearby ProximityPrompts. Inspect its name first.
-- TOOL: equip a tool yourself; AUTO TOOL activates that equipped tool only.
-- All settings and the saved position last for the current execution only.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer
if not player then
    warn("VENOM needs a client Lua context.")
    return
end
local playerGui = player:WaitForChild("PlayerGui", 15)
if not playerGui then warn("VENOM: PlayerGui not ready; try again after loading.") return end

local GUI_NAME = "VENOM_V18"
-- Clean up earlier versions when a new version is executed.
for _, oldName in ipairs({"VENOM_VENOM_V1", GUI_NAME}) do
    local previous = playerGui:FindFirstChild(oldName)
    if previous then
        local shutdown = previous:FindFirstChild("Shutdown")
        if shutdown and shutdown:IsA("BindableEvent") then pcall(function() shutdown:Fire() end) end
        previous:Destroy()
    end
end

local TweenService = game:GetService("TweenService")
local running = true
local connections = {}
local state = {speed = false, jump = false, noclip = false, hold = false, tool = false, prompt = false, train = false, fight = true, afk = false, progress = false, tower = true}
local values = {speed = 32, jump = 80, interval = 2, stageLimit = 0, attackMs = 35, rushStep = 11, dodgeRange = 10, retreatHealth = 35, dodgeMs = 100, projectileRadius = 85, targetLevel = 0, targetWins = 0}
local savedSpot, chosenPrompt, activeTool, heldPrompt
local trainingArrived, trainingAttempted = false, false
local promptOwner, toolReleaseAt, promptReleaseAt
local lastReturn, lastTool, lastPrompt = -math.huge, 0, -math.huge
local virtualUser, afkInputs = nil, 0
local character, humanoid, root
local characterReadyAt = math.huge
local motionOriginals = setmetatable({}, {__mode = "k"})
local collisionOriginals = setmetatable({}, {__mode = "k"})
local parts = {}
local characterConnection
local refreshers = {}
local stopAll, cleanup, stopProgress
local progress = {
    strategy = "SMART", mode = "idle", detail = "Enable Evolution Autopilot",
    lastEvaluation = -math.huge, lastSwitch = -math.huge, modeStart = -math.huge,
    lastEvolutionCheck = -math.huge, evoAttempts = 0, autoEvolve = true,
    safeFarm = true, saferUntil = 0, failedStage = nil, safeStageCap = nil,
    winsEarned = 0, evolutionsObserved = 0, previousWins = nil,
    previousEvolutions = nil, previousLevel = nil, successRuns = 0,
    storedAdvance = nil, storedRepeat = nil, goalLevel = nil, goalWins = nil,
    goalSource = "Awaiting progress", lastNotice = -math.huge, latest = {},
    completedAt = nil, fallbackStart = 0, lastStatAt = -math.huge,
}
local native = {modules = {}, loading = {}, retryAt = {}, workers = {}, stations = {},
    scanAt = -math.huge, current = nil, departing = nil, waitUntil = 0, attempts = {}, detail = "Off"}
local stopNative, tickNative, loadNative, scanNative
local fight = {run = nil, waitUntil = 0, lastAttack = -math.huge, lastMove = -math.huge,
    detail = "Off", advance = true, repeatRuns = true, rapid = true, overdrive = true, adaptiveDodge = true, finishWeak = true, preemptive = true, windupCounter = true,
    attacks = 0, accepted = 0, defeats = 0, receiptConnection = nil,
    dodge = true, bosses = true, retreat = true, continuousAttack = true, ballistic = true, dodgeCount = 0, bossHits = 0,
    lastDodge = -math.huge, lastHealth = nil, lastHurtAt = -math.huge,
    lastDefensiveScan = -math.huge, lastBossScan = -math.huge,
    cachedBosses = {}, previousStage = nil, bossDetected = false,
    seenProjectiles = 0, healthLost = 0, lastRetreat = -math.huge,
    lastThreatInstance = nil, lastThreatAt = -math.huge, dodgeReason = "None", lastCombatReport = -math.huge,
    lastAttackTarget = nil, lastHitHealth = 0, lastHitAt = -math.huge, lastAggro = -math.huge,
    projectileHistory = setmetatable({}, {__mode = "k"}), stageNPCs = {}, stageNPCAt = -math.huge,
    lastCombatPhase = nil, lastCombatFolder = nil, lastCombatTarget = nil, lastCombatReach = 7,
    lastChaseAt = -math.huge, lastDodgeTo = nil, lastDodgeFrom = nil,
    lastDodgeVerifyAt = 0, dodgesCorrected = 0, shotsDodged = 0,
    lastAction = "Waiting", blockedGrounds = 0, targetSource = "none",
    attackWindowUntil = -math.huge, lastCriticalDodge = -math.huge,
    lastThreatClass = "None", suppressedStrafes = 0, deniedApproach = 0,
    hpConfirmedHits = 0, hpConfirmedBossHits = 0, hpDamageDealt = 0,
    attacksBlocked = 0, groundFallbacks = 0, chaseFallbacks = 0,
    attackStatus = "Awaiting a target", noDamageSince = 0,
    bossStall = 0, lastConfirmedDamageAt = -math.huge, projectileInterceptTime = 0,
    lastEnemyHp = nil, lastEnemyName = "None", lastStrikeProbe = -math.huge,
    strikeBusy = false, overdriveAttempts = 0, cooldownSkips = 0,
    lastCombatRangeAt = -math.huge, recentHitsAt = -math.huge,
    dodgedWithoutLeavingRange = 0, rangedDamageWindow = 0, damageWindowStarted = -math.huge,
    lastFirstStrike = -math.huge, lastPreemptMove = -math.huge, lastPreemptGoal = nil,
    firstStrikeRushes = 0, openingAttackRequests = 0, lastFirstStrikeStatus = "Waiting",
    lastTargetSeenAt = -math.huge, targetAges = setmetatable({}, {__mode = "k"}),
    lastCounterAt = -math.huge, lastFirstStrikeTarget = nil,
    allPortals = true, portalMode = "AUTO", selectedWorld = 0, knownWorlds = {}, lastWorldScan = -math.huge,
    lastPortalHop = -math.huge, portalStatus = "Idle", portalWorld = 0,
    mainTapFallback = true, mainFallbackAt = -math.huge, mainFallbackCount = 0,
    objective = nil, objectiveAt = -math.huge, objectiveHP = nil,
    objectiveName = "None", objectivesDamaged = 0, objectiveAttempts = 0,
    objectiveLastStrike = -math.huge, objectiveStatus = "Ready", objectiveAttackAt = -math.huge,
    combatTools = true, lastCombatTool = -math.huge, toolAttacks = 0, toolName = "None",
    autoShieldObjectives = true, lastWorldSeen = 0, worldResyncs = 0}
local tower = {
    detected = false, source = "Not in tower", checkAt = -math.huge,
    lastAttack = -math.huge, lastInput = -math.huge, lastScan = -math.huge,
    lastChase = -math.huge, lastTargetHealth = nil, lastDamageAt = -math.huge,
    nativeRequests = 0, inputRequests = 0, target = nil, status = "Ready",
    failedNative = 0, inputFallback = true, autoChase = true,
    attackPeriod = 0.07, inputPeriod = 0.22,
    autoDodge = true, predictProjectiles = true, counterWindups = true,
    lowHealthRetreat = true, bossPriority = true, quickFinisher = true,
    dodgeCooldown = 0.115, lastDodge = -math.huge, dodgeCount = 0,
    dodgeReason = "Idle", lastHealth = nil, lastHurtAt = -math.huge,
    lastSafeSpot = nil, lastDefenseStep = -math.huge,
    skippedFalseTower = 0, lastActiveMain = -math.huge,
}
local stopFight, tickFight, resetFightCharacter

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end

local function make(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    return object
end

-- BLACKOUT: deliberately high-contrast charcoal, cool-gray, ivory and pale emerald.
local color = {
    bg = Color3.fromRGB(22, 24, 29), deep = Color3.fromRGB(32, 35, 41),
    card = Color3.fromRGB(48, 52, 60), cardTint = Color3.fromRGB(39, 43, 51),
    muted = Color3.fromRGB(185, 194, 207), text = Color3.fromRGB(244, 247, 252),
    edge = Color3.fromRGB(90, 99, 111), on = Color3.fromRGB(140, 241, 183),
    accent = Color3.fromRGB(89, 100, 117), purple = Color3.fromRGB(62, 70, 83),
    danger = Color3.fromRGB(255, 128, 138), gold = Color3.fromRGB(202, 216, 228),
    active = Color3.fromRGB(33, 78, 57), activeTint = Color3.fromRGB(32, 63, 52),
    hud = Color3.fromRGB(42, 49, 58), section = Color3.fromRGB(38, 43, 51),
    dangerSurface = Color3.fromRGB(89, 44, 52), dangerTint = Color3.fromRGB(65, 37, 44),
}
local function round(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, object)
end
local function label(parent, text, size)
    return make("TextLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Text = text,
        Font = Enum.Font.Gotham, TextSize = size or 13, TextColor3 = color.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 34),
    }, parent)
end
local function button(parent, text, callback)
    local b = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = color.card,
        BorderSizePixel = 0, Text = text, TextColor3 = color.text,
        Font = Enum.Font.GothamSemibold, TextSize = 13, TextWrapped = true,
        AutoButtonColor = true,
    }, parent)
    round(b, 11)
    make("UIStroke", {Name = "Edge", Color = color.edge, Thickness = 1.15, Transparency = 0.02}, b)
    make("UIGradient", {
        Name = "FillGradient",
        Color = ColorSequence.new(color.card, color.cardTint), Rotation = 90,
    }, b)
    local baseline = b.Size
    connect(b.MouseEnter, function()
        if not running then return end
        pcall(function() TweenService:Create(b, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {BackgroundTransparency = 0.04}):Play() end)
    end)
    connect(b.MouseLeave, function()
        if not running then return end
        pcall(function() TweenService:Create(b, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {BackgroundTransparency = 0}):Play() end)
    end)
    if callback then
        connect(b.Activated, function()
            if not running then return end
            local ok, err = pcall(callback)
            if not ok then warn("VENOM button: " .. tostring(err)) end
            -- Small touch feedback; Roblox's button controls remain native and accessible.
            pcall(function()
                local stroke = b:FindFirstChild("Edge")
                if stroke then
                    stroke.Thickness = 2
                    TweenService:Create(stroke, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {Thickness = 1.15}):Play()
                end
            end)
        end)
    end
    return b
end
-- Theme states update visual gradients, not game logic or callback wiring.
local function recolorButton(b, top, bottom, outline, ink)
    local gradient = b:FindFirstChild("FillGradient")
    local whiteInk = ink.R > 0.95 and ink.G > 0.95 and ink.B > 0.95
    if gradient then
        gradient.Color = ColorSequence.new(top, bottom)
        gradient.Enabled = not whiteInk -- prevent tinting white labels on vivid tabs
    end
    b.BackgroundColor3 = whiteInk and top or bottom
    b.TextColor3 = ink
    local stroke = b:FindFirstChild("Edge")
    if stroke then stroke.Color = outline end
end

local gui = make("ScreenGui", {
    Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = false,
    DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local shutdown = make("BindableEvent", {Name = "Shutdown"}, gui)
local screen = make("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
}, gui)
local panel = make("Frame", {
    Size = UDim2.fromOffset(384, 575), Position = UDim2.fromOffset(20, 40),
    BackgroundColor3 = color.bg, BorderSizePixel = 0, ClipsDescendants = true,
}, screen)
round(panel, 17)
local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(430, 700)
panel.Size = UDim2.fromOffset(math.min(384, math.max(260, viewport.X - 22)),
    math.min(575, math.max(355, viewport.Y - 62)))
local panelDefaultPos = panel.Position
panel.Position = panelDefaultPos + UDim2.fromOffset(0, 18)
panel.BackgroundTransparency = 0.32
pcall(function()
    TweenService:Create(panel, TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = panelDefaultPos, BackgroundTransparency = 0,
    }):Play()
end)
make("UIStroke", {Color = color.accent, Thickness = 1.7, Transparency = 0.18}, panel)
make("UIGradient", {Color = ColorSequence.new(color.bg, color.deep), Rotation = 85}, panel)
local accentBar = make("Frame", {Size = UDim2.new(1, -28, 0, 3), Position = UDim2.fromOffset(14, 58),
    BorderSizePixel = 0, BackgroundColor3 = color.accent}, panel)
round(accentBar, 2)
make("UIGradient", {Color = ColorSequence.new(color.accent, color.purple), Rotation = 0}, accentBar)
local logoPlate = make("Frame", {
    Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(12, 9),
    BackgroundColor3 = color.accent, BorderSizePixel = 0,
}, panel)
round(logoPlate, 14)
make("UIStroke", {Color = color.edge, Thickness = 1.2, Transparency = 0.15}, logoPlate)
make("UIGradient", {Color = ColorSequence.new(color.accent, color.purple), Rotation = 45}, logoPlate)
make("TextLabel", {
    Size = UDim2.new(1, 0, 1, -8), Position = UDim2.fromOffset(0, 1),
    BackgroundTransparency = 1, Text = "V", Font = Enum.Font.GothamBlack,
    TextSize = 25, TextColor3 = Color3.fromRGB(247, 250, 253),
}, logoPlate)
make("TextLabel", {
    Size = UDim2.new(1, 0, 0, 11), Position = UDim2.new(0, 0, 1, -11),
    BackgroundTransparency = 1, Text = "VENOM", Font = Enum.Font.GothamBold,
    TextSize = 7, TextColor3 = Color3.fromRGB(255, 245, 223),
}, logoPlate)
local logoSpark = make("Frame", {
    Size = UDim2.fromOffset(7, 7), Position = UDim2.fromOffset(38, 1),
    BackgroundColor3 = color.on, BorderSizePixel = 0, Rotation = 45,
}, logoPlate)
round(logoSpark, 2)
-- Angular white fang accents make a standalone original emblem.
for _, side in ipairs({{6, -25}, {31, 25}}) do
    make("Frame", {Size = UDim2.fromOffset(9, 3), Position = UDim2.fromOffset(side[1], 8),
        Rotation = side[2], BackgroundColor3 = color.text, BorderSizePixel = 0}, logoPlate)
end
local dragHandle = make("TextLabel", {
    Size = UDim2.new(1, -154, 0, 28), Position = UDim2.fromOffset(67, 5),
    BackgroundTransparency = 1, Active = true, Text = "VENOM",
    Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = color.text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
local titleSub = make("TextLabel", {
    Size = UDim2.new(1, -154, 0, 18), Position = UDim2.fromOffset(67, 28),
    BackgroundTransparency = 1, Text = "V18  /  BLACKOUT  /  ALL WORLDS",
    Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = color.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
local minimize = button(panel, "-", function() panel.Visible = false end)
minimize.Size, minimize.Position = UDim2.fromOffset(30, 30), UDim2.new(1, -76, 0, 9)
recolorButton(minimize, color.card, color.cardTint, color.edge, color.text)
local close = button(panel, "X", function() cleanup() end)
close.Size, close.Position = UDim2.fromOffset(30, 30), UDim2.new(1, -40, 0, 9)
recolorButton(close, color.dangerSurface, color.dangerTint, color.danger, color.text)
local status = label(panel, "VENOM SYSTEM  /  Active combat scanner", 12)
status.Position, status.Size = UDim2.fromOffset(15, 56), UDim2.new(1, -30, 0, 44)
status.TextColor3 = color.muted
local hud = label(panel, "FIGHT OFF   |   WORLD --   |   DODGES 0", 11)
hud.Position, hud.Size = UDim2.fromOffset(16, 100), UDim2.new(1, -32, 0, 27)
hud.TextColor3 = color.text
hud.BackgroundTransparency = 0
hud.BackgroundColor3 = color.hud
hud.Font = Enum.Font.GothamBold
round(hud, 8)
make("UIPadding", {PaddingLeft = UDim.new(0, 10)}, hud)
make("UIStroke", {Color = color.edge, Transparency = 0.4, Thickness = 1}, hud)
local function notify(message)
    if running then status.Text = tostring(message) end
end
local scroll = make("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 174), Size = UDim2.new(1, -24, 1, -239),
    BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
    ScrollBarThickness = 5, ScrollBarImageColor3 = color.muted,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
make("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, scroll)
local layout = make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, scroll)
local nav = make("Frame", {Position = UDim2.fromOffset(12, 132), Size = UDim2.new(1, -24, 0, 33),
    BackgroundTransparency = 1, BorderSizePixel = 0}, panel)
local navLayout = make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6)}, nav)
local sectionMarkers = {}
local function jump(label)
    local marker = sectionMarkers[label]
    if marker then
        local y = marker.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
        scroll.CanvasPosition = Vector2.new(0, math.max(0, y))
    end
end
local navButtons = {}
local function markNav(active)
    for _, tab in ipairs(navButtons) do
        if tab.key == active then
            recolorButton(tab.button, color.accent, color.purple, color.accent, Color3.fromRGB(255, 255, 255))
        else
            recolorButton(tab.button, color.card, color.cardTint, color.edge, color.text)
        end
    end
end
for _, item in ipairs({{"EVOLVE", "EVOLUTION AUTOPILOT"}, {"FIGHT", "AUTO FIGHTS"}, {"WORLDS", "WORLD NAVIGATOR"}, {"DODGE", "PHANTOM DEFENSE"}, {"TRAIN", "AUTO TRAIN"}, {"TOOLS", "MOVEMENT"}}) do
    local navButton = button(nav, item[1], function()
        jump(item[2])
        markNav(item[1])
    end)
    navButton.Size = UDim2.new(1/6, -5, 1, 0)
    navButton.TextSize = 9
    navButtons[#navButtons + 1] = {key = item[1], button = navButton}
end
markNav("EVOLVE")
local order = 0
local function ordered(object)
    order = order + 1
    object.LayoutOrder = order
    return object
end
local function section(text)
    local l = ordered(label(scroll, "  / /  " .. text, 11))
    l.TextColor3, l.Size = color.on, UDim2.new(1, 0, 0, 32)
    l.BackgroundTransparency = 0
    l.BackgroundColor3 = color.section
    round(l, 8)
    l.Font = Enum.Font.GothamBold
    sectionMarkers[text] = l
    make("Frame", {BackgroundColor3 = color.accent, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 7), Size = UDim2.fromOffset(3, 15)}, l)
end
local function note(text)
    local l = ordered(label(scroll, text, 11))
    l.TextColor3, l.Size = color.muted, UDim2.new(1, 0, 0, 56)
end
local function refresh()
    for _, callback in ipairs(refreshers) do callback() end
end

local function endPrompt()
    if heldPrompt then pcall(function() heldPrompt:InputHoldEnd() end) end
    heldPrompt, promptReleaseAt, promptOwner = nil, nil, nil
end
local function endTool()
    if activeTool then pcall(function() activeTool:Deactivate() end) end
    activeTool, toolReleaseAt = nil, nil
end
local function endInteractions()
    endPrompt()
    endTool()
end
local function restoreMotion()
    for h, originals in pairs(motionOriginals) do
        for property, value in pairs(originals) do
            local controlled = (property == "WalkSpeed" and state.speed)
                or (property ~= "WalkSpeed" and state.jump)
            if not controlled then
                pcall(function() h[property] = value end)
                originals[property] = nil
            end
        end
    end
end
local function restoreCollisions()
    for part, value in pairs(collisionOriginals) do
        pcall(function() part.CanCollide = value end)
        collisionOriginals[part] = nil
    end
end
local function applyProperty(h, property, value)
    local originals = motionOriginals[h]
    if not originals then originals = {} motionOriginals[h] = originals end
    if originals[property] == nil then originals[property] = h[property] end
    if h[property] ~= value then h[property] = value end
end
local function alive()
    return character and character.Parent and humanoid and humanoid.Parent
        and humanoid.Health > 0 and root and root.Parent
        and os.clock() >= characterReadyAt
end

local function toggle(text, key, prerequisite)
    local b
    b = ordered(button(scroll, "", function()
        if (key == "train" or key == "fight") and state.progress and stopProgress then
            stopProgress() -- explicit manual override cancels the automatic schedule.
            if key == "train" and state.fight then state.fight = false stopFight() end
            if key == "fight" and state.train then state.train = false stopNative(true) end
        end
        if not state[key] and (state.train or state.fight) and (key == "speed" or key == "jump" or key == "tool") then
            notify("Stop Auto train and Auto fights before enabling other character controls.") return
        end
        if not state[key] and prerequisite and not prerequisite() then return end
        state[key] = not state[key]
        if not state[key] then
            if key == "noclip" then restoreCollisions() end
            if key == "tool" then endTool() end
            if key == "prompt" then endPrompt() end
            if key == "train" then
                if stopNative then stopNative(true) end
                trainingArrived, trainingAttempted = false, false
            end
            if key == "fight" and stopFight then stopFight() end
            restoreMotion()
        end
        refresh()
        notify(text .. (state[key] and " enabled." or " disabled."))
    end))
    refreshers[#refreshers + 1] = function()
        b.Text = (state[key] and "  ●  " or "  ○  ") .. text .. (state[key] and "   [ON]" or "   [OFF]")
        if state[key] then
            recolorButton(b, color.active, color.activeTint, color.on, color.on)
        else
            recolorButton(b, color.card, color.cardTint, color.edge, color.text)
        end
    end
end
local function stepper(text, key, low, high, step)
    local row = ordered(make("Frame", {
        Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = color.card, BorderSizePixel = 0,
    }, scroll))
    round(row, 10)
    make("UIStroke", {Color = color.edge, Thickness = 1, Transparency = 0.25}, row)
    local l = label(row, "", 12)
    l.Position, l.Size = UDim2.fromOffset(10, 0), UDim2.new(1, -102, 1, 0)
    local function update() l.Text = text .. ": " .. tostring(values[key]) end
    local minus = button(row, "-", function() values[key] = math.max(low, values[key] - step) update() end)
    minus.Position, minus.Size = UDim2.new(1, -82, 0, 4), UDim2.fromOffset(34, 32)
    local plus = button(row, "+", function() values[key] = math.min(high, values[key] + step) update() end)
    plus.Position, plus.Size = UDim2.new(1, -42, 0, 4), UDim2.fromOffset(34, 32)
    update()
end

local function returnToSpot()
    if state.train or state.fight then notify("Stop Auto train and Auto fights before using a manual bookmark.") return false end
    if not savedSpot then notify("Stand at a training machine and save a spot first.") return false end
    if not alive() then notify("Waiting for your character to finish spawning.") return false end
    character:PivotTo(savedSpot)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end
local function promptPosition(prompt)
    if not prompt or not prompt.Parent then return nil end
    local parent = prompt.Parent
    if parent:IsA("Attachment") then return parent.WorldPosition end
    if parent:IsA("BasePart") then return parent.Position end
    if parent:IsA("Model") then return parent:GetPivot().Position end
    return nil
end
local function promptUsable()
    if not alive() or not chosenPrompt or not chosenPrompt:IsDescendantOf(workspace)
        or not chosenPrompt.Enabled then return false end
    local position = promptPosition(chosenPrompt)
    return position and (position - root.Position).Magnitude <= chosenPrompt.MaxActivationDistance
end

-- Native speaker integration. No guessed coordinates or reward RemoteEvents.
local function atPath(object, path)
    for _, name in ipairs(path) do
        object = object and object:FindFirstChild(name)
        if not object then return nil end
    end
    return object
end
local function number(value)
    value = tonumber(value)
    if value and value == value and math.abs(value) < math.huge then return value end
end
-- V17: a remembered Floor overlay must never disable ordinary stage combat.
-- Main-world active stages take priority; a hidden ancestor GUI is not an
-- active tower indicator. Explicit Tower attribute is still respected when
-- there is no simultaneous native stage encounter.
tower.active = function(now)
    now = now or os.clock()
    if now - tower.checkAt < 0.20 then return tower.detected end
    tower.checkAt = now
    local isMainStage = false
    local currentEncounter = native.modules.encounter
    if type(currentEncounter) == "table" and type(currentEncounter.Active) == "function" then
        local ok, stage = pcall(currentEncounter.Active, currentEncounter)
        if ok and tonumber(stage) and tonumber(stage) > 0 then isMainStage = true end
    end
    local fightingStage = tonumber(player:GetAttribute("Fighting"))
    if fightingStage and fightingStage > 0 then isMainStage = true end
    if isMainStage then
        tower.detected, tower.source = false, "Active normal stage wins over Tower overlay"
        tower.lastActiveMain = now
        tower.skippedFalseTower = tower.skippedFalseTower + 1
        return false
    end
    for _, key in ipairs({"Tower", "TowerFloor", "ActiveTower", "DungeonFloor"}) do
        local value = player:GetAttribute(key)
        if value ~= nil and value ~= false and value ~= 0 and value ~= "" then
            tower.detected, tower.source = true, "Tower attribute: " .. key
            return true
        end
    end
    -- Check all GUI ancestors, not only the TextLabel Visible property.
    local function reallyVisible(item)
        local ancestor = item
        while ancestor and ancestor ~= playerGui do
            if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
            if ancestor:IsA("ScreenGui") and not ancestor.Enabled then return false end
            ancestor = ancestor.Parent
        end
        return true
    end
    for _, item in ipairs(playerGui:GetDescendants()) do
        if item:IsA("TextLabel") and reallyVisible(item) and type(item.Text) == "string" then
            local msg = item.Text:upper()
            if msg:match("^%s*FLOOR%s*%d+") or msg:find("TOWER TICKET USED", 1, true) then
                tower.detected, tower.source = true, "Visible Tower floor UI"
                return true
            end
        end
    end
    tower.detected, tower.source = false, "Normal world"
    return false
end
local function nativeCall(object, method, selfCall, ...)
    if type(object) ~= "table" or type(object[method]) ~= "function" then return nil end
    local ok, result
    if selfCall then ok, result = pcall(object[method], object, ...)
    else ok, result = pcall(object[method], ...) end
    if ok then return result end
end
loadNative = function()
    if game.GameId ~= 10769464063 then return end
    local paths = {
        config = {ReplicatedStorage, {"Shared", "Config", "Training"}},
        maps = {ReplicatedStorage, {"Shared", "Maps"}},
        training = {player, {"PlayerScripts", "Client", "Controllers", "TrainingController"}},
        data = {player, {"PlayerScripts", "Client", "Controllers", "DataController"}},
        evolutionConfig = {ReplicatedStorage, {"Shared", "Config", "Evolutions"}},
        -- World metadata is needed by the selector even before Auto Fights is enabled.
        stages = {ReplicatedStorage, {"Shared", "Config", "Stages"}},
        encounters = {ReplicatedStorage, {"Shared", "Config", "Encounters"}},
    }
    if state.fight or (state.tower and tower.active()) then
        paths.encounter = {player, {"PlayerScripts", "Client", "Controllers", "EncounterController"}}
        paths.combat = {player, {"PlayerScripts", "Client", "Controllers", "CombatController"}}
        paths.combatConfig = {ReplicatedStorage, {"Shared", "Config", "Combat"}}
    end
    for key, spec in pairs(paths) do
        if not native.modules[key] and not native.loading[key] and os.clock() >= (native.retryAt[key] or 0) then
            local module = atPath(spec[1], spec[2])
            native.retryAt[key] = os.clock() + 10
            if module and module:IsA("ModuleScript") then
                native.loading[key] = true
                native.workers[#native.workers + 1] = task.spawn(function()
                    local ok, result = pcall(require, module)
                    if not running then return end
                    native.loading[key] = nil
                    if ok and type(result) == "table" then
                        native.modules[key] = result
                        native.scanAt = -math.huge
                    end
                end)
            end
        end
    end
end
local function readVenom()
    return number(nativeCall(native.modules.data, "Get", true, "Venom"))
        or number(player:GetAttribute("Venom"))
        or number(player:GetAttribute("TotalVenom"))
end
local function nativeActive()
    local value = nativeCall(native.modules.training, "Active", true)
    if type(value) == "boolean" then return value end
end
local function ownedChambers()
    local owned = {[1] = true}
    local raw = player:GetAttribute("Chambers")
    if type(raw) == "string" and #raw <= 8192 then
        for token in raw:gmatch("%d+") do
            local index = tonumber(token)
            if index and index >= 1 and index <= 10000 then owned[index] = true end
        end
    end
    return owned
end
local function chamberMultiplier(model, index)
    local config = native.modules.config
    local entry = config and type(config.Chambers) == "table" and config.Chambers[index]
    local mult = type(entry) == "table" and number(entry.mult)
    if config and type(config.Heaven) == "table" and config.Heaven.Index == index then
        mult = number(nativeCall(config, "HeavenMult", false)) or mult
    end
    if not mult then
        for _, item in ipairs(model:GetDescendants()) do
            if item:IsA("TextLabel") or item:IsA("TextButton") then
                local text = item.Text:gsub("<[^>]->", ""):gsub("×", "x"):lower()
                mult = number(text:match("x%s*(%d+%.?%d*)%s*venom"))
                if mult then break end
            end
        end
    end
    if not mult and index == 1 then mult = 1 end
    return mult, type(entry) == "table" and tostring(entry.name or model.Name) or model.Name
end
scanNative = function()
    local ok, models = pcall(function() return CollectionService:GetTagged("SoundChamber") end)
    if not ok or type(models) ~= "table" then models = {} end
    if #models == 0 then
        for _, item in ipairs(workspace:GetDescendants()) do
            if item:IsA("Model") and number(item:GetAttribute("Chamber")) and item:FindFirstChild("Pad") then
                models[#models + 1] = item
            end
        end
    end
    local stations = {}
    for _, model in ipairs(models) do
        if model:IsA("Model") and model:IsDescendantOf(workspace) then
            local index, pad = number(model:GetAttribute("Chamber")), model:FindFirstChild("Pad")
            if index and index >= 1 and index % 1 == 0 and pad and pad:IsA("BasePart") then
                local mult, name = chamberMultiplier(model, index)
                stations[#stations + 1] = {index = index, pad = pad, model = model, mult = mult, name = name,
                    world = number(nativeCall(native.modules.maps, "WorldAt", false, pad.Position))
                        or number(model:GetAttribute("World"))}
            end
        end
    end
    native.stations, native.scanAt = stations, os.clock()
    return stations
end
local function bestNative()
    local owned, best, bestDistance = ownedChambers(), nil, math.huge
    local world = number(nativeCall(native.modules.maps, "WorldAt", false, root.Position))
        or number(player:GetAttribute("World"))
    for _, station in ipairs(native.stations) do
        if station.pad:IsDescendantOf(workspace) and owned[station.index] and station.mult and station.mult > 0 then
            local distance = (station.pad.Position - root.Position).Magnitude
            local sameWorld = world and station.world and world == station.world
                or (not (world and station.world) and distance < 600)
            if sameWorld and (not best or station.mult > best.mult
                or (station.mult == best.mult and distance < bestDistance)) then
                best, bestDistance = station, distance
            end
        end
    end
    return best
end
local function trainingNotice(message)
    if native.detail ~= message then native.detail = message notify(message) end
end
local function padHeight(pad)
    local cf, size = pad.CFrame, pad.Size
    return (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y
        + math.abs(cf.LookVector.Y) * size.Z) * 0.5
end
local function moveRoot(position)
    root.CFrame = CFrame.new(position) * root.CFrame.Rotation
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
end
local function stepOff(record)
    if not record or not record.pad.Parent or not alive() then return end
    local pad = record.pad
    local radius = math.max(pad.Size.X, pad.Size.Y, pad.Size.Z) * 0.5 + 8
    local y = pad.Position.Y + padHeight(pad) + humanoid.HipHeight + root.Size.Y * 0.5 + 0.2
    local exitPosition, bestClearance = nil, -math.huge
    for _, direction in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        local position = Vector3.new(pad.Position.X + direction[1] * radius, y, pad.Position.Z + direction[2] * radius)
        local clearance = math.huge
        for _, station in ipairs(native.stations) do
            if station.pad.Parent then
                local dx, dz = position.X - station.pad.Position.X, position.Z - station.pad.Position.Z
                local width = math.max(station.pad.Size.X, station.pad.Size.Y, station.pad.Size.Z) * 0.5
                clearance = math.min(clearance, math.sqrt(dx * dx + dz * dz) - width)
            end
        end
        if clearance > bestClearance then exitPosition, bestClearance = position, clearance end
    end
    if exitPosition then moveRoot(exitPosition) end
end
stopNative = function(exitPad)
    if exitPad and native.current and native.current.character == character then
        stepOff(native.current.station)
    end
    native.current, native.departing = nil, nil
    native.waitUntil, native.attempts, native.detail = 0, {}, "Off"
end
local function leaveNative(now)
    local record = native.current
    stepOff(record and record.station)
    native.current, native.departing, native.waitUntil = nil, now, now + 1
end
tickNative = function(now)
    loadNative()
    if now - native.scanAt >= 2 then scanNative() end
    if player:GetAttribute("Fighting") ~= nil or player:GetAttribute("Tower") ~= nil
        or playerGui:FindFirstChild("IntroCutscene") or playerGui:FindFirstChild("GooCutscene") then
        trainingNotice("Auto train paused during combat or a cutscene.") return
    end
    local best = bestNative()
    if not best then
        trainingNotice("No owned speaker pad detected in this world. Rescan or open diagnostics.") return
    end
    local active = nativeActive()
    local current = native.current
    if native.departing then
        if now < native.waitUntil then return end
        if active == true then
            if now - native.departing > 5 then
                state.train = false stopNative(false) refresh()
                notify("The previous speaker did not release. Open diagnostics.")
            end
            return
        end
        native.departing = nil
    end
    if current and current.station.pad ~= best.pad then
        trainingNotice("Switching to x" .. tostring(best.mult) .. " " .. best.name)
        leaveNative(now) return
    end
    if not current then
        if active == true then
            local closest, distance
            for _, station in ipairs(native.stations) do
                local d = (station.pad.Position - root.Position).Magnitude
                if not distance or d < distance then closest, distance = station, d end
            end
            if closest and distance < 30 then
                native.current = {station = closest, character = character, entered = now, confirmed = true}
                return
            end
            trainingNotice("Finish the current training session before changing speakers.") return
        end
        if now < native.waitUntil then return end
        if not ownedChambers()[best.index] then native.scanAt = -math.huge return end
        local y = padHeight(best.pad) + humanoid.HipHeight + root.Size.Y * 0.5 + 0.2
        moveRoot(best.pad.Position + Vector3.new(0, y, 0))
        native.attempts[best.pad] = (native.attempts[best.pad] or 0) + 1
        native.current = {station = best, character = character, entered = now, venom = readVenom(),
            level = number(player:GetAttribute("Level")), confirmed = false}
        trainingNotice("Entering x" .. tostring(best.mult) .. " " .. best.name .. "; awaiting training confirmation.")
        return
    end
    local venom, level = readVenom(), number(player:GetAttribute("Level"))
    if active == true or (venom and current.venom and venom > current.venom)
        or (level and current.level and level > current.level) then
        current.confirmed = true
        native.attempts[best.pad] = 0
        trainingNotice("Training: x" .. tostring(best.mult) .. " " .. best.name .. " | Level " .. tostring(level or "?"))
    end
    if current.confirmed then
        if active == false and now - current.entered > 2 then leaveNative(now) end
    elseif now - current.entered > 12 then
        if (native.attempts[best.pad] or 0) >= 3 then
            state.train = false stopNative(false) refresh()
            notify("Could not confirm training after 3 attempts. Open diagnostics and copy the report.")
        else leaveNative(now) end
    end
end

-- Normal stage combat through the game's own client controllers.
local function fightCall(object, method, selfCall, ...)
    if type(object) ~= "table" or type(object[method]) ~= "function" then return false end
    if selfCall then return pcall(object[method], object, ...) end
    return pcall(object[method], ...)
end
local function fightNotice(message)
    if fight.detail ~= message then fight.detail = message notify(message) end
end
stopFight = function()
    fight.run, fight.waitUntil, fight.detail = nil, 0, "Off"
    fight.releasingTraining, fight.releaseStartedAt = false, nil
    fight.lastHealth, fight.lastHurtAt, fight.cachedBosses = nil, -math.huge, {}
    fight.lastThreatInstance, fight.lastThreatAt, fight.dodgeReason = nil, -math.huge, "None"
    fight.lastCombatPhase, fight.lastCombatFolder, fight.lastCombatTarget = nil, nil, nil
    fight.strikeBusy, fight.lastStrikeProbe = false, -math.huge
    fight.lastPreemptMove, fight.lastFirstStrike = -math.huge, -math.huge
    fight.lastFirstStrikeTarget, fight.lastPreemptGoal = nil, nil
    fight.lastDodgeTo, fight.lastDodgeFrom = nil, nil
    fight.projectileHistory = setmetatable({}, {__mode = "k"})
end
resetFightCharacter = function()
    local lastFightStage = fight.run and fight.run.stage
    if state.fight and fight.run and not fight.run.won then fight.defeats = fight.defeats + 1 end
    fight.run, fight.waitUntil = nil, os.clock() + 5
    fight.releasingTraining, fight.releaseStartedAt = false, nil
    fight.lastHealth, fight.lastHurtAt = nil, -math.huge
    if state.progress and progress.safeFarm then
        local failed = lastFightStage
        if failed then
            progress.failedStage = failed
            progress.levelAtFail = number(player:GetAttribute("Level"))
            progress.safeStageCap = math.max(1, failed - 1)
        end
        if fight.defeats >= 2 then
            progress.saferUntil = os.clock() + 35
            progress.mode = "train"
            progress.detail = "Combat losses: train 35s, then retry easier stages."
        end
    end
    if state.fight and fight.defeats >= 3 then
        state.fight = false refresh()
        notify("Auto fights paused after 3 defeats; Evolution Autopilot can resume training.")
    end
end
local function fightModulesReady()
    local m = native.modules
    return type(m.encounter) == "table" and type(m.encounter.Active) == "function"
        and type(m.encounter.StageState) == "function" and type(m.encounter.Brain) == "function"
        and type(m.combat) == "table" and type(m.combat.Attack) == "function" and type(m.combat.Busy) == "function"
        and type(m.stages) == "table" and type(m.stages.List) == "table" and type(m.stages.Advice) == "function"
        and type(m.encounters) == "table" and type(m.encounters.Stages) == "table"
        and type(m.maps) == "table" and type(m.maps.StageFolder) == "function"
end
local function fightReceipt()
    if fight.receiptConnection then return end
    local remote = atPath(ReplicatedStorage, {"Remotes", "Encounter"})
    if remote and remote:IsA("RemoteEvent") then
        fight.receiptConnection = connect(remote.OnClientEvent, function(kind, stage)
            local run = fight.run
            if running and state.fight and run and run.claimedAt and kind == "Won" and number(stage) == run.stage then
                run.won = true
            end
        end)
    end
end
local function stageWorld(stage)
    return number(nativeCall(native.modules.maps, "WorldOfStage", false, stage))
end
local function currentWorld()
    return number(nativeCall(native.modules.maps, "WorldAt", false, root and root.Position))
        or number(player:GetAttribute("World"))
end
local function worldReleased(world)
    local maps = native.modules.maps
    if not world then return false end
    if type(maps.Released) == "function" then
        return nativeCall(maps, "Released", false, world) == true
    end
    return true
end
local function stageAvailable(stage, ignoreWorld)
    local m = native.modules
    if not m.stages.List[stage] or not m.encounters.Stages[stage] then return false end
    local world = stageWorld(stage)
    local liveWorld = currentWorld()
    if not world or (not ignoreWorld and liveWorld and world ~= liveWorld) then return false end
    if not worldReleased(world) then return false end
    if world > 1 then
        local best = number(nativeCall(m.data, "Get", true, "BestStage"))
        nativeCall(m.maps, "Open", false, player, world, best)
    end
    if player:GetAttribute("AllStages") == true then return true end
    if stage == 1 then
        return (number(player:GetAttribute("BondStage")) or 0) >= (number(m.encounters.Stage1Form) or 1)
    end
    if world > 1 and type(m.maps.FirstStage) == "table" and m.maps.FirstStage[world] == stage then return true end
    local ready = player:GetAttribute("WinReady")
    return type(ready) == "string" and ready:find("," .. tostring(stage - 1) .. ",", 1, true) ~= nil
end
-- WORLD NAVIGATOR V15: read available worlds from the game's own stage/map tables.
-- Never invent portal coordinates or trigger an unrelated portal by name alone.
local function discoveredWorlds(force)
    local now = os.clock()
    if not force and now - fight.lastWorldScan < 5 and #fight.knownWorlds > 0 then
        return fight.knownWorlds
    end
    fight.lastWorldScan = now
    local seen, result = {}, {}
    local stages = native.modules.stages
    if type(stages) == "table" and type(stages.List) == "table" then
        for stage in pairs(stages.List) do
            if type(stage) == "number" then
                local world = stageWorld(stage)
                if world and world >= 1 and world <= 30 and not seen[world] then
                    seen[world] = true
                    result[#result + 1] = world
                end
            end
        end
    end
    local maps = native.modules.maps
    if type(maps) == "table" and type(maps.FirstStage) == "table" then
        for world in pairs(maps.FirstStage) do
            if type(world) == "number" and world >= 1 and world <= 30 and not seen[world] then
                seen[world] = true
                result[#result + 1] = world
            end
        end
    end
    local here = currentWorld()
    if here and here >= 1 and not seen[here] then result[#result + 1] = here end
    table.sort(result)
    fight.knownWorlds = result
    if fight.selectedWorld == 0 then fight.selectedWorld = here or result[1] or 1 end
    return result
end
local function portalWorldLabel(instance)
    local node = instance
    local contextIsPortal = false
    for _ = 1, 4 do
        if not node then break end
        local str = node.Name:lower()
        if str:find("portal", 1, true) or str:find("teleport", 1, true)
            or str:find("gateway", 1, true) or str:find("worldgate", 1, true) then
            contextIsPortal = true
        end
        -- Destination-specific attributes can identify a portal even if its name is generic.
        local destination = number(node:GetAttribute("PortalWorld"))
            or number(node:GetAttribute("TargetWorld"))
            or number(node:GetAttribute("DestinationWorld"))
        if destination then return destination end
        if contextIsPortal then
            local world = number(node:GetAttribute("World"))
            local named = tonumber(str:match("world[%s_%-]*(%d+)"))
                or tonumber(str:match("w[%s_%-]*(%d+)%s*portal"))
            if world or named then return world or named end
        end
        node = node.Parent
    end
    return nil
end
local function portalCandidate(instance, targetWorld)
    if not instance or not instance.Parent then return false end
    local declared = portalWorldLabel(instance)
    if declared and declared == targetWorld then return true end
    if declared then return false end
    if instance:IsA("ProximityPrompt") then
        local str = ((instance.ActionText or "") .. " " .. (instance.ObjectText or "")):lower()
        local n = tonumber(str:match("world[%s_%-]*(%d+)"))
        return n == targetWorld
    end
    return false
end
local function travelToWorld(targetWorld, now)
    if not alive() then fight.portalStatus = "Waiting for character" return false end
    local live = currentWorld()
    if not targetWorld or live == targetWorld then
        fight.portalWorld, fight.portalStatus = live or 0, "World ready"
        return true
    end
    if not worldReleased(targetWorld) then
        fight.portalStatus = "World " .. tostring(targetWorld) .. " not released"
        return false
    end
    local timestamp = now or os.clock()
    if timestamp - (fight.lastPortalHop or -math.huge) < 2.0 then return false end
    fight.lastPortalHop, fight.portalWorld = timestamp, targetWorld
    local bestStage = number(nativeCall(native.modules.data, "Get", true, "BestStage"))
    if type(native.modules.maps.Open) == "function"
        and nativeCall(native.modules.maps, "Open", false, player, targetWorld, bestStage) ~= true then
        fight.portalStatus = "World " .. tostring(targetWorld) .. " remains locked"
        return false
    end
    local closest, distance, prompt
    for _, item in ipairs(workspace:GetDescendants()) do
        if item:IsA("ProximityPrompt") and item.Enabled and portalCandidate(item, targetWorld) then
            local pos = promptPosition(item)
            if pos then
                local dist = (pos - root.Position).Magnitude
                if not distance or dist < distance then closest, distance, prompt = pos, dist, item end
            end
        end
    end
    if prompt and closest then
        if distance > prompt.MaxActivationDistance - 1 then
            moveRoot(closest + Vector3.new(0, 2.5, 0))
        end
        if (root.Position - closest).Magnitude <= prompt.MaxActivationDistance then
            if heldPrompt and heldPrompt ~= prompt then endPrompt() end
            heldPrompt, promptOwner = prompt, "portal"
            local ok = pcall(function() prompt:InputHoldBegin() end)
            if ok then
                promptReleaseAt = timestamp + math.max(0, prompt.HoldDuration) + 0.15
                fight.portalStatus = "Activating world " .. tostring(targetWorld) .. " portal"
            else
                fight.portalStatus = "Portal interaction was rejected"
            end
        else
            fight.portalStatus = "Approaching world " .. tostring(targetWorld) .. " portal"
        end
        return false
    end
    local targetPart, partDistance
    for _, item in ipairs(workspace:GetDescendants()) do
        if item:IsA("BasePart") and portalCandidate(item, targetWorld) then
            local dist = (root.Position - item.Position).Magnitude
            if not partDistance or dist < partDistance then
                targetPart, partDistance = item, dist
            end
        end
    end
    if targetPart then
        moveRoot(targetPart.Position + Vector3.new(0, targetPart.Size.Y * 0.5 + 3, 0))
        fight.portalStatus = "Approaching world " .. tostring(targetWorld) .. " entrance"
    else
        fight.portalStatus = "No identified portal for world " .. tostring(targetWorld)
    end
    return false
end
local function stageAdvice(stage)
    local evolution = number(nativeCall(native.modules.data, "Get", true, "Evolutions"))
    local level = number(player:GetAttribute("Level"))
    if not evolution or not level then return "Waiting for progression data.", nil end
    local ok, message, status = fightCall(native.modules.stages, "Advice", false, stage, evolution, level)
    if ok then return tostring(message or ""), status end
    return "Stage recommendation is unavailable.", nil
end
local function startStage()
    local best, bestWaiting, reason, bestLocal, waitingLocal
    local cap = values.stageLimit > 0 and values.stageLimit or 1000
    if state.progress and progress.safeFarm and progress.safeStageCap then
        cap = math.min(cap, progress.safeStageCap)
    end
    local requestedWorld
    if not fight.allPortals or fight.portalMode == "CURRENT" then
        requestedWorld = currentWorld()
    elseif fight.portalMode == "SELECT" then
        requestedWorld = fight.selectedWorld
    end
    for stage in pairs(native.modules.stages.List) do
        if type(stage) == "number" and stage % 1 == 0 and stage >= 1 and stage <= cap
            and (not requestedWorld or stageWorld(stage) == requestedWorld)
            and stageAvailable(stage, fight.allPortals and fight.portalMode ~= "CURRENT") then
            local message, advice = stageAdvice(stage)
            local localStage = (stageWorld(stage) == currentWorld())
            if advice == "ready" then
                if localStage and (not bestLocal or stage > bestLocal) then bestLocal = stage end
                if not best or stage > best then best = stage end
            end
            if localStage then waitingLocal = message end
            if not bestWaiting or stage > bestWaiting then bestWaiting, reason = stage, message end
        end
    end
    -- In AUTO mode continue fighting in the world the player deliberately
    -- entered; travel elsewhere only when nothing playable is here.
    if fight.portalMode == "AUTO" and bestLocal then return bestLocal, "Current world ready" end
    return best, waitingLocal or reason or "Unlock the first combat form or complete the previous stage."
end
local function stageFolder(stage)
    local folder = nativeCall(native.modules.maps, "StageFolder", false, stage)
    if typeof(folder) == "Instance" and folder:IsDescendantOf(workspace) then return folder end
end
local function stageZone(folder)
    -- Arena may despawn during the transition between waves and a boss.
    if typeof(folder) ~= "Instance" or not folder.Parent then return nil, nil end
    local cf, size = folder:GetAttribute("ZoneCFrame"), folder:GetAttribute("ZoneSize")
    if typeof(cf) == "CFrame" and typeof(size) == "Vector3" then return cf, size end
    local part = folder:FindFirstChild("EnemyZone", true)
    if part and part:IsA("BasePart") then return part.CFrame, part.Size end
end
local function blockedSurface(part, folder, reward)
    local hazards = {GooCrust = true, PoisonGoo = true, StreetGoo = true, KillFloor = true,
        CloudSea = true, FogSea = true, RisingFog = true, Lava = true, KillBrick = true}
    local object = part
    while object and object ~= folder do
        if hazards[object.Name:gsub("%d+", "")] or object:GetAttribute("Poison") == true
            or object:GetAttribute("ProductId") ~= nil or object:GetAttribute("Paid") == true
            or (number(object:GetAttribute("Price")) or 0) > 0
            or (not reward and object.Name == "WinPad") then return true end
        object = object.Parent
    end
    return object ~= folder
end
-- V10: V9 rejected a valid arena floor when it belonged to Workspace rather
-- than the StageFolder. Reject actual hazards and paid/win surfaces, but allow
-- ordinary collidable ground inside the CURRENT encounter zone.
local function safeExternalArenaFloor(part)
    local obj = part
    while obj and obj ~= workspace do
        local name = obj.Name:gsub("%d+", "")
        if name == "GooCrust" or name == "PoisonGoo" or name == "StreetGoo"
            or name == "KillFloor" or name == "KillBrick" or name == "Lava"
            or name == "FogSea" or name == "CloudSea" or name == "RisingFog"
            or name == "WinPad" or name == "DamageZone"
            or obj:GetAttribute("Poison") == true
            or obj:GetAttribute("Hazard") == true
            or obj:GetAttribute("Paid") == true
            or obj:GetAttribute("ProductId") ~= nil
            or (number(obj:GetAttribute("Price")) or 0) > 0 then return false end
        obj = obj.Parent
    end
    return true
end
local function fightGround(position, folder, reward, outside)
    local cf, size = stageZone(folder)
    if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local ignored = {character}
    for _, enemy in ipairs(CollectionService:GetTagged("VenomEnemy")) do ignored[#ignored + 1] = enemy end
    -- Include untagged ranged bosses so raycasts don't mistake their bodies for floor.
    for _, entry in ipairs(fight.stageNPCs or {}) do
        if entry.model and entry.model.Parent then ignored[#ignored + 1] = entry.model end
    end
    local height = math.max(16, math.min(128, size.Y * 0.5 + 12))
    local origin = position + Vector3.new(0, height, 0)
    for _ = 1, 12 do
        params.FilterDescendantsInstances = ignored
        local result = workspace:Raycast(origin, Vector3.new(0, -math.min(512, size.Y + height + 80), 0), params)
        if not result then return nil end
        local part = result.Instance
        if not part:IsA("BasePart") then return nil end
        local point = cf:PointToObjectSpace(result.Position)
        local inArena = math.abs(point.X) <= size.X * 0.5 + 2
            and math.abs(point.Z) <= size.Z * 0.5 + 2
        if not outside and not inArena then return nil end
        if outside and number(nativeCall(native.modules.maps, "WorldAt", false, result.Position)) ~= stageWorld(fight.run.stage) then return nil end
        local isBlocked = blockedSurface(part, outside and workspace or folder, reward)
        if isBlocked and inArena and not outside and not reward
            and not part:IsDescendantOf(folder) and safeExternalArenaFloor(part) then
            isBlocked = false
            fight.groundFallbacks = fight.groundFallbacks + 1
        end
        if isBlocked then
            -- Never phase through lethal floors or other-stage surfaces.
            return nil
        end
        if part.CanCollide and result.Normal.Y >= 0.65 then
            return result.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y * 0.5 + 0.1, 0)
        end
        ignored[#ignored + 1] = part
    end
end
local function outsideFight(position, folder)
    local cf, size = stageZone(folder)
    if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then return false end
    local point = cf:PointToObjectSpace(position)
    local dx, dz = math.max(0, math.abs(point.X) - size.X * 0.5), math.max(0, math.abs(point.Z) - size.Z * 0.5)
    return math.sqrt(dx * dx + dz * dz) > (number(native.modules.encounters.LeaveRange) or 130) + 5
end
local function fightExit(folder)
    local cf, size = stageZone(folder)
    if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then return nil end
    local points = {}
    if fight.origin and outsideFight(fight.origin, folder) then points[#points + 1] = fight.origin end
    local distance = math.max(size.X, size.Z) * 0.5 + (number(native.modules.encounters.LeaveRange) or 130) + 25
    for _, direction in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        points[#points + 1] = cf.Position + Vector3.new(direction[1] * distance, 0, direction[2] * distance)
    end
    for _, point in ipairs(points) do
        local ground = fightGround(point, folder, false, true)
        local clear = ground and outsideFight(ground, folder)
        if clear then
            for _, model in ipairs(CollectionService:GetTagged("SoundChamber")) do
                local pad = model:FindFirstChild("Pad")
                if pad and pad:IsA("BasePart") then
                    local delta = ground - pad.Position
                    if Vector3.new(delta.X, 0, delta.Z).Magnitude <= math.max(pad.Size.X, pad.Size.Z) * 0.5 + 4 then clear = false break end
                end
            end
        end
        if clear then
            for stage in pairs(native.modules.stages.List) do
                if type(stage) == "number" then
                    local other = stageFolder(stage)
                    local zone, dimensions
                    if other then zone, dimensions = stageZone(other) end
                    if typeof(zone) == "CFrame" and typeof(dimensions) == "Vector3" then
                        local localPoint = zone:PointToObjectSpace(ground)
                        local startRange = (number(native.modules.encounters.StartRange) or 30) + 5
                        if math.abs(localPoint.X) <= dimensions.X * 0.5 + startRange
                            and math.abs(localPoint.Z) <= dimensions.Z * 0.5 + startRange then clear = false break end
                    end
                end
            end
        end
        if clear then return ground end
    end
end
local function fightEntry(folder)
    local points = {}
    for _, part in ipairs(folder:GetDescendants()) do
        if part:IsA("BasePart") and part.Name:gsub("%d+", "") == "EntryDeck" then points[#points + 1] = part.Position end
    end
    local cf = stageZone(folder)
    if cf then
        points[#points + 1] = cf.Position
        for _, direction in ipairs({{8, 0}, {-8, 0}, {0, 8}, {0, -8}}) do
            points[#points + 1] = cf.Position + Vector3.new(direction[1], 0, direction[2])
        end
    end
    for _, point in ipairs(points) do
        local ground = fightGround(point, folder, false)
        if ground then return ground end
    end
end
-- V6 boss discovery. Gun-wielding bosses can have no Boss tag and no explicit
-- Stage attribute; the active arena and native encounter phase are the bounds.
local function modelHumanoid(model)
    return model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("Humanoid", true)
end
local function rigRoot(model, hum)
    local candidate = (hum and hum.RootPart) or model:FindFirstChild("HumanoidRootPart", true)
        or model.PrimaryPart or model:FindFirstChild("UpperTorso", true)
        or model:FindFirstChild("Torso", true) or model:FindFirstChild("Head", true)
    return candidate and candidate:IsA("BasePart") and candidate or nil
end
local function isStageBoss(model)
    if not model or not model:IsA("Model") then return false end
    if CollectionService:HasTag(model, "VenomBoss") or CollectionService:HasTag(model, "Boss") then return true end
    for _, key in ipairs({"Boss", "IsBoss", "BossEnemy", "StageBoss", "EnemyBoss", "BossType"}) do
        local value = model:GetAttribute(key)
        if value == true or (type(value) == "string" and value ~= "") then return true end
    end
    local n = model.Name:lower()
    return n:find("boss", 1, true) ~= nil or n:find("overlord", 1, true) ~= nil
end
local function stageNPCs(stage, folder, now)
    if fight.previousStage == stage and fight.lastCombatFolder == folder
        and now - fight.stageNPCAt < (fight.preemptive and 0.11 or 0.32) then return fight.stageNPCs end
    local list, seen = {}, {}
    local function add(model, source)
        if typeof(model) ~= "Instance" or not model:IsA("Model") or seen[model]
            or not model:IsDescendantOf(workspace) or model == character
            or Players:GetPlayerFromCharacter(model) then return end
        local hum = modelHumanoid(model)
        if not hum or not hum:IsA("Humanoid") or hum.Health <= 0 then return end
        local rootPart = rigRoot(model, hum)
        if not rootPart then return end
        local stageValue = number(model:GetAttribute("Stage"))
        if stageValue and stageValue ~= stage then return end
        if not stageValue and (not folder or not model:IsDescendantOf(folder)) then
            -- CRITICAL V11 FIX: Lua `and` only returns one value, so writing
            -- `folder and stageZone(folder)` silently discards dimensions.
            -- V10 then crashed on dimensions.X, preventing all subsequent combat.
            local zone, dimensions
            if folder then
                zone, dimensions = stageZone(folder)
            end
            if typeof(zone) ~= "CFrame" or typeof(dimensions) ~= "Vector3" then
                return
            end
            local localPoint = zone:PointToObjectSpace(rootPart.Position)
            if math.abs(localPoint.X) > dimensions.X * 0.5 + 12
                or math.abs(localPoint.Z) > dimensions.Z * 0.5 + 12
                or math.abs(localPoint.Y) > math.max(30, dimensions.Y * 0.5 + 15) then return end
        end
        seen[model] = true
        list[#list + 1] = {model = model, root = rootPart, humanoid = hum, source = source}
    end
    for _, tag in ipairs({"VenomEnemy", "VenomBoss", "Boss"}) do
        for _, model in ipairs(CollectionService:GetTagged(tag)) do add(model, tag) end
    end
    if folder then
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
                add(obj.Parent, "arena rig")
            end
        end
        -- Some encounter stages parent ranged bosses directly under Workspace,
        -- outside their StageFolder. Scan only the bounded active arena.
        local zone, dimensions = stageZone(folder)
        if typeof(zone) == "CFrame" and typeof(dimensions) == "Vector3" then
            local params = OverlapParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character}
            params.MaxParts = 260
            local ok, overlapping = pcall(workspace.GetPartBoundsInBox, workspace,
                zone, dimensions + Vector3.new(14, 24, 14), params)
            if ok and type(overlapping) == "table" then
                for _, part in ipairs(overlapping) do
                    local model = part:FindFirstAncestorOfClass("Model")
                    if model and modelHumanoid(model) then add(model, "nearby arena") end
                end
            end
        end
    end
    -- The active encounter is checked frequently; discovering a newly spawned
    -- boss sooner matters more than repeatedly probing an unavailable attack.
    fight.stageNPCs, fight.stageNPCAt, fight.previousStage = list, now, stage
    return list
end
local function fightEnemies(stage, phase, folder, now)
    local target, bestScore, count, total = nil, math.huge, 0, 0
    fight.bossDetected, fight.targetSource = false, "none"
    for _, entry in ipairs(stageNPCs(stage, folder, now)) do
        local model, h, r = entry.model, entry.humanoid, entry.root
        if model.Parent and h.Parent and h.Health > 0
            and model:GetAttribute("Dead") ~= true and model:GetAttribute("KilledBy") == nil then
            local brain = nativeCall(native.modules.encounter, "Brain", true, model)
            local brainStage = type(brain) == "table" and type(brain.stage) == "table"
                and number(brain.stage.index) or nil
            if (not brainStage or brainStage == stage)
                and not (type(brain) == "table" and brain.state == "dead") then
                local explicitBoss = isStageBoss(model)
                -- Gun bosses may be tagged only VenomEnemy, with no Boss name.
                -- In an active boss phase, accept any NPC rig in this arena.
                local boss = explicitBoss or (phase == "boss" and folder and model:IsDescendantOf(folder))
                local valid = (type(brain) == "table" and type(brain.stage) == "table")
                    or boss or phase == "snipers" or entry.source == "arena rig"
                    or entry.source == "nearby arena"
                if valid and (boss or (model:GetAttribute("Bonus") == nil
                    and model:GetAttribute("Tower") == nil)) then
                    count, total = count + 1, total + h.Health
                    if boss then fight.bossDetected = true end
                    if model:GetAttribute("Finishing") ~= true and model:GetAttribute("Pulled") ~= true then
                        local dist = (r.Position - root.Position).Magnitude
                        local score = dist
                        if fight.finishWeak and dist <= 30 and h.MaxHealth > 0 then
                            local ratio = math.clamp(h.Health / h.MaxHealth, 0, 1)
                            if ratio < 0.5 then score = score * 0.72 - (1 - ratio) * 4 end
                        end
                        if fight.run and fight.run.lockedTarget == model then score = score - 8 end
                        if boss and phase == "boss" and fight.bosses then
                            score = score - 1000
                            if explicitBoss then score = score - 1500 end
                            if entry.model:GetAttribute("Ranged") or entry.model:GetAttribute("Shooter") then
                                score = score - 200
                            end
                        elseif phase == "snipers" then
                            -- Handle active ranged threats before they get to aim.
                            if model:GetAttribute("Ranged") == true
                                or model:GetAttribute("Shooter") == true
                                or model:GetAttribute("HasGun") == true
                                or model.Name:lower():find("sniper", 1, true) then
                                score = score - 20
                            end
                        end
                        if score < bestScore then
                            bestScore = score
                            target = {model = model, root = r, humanoid = h, brain = brain,
                                boss = boss, source = entry.source}
                            fight.targetSource = entry.source
                        end
                    end
                end
            end
        end
    end
    return target, count, total
end

-- Attack anticipation is heuristic; enemy AI may not expose a telegraph.
local function hasAttackTelegraph(target)
    if not target then return false end
    local model, brain = target.model, target.brain
    for _, key in ipairs({"Attacking", "IsAttacking", "AttackWindup", "Charging", "Casting", "Slam", "Strike", "WindingUp"}) do
        if model:GetAttribute(key) == true then return true end
    end
    if type(brain) == "table" then
        local value = brain.state
        if type(value) == "string" then
            value = value:lower()
            for _, name in ipairs({"attack", "strike", "windup", "lunge", "slam", "cast", "charge", "aim", "fire", "shoot", "throw", "reload"}) do
                if value:find(name, 1, true) then return true end
            end
        end
    end
    return false
end
-- V6 predictive defense: both replicated physics velocity and visible
-- position delta are used, since some bullets are tweened/anchored cosmetics.
local projectileNames = {"projectile", "missile", "bullet", "fireball", "spit", "acidball",
    "enemyhitbox", "attackhitbox", "shockwave", "rocket", "grenade", "arrow",
    "laser", "bolt", "plasma", "shard", "orb", "bomb", "shot", "throw",
    "spear", "knife", "blast", "cannonball", "poisonball", "energyball", "tracer"}
local function hostileProjectile(part)
    if not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then return false end
    if part:IsDescendantOf(character) or (part.Transparency >= 1 and not part.CanTouch) then return false end
    local owner = part:GetAttribute("OwnerUserId") or part:GetAttribute("ShooterUserId")
    if owner == player.UserId then return false end
    if part:GetAttribute("Friendly") == true or part:GetAttribute("PlayerAttack") == true then return false end
    if part:GetAttribute("Projectile") == true or part:GetAttribute("IsProjectile") == true
        or part:GetAttribute("EnemyAttack") == true or part:GetAttribute("Hostile") == true then return true end
    local names = {part.Name:lower()}
    local p = part.Parent
    for _ = 1, 3 do
        if p and p ~= workspace then names[#names + 1] = p.Name:lower() p = p.Parent end
    end
    for _, name in ipairs(names) do
        for _, word in ipairs(projectileNames) do
            if name:find(word, 1, true) then return true end
        end
    end
    return false
end
local function maybeUnlabeledProjectile(part)
    if not part:IsA("BasePart") or not part:IsDescendantOf(workspace)
        or part:IsDescendantOf(character) or part.Size.Magnitude > 9 then return false end
    if part.CanCollide and part.Size.Magnitude > 3 then return false end
    local host = part:FindFirstAncestorOfClass("Model")
    -- Don't classify living NPC limbs or another player's moving limbs as bullets.
    if host and (modelHumanoid(host) or Players:GetPlayerFromCharacter(host)) then return false end
    return true
end
local function nearbyThreat(now)
    if now - fight.lastDefensiveScan < 0.025 then return fight.cachedThreat end
    fight.lastDefensiveScan = now
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.MaxParts = 400
    local ok, nearby = pcall(workspace.GetPartBoundsInRadius, workspace, root.Position,
        math.max(15, values.projectileRadius), params)
    if not ok or type(nearby) ~= "table" then fight.cachedThreat = nil return nil end
    local choice, score = nil, math.huge
    for _, part in ipairs(nearby) do
        local namedProjectile = hostileProjectile(part)
        local plausible = namedProjectile or maybeUnlabeledProjectile(part)
        if plausible then
            local old = fight.projectileHistory[part]
            local velocity = part.AssemblyLinearVelocity
            if old and now > old.time + 0.012 then
                local measured = (part.Position - old.position) / (now - old.time)
                -- Tweened bullets have zero physics velocity. The measured
                -- position delta is more useful for those visual projectiles.
                if measured.Magnitude > 3 and (velocity.Magnitude < 4 or part.Anchored) then
                    velocity = measured
                end
            end
            fight.projectileHistory[part] = {position = part.Position, time = now}
            local offset = part.Position - root.Position
            local dist = offset.Magnitude
            -- For unlabeled objects require meaningful actual velocity, not
            -- a static decorative part. Invisible/anchored gun cosmetics are
            -- only accepted when their measured positions are changing fast.
            if namedProjectile or (velocity.Magnitude >= 45 and dist < 55) then
            local relative = velocity - root.AssemblyLinearVelocity * 0.35
            local speed2 = relative:Dot(relative)
            local eta = speed2 > 25 and math.clamp(-offset:Dot(relative) / speed2, 0, 1.35) or 0
            local nearest = offset + relative * eta
            local envelope = math.clamp(root.Size.Magnitude * 0.7 + part.Size.Magnitude * 0.3 + 1.5, 4, 10)
            local approaching = speed2 > 25 and offset:Dot(relative) < -1
            local collision = approaching and nearest.Magnitude < envelope and eta < 1.25
            local close = dist < envelope + 1.3 and (not approaching or eta < 0.25)
            if collision or close then
                local priority = eta * 8 + nearest.Magnitude * 0.4 + dist * 0.025
                if priority < score then
                    score = priority
                    choice = {part = part, position = part.Position, velocity = velocity,
                        intercept = part.Position + velocity * eta, time = eta,
                        distance = dist, radius = envelope, moving = approaching,
                        kind = namedProjectile and "named" or "unlabeled-moving"}
                end
            end
            end -- named projectile or fast unlabeled object
        end
    end
    fight.cachedThreat = choice
    if choice then fight.lastThreatClass = choice.kind end
    if choice and (fight.lastThreatInstance ~= choice.part or now - fight.lastThreatAt > 0.6) then
        fight.seenProjectiles = fight.seenProjectiles + 1
        fight.lastThreatInstance, fight.lastThreatAt = choice.part, now
    end
    return choice
end
local function enemyRanged(target)
    if not target then return false end
    local m = target.model
    for _, attr in ipairs({"Ranged", "Shooter", "Sniper", "Gun", "HasGun", "Thrower", "UsesProjectiles"}) do
        if m:GetAttribute(attr) == true then return true end
    end
    for _, word in ipairs({"gun", "sniper", "rifle", "archer", "caster", "throw", "ranged", "turret", "pistol", "shooter"}) do
        if m.Name:lower():find(word, 1, true) then return true end
    end
    if target.boss and target.brain and type(target.brain.state) == "string" then
        local stateName = target.brain.state:lower()
        if stateName:find("shoot", 1, true) or stateName:find("aim", 1, true)
            or stateName:find("fire", 1, true) then return true end
    end
    for _, item in ipairs(m:GetDescendants()) do
        if item:IsA("Tool") or item:IsA("Attachment") or item:IsA("BasePart") then
            local name = item.Name:lower()
            if name:find("gun", 1, true) or name:find("muzzle", 1, true)
                or name:find("barrel", 1, true) or name:find("rifle", 1, true) then return true end
        end
    end
    return false
end
-- Detect roughly aligned gun muzzle/face direction. Hitscan weapons can have
-- no visible projectile, so this is only anticipatory movement, not immunity.
local function gunLaneDanger(target)
    if not target or not enemyRanged(target) then return false end
    local muzzle
    for _, item in ipairs(target.model:GetDescendants()) do
        if item:IsA("Attachment") or item:IsA("BasePart") then
            local n = item.Name:lower()
            if n:find("muzzle", 1, true) or n:find("firepoint", 1, true)
                or n:find("guntip", 1, true) then muzzle = item break end
        end
    end
    local cf = muzzle and (muzzle:IsA("Attachment") and muzzle.WorldCFrame or muzzle.CFrame)
        or target.root.CFrame
    local v = root.Position - cf.Position
    if v.Magnitude < 0.5 or v.Magnitude > 75 then return false end
    local facing = cf.LookVector:Dot(v.Unit)
    -- Rig conventions vary. For close targets, a facing muzzle is an early cue.
    return facing > 0.65 and (v - cf.LookVector * v:Dot(cf.LookVector)).Magnitude <= 12
end
local function verifyPreviousDodge(now)
    if fight.lastDodgeTo and now >= fight.lastDodgeVerifyAt then
        local moved = (root.Position - fight.lastDodgeFrom).Magnitude
        local planned = (fight.lastDodgeTo - fight.lastDodgeFrom).Magnitude
        if planned >= 5 and moved < math.max(1.5, planned * 0.2) then
            fight.dodgesCorrected = fight.dodgesCorrected + 1
            -- Server corrections cannot be bypassed by a client script.
            pcall(function() humanoid:MoveTo(fight.lastDodgeTo) end)
        else
            fight.shotsDodged = fight.shotsDodged + 1 -- evasive movement completed; not a proof of invulnerability
        end
        fight.lastDodgeTo, fight.lastDodgeFrom = nil, nil
    end
end
local function evadeFight(now, target, phase, folder, reach)
    if not fight.dodge or not root or not humanoid or humanoid.Health <= 0 or not folder then return false end
    reach = reach or 7
    verifyPreviousDodge(now)
    local previous, health = fight.lastHealth, humanoid.Health
    fight.lastHealth = health
    if previous and health < previous then
        fight.lastHurtAt = now
        fight.healthLost = fight.healthLost + (previous - health)
        if now - fight.damageWindowStarted > 3 then
            fight.damageWindowStarted, fight.rangedDamageWindow = now, 0
        end
        fight.rangedDamageWindow = fight.rangedDamageWindow + (previous - health)
        fight.recentHitsAt = now
    end
    local threat = fight.ballistic and nearbyThreat(now) or nil
    local enemyPos = target and target.root and target.root.Position or nil
    local dist = enemyPos and (enemyPos - root.Position).Magnitude or math.huge
    local ranged = target and (phase == "snipers" or enemyRanged(target)) or false
    local attackTell = target and dist < math.max(55, reach * 5) and hasAttackTelegraph(target) or false
    local firingLane = ranged and target and dist < 68 and gunLaneDanger(target) or false
    local justHit = now - fight.lastHurtAt < 0.40
    local retreat = fight.retreat and humanoid.MaxHealth > 0
        and health / humanoid.MaxHealth <= values.retreatHealth / 100
        and now - fight.lastRetreat > 2.2
    -- Avoid a repeated sidestep/chase cycle: when farther than attack reach
    -- only real projectile, muzzle, or windup cues justify an evasion.
    -- During FIRST STRIKE, reduce routine non-threatening sidesteps so the
    -- next server-permitted attack can land. Genuine imminent threats still
    -- trigger the projectile/telegraph branches above.
    local rangedLane = ranged and target and dist <= reach + 1.5
        and now - fight.lastDodge > 0.5
        and (not fight.preemptive or now - fight.lastAttack > 0.5)
    local bossFootwork = target and phase == "boss" and target.boss
        and not fight.preemptive
        and dist < math.max(12, reach + 2) and now - fight.lastDodge > 0.95
    local reason = threat and "incoming projectile" or firingLane and "gun line"
        or attackTell and "attack telegraph" or justHit and "recent hit"
        or retreat and "low health" or rangedLane and "ranged pressure"
        or bossFootwork and "boss footwork" or nil
    if not reason then return false end
    local urgent = threat or attackTell or retreat
    -- An enemy merely facing us is not proof a hitscan shot will be fired.
    -- Allow a full attack window unless there is a visible incoming projectile
    -- or a confirmed attack windup, otherwise the player just strafes forever.
    if firingLane and not urgent and now < fight.attackWindowUntil then return false end
    -- Preserve a small quiet window for a server-recognized melee attack.
    -- If a bullet is actually on a collision course, defense still wins.
    if now < fight.attackWindowUntil and not urgent then
        fight.suppressedStrafes = fight.suppressedStrafes + 1
        return false
    end
    if target and dist > reach + 3 and not urgent and not justHit then
        fight.suppressedStrafes = fight.suppressedStrafes + 1
        return false
    end
    -- Avoid undoing a combat chase almost immediately after moving.
    if now - fight.lastChaseAt < 0.13 and not urgent then return false end
    local cooldown = threat and 0.085 or (firingLane and 0.30 or (attackTell and 0.13
        or (justHit and 0.17 or math.min(0.40, values.dodgeMs / 1000))))
    if now - fight.lastDodge < cooldown then return false end
    local threatPos = threat and threat.intercept or enemyPos
    if not threatPos then return false end
    -- Lateral dodges must be perpendicular to the bullet's actual travel lane,
    -- not just the line connecting the bullet and the player.
    local heading = threat and threat.velocity or (threatPos - root.Position)
    heading = Vector3.new(heading.X, 0, heading.Z)
    if threat and heading.Magnitude < 8 then
        heading = threatPos - root.Position
        heading = Vector3.new(heading.X, 0, heading.Z)
    end
    if heading.Magnitude < 0.1 then
        heading = Vector3.new(root.CFrame.LookVector.Z, 0, -root.CFrame.LookVector.X)
    end
    if heading.Magnitude < 0.1 then heading = Vector3.new(0, 0, 1) end
    heading = heading.Unit
    local side = Vector3.new(-heading.Z, 0, heading.X)
    local sign = (fight.dodgeCount % 2 == 0) and 1 or -1
    local evasive = urgent or justHit
    -- V12: small, rapid sidesteps near enemies preserve melee pressure.
    -- V11 used full 13-stud dodges, often leaving a 7-stud melee reach.
    local closeCombat = fight.adaptiveDodge and target and dist <= reach + 2.5
    local targetLen = closeCombat and math.clamp(reach * 0.82, 4.5, 8.0)
        or math.clamp(reach * 1.12, 5.5, 12.0)
    local len = math.min(values.dodgeRange, targetLen)
    if threat and (threat.time or 0.25) <= 0.16 then
        len = math.min(values.dodgeRange, math.max(len, 7.5))
    end
    if not evasive then len = math.min(len, math.max(3.5, reach * 0.58)) end
    if not fight.adaptiveDodge then
        len = evasive and values.dodgeRange or math.min(values.dodgeRange, math.max(3.5, reach * 0.6))
    end
    local origin = root.Position
    local far = target and dist > reach + 3 and not retreat
    -- Gun bosses must be approached, not endlessly orbited: sidesteps advance
    -- diagonally when outside attack reach, while urgent close hits dodge away.
    local towardEnemy = enemyPos and (enemyPos - origin) or heading
    towardEnemy = Vector3.new(towardEnemy.X, 0, towardEnemy.Z)
    if towardEnemy.Magnitude > 0.01 then towardEnemy = towardEnemy.Unit else towardEnemy = heading end
    local forward = far and towardEnemy * 0.65 or -heading * 0.1
    local choices = {
        origin + (side * sign + forward).Unit * len,
        origin + (-side * sign + forward).Unit * len,
        origin + side * len * sign,
        origin - side * len * sign,
        origin + (side * sign - heading * 0.55).Unit * len,
        origin + (-side * sign - heading * 0.55).Unit * len,
        origin + heading * len * 0.85,
        origin - heading * len * 0.85,
    }
    local best, bestScore = nil, -math.huge
    for _, proposed in ipairs(choices) do
        local point = fightGround(proposed, folder, false)
        if point then
            local score = 0
            if threat then
                local eta = math.clamp(threat.time or 0.18, 0.02, 0.9)
                for _, t in ipairs({eta, math.max(0.05, eta - 0.10), eta + 0.10}) do
                    local bullet = threat.position + threat.velocity * t
                    local distance = (point - bullet).Magnitude
                    score = score + math.min(distance, 25) * 1.2
                    if distance < (threat.radius or 5) + 1 then score = score - 35 end
                end
            end
            if enemyPos then
                local rangeAfter = (point - enemyPos).Magnitude
                if not retreat then
                    local desired = math.max(3, reach * 0.72)
                    score = score - math.abs(rangeAfter - desired) * (far and 3.7 or threat and 1.35 or 2.3)
                    if rangeAfter > reach + 1.5 then
                        score = score - (rangeAfter - reach - 1.5) * (threat and 1.4 or 4.4)
                    end
                    if far then score = score + (dist - rangeAfter) * 2.3 end
                    if rangeAfter > reach + 2 then score = score - (rangeAfter - reach - 2) * 0.6 end
                else
                    score = score + math.min(rangeAfter, 32) * 1.7
                end
            end
            -- Prefer a lateral deviation over backing up along the gun line.
            local delta = (point - origin)
            local sideways = delta:Dot(side)
            score = score + math.abs(sideways) * 0.3
            if score > bestScore then best, bestScore = point, score end
        end
    end
    if not best then fight.blockedGrounds = fight.blockedGrounds + 1 return false end
    moveRoot(best)
    if threat then fight.lastCriticalDodge = now end
    fight.lastDodge, fight.dodgeCount, fight.dodgeReason = now, fight.dodgeCount + 1, reason
    fight.lastDodgeFrom, fight.lastDodgeTo, fight.lastDodgeVerifyAt = origin, best, now + 0.18
    if enemyPos and (best - enemyPos).Magnitude <= reach + 1.5 then
        fight.dodgedWithoutLeavingRange = fight.dodgedWithoutLeavingRange + 1
    end
    fight.lastAction = "Dodging " .. reason
    if retreat then fight.lastRetreat = now end
    if now - fight.lastCombatReport > 0.8 then
        fight.lastCombatReport = now
        fightNotice("PHANTOM Evasion / " .. reason .. " / " .. tostring(fight.dodgeCount))
    end
    return true
end

local function fightWinPad(stage, folder)
    for _, pad in ipairs(CollectionService:GetTagged("VenomWinPad")) do
        if pad:IsA("BasePart") and pad:IsDescendantOf(folder) and number(pad:GetAttribute("Stage")) == stage
            and pad.CanTouch ~= false and not blockedSurface(pad, folder, true) then return pad end
    end
end
local function failFight(message)
    state.fight = false stopFight() refresh() notify(message)
end
-- V12 OVERDRIVE: one native attack scheduler for the fight loop AND Heartbeat.
-- The server is authoritative: never fake HP or spam network remotes.
-- This only reduces our own timing jitter when combat Busy() changes to false.
local function strikeTargetInRange(target, reach)
    if not root or not target or not target.root or not target.root.Parent
        or not target.humanoid or target.humanoid.Health <= 0 then return false end
    local delta = target.root.Position - root.Position
    local planar = Vector3.new(delta.X, 0, delta.Z).Magnitude
    return delta.Magnitude <= reach or (planar <= reach * 0.85
        and math.abs(delta.Y) <= math.max(9, reach * 1.5))
end

local function tryNativeStrike(now, target, reach, run)
    if not running or not state.fight or not alive() or not run or fight.run ~= run
        or fight.strikeBusy or not strikeTargetInRange(target, reach) then return false end
    local period = fight.rapid and math.max(0.035, values.attackMs / 1000) or 0.20
    if now - fight.lastAttack < period then return false end
    if now - fight.lastStrikeProbe < 0.028 then return false end
    fight.lastStrikeProbe = now
    local m = native.modules.combat
    if type(m) ~= "table" or type(m.Attack) ~= "function" or type(m.Busy) ~= "function" then
        return false
    end
    fight.strikeBusy = true
    local busyOK, busy = fightCall(m, "Busy", true)
    if not busyOK then
        fight.strikeBusy = false
        fight.attackStatus = "Native Busy() unavailable"
        return false
    end
    if busy then
        fight.strikeBusy = false
        fight.cooldownSkips = fight.cooldownSkips + 1
        fight.attackStatus = "Waiting for combat controller cooldown"
        return false
    end
    -- Orientation is part of normal melee hit detection in some encounters.
    -- Face the real target BEFORE Attack(), not after the stage loop finishes.
    local face = target.root.Position
    local flattened = Vector3.new(face.X, root.Position.Y, face.Z)
    if (flattened - root.Position).Magnitude > 0.1 then
        root.CFrame = CFrame.lookAt(root.Position, flattened)
    end
    fight.lastAttack = now
    local attacked, accepted = fightCall(m, "Attack", true)
    fight.strikeBusy = false
    if not attacked then
        fight.attackStatus = "Native attack error; check diagnostics"
        return false
    end
    fight.attacks = fight.attacks + 1
    run.targetAttackRequests = (run.targetAttackRequests or 0) + 1
    if accepted ~= false then fight.accepted = fight.accepted + 1 end
    fight.attackWindowUntil = accepted == false and now or now + 0.12
    fight.lastAction = "Strike " .. target.model.Name
    fight.attackStatus = accepted == false and "Combat controller rejected strike"
        or "Strike requested; awaiting enemy HP change"
    if fight.overdrive then fight.overdriveAttempts = fight.overdriveAttempts + 1 end
    if now - fight.lastCombatReport > 1.0 then
        fight.lastCombatReport = now
        fightNotice(accepted == false and "Combat cooling down: keeping target in range."
            or "OVERDRIVE | " .. target.model.Name .. " | Stage " .. tostring(run.stage))
    end
    return accepted ~= false
end

do
-- V18 COMBAT EQUIPMENT. The ordinary Auto Tool toggle is disabled during fighting.
-- Detect usable weapons/attacks held as Roblox Tools, not GUI shop buttons or passes.
local combatWeaponPattern = {"gun", "claw", "sword", "fang", "blade", "bite", "weapon", "cannon",
    "blaster", "devour", "tendril", "strike", "whip", "laser", "venom", "bow"}
local function isCombatTool(tool)
    if not tool or not tool:IsA("Tool") or tool.Enabled == false then return false end
    local name = tool.Name:lower()
    if name:find("ticket", 1, true) or name:find("potion", 1, true)
        or name:find("boost", 1, true) or name:find("evolve", 1, true)
        or name:find("portal", 1, true) or name:find("teleport", 1, true)
        or name:find("gift", 1, true) or name:find("purchase", 1, true) then return false end
    if tool:GetAttribute("Weapon") == true or tool:GetAttribute("Combat") == true then return true end
    for _, pattern in ipairs(combatWeaponPattern) do
        if name:find(pattern, 1, true) then return true end
    end
    return false
end
local function attackWithCombatTool(now)
    if not fight.combatTools or not alive() or now - fight.lastCombatTool < 0.32 then return false end
    local tool
    for _, child in ipairs(character:GetChildren()) do
        if isCombatTool(child) then tool = child break end
    end
    if not tool then
        local backpack = player:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if isCombatTool(child) then
                    pcall(function() humanoid:EquipTool(child) end)
                    if child.Parent == character then tool = child end
                    break
                end
            end
        end
    end
    if not tool then return false end
    local ok = pcall(function() tool:Activate() end)
    if ok then
        fight.lastCombatTool, fight.toolAttacks, fight.toolName = now, fight.toolAttacks + 1, tool.Name
        -- Do not deactivate immediately; some tools require a short held activation.
        task.delay(0.18, function()
            if running and tool and tool.Parent then pcall(function() tool:Deactivate() end) end
        end)
    end
    return ok
end

-- V18 SHIELD OBJECTIVE SCANNER. Bosses sometimes have separate destructible
-- pylons / cannons / generators. V17 only targeted Humanoid rigs, so a protected
-- boss could absorb endless native attacks while its shield modules remained alive.
local objectiveWords = {"shield", "generator", "pylon", "pillar", "totem", "turret",
    "cannon", "battery", "drone", "beacon", "destruct", "node", "reactor", "emitter"}
local function objectiveHealth(node)
    if not node or not node.Parent then return nil end
    local hum = node:IsA("Model") and modelHumanoid(node)
    if hum then return hum.Health, hum.MaxHealth end
    for _, key in ipairs({"Health", "HP", "HitPoints", "HealthPoints", "Durability"}) do
        local v = number(node:GetAttribute(key))
        if v ~= nil then return v, number(node:GetAttribute("MaxHealth")) end
        local child = node:FindFirstChild(key)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then return child.Value, nil end
    end
end
local function objectiveCandidate(part, folder, boss)
    local node = part:FindFirstAncestorOfClass("Model")
    if not node or node == character then return nil end
    if Players:GetPlayerFromCharacter(node) then return nil end
    if boss and (node == boss.model or node:IsDescendantOf(boss.model)) then return nil end
    local name = (node.Name .. " " .. part.Name):lower()
    local hitName = false
    for _, word in ipairs(objectiveWords) do
        if name:find(word, 1, true) then hitName = true break end
    end
    if not hitName and node:GetAttribute("Destructible") ~= true
        and node:GetAttribute("Objective") ~= true then return nil end
    local hp, maxHP = objectiveHealth(node)
    local bar = node:FindFirstChild("HealthBar", true) or node:FindFirstChild("HealthGui", true)
        or node:FindFirstChild("HPBar", true)
    if hp ~= nil and hp <= 0 then return nil end
    -- Require an objective marker or a health signal; ignore ordinary scenery.
    if hp == nil and not bar and node:GetAttribute("Objective") ~= true
        and node:GetAttribute("Destructible") ~= true then return nil end
    if boss and (part.Position - boss.root.Position).Magnitude > 75 then return nil end
    return {model = node, part = part, root = part, hp = hp, maxHP = maxHP,
        name = node.Name, humanoid = modelHumanoid(node)}
end
local function findStageObjective(folder, boss, now)
    if not fight.autoShieldObjectives or not folder or not folder.Parent or not root then return nil end
    if now - fight.objectiveAt < 0.30 then
        local old = fight.objective
        if old and old.part and old.part.Parent and (old.hp == nil or old.hp > 0) then return old end
    end
    fight.objectiveAt = now
    local best, bestScore, seen = nil, math.huge, {}
    local region, size = stageZone(folder)
    local candidates
    if typeof(region) == "CFrame" and typeof(size) == "Vector3" then
        local filter = OverlapParams.new()
        filter.FilterType = Enum.RaycastFilterType.Exclude
        filter.FilterDescendantsInstances = {character}
        filter.MaxParts = 550
        local ok, partsFound = pcall(workspace.GetPartBoundsInBox, workspace,
            region, size + Vector3.new(22, 35, 22), filter)
        if ok then candidates = partsFound end
    end
    if not candidates then candidates = folder:GetDescendants() end
    for _, part in ipairs(candidates) do
        if part:IsA("BasePart") then
            local node = part:FindFirstAncestorOfClass("Model")
            if node and not seen[node] then
                seen[node] = true
                local candidate = objectiveCandidate(part, folder, boss)
                if candidate then
                    local dist = (part.Position - root.Position).Magnitude
                    local proximity = boss and (part.Position - boss.root.Position).Magnitude or 0
                    local score = dist + proximity * 0.15
                    if score < bestScore then best, bestScore = candidate, score end
                end
            end
        end
    end
    local old = fight.objective
    if old and old.model == (best and best.model) then
        local newHP = best.hp
        if old.hp and newHP and newHP < old.hp then
            fight.objectivesDamaged = fight.objectivesDamaged + 1
            if fight.run then fight.run.progressAt = now end
        end
    end
    fight.objective = best
    fight.objectiveName = best and best.name or "None"
    return best
end
local function tickStageObjective(now, folder, target, run, reach)
    if not target or not target.part or not target.part.Parent then return false end
    local pos = target.part.Position
    local relative = pos - root.Position
    local flat = Vector3.new(relative.X, 0, relative.Z)
    local dist = flat.Magnitude
    if dist > math.max(3, reach * 0.78) then
        if now - fight.lastMove > 0.11 and now - fight.lastDodge > 0.09 then
            local dir = dist > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
            local candidate = pos - dir * math.max(2.3, reach * 0.5)
            local point = fightGround(candidate, folder, false)
            if point then moveRoot(point) else
                pcall(function() humanoid:MoveTo(candidate) end)
            end
            fight.lastMove = now
        end
        fight.objectiveStatus = "Closing on shield object: " .. target.name
        return true
    end
    if flat.Magnitude > 0.1 then
        root.CFrame = CFrame.lookAt(root.Position, Vector3.new(pos.X, root.Position.Y, pos.Z))
    end
    -- Damage is verified through observed health, not by an Attack() return.
    attackWithCombatTool(now)
    if now - fight.objectiveLastStrike >= math.max(0.04, values.attackMs / 1000) then
        fight.objectiveLastStrike = now
        local combat = native.modules.combat
        local ready = false
        if type(combat) == "table" and type(combat.Attack) == "function" then
            local ok, busy = fightCall(combat, "Busy", true)
            ready = ok and not busy
            if ready then
                local sent = fightCall(combat, "Attack", true)
                if sent then fight.objectiveAttempts = fight.objectiveAttempts + 1 end
            end
        end
        if not ready or now - fight.objectiveAttackAt > 0.50 then
            tower.tapInput(now, "Objective", pos)
            fight.objectiveAttackAt = now
        end
    end
    fight.objectiveStatus = "Breaking " .. target.name .. " | HP " .. tostring(target.hp or "unknown")
    return true
end

fight.attackWithCombatTool = attackWithCombatTool
fight.findStageObjective = findStageObjective
fight.tickStageObjective = tickStageObjective
end

-- V16: TOWER AUTO COMBAT
-- Halloween Tower has its own floor/wave flow, not the ordinary StageState API.
-- This loop never claims a reward or forces a floor transition: it only aims,
-- optionally walks toward real enemies, and requests ordinary local attacks.
tower.findEnemy = function(now)
    if now - tower.lastScan < 0.22 and tower.target and tower.target.model.Parent
        and tower.target.humanoid.Health > 0 then return tower.target end
    if now - tower.lastScan < 0.22 then return tower.target end
    tower.lastScan = now
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.MaxParts = 420
    local ok, candidateParts = pcall(workspace.GetPartBoundsInRadius, workspace, root.Position, 125, params)
    if not ok or type(candidateParts) ~= "table" then
        tower.target = nil
        return nil
    end
    local seen, best, bestScore = {}, nil, math.huge
    for _, part in ipairs(candidateParts) do
        local model = part:FindFirstAncestorOfClass("Model")
        if model and model ~= character and not seen[model] then
            seen[model] = true
            local hum = modelHumanoid(model)
            if hum and hum.Health > 0 and not Players:GetPlayerFromCharacter(model) then
                local npcRoot = rigRoot(model, hum)
                if npcRoot and npcRoot:IsDescendantOf(workspace) then
                    local distance = (npcRoot.Position - root.Position).Magnitude
                    local isBoss = isStageBoss(model)
                    local healthRatio = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 1
                    local score = distance - (tower.bossPriority and isBoss and 24 or 0)
                        - (tower.quickFinisher and healthRatio < 0.28 and 15 or 0)
                    if distance < 125 and math.abs(npcRoot.Position.Y - root.Position.Y) <= 22
                        and score < bestScore then
                        best, bestScore = {model = model, humanoid = hum, root = npcRoot,
                            boss = isBoss}, score
                    end
                end
            end
        end
    end
    if (best and best.model) ~= tower.lastTargetModel then
        tower.lastTargetModel = best and best.model or nil
        tower.lastDamageAt = now
        tower.lastTargetHealth = nil
    end
    tower.target = best
    return best
end
tower.tapInput = function(now, context, aimPosition)
    if (context ~= "Main" and not tower.inputFallback) or now - tower.lastInput < tower.inputPeriod then return false end
    tower.lastInput = now
    local camera = workspace.CurrentCamera
    if not camera then tower.status = "Waiting for camera" return false end
    local view = camera.ViewportSize
    -- Lower-middle area avoids the game's usual inventory, menus, and jump controls.
    local x, y = math.floor(view.X * 0.54), math.floor(view.Y * 0.65)
    if typeof(aimPosition) == "Vector3" then
        local screenPoint, visible = camera:WorldToViewportPoint(aimPosition)
        if visible and screenPoint.Z > 0 and screenPoint.X > view.X * 0.15
            and screenPoint.X < view.X * 0.88 and screenPoint.Y > view.Y * 0.1
            and screenPoint.Y < view.Y * 0.90 then
            x, y = math.floor(screenPoint.X), math.floor(screenPoint.Y)
        end
    end
    -- Never purposely click the script's own panel or the top Roblox menu.
    if panel.Visible and x >= panel.AbsolutePosition.X and x <= panel.AbsolutePosition.X + panel.AbsoluteSize.X
        and y >= panel.AbsolutePosition.Y and y <= panel.AbsolutePosition.Y + panel.AbsoluteSize.Y then
        x, y = math.floor(view.X * 0.58), math.floor(view.Y * 0.62)
    end
    -- Prefer a touch event on mobile. Different Roblox executors expose
    -- different virtual-input APIs; unavailable methods are caught safely.
    local ok, vim = pcall(game.GetService, game, "VirtualInputManager")
    if ok and vim then
        local touched = pcall(function()
            vim:SendTouchEvent(0, Enum.UserInputState.Begin, x, y)
            vim:SendTouchEvent(0, Enum.UserInputState.End, x, y)
        end)
        if touched then
            tower.inputRequests = tower.inputRequests + 1
            tower.status = (context or "Tower") .. " touch attack sent"
            return true
        end
        local clicked = pcall(function()
            vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
            vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if clicked then
            tower.inputRequests = tower.inputRequests + 1
            tower.status = "Tower click attack sent"
            return true
        end
    end
    local userOK = pcall(function()
        virtualUser = virtualUser or game:GetService("VirtualUser")
        virtualUser:CaptureController()
        virtualUser:ClickButton1(Vector2.new(x, y), camera.CFrame)
    end)
    if userOK then
        tower.inputRequests = tower.inputRequests + 1
        tower.status = "Tower virtual click sent"
        return true
    end
    tower.status = "Virtual touch blocked; try native attacks or executor input permissions"
    return false
end
-- V17 TOWER DEFENSE: independent of StageFolder and the stage attack loop.
-- Predicts locally observed projectiles; no client dodge is guaranteed to
-- override server-authoritative hits or instantaneous boss damage.
tower.safeGround = function(candidate, enemy)
    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {character}
    if enemy and enemy.model then exclude[#exclude + 1] = enemy.model end
    ray.FilterDescendantsInstances = exclude
    local hit = workspace:Raycast(candidate + Vector3.new(0, 12, 0), Vector3.new(0, -35, 0), ray)
    if not hit or not hit.Instance or not hit.Instance.CanCollide then return nil end
    local hitName = hit.Instance.Name:lower()
    for _, unsafe in ipairs({"lava", "poison", "kill", "goo", "fogsea", "acid", "hazard", "death"}) do
        if hitName:find(unsafe, 1, true) then return nil end
    end
    local floorY = hit.Position.Y
    if math.abs(floorY - root.Position.Y) > 8 then return nil end
    return Vector3.new(candidate.X, floorY + humanoid.HipHeight + root.Size.Y * 0.5 + 0.12, candidate.Z)
end

tower.dodgeStep = function(now, enemy, reach)
    if not state.tower or not tower.autoDodge or not tower.active(now) or not alive() then return false end
    if now - tower.lastDefenseStep < 0.035 then return false end
    tower.lastDefenseStep = now
    local hp = humanoid.Health
    if tower.lastHealth and hp < tower.lastHealth then tower.lastHurtAt = now end
    tower.lastHealth = hp
    local projectile = tower.predictProjectiles and nearbyThreat(now) or nil
    local enemyPos = enemy and enemy.root and enemy.root.Position or nil
    local enemyDist = enemyPos and (enemyPos - root.Position).Magnitude or math.huge
    local incomingWindup = tower.counterWindups and enemy and enemyDist < 55
        and hasAttackTelegraph(enemy) or false
    local rangedLine = enemy and enemyDist < 45 and enemyRanged(enemy) and gunLaneDanger(enemy) or false
    local retreat = tower.lowHealthRetreat and humanoid.MaxHealth > 0
        and hp / humanoid.MaxHealth < values.retreatHealth / 100
    local recentlyHit = now - tower.lastHurtAt < 0.32
    local reason = projectile and "projectile" or incomingWindup and "boss windup"
        or (rangedLine and now - tower.lastDodge > 0.65) and "gun line"
        or recentlyHit and "recent damage" or retreat and "low HP" or nil
    if not reason then return false end
    local cooldown = projectile and 0.08 or tower.dodgeCooldown
    if now - tower.lastDodge < cooldown then return false end
    local velocity = projectile and projectile.velocity
    local heading = velocity or (enemyPos and enemyPos - root.Position) or root.CFrame.LookVector
    heading = Vector3.new(heading.X, 0, heading.Z)
    if heading.Magnitude < 0.1 then heading = root.CFrame.LookVector end
    heading = heading.Unit
    local side = Vector3.new(-heading.Z, 0, heading.X)
    local extent = math.clamp(values.dodgeRange * 0.65, 4.2, 9)
    if enemy and enemyDist <= reach + 3 and not retreat then extent = math.min(extent, reach * 0.8) end
    local origin = root.Position
    local options = {origin + side * extent, origin - side * extent,
        origin + (side - heading * 0.5).Unit * extent,
        origin + (-side - heading * 0.5).Unit * extent}
    local selected, score = nil, -math.huge
    for _, point in ipairs(options) do
        local safe = tower.safeGround(point, enemy)
        if safe then
            local rank = 0
            if projectile then
                local eta = math.clamp(projectile.time or 0.18, 0.04, 0.75)
                local bullet = projectile.position + projectile.velocity * eta
                rank = rank + (safe - bullet).Magnitude * 2.4
            end
            if enemyPos then
                local distance = (safe - enemyPos).Magnitude
                if retreat then rank = rank + distance * 1.5
                else rank = rank - math.abs(distance - math.max(3, reach * 0.72)) * 2 end
            end
            if rank > score then selected, score = safe, rank end
        end
    end
    if not selected then
        tower.dodgeReason = "No safe landing: " .. reason
        return false
    end
    moveRoot(selected)
    tower.lastDodge, tower.dodgeCount = now, tower.dodgeCount + 1
    tower.dodgeReason, tower.status = reason, "Tower evade: " .. reason
    tower.lastSafeSpot = selected
    return true
end

tower.tick = function(now)
    if not state.tower or not alive() or not tower.active(now) then return false end
    if playerGui:FindFirstChild("IntroCutscene") or playerGui:FindFirstChild("GooCutscene") then
        tower.status = "Tower paused for cutscene"
        return true
    end
    loadNative()
    local enemy = tower.findEnemy(now)
    local reach = 8
    local moves = native.modules.combatConfig and native.modules.combatConfig.Moves
    local move = moves and (moves.ClawR or moves.Bite)
    if type(move) == "table" then reach = math.clamp(number(move.reach) or reach, 4, 40) end
    local canAttack = true
    -- The main fight loop is disabled in Tower, so defense must be called
    -- explicitly here and again from the independent heartbeat.
    tower.dodgeStep(now, enemy, reach)
    if enemy and enemy.root and enemy.root.Parent then
        local offset = enemy.root.Position - root.Position
        local horizontal = Vector3.new(offset.X, 0, offset.Z)
        local distance = horizontal.Magnitude
        if distance > 0.1 then
            -- Face nearest live NPC before issuing a permitted strike.
            root.CFrame = CFrame.lookAt(root.Position, Vector3.new(enemy.root.Position.X, root.Position.Y, enemy.root.Position.Z))
        end
        if tower.autoChase and distance > math.max(3, reach * 0.78)
            and now - tower.lastChase >= 0.14 and now - tower.lastDodge >= 0.12 then
            tower.lastChase = now
            local standOff = math.max(2.0, reach * 0.6)
            local goal = enemy.root.Position - horizontal.Unit * standOff
            humanoid:MoveTo(Vector3.new(goal.X, root.Position.Y, goal.Z))
            tower.status = "Approaching tower enemy: " .. enemy.model.Name
        end
        canAttack = distance <= reach * 1.35 or not tower.autoChase
        if tower.lastTargetHealth and tower.lastTargetHealth > enemy.humanoid.Health then
            tower.lastDamageAt = now
        end
        tower.lastTargetHealth = enemy.humanoid.Health
    else
        tower.lastTargetHealth = nil
    end
    if not canAttack then return true end
    if now - tower.lastAttack < tower.attackPeriod then return true end
    tower.lastAttack = now
    local m = native.modules.combat
    local success = false
    local nativeUnavailable = type(m) ~= "table" or type(m.Attack) ~= "function"
    if not nativeUnavailable and not fight.strikeBusy then
        fight.strikeBusy = true
        local busyOK, busy = fightCall(m, "Busy", true)
        if busyOK and not busy then
            local ok, accepted = fightCall(m, "Attack", true)
            if ok and accepted ~= false then
                tower.nativeRequests = tower.nativeRequests + 1
                tower.status = enemy and ("Tower native attack: " .. enemy.model.Name) or "Tower native attack"
                success = true
                tower.failedNative = 0
            else
                tower.failedNative = tower.failedNative + 1
            end
        elseif not busyOK then
            tower.failedNative = tower.failedNative + 1
        end
        fight.strikeBusy = false
    end
    -- If the controller is absent or keeps failing, synthesize the normal
    -- screen tap that the user makes manually. Also allow fallback if native
    -- attacks appear to do no damage for a sustained interval.
    if not success or (enemy and tower.nativeRequests > 0
        and now - tower.lastDamageAt > 1.4) then
        tower.tapInput(now, "Tower", enemy and enemy.root and enemy.root.Position)
    end
    if enemy and enemy.root then fight.attackWithCombatTool(now) end
    return true
end

-- V13 FIRST STRIKE: move toward a known boss before its first volley.
-- Uses short, grounded steps and the game's existing native Attack() only.
-- When a real incoming projectile is detected, dodge still has priority.
local function firstStrikeAdvance(now, target, phase, folder, reach, run)
    if not fight.preemptive or not state.fight or not run or fight.run ~= run
        or not root or not humanoid or humanoid.Health <= 0
        or not target or not target.root or not target.root.Parent
        or not target.humanoid or target.humanoid.Health <= 0
        or not folder or not folder.Parent then return false end
    if phase ~= "boss" and phase ~= "snipers" and not target.boss then return false end
    if strikeTargetInRange(target, reach) then return false end
    if now - fight.lastPreemptMove < 0.075 or now - fight.lastMove < 0.065 then return false end
    if now - fight.lastDodge < 0.065 then return false end
    local threat = fight.cachedThreat
    if threat and now - fight.lastDefensiveScan < 0.16
        and (threat.time or 1) < 0.23 then
        fight.lastFirstStrikeStatus = "Incoming projectile: defending first"
        return false
    end
    local delta = target.root.Position - root.Position
    local planar = Vector3.new(delta.X, 0, delta.Z)
    if planar.Magnitude <= math.max(1, reach * 0.64) then return false end
    local direction = planar.Unit
    local remaining = math.max(0, planar.Magnitude - math.max(2.1, math.min(3.5, reach * 0.46)))
    local windup = fight.windupCounter and hasAttackTelegraph(target)
    local stepBudget = math.clamp(values.rushStep or 11, 6, 14)
    if windup then
        stepBudget = math.min(14, stepBudget + 2)
        fight.lastFirstStrikeStatus = "Boss windup: closing fast"
    end
    local step = math.min(stepBudget, remaining)
    if step <= 0.5 then return false end
    local point = fightGround(root.Position + direction * step, folder, false)
    if not point then
        -- Retry a smaller, ground-supported step instead of a long warp.
        point = fightGround(root.Position + direction * math.min(step, 5), folder, false)
    end
    if not point then
        fight.lastFirstStrikeStatus = "Waiting for safe arena footing"
        return false
    end
    local previous = root.Position
    moveRoot(point)
    fight.lastPreemptMove, fight.lastMove, fight.lastChaseAt = now, now, now
    fight.firstStrikeRushes = fight.firstStrikeRushes + 1
    fight.lastPreemptGoal = point
    fight.lastFirstStrikeStatus = "Closing on " .. target.model.Name
    fight.lastAction = "First Strike pursuit"
    -- If the short movement put us within range, attack immediately instead
    -- of waiting for another stage loop. Busy() still limits every strike.
    if strikeTargetInRange(target, reach) then
        local did = tryNativeStrike(now, target, reach, run)
        if did then
            fight.openingAttackRequests = fight.openingAttackRequests + 1
            fight.lastFirstStrikeStatus = "First Strike request accepted"
        end
    end
    return (root.Position - previous).Magnitude > 0.1
end

tickFight = function(now)
    loadNative()
    local actualWorld = currentWorld()
    if actualWorld and fight.lastWorldSeen ~= 0 and actualWorld ~= fight.lastWorldSeen then
        fight.run = nil
        fight.waitUntil = now + 0.2
        fight.stageNPCAt, fight.lastBossScan = -math.huge, -math.huge
        fight.lastCombatTarget, fight.lastCombatFolder, fight.lastCombatPhase = nil, nil, nil
        fight.objective, fight.objectiveAt = nil, -math.huge
        fight.worldResyncs = fight.worldResyncs + 1
        fightNotice("World changed to " .. tostring(actualWorld) .. "; resyncing stage combat.")
    end
    if actualWorld then fight.lastWorldSeen = actualWorld end
    if not fightModulesReady() then fightNotice("Auto fights: waiting for native combat controllers.") return false end
    fightReceipt()
    if tower.active(now) then
        fightNotice("Tower active: V17 dual combat switched to Tower controls.") return true
    end
    if playerGui:FindFirstChild("IntroCutscene") or playerGui:FindFirstChild("GooCutscene") then
        fightNotice("Auto fights paused during a cutscene.") return true
    end
    if now < fight.waitUntil then return fight.releasingTraining == true or fight.run ~= nil end
    local ok, active = fightCall(native.modules.encounter, "Active", true)
    if not ok then fightNotice("Native encounter state is unavailable.") return false end
    active = number(active)
    if active and (active < 1 or active > 1000 or active % 1 ~= 0) then active = nil end
    if not fight.run then
        local stage, reason = active, nil
        if not stage then stage, reason = startStage() end
        if not stage then fightNotice("Auto fights: " .. reason) return false end
        if native.current then
            stopNative(true)
            fight.releasingTraining, fight.releaseStartedAt, fight.waitUntil = true, now, now + 1
            return true
        end
        if nativeActive() == true then
            fightNotice("Leave the current speaker before starting a fight.")
            if fight.releaseStartedAt and now - fight.releaseStartedAt > 5 then
                failFight("The speaker did not release before combat. Leave it and retry Auto fights.")
            end
            return true
        end
        fight.releasingTraining, fight.releaseStartedAt = false, nil
        local targetWorld = stageWorld(stage)
        if fight.allPortals and targetWorld and currentWorld() ~= targetWorld then
            if not travelToWorld(targetWorld, now) then
                fightNotice("Portal routing: " .. tostring(fight.portalStatus))
                return true
            end
        end
        if targetWorld and currentWorld() and currentWorld() ~= targetWorld then
            fightNotice("Waiting to arrive in world " .. tostring(targetWorld) .. ".")
            return true
        end
        fight.run = {stage = stage, character = character, started = now, progressAt = now,
            totalHealth = math.huge, count = math.huge, enteredAt = -math.huge, lastEntry = -math.huge}
    end
    local run = fight.run
    if run.character ~= character then resetFightCharacter() return false end
    if run.won then
        local stage = run.stage
        if state.progress then
            progress.successRuns = progress.successRuns + 1
            -- Stay on a proven stage while farming Wins; retry hard stages only
            -- after more levels or a new Evolution improves combat power.
        end
        local folder = fight.repeatRuns and stageFolder(stage)
        if folder and not outsideFight(root.Position, folder) then
            local point = fightExit(folder)
            if not point then fightNotice("Reward confirmed. Move outside the stage to allow a replay.") return true end
            moveRoot(point)
            fight.waitUntil = now + 1
            return true
        end
        fight.run, fight.defeats, fight.waitUntil = nil, 0, now + 2
        if not fight.repeatRuns then state.fight = false refresh() end
        fightNotice("Stage " .. tostring(stage) .. " reward confirmed.") return false
    end
    if active and active ~= run.stage and now - run.enteredAt > 5 then
        run.stage, run.started, run.progressAt = active, now, now
        run.claimedAt, run.won, run.count, run.totalHealth = nil, false, math.huge, math.huge
        run.lockedTarget = nil
        fight.cachedBosses, fight.lastBossScan, fight.stageNPCAt, fight.stageNPCs = {}, -math.huge, -math.huge, {}
    end
    local folder = stageFolder(run.stage)
    if not folder then fightNotice("Waiting for stage " .. tostring(run.stage) .. " to load.") return true end
    local stateOK, phase, alreadyWon = fightCall(native.modules.encounter, "StageState", true, run.stage)
    if not stateOK or type(phase) ~= "string" then fightNotice("Waiting for the native stage state.") return true end
    if run.claimedAt then
        if now - run.claimedAt > 12 then failFight("Reward acknowledgement timed out. Open diagnostics before retrying.") end
        return true
    end
    if alreadyWon == true then
        if now - run.started > 25 then failFight("The completed stage did not reset. Leave the arena before retrying.") return false end
        if not outsideFight(root.Position, folder) and now - run.lastEntry >= 2 then
            local point = fightExit(folder)
            if point then moveRoot(point) run.lastEntry = now end
        end
        fightNotice("Waiting outside the completed stage for replay readiness.") return true
    end
    local target, count, health = fightEnemies(run.stage, phase, folder, now)
    fight.lastCombatPhase, fight.lastCombatFolder, fight.lastCombatTarget = phase, folder, target
    if count == nil then fightNotice("Waiting for the stage's enemy roster to load.") return true end
    if count < run.count or health < run.totalHealth or (run.count == 0 and count > 0) then run.progressAt = now end
    run.count, run.totalHealth = count, health
    if phase == "cleared" then
        local ready = player:GetAttribute("WinReady")
        if count > 0 or type(ready) ~= "string" or not ready:find("," .. tostring(run.stage) .. ",", 1, true) then
            fightNotice("Waiting for the server to confirm stage " .. tostring(run.stage) .. " is cleared.") return true
        end
        local nextStage = run.stage + 1
        if fight.advance and (values.stageLimit == 0 or nextStage <= values.stageLimit) and stageAvailable(nextStage) then
            local _, advice = stageAdvice(nextStage)
            local nextFolder = advice == "ready" and stageFolder(nextStage)
            local point = nextFolder and fightEntry(nextFolder)
            if advice == "ready" and not point then fightNotice("Waiting for the next stage's landing area.") return true end
            if point then
                moveRoot(point)
                run.stage, run.started, run.progressAt, run.enteredAt, run.lastEntry = nextStage, now, now, now, now
                run.count, run.totalHealth = math.huge, math.huge
                run.lockedTarget = nil
                fight.cachedBosses, fight.lastBossScan, fight.stageNPCAt, fight.stageNPCs = {}, -math.huge, -math.huge, {}
                fightNotice("Advancing to stage " .. tostring(nextStage) .. ".") return true
            end
        end
        local pad = fightWinPad(run.stage, folder)
        local point = pad and fightGround(pad.Position, folder, true)
        if not point then fightNotice("Waiting for the stage's free Wins pad.") return true end
        run.claimedAt = now moveRoot(point)
        fightNotice("Collecting stage " .. tostring(run.stage) .. " reward; waiting for server confirmation.") return true
    end
    if phase == "idle" then
        if not stageAvailable(run.stage) then failFight("This stage is locked. Unlock it before enabling Auto fights.") return false end
        local message, advice = stageAdvice(run.stage)
        if advice ~= "ready" then fight.run = nil fightNotice(message) return false end
        if now - run.started > 25 then failFight("The stage did not start. Open diagnostics before retrying.") return false end
        if now - run.lastEntry >= 3 then
            local point = fightEntry(folder)
            if not point then fightNotice("No supported landing area in this stage. Open diagnostics.") return true end
            run.enteredAt, run.lastEntry = now, now moveRoot(point)
            fightNotice("Entering stage " .. tostring(run.stage) .. ".")
        end
        return true
    end
    if phase ~= "waves" and phase ~= "boss" and phase ~= "snipers" then
        fightNotice("Waiting for the next encounter phase: " .. phase) return true
    end
    if active ~= run.stage then return true end
    if now - run.progressAt > (phase == "boss" and 85 or 55) then
        if state.progress and progress.safeFarm then
            progress.failedStage = run.stage
            progress.safeStageCap = math.max(1, run.stage - 1)
            progress.levelAtFail = number(player:GetAttribute("Level"))
            progress.saferUntil = now + 30
        end
        failFight("No combat progress; the enemy may be unreachable. Inspect the target and stage diagnostics.")
        return false
    end
    -- Prioritize shield generators / turret pylons before an invulnerable boss.
    -- Scan nearby objects only during boss phases; regular waves work unchanged.
    if fight.autoShieldObjectives and (phase == "boss" or phase == "snipers" or not target) then
        local structure = fight.findStageObjective(folder, target, now)
        if structure then
            local moves = native.modules.combatConfig and native.modules.combatConfig.Moves
            local default = moves and (moves.ClawR or moves.Bite)
            local reachObjective = type(default) == "table" and (number(default.reach) or 7) or 7
            if fight.tickStageObjective(now, folder, structure, run, math.clamp(reachObjective, 3, 40)) then
                fight.lastCombatTarget = nil
                run.lockedTarget = nil
                fight.lastAction = "Shield objective: " .. structure.name
                fightNotice("Stage " .. tostring(run.stage) .. " | " .. fight.objectiveStatus)
                return true
            end
        end
    end
    if not target then
        evadeFight(now, nil, phase, folder, 7)
        if now - run.progressAt > 5 then fight.stageNPCAt = -math.huge end
        fightNotice("Stage " .. tostring(run.stage) .. ": scanning stage rigs for enemies and gun bosses.")
        return true
    end
    -- Chase targets even while an attack animation is active. The native
    -- combat controller still determines whether another strike is permitted.
    if run.lockedTarget ~= target.model then
        run.lockedTarget = target.model
        run.targetHp, run.targetDamageAt, run.targetAttackRequests = target.humanoid.Health, now, 0
        run.targetFallbackAt = now
        fight.lastTargetSeenAt = now
        fight.lastFirstStrikeTarget = target.model
        fight.lastFirstStrikeStatus = "Target acquired: " .. target.model.Name
    end
    local hpNow = target.humanoid.Health
    if run.targetHp and hpNow < run.targetHp then
        local dealt = run.targetHp - hpNow
        fight.hpDamageDealt = fight.hpDamageDealt + dealt
        fight.hpConfirmedHits = fight.hpConfirmedHits + 1 -- observed damage events, not every swing
        if target.boss then fight.hpConfirmedBossHits = fight.hpConfirmedBossHits + 1 end
        fight.lastConfirmedDamageAt = now
        run.targetDamageAt, run.targetFallbackAt = now, now
        run.targetAttackRequests = 0
        fight.attackStatus = "Enemy HP decreased: " .. tostring(math.floor(dealt * 10) / 10)
    end
    run.targetHp = hpNow
    fight.lastEnemyHp = hpNow
    fight.lastEnemyName = target.model.Name
    local stall = (run.targetAttackRequests or 0) >= 3 and (now - (run.targetDamageAt or now) > 2.4)
    fight.bossStall = stall and (now - (run.targetDamageAt or now)) or 0
    local moves = native.modules.combatConfig and native.modules.combatConfig.Moves
    local move = moves and moves.Bite
    if moves and type(moves.ClawR) == "table" and (number(player:GetAttribute("BondStage")) or 0) >= (number(moves.ClawR.level) or math.huge) then
        move = moves.ClawR
    end
    local reach = type(move) == "table" and number(move.reach) or 7
    reach = math.max(1, math.min(100, (reach or 7) - 0.25))
    fight.lastCombatReach = reach
    -- Defensive movement is independent of native attack readiness. Dodging
    -- must never cancel an eligible boss attack that is still in reach.
    local distance3d = (target.root.Position - root.Position).Magnitude
    local offset3d = target.root.Position - root.Position
    local horizontalDistance = Vector3.new(offset3d.X, 0, offset3d.Z).Magnitude
    -- A very large evolved avatar's root can be higher than normal NPC rigs.
    -- Try an attack when horizontally in reach, but leave true hit validation
    -- to the game server.
    local inRange = distance3d <= reach or
        (horizontalDistance <= reach * 0.85 and math.abs(offset3d.Y) <= math.max(9, reach * 1.5))
    -- Make the first attack as soon as native combat allows it. This can
    -- precede the boss's windup but cannot ignore the server's cooldown.
    if inRange then
        if fight.windupCounter and hasAttackTelegraph(target) then
            fight.lastCounterAt = now
            fight.lastFirstStrikeStatus = "Boss windup: attacking while in range"
        end
        local accepted = tryNativeStrike(now, target, reach, run)
        if accepted and now - fight.lastTargetSeenAt < 0.6 then
            fight.openingAttackRequests = fight.openingAttackRequests + 1
        end
    elseif fight.preemptive then
        firstStrikeAdvance(now, target, phase, folder, reach, run)
    end
    -- Defense runs independently and keeps an actual projectile as priority.
    local newOffset = target.root.Position - root.Position
    inRange = newOffset.Magnitude <= reach or
        (Vector3.new(newOffset.X, 0, newOffset.Z).Magnitude <= reach * 0.85
            and math.abs(newOffset.Y) <= math.max(9, reach * 1.5))
    local dodged = false
    if not inRange then
        dodged = evadeFight(now, target, phase, folder, reach)
    end
    local distance = (target.root.Position - root.Position).Magnitude
    if not inRange and distance > reach then
        local since = now - fight.lastMove
        -- IMPORTANT: V5 skipped chasing after every dodge. Gun bosses therefore
        -- never got into melee reach. V6 keeps closing with short intervals.
        if since >= 0.11 and (not dodged or distance > reach + 4)
            and now - fight.lastDodge >= 0.085 then
            local delta = root.Position - target.root.Position
            local flat = Vector3.new(delta.X, 0, delta.Z)
            local direction = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, 1)
            local radius = stall and math.max(1.5, math.min(2.5, reach * 0.32))
                or math.max(2, math.min(3.3, reach * 0.45))
            local center = target.root.Position
            local attempts = {
                center + direction * radius,
                center + Vector3.new(-direction.Z, 0, direction.X) * radius,
                center + Vector3.new(direction.Z, 0, -direction.X) * radius,
                center + direction * (radius + 4),
            }
            local point
            for _, candidate in ipairs(attempts) do
                point = fightGround(candidate, folder, false)
                if point then break end
            end
            if point then
                -- Once within effective range, the native attack has priority.
                moveRoot(point)
                fight.lastMove, fight.lastChaseAt = now, now
                distance = (target.root.Position - root.Position).Magnitude
            else
                -- Fallback to built-in movement. The enemy may be on another
                -- BasePart that the arena ground ray cannot identify.
                local toward = target.root.Position - root.Position
                toward = Vector3.new(toward.X, 0, toward.Z)
                if toward.Magnitude > 2.5 then
                    humanoid:MoveTo(root.Position + toward.Unit * math.min(7, toward.Magnitude - 2))
                    fight.lastMove, fight.lastChaseAt = now, now
                    fight.chaseFallbacks = fight.chaseFallbacks + 1
                end
                if now - fight.lastCombatReport > 1.2 then
                    fight.lastCombatReport = now
                    fightNotice("Ground fallback: approaching " .. target.model.Name .. " by MoveTo.")
                end
            end
        end
        local planar = target.root.Position - root.Position
        local planarDistance = Vector3.new(planar.X, 0, planar.Z).Magnitude
        if distance > reach and not (planarDistance <= reach * 0.85
            and math.abs(planar.Y) <= math.max(9, reach * 1.5)) then
            fight.lastAction = "Chasing " .. target.model.Name .. " / " .. math.floor(distance) .. " studs"
            return true
        end
    end
    -- If the server confirms no damage after multiple attack requests,
    -- correct distance before trying again instead of continuing to swing
    -- helplessly at the enemy's collision edge.
    if stall and now - fight.lastMove > 0.40 then
        local offset = target.root.Position - root.Position
        local lateral = Vector3.new(offset.X, 0, offset.Z)
        if lateral.Magnitude > 2.7 then
            local closer = target.root.Position - lateral.Unit * 2.0
            local safe = fightGround(closer, folder, false)
            if safe then
                moveRoot(safe)
                fight.lastMove, fight.lastChaseAt = now, now
            else
                humanoid:MoveTo(root.Position + lateral.Unit * math.min(lateral.Magnitude - 2, 5))
            end
        end
        run.targetDamageAt = now - 1.25 -- avoid chasing every 50ms
    end
    -- Attack windows now begin only when a real native strike is sent.
    -- Rewriting this every 50ms previously suppressed ranged defense forever.
    local face = Vector3.new(target.root.Position.X, root.Position.Y, target.root.Position.Z)
    if (face - root.Position).Magnitude > 0.01 then
        root.CFrame = CFrame.lookAt(root.Position, face)
    end
    -- Attack even after a dodge, if we remain in legitimate melee range.
    -- Heartbeat also checks readiness between normal 50ms fight iterations.
    tryNativeStrike(now, target, reach, run)
    if inRange then fight.attackWithCombatTool(now) end
    -- V17 main-world regression recovery: if attack requests are not changing
    -- real enemy HP, optionally send the same short input used for Tower.
    -- Do not infer damage from a native Attack() return value.
    if fight.mainTapFallback and strikeTargetInRange(target, reach)
        and now - (run.targetFallbackAt or run.started) >= 1.3
        and now - fight.mainFallbackAt >= 0.30 then
        fight.mainFallbackAt = now
        if tower.tapInput(now, "Main", target.root.Position) then
            fight.mainFallbackCount = fight.mainFallbackCount + 1
            fight.attackStatus = "Main input fallback tried after no HP change"
        end
    end
    return true
end

-- ASCENSION: progression is read from the actual player + DataController.
-- No client-side writes to Level/Wins/Evolutions, no purchases, and no guessed remotes.
local function statValue(key)
    local raw = number(nativeCall(native.modules.data, "Get", true, key))
    if raw ~= nil then return raw end
    raw = number(player:GetAttribute(key))
    if raw ~= nil then return raw end
    local stats = player:FindFirstChild("leaderstats")
    local entry = stats and stats:FindFirstChild(key)
    if entry and entry:IsA("ValueBase") then return number(entry.Value) end
end
local function firstStat(keys)
    for _, key in ipairs(keys) do
        local v = statValue(key)
        if v ~= nil then return v end
    end
end
local function configStat(row, keys)
    if type(row) ~= "table" then return nil end
    for _, key in ipairs(keys) do
        local v = number(row[key])
        if v ~= nil then return v end
    end
end
local function nextGoal(evo)
    local tier = number(evo)
    local config = native.modules.evolutionConfig
    local source = "Live evolution configuration"
    -- Prefer explicit values from the live game's config when recognized.
    if tier ~= nil and type(config) == "table" then
        local list = type(config.List) == "table" and config.List
            or type(config.Forms) == "table" and config.Forms
            or type(config.Evolutions) == "table" and config.Evolutions
            or config
        local entry = list[tier + 1] or list[tostring(tier + 1)]
        local level = configStat(entry, {"Level", "level", "RequiredLevel", "LevelRequired", "MinLevel", "levelRequired"})
        local wins = configStat(entry, {"Wins", "wins", "RequiredWins", "WinCost", "WinsRequired", "winCost"})
        if level and wins and level > 0 and wins >= 0 then return level, wins, source end
    end
    if tier == nil then
        return nil, nil, "Evolution tier unavailable; check in-game panel"
    elseif tier == 0 then
        return 30, 75, "Published Feral checkpoint"
    elseif tier == 1 then
        return 35, 109, "Published post-Feral checkpoint"
    end
    return nil, nil, "Later evolution requirements unknown; use in-game panel"
end
local function snapshotProgress()
    local data = {
        level = firstStat({"Level", "level"}),
        wins = firstStat({"Wins", "wins"}),
        evolutions = firstStat({"Evolutions", "Evolution", "EvolutionCount"}),
        venom = readVenom(),
    }
    local levelGoal, winGoal, source = nextGoal(data.evolutions)
    if values.targetLevel > 0 then levelGoal, source = values.targetLevel, "Manual goal override" end
    if values.targetWins > 0 then winGoal, source = values.targetWins, "Manual goal override" end
    data.goalLevel, data.goalWins, data.source = levelGoal, winGoal, source
    data.levelMissing = levelGoal and data.level and math.max(0, levelGoal - data.level) or nil
    data.winsMissing = winGoal and data.wins and math.max(0, winGoal - data.wins) or nil
    return data
end
local function progressNotice(message, now)
    progress.detail = message
    if now - progress.lastNotice > 9 then
        progress.lastNotice = now
        notify("ASCENSION: " .. message)
    end
end
local function isShown(item)
    local node = item
    while node and node ~= playerGui do
        if node:IsA("GuiObject") and not node.Visible then return false end
        node = node.Parent
    end
    return node == playerGui
end
local function freeEvolveButton()
    -- Exact text matching avoids buttons for paid gamepasses, boosts, or products.
    for _, item in ipairs(playerGui:GetDescendants()) do
        if item:IsA("GuiButton") and isShown(item) then
            local name = item.Name:lower()
            local label = item:IsA("TextButton") and item.Text:lower():gsub("<[^>]+>", "") or ""
            label = label:gsub("^%s+", ""):gsub("%s+$", "")
            local exact = label == "evolve" or label == "evolve!" or name == "evolvebutton"
                or name == "evolve" or name == "evolvenow"
            local unsafe = (name .. " " .. label):find("buy", 1, true)
                or (name .. " " .. label):find("robux", 1, true)
                or (name .. " " .. label):find("purchase", 1, true)
                or (name .. " " .. label):find("pass", 1, true)
            local interactable = true
            pcall(function() interactable = item.Interactable end)
            if exact and not unsafe and interactable then return item end
        end
    end
end
local function tryFreeEvolve(now)
    if not progress.autoEvolve or now - progress.lastEvolutionCheck < 15 then return end
    progress.lastEvolutionCheck = now
    if progress.evoAttempts >= 3 then
        progressNotice("Evolution ready. Open the game Evolution menu and tap Evolve.", now)
        return
    end
    local button = freeEvolveButton()
    if not button then
        progressNotice("Evolution ready. Open the game Evolution menu to confirm the FREE Evolve action.", now)
        return
    end
    local ok = pcall(function() button:Activate() end)
    if ok then
        progress.evoAttempts = progress.evoAttempts + 1
        progressNotice("Pressed recognized free Evolve button; waiting for the server.", now)
    else
        progressNotice("Automatic Evolve click wasn't accepted. Use the in-game button.", now)
    end
end
local function restoreProgressSettings()
    if progress.storedAdvance ~= nil then fight.advance = progress.storedAdvance progress.storedAdvance = nil end
    if progress.storedRepeat ~= nil then fight.repeatRuns = progress.storedRepeat progress.storedRepeat = nil end
end
stopProgress = function()
    state.progress = false
    restoreProgressSettings()
    progress.mode, progress.detail = "idle", "Evolution Autopilot stopped"
end
local function desiredProgressMode(now, data)
    if progress.strategy == "TRAIN" then return "train" end
    if progress.strategy == "WINS" then return "fight" end
    if now < progress.saferUntil then return "train" end
    if data.goalLevel and data.level and data.level < data.goalLevel then return "train" end
    if data.goalWins and data.wins and data.wins < data.goalWins then return "fight" end
    if data.goalLevel and data.goalWins and data.level and data.wins then
        if data.level >= data.goalLevel and data.wins >= data.goalWins then return "ready" end
    end
    -- Unknown stats or later evolutions: alternate a reasonable training / Wins loop.
    if progress.fallbackStart == 0 then progress.fallbackStart = now end
    local elapsed = (now - progress.fallbackStart) % 110
    return elapsed < 70 and "train" or "fight"
end
local function setProgressMode(wanted, now)
    if wanted == progress.mode and (wanted == "train" and state.train and not state.fight
        or wanted == "fight" and state.fight and not state.train
        or wanted == "ready" and not state.train and not state.fight) then return end
    if wanted == "train" and state.fight and fight.run and not fight.run.won then
        local phase = fight.lastCombatPhase
        local progressAt = fight.run.progressAt or now
        if (phase == "waves" or phase == "boss" or phase == "snipers") and now - progressAt < 10
            and now >= progress.saferUntil then
            progress.detail = "Finishing active stage before changing to training"
            return
        end
    end
    if state.fight then state.fight = false stopFight() end
    if state.train then state.train = false stopNative(true) end
    if wanted == "fight" then
        state.fight = true
        fight.lastAttack, fight.lastMove, fight.waitUntil = -math.huge, -math.huge, now + 0.5
        fight.defeats = 0
        progress.detail = "Farming repeatable stages for Wins"
    elseif wanted == "train" then
        state.train = true
        native.scanAt = -math.huge
        progress.detail = "Training at strongest unlocked speaker"
    else
        progress.detail = "Evolution requirements met; awaiting free Evolution action"
    end
    progress.mode, progress.modeStart, progress.lastSwitch = wanted, now, now
    refresh()
end
local function tickProgress(now)
    if not state.progress or not alive() or now - progress.lastEvaluation < 0.7 then return end
    progress.lastEvaluation = now
    loadNative()
    local data = snapshotProgress()
    progress.latest = data
    progress.goalLevel, progress.goalWins, progress.goalSource = data.goalLevel, data.goalWins, data.source
    if data.evolutions and progress.previousEvolutions and data.evolutions > progress.previousEvolutions then
        progress.evolutionsObserved = progress.evolutionsObserved + (data.evolutions - progress.previousEvolutions)
        progress.saferUntil, progress.safeStageCap, progress.failedStage, progress.levelAtFail = 0, nil, nil, nil
        progress.evoAttempts, progress.fallbackStart = 0, 0
        native.scanAt = -math.huge
        stopNative(true)
        progressNotice("Evolution confirmed! Rescanning newly unlocked speakers.", now)
    end
    if data.level and progress.levelAtFail and data.level >= progress.levelAtFail + 3 then
        -- More combat power: allow a previously failed stage to be retried.
        progress.safeStageCap, progress.levelAtFail = nil, nil
    end
    if data.wins and progress.previousWins and data.wins > progress.previousWins then
        progress.winsEarned = progress.winsEarned + (data.wins - progress.previousWins)
        progress.saferUntil = 0
    end
    progress.previousEvolutions = data.evolutions or progress.previousEvolutions
    progress.previousLevel = data.level or progress.previousLevel
    progress.previousWins = data.wins or progress.previousWins
    local wanted = desiredProgressMode(now, data)
    if wanted ~= progress.mode and now - progress.lastSwitch < 2.5 then return end
    setProgressMode(wanted, now)
    if wanted == "ready" then tryFreeEvolve(now) end
end

local function antiAfkInput()
    local ok, err = pcall(function()
        virtualUser = virtualUser or game:GetService("VirtualUser")
        virtualUser:CaptureController()
        local camera = workspace.CurrentCamera
        if camera then virtualUser:ClickButton2(Vector2.new(0, 0), camera.CFrame)
        else virtualUser:ClickButton2(Vector2.new(0, 0)) end
    end)
    if ok then afkInputs = afkInputs + 1
    else notify("Anti-AFK input blocked: " .. tostring(err):sub(1, 100)) end
    return ok
end

section("EVOLUTION AUTOPILOT")
note("ASCENSION automatically selects training or fight stages based on real Level/Wins, and confirms evolution through the game's own free UI only.")
local progressStats = ordered(label(scroll, "LV ? -> ?  |  WINS ? -> ?  |  FORM ?", 12))
progressStats.Size = UDim2.new(1, 0, 0, 42)
progressStats.BackgroundColor3 = color.hud
progressStats.BackgroundTransparency = 0
progressStats.TextColor3 = color.on
progressStats.Font = Enum.Font.GothamBold
round(progressStats, 9)
local progressStatus = ordered(label(scroll, "ASCENSION OFF  /  Enable autopilot to begin", 11))
progressStatus.Size = UDim2.new(1, 0, 0, 42)
progressStatus.TextColor3 = color.muted
progressStatus.TextWrapped = true
local progressButton = ordered(button(scroll, "", function()
    if not state.progress then
        if game.GameId ~= 10769464063 or not alive() then
            notify("Enter +1 Venom Evolution and wait for your character to load.") return
        end
        state.noclip, state.hold, state.prompt, state.tool, state.speed, state.jump = false, false, false, false, false, false
        restoreCollisions() restoreMotion() endInteractions()
        if progress.storedAdvance == nil then progress.storedAdvance = fight.advance end
        if progress.storedRepeat == nil then progress.storedRepeat = fight.repeatRuns end
        fight.advance, fight.repeatRuns = false, true
        state.progress = true
        progress.lastEvaluation, progress.lastSwitch = -math.huge, -math.huge
        progress.mode, progress.fallbackStart, progress.evoAttempts = "idle", 0, 0
        progress.previousLevel, progress.previousWins, progress.previousEvolutions = nil, nil, nil
        loadNative() scanNative()
        notify("ASCENSION enabled. Selecting best available progression route.")
    else
        stopProgress()
        state.train, state.fight = false, false
        stopNative(true) stopFight()
        notify("ASCENSION stopped. Auto Train and Auto Fights disabled.")
    end
    refresh()
end))
local strategyButton = ordered(button(scroll, "", function()
    if progress.strategy == "SMART" then progress.strategy = "TRAIN"
    elseif progress.strategy == "TRAIN" then progress.strategy = "WINS"
    else progress.strategy = "SMART" end
    progress.lastEvaluation, progress.lastSwitch = -math.huge, -math.huge
    refresh()
end))
local autoEvolveButton = ordered(button(scroll, "", function()
    progress.autoEvolve = not progress.autoEvolve
    refresh()
end))
local safeFarmButton = ordered(button(scroll, "", function()
    progress.safeFarm = not progress.safeFarm
    if not progress.safeFarm then progress.saferUntil, progress.safeStageCap = 0, nil end
    refresh()
end))
refreshers[#refreshers + 1] = function()
    progressButton.Text = (state.progress and "● " or "○ ") .. "EVOLUTION AUTOPILOT" .. (state.progress and "   [ON]" or "   [OFF]")
    if state.progress then recolorButton(progressButton, color.active, color.activeTint, color.on, color.on)
    else recolorButton(progressButton, color.card, color.cardTint, color.edge, color.text) end
    strategyButton.Text = "Priority: " .. progress.strategy .. "  |  Tap to change"
    autoEvolveButton.Text = "FREE evolution UI click: " .. (progress.autoEvolve and "ON" or "OFF")
    safeFarmButton.Text = "Back off hard stages: " .. (progress.safeFarm and "ON" or "OFF")
end
stepper("Goal Level override (0 = auto)", "targetLevel", 0, 200, 5)
stepper("Goal Wins override (0 = auto)", "targetWins", 0, 2000, 25)
note("SMART trains until the next Level threshold, then farms free Wins. Unknown later requirements trigger a balanced fallback. Auto Evolve never buys passes or fabricates progress.")
ordered(button(scroll, "Check evolution progress now", function()
    loadNative()
    local d = snapshotProgress()
    notify("Level " .. tostring(d.level or "?") .. "/" .. tostring(d.goalLevel or "?")
        .. " | Wins " .. tostring(d.wins or "?") .. "/" .. tostring(d.goalWins or "?")
        .. " | Evolutions " .. tostring(d.evolutions or "?") .. ". " .. d.source)
end))

section("AUTO TRAIN")
note("Finds the speaker pads automatically and chooses your strongest unlocked chamber. Rechecks unlocks as you progress.")
ordered(button(scroll, "Rescan speaker pads", function()
    loadNative()
    scanNative()
    local best = alive() and bestNative()
    notify("Found " .. tostring(#native.stations) .. " speaker pads. "
        .. (best and ("Best owned: x" .. tostring(best.mult) .. " " .. best.name) or "Open diagnostics if no owned pad is available."))
end))
toggle("Auto train: best unlocked speaker", "train", function()
    if game.GameId ~= 10769464063 then notify("This Auto train integration targets +1 Venom Evolution.") return false end
    if not alive() then notify("Wait until your character is ready.") return false end
    state.noclip, state.hold, state.prompt, state.tool, state.speed, state.jump = false, false, false, false, false, false
    restoreCollisions()
    restoreMotion()
    endInteractions()
    stopNative(false)
    native.scanAt = -math.huge
    loadNative()
    scanNative()
    return true
end)
note("Speaker access follows the game's unlocks. A higher level alone may not unlock the next chamber; evolution and group requirements still apply.")

section("AUTO FIGHTS")
toggle("Auto fights", "fight", function()
    if game.GameId ~= 10769464063 then notify("This integration targets +1 Venom Evolution.") return false end
    if not alive() then notify("Wait until your character is ready.") return false end
    state.noclip, state.hold, state.prompt, state.tool, state.speed, state.jump = false, false, false, false, false, false
    restoreCollisions() restoreMotion() endInteractions()
    stopFight()
    fight.defeats, fight.origin, fight.attacks, fight.accepted = 0, root.Position, 0, 0
    fight.hpConfirmedHits, fight.hpConfirmedBossHits, fight.hpDamageDealt = 0, 0, 0
    fight.chaseFallbacks, fight.groundFallbacks, fight.attacksBlocked = 0, 0, 0
    fight.attackStatus, fight.lastEnemyHp, fight.lastEnemyName = "Starting", nil, "None"
    fight.dodgeCount, fight.bossHits, fight.healthLost, fight.seenProjectiles = 0, 0, 0, 0
    fight.lastHealth, fight.lastHurtAt, fight.lastDodge = humanoid.Health, -math.huge, -math.huge
    fight.lastAttack, fight.lastMove, fight.lastChaseAt = -math.huge, -math.huge, -math.huge
    fight.attackWindowUntil, fight.lastCriticalDodge = -math.huge, -math.huge
    fight.suppressedStrafes, fight.deniedApproach, fight.lastThreatClass = 0, 0, "None"
    fight.lastDefensiveScan, fight.cachedThreat = -math.huge, nil
    fight.lastCombatReport, fight.dodgeReason = -math.huge, "None"
    fight.projectileHistory, fight.stageNPCAt, fight.stageNPCs = setmetatable({}, {__mode = "k"}), -math.huge, {}
    fight.dodgesCorrected, fight.shotsDodged, fight.blockedGrounds = 0, 0, 0
    fight.lastStrikeProbe, fight.strikeBusy = -math.huge, false
    fight.overdriveAttempts, fight.cooldownSkips, fight.dodgedWithoutLeavingRange = 0, 0, 0
    fight.firstStrikeRushes, fight.openingAttackRequests = 0, 0
    fight.lastFirstStrike, fight.lastPreemptMove, fight.lastTargetSeenAt = -math.huge, -math.huge, -math.huge
    fight.lastFirstStrikeTarget, fight.lastPreemptGoal, fight.lastFirstStrikeStatus = nil, nil, "Armed"
    fight.damageWindowStarted, fight.rangedDamageWindow = -math.huge, 0
    return true
end)
note("V17: Main Auto Fights starts ON for immediate combat. Tower is detected separately; active normal stages always take priority. Use Auto fights to pause main-stage combat.")
fight.mainFallbackButton = ordered(button(scroll, "", function()
    fight.mainTapFallback = not fight.mainTapFallback
    refresh()
end))
refreshers[#refreshers + 1] = function()
    fight.mainFallbackButton.Text = "MAIN attack input fallback  |  " .. (fight.mainTapFallback and "ON" or "OFF")
end

do
do
section("TOWER AUTO COMBAT")
note("Halloween Tower and other floor encounters use different combat logic. Auto Tower Combat is ON by default: enter the tower and it will try attacks without screen taps.")
local towerButton = ordered(button(scroll, "", function()
    state.tower = not state.tower
    tower.lastAttack, tower.lastInput, tower.lastScan, tower.lastDodge = -math.huge, -math.huge, -math.huge, -math.huge
    tower.status = state.tower and "Tower Auto Combat armed" or "Tower Auto Combat disabled"
    refresh()
    notify(tower.status)
end))
local towerFallbackButton = ordered(button(scroll, "", function()
    tower.inputFallback = not tower.inputFallback
    refresh()
end))
local towerChaseButton = ordered(button(scroll, "", function()
    tower.autoChase = not tower.autoChase
    refresh()
end))
tower.dodgeButton = ordered(button(scroll, "", function() tower.autoDodge = not tower.autoDodge refresh() end))
tower.bulletsButton = ordered(button(scroll, "", function() tower.predictProjectiles = not tower.predictProjectiles refresh() end))
tower.bossButton = ordered(button(scroll, "", function() tower.bossPriority = not tower.bossPriority refresh() end))
tower.finisherButton = ordered(button(scroll, "", function() tower.quickFinisher = not tower.quickFinisher refresh() end))
tower.retreatButton = ordered(button(scroll, "", function() tower.lowHealthRetreat = not tower.lowHealthRetreat refresh() end))
tower.counterButton = ordered(button(scroll, "", function() tower.counterWindups = not tower.counterWindups refresh() end))
tower.statusLabel = ordered(label(scroll, "Tower combat armed; awaiting a tower floor.", 11))
tower.statusLabel.TextColor3 = color.muted
tower.statusLabel.Size = UDim2.new(1, 0, 0, 60)
refreshers[#refreshers + 1] = function()
    towerButton.Text = "AUTO TOWER ATTACK  |  " .. (state.tower and "ON" or "OFF")
    towerFallbackButton.Text = "Screen-tap fallback  |  " .. (tower.inputFallback and "ON" or "OFF")
    towerChaseButton.Text = "Chase tower enemies  |  " .. (tower.autoChase and "ON" or "OFF")
    tower.dodgeButton.Text = "Tower SMART DODGE  |  " .. (tower.autoDodge and "ON" or "OFF")
    tower.bulletsButton.Text = "Tower projectile prediction  |  " .. (tower.predictProjectiles and "ON" or "OFF")
    tower.bossButton.Text = "Tower boss-first targeting  |  " .. (tower.bossPriority and "ON" or "OFF")
    tower.finisherButton.Text = "QUICK FINISHER / weakened enemies  |  " .. (tower.quickFinisher and "ON" or "OFF")
    tower.counterButton.Text = "Tower attack-windup dodge  |  " .. (tower.counterWindups and "ON" or "OFF")
    tower.retreatButton.Text = "Tower low-HP retreat  |  " .. (tower.lowHealthRetreat and "ON" or "OFF")
    if state.tower then
        recolorButton(towerButton, color.active, color.activeTint, color.on, color.on)
    else
        recolorButton(towerButton, color.card, color.cardTint, color.edge, color.text)
    end
end
ordered(button(scroll, "Check Tower combat now", function()
    loadNative()
    local detected = tower.active(os.clock())
    notify("Tower detected: " .. tostring(detected) .. " (" .. tower.source .. ")  |  " .. tower.status
        .. "  |  native requests=" .. tostring(tower.nativeRequests)
        .. "  |  fallback taps=" .. tostring(tower.inputRequests))
end))
note("V17: Tower now has its own projectile prediction, boss-first targeting, short dodges, windup counter and low-HP retreat. QUICK FINISHER prioritizes weakened enemies; no client script can guarantee one-hit kills.")
end
section("WORLD NAVIGATOR")
note("World/portal metadata is read at runtime. Combat resets when your world changes. A portal with an unknown destination still needs manual travel.")
local worldHud = ordered(label(scroll, "CURRENT WORLD ?    /    DESTINATION ?", 12))
worldHud.Size = UDim2.new(1, 0, 0, 44)
worldHud.BackgroundTransparency = 0
worldHud.BackgroundColor3 = color.hud
worldHud.TextColor3 = color.on
worldHud.Font = Enum.Font.GothamBold
round(worldHud, 10)
make("UIPadding", {PaddingLeft = UDim.new(0, 12)}, worldHud)
local portalButton = ordered(button(scroll, "", function()
    fight.allPortals = not fight.allPortals
    if not fight.allPortals then fight.portalMode = "CURRENT" end
    if fight.allPortals and fight.portalMode == "CURRENT" then fight.portalMode = "AUTO" end
    fight.run = nil
    refresh()
end))
local portalModeButton = ordered(button(scroll, "", function()
    if not fight.allPortals then
        notify("Enable ALL PORTALS before selecting another world.") return
    end
    if fight.portalMode == "AUTO" then fight.portalMode = "SELECT"
    elseif fight.portalMode == "SELECT" then fight.portalMode = "CURRENT"
    else fight.portalMode = "AUTO" end
    fight.run = nil
    refresh()
end))
local worldSelectButton = ordered(button(scroll, "", function()
    loadNative()
    local worlds = discoveredWorlds(true)
    if #worlds == 0 then notify("No world metadata detected. Try again after joining a stage.") return end
    local nextIndex = 1
    for i, world in ipairs(worlds) do
        if world == fight.selectedWorld then nextIndex = (i % #worlds) + 1 break end
    end
    fight.selectedWorld = worlds[nextIndex]
    fight.portalMode, fight.allPortals = "SELECT", true
    fight.run = nil
    refresh()
end))
local portalRouteButton = ordered(button(scroll, "ROUTE TO SELECTED WORLD", function()
    if not alive() then notify("Your character is not ready.") return end
    loadNative()
    discoveredWorlds(true)
    if fight.selectedWorld <= 0 then notify("Select a world first.") return end
    travelToWorld(fight.selectedWorld, os.clock())
    notify(fight.portalStatus)
end))
local portalScanButton = ordered(button(scroll, "RESCAN AVAILABLE WORLDS", function()
    loadNative()
    local worlds = discoveredWorlds(true)
    local names = {}
    for _, world in ipairs(worlds) do
        names[#names + 1] = tostring(world) .. (worldReleased(world) and "" or " (unreleased)")
    end
    notify("Detected worlds: " .. (#names > 0 and table.concat(names, ", ") or "none") .. ".")
    refresh()
end))
refreshers[#refreshers + 1] = function()
    portalButton.Text = "ALL PORTALS  |  " .. (fight.allPortals and "ON" or "OFF")
    portalModeButton.Text = "ROUTING MODE  |  " .. fight.portalMode
    worldSelectButton.Text = "SELECTED WORLD  |  " .. tostring(fight.selectedWorld > 0 and fight.selectedWorld or "AUTO")
    worldHud.Text = "  YOU: World " .. tostring(currentWorld() or "?") .. "    →    "
        .. (fight.portalMode == "AUTO" and "Auto destination" or ("World " .. tostring(fight.selectedWorld)))
    portalRouteButton.Text = "ROUTE TO WORLD " .. tostring(fight.selectedWorld)
    if fight.allPortals then recolorButton(portalButton, color.active, color.activeTint, color.on, color.on)
    else recolorButton(portalButton, color.card, color.cardTint, color.edge, color.text) end
end
note("World travel is server-controlled. If a portal has no identifiable destination, the status explains what is missing instead of using a random gate.")
end
do
local objectiveButton, combatToolButton
objectiveButton = ordered(button(scroll, "", function()
    fight.autoShieldObjectives = not fight.autoShieldObjectives
    fight.objective, fight.objectiveAt = nil, -math.huge
    refresh()
end))
combatToolButton = ordered(button(scroll, "", function()
    fight.combatTools = not fight.combatTools
    refresh()
end))
refreshers[#refreshers + 1] = function()
    objectiveButton.Text = "BREAK BOSS SHIELDS  /  towers & generators  |  " .. (fight.autoShieldObjectives and "ON" or "OFF")
    combatToolButton.Text = "AUTO COMBAT TOOLS  /  equipped weapons  |  " .. (fight.combatTools and "ON" or "OFF")
end
note("V18 boss repair: identifies destructible generators and shield pylons, then attacks their actual position. Also activates equipped combat Tools. Will not click purchases or guess ability keys.")
end
section("PHANTOM DEFENSE")
local dodgeButton, bossButton, retreatButton, ballisticButton
dodgeButton = ordered(button(scroll, "", function() fight.dodge = not fight.dodge refresh() end))
bossButton = ordered(button(scroll, "", function() fight.bosses = not fight.bosses fight.lastBossScan = -math.huge refresh() end))
retreatButton = ordered(button(scroll, "", function() fight.retreat = not fight.retreat refresh() end))
ballisticButton = ordered(button(scroll, "", function() fight.ballistic = not fight.ballistic refresh() end))
refreshers[#refreshers + 1] = function()
    dodgeButton.Text = "AUTO DODGE ATTACKS  |  " .. (fight.dodge and "ON" or "OFF")
    bossButton.Text = "AUTO TARGET BOSSES  |  " .. (fight.bosses and "ON" or "OFF")
    retreatButton.Text = "Low-health retreat  |  " .. (fight.retreat and "ON" or "OFF")
    ballisticButton.Text = "Bullet/throw detection  |  " .. (fight.ballistic and "ON" or "OFF")
end
stepper("Dodge distance (studs)", "dodgeRange", 7, 25, 2)
stepper("Dodge cooldown (ms)", "dodgeMs", 70, 470, 10)
stepper("Projectile scan radius", "projectileRadius", 25, 85, 5)
stepper("Retreat below HP (%)", "retreatHealth", 10, 50, 5)
note("V12 smart short dodge stays nearer to melee reach while reacting to bullets. Faster inputs cannot prevent instant or server-side hits.")
local rapidButton, finishButton, overdriveButton, adaptiveButton, preemptButton, counterButton
preemptButton = ordered(button(scroll, "", function() fight.preemptive = not fight.preemptive refresh() end))
counterButton = ordered(button(scroll, "", function() fight.windupCounter = not fight.windupCounter refresh() end))
refreshers[#refreshers + 1] = function()
    preemptButton.Text = "FIRST STRIKE / rush bosses  |  " .. (fight.preemptive and "ON" or "OFF")
    counterButton.Text = "WINDUP COUNTER / attack early  |  " .. (fight.windupCounter and "ON" or "OFF")
end
stepper("First Strike step (studs)", "rushStep", 6, 14, 1)
note("V13: approaches newly visible bosses in short, grounded steps, attacks on first allowed opening, and keeps dodging actual bullets. No guaranteed pre-shot kill.")
overdriveButton = ordered(button(scroll, "", function() fight.overdrive = not fight.overdrive refresh() end))
adaptiveButton = ordered(button(scroll, "", function() fight.adaptiveDodge = not fight.adaptiveDodge refresh() end))
rapidButton = ordered(button(scroll, "", function() fight.rapid = not fight.rapid refresh() end))
finishButton = ordered(button(scroll, "", function() fight.finishWeak = not fight.finishWeak refresh() end))
refreshers[#refreshers + 1] = function()
    overdriveButton.Text = "OVERDRIVE / low-latency strikes  |  " .. (fight.overdrive and "ON" or "OFF")
    adaptiveButton.Text = "SMART short dodges  |  " .. (fight.adaptiveDodge and "ON" or "OFF")
    rapidButton.Text = "QUICK STRIKE attempts  |  " .. (fight.rapid and "ON" or "OFF")
    finishButton.Text = "Focus weakened enemies  |  " .. (fight.finishWeak and "ON" or "OFF")
end
stepper("Strike check interval (ms)", "attackMs", 35, 350, 15)
note("V12: OVERDRIVE checks native Busy() on Heartbeat (no direct damage edits). Enemy HP changes confirm actual hits; cooldowns and damage remain server-controlled.")
local advanceButton, repeatButton
advanceButton = ordered(button(scroll, "", function() fight.advance = not fight.advance refresh() end))
repeatButton = ordered(button(scroll, "", function() fight.repeatRuns = not fight.repeatRuns refresh() end))
refreshers[#refreshers + 1] = function()
    advanceButton.Text = "Advance eligible stages  |  " .. (fight.advance and "ON" or "OFF")
    repeatButton.Text = "Repeat fight runs  |  " .. (fight.repeatRuns and "ON" or "OFF")
end
stepper("Stage cap (0 = all)", "stageLimit", 0, 1000, 1)
note("Uses normal server-recognized attacks and free stage rewards. Auto Train pauses during fights. A lower strike interval is NOT increased damage.")

section("MANUAL BOOKMARK")
ordered(button(scroll, "Save current training spot", function()
    if not alive() then notify("Wait until your character is ready.") return end
    savedSpot = character:GetPivot()
    trainingArrived, trainingAttempted = false, false
    if promptOwner == "train" then endPrompt() end
    notify("Manual bookmark saved. Auto train uses detected speaker pads instead.")
end))
ordered(button(scroll, "Return to saved spot", function() if returnToSpot() then notify("Returned to saved training spot.") end end))
toggle("Hold training spot", "hold", function()
    if state.train or state.fight then notify("Stop Auto train and Auto fights before using a manual bookmark.") return false end
    if savedSpot then return true end
    notify("Save a training spot first.") return false
end)

section("INTERACTIONS")
ordered(button(scroll, "Select nearest prompt", function()
    if not alive() then notify("Wait until your character is ready.") return end
    state.prompt = false
    if state.train or state.fight then notify("Stop Auto train and Auto fights before selecting a manual prompt.") return end
    trainingArrived, trainingAttempted = false, false
    endPrompt()
    chosenPrompt = nil
    local bestDistance = 18
    for _, item in ipairs(workspace:GetDescendants()) do
        if item:IsA("ProximityPrompt") and item.Enabled then
            local position = promptPosition(item)
            if position then
                local distance = (position - root.Position).Magnitude
                if distance <= bestDistance then bestDistance, chosenPrompt = distance, item end
            end
        end
    end
    refresh()
    if chosenPrompt then
        notify("Selected: " .. chosenPrompt.Parent.Name .. " / " .. chosenPrompt.ActionText .. ". Check this is the action you want.")
    else notify("No enabled prompt within 18 studs. Move beside the desired prompt.") end
end))
toggle("Repeat selected prompt", "prompt", function()
    if state.train or state.fight then notify("Stop Auto train and Auto fights before enabling independent prompt repetition.") return false end
    if chosenPrompt and chosenPrompt.Parent then return true end
    notify("Select a nearby prompt first.") return false
end)
stepper("Prompt interval (seconds)", "interval", 1, 10, 1)
toggle("Auto activate equipped tool", "tool")
note("Prompt repetition waits until you are within its normal distance. Auto tool only uses a tool you have already equipped.")

section("ANTI-AFK")
toggle("Anti-AFK", "afk", antiAfkInput)
note("Sends simulated input when Roblox reports idle. If your executor blocks that input, the toggle switches OFF and reports the error.")

section("MOVEMENT")
stepper("Walk speed", "speed", 16, 100, 4)
toggle("Apply walk speed", "speed")
stepper("Jump power", "jump", 40, 140, 10)
toggle("Apply jump boost", "jump")
toggle("Noclip", "noclip", function()
    if state.train or state.fight then notify("Stop Auto train and Auto fights before enabling Noclip.") return false end
    return true
end)
note("Client movement can be corrected by the game. Noclip also disables floor collisions. Turn it OFF before using a training spot.")

section("SUPPORT")
local reportFrame = make("Frame", {
    Position = UDim2.fromOffset(10, 96), Size = UDim2.new(1, -20, 1, -154),
    BackgroundColor3 = color.bg, BorderSizePixel = 0, Visible = false, ZIndex = 10,
}, panel)
local reportText = make("TextBox", {
    Position = UDim2.fromOffset(4, 44), Size = UDim2.new(1, -8, 1, -48),
    BackgroundColor3 = color.card, TextColor3 = color.text, BorderSizePixel = 0,
    ClearTextOnFocus = false, MultiLine = true, TextEditable = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextSize = 11, Font = Enum.Font.Code, TextWrapped = true, Text = "", ZIndex = 11,
}, reportFrame)
local reportBack = button(reportFrame, "Back to menu", function() reportFrame.Visible = false scroll.Visible = true end)
reportBack.Size, reportBack.ZIndex = UDim2.new(1, 0, 0, 36), 11
ordered(button(scroll, "Show game diagnostics", function()
    local lines = {"VENOM V18 BLACKOUT / WORLD RESYNC / SHIELD BREAKER / TOOL ATTACKS", "Place: " .. tostring(game.PlaceId), "Universe: " .. tostring(game.GameId),
        "Auto train: " .. native.detail, "Level: " .. tostring(player:GetAttribute("Level")),
        "Ascension enabled: " .. tostring(state.progress) .. " | Mode: " .. tostring(progress.mode),
        "Ascension strategy: " .. progress.strategy .. " | Reason: " .. progress.detail,
        "Live Level: " .. tostring(progress.latest.level) .. " | Goal: " .. tostring(progress.goalLevel),
        "Live Wins: " .. tostring(progress.latest.wins) .. " | Goal: " .. tostring(progress.goalWins),
        "Evolution tier: " .. tostring(progress.latest.evolutions) .. " | Source: " .. progress.goalSource,
        "Earned Wins observed: " .. tostring(progress.winsEarned) .. " | Evolved: " .. tostring(progress.evolutionsObserved),
        "Fallback farm stage cap: " .. tostring(progress.safeStageCap),
        "World: " .. tostring(player:GetAttribute("World")), "Chambers: " .. tostring(player:GetAttribute("Chambers")),
        "Native training active: " .. tostring(nativeActive()), "Venom: " .. tostring(readVenom()),
        "Auto fights: " .. fight.detail, "Main ON: " .. tostring(state.fight), "Fight stage: " .. tostring(fight.run and fight.run.stage),
        "Main fallback taps: " .. tostring(fight.mainFallbackCount),
        "Shield objective: " .. fight.objectiveName .. " | " .. tostring(fight.objectiveStatus),
        "Shield attempts: " .. tostring(fight.objectiveAttempts) .. " | HP drops " .. tostring(fight.objectivesDamaged),
        "Combat Tools: " .. tostring(fight.toolAttacks) .. " / " .. tostring(fight.toolName),
        "World resyncs: " .. tostring(fight.worldResyncs),
        "Portal mode: " .. tostring(fight.portalMode), "Selected world: " .. tostring(fight.selectedWorld),
        "Current world: " .. tostring(currentWorld()), "Portal status: " .. tostring(fight.portalStatus),
        "Fight defeats: " .. tostring(fight.defeats), "Strike attempts: " .. tostring(fight.attacks),
        "Native strike requests: " .. tostring(fight.accepted),
        "Rapid strike: " .. tostring(fight.rapid) .. " / " .. tostring(values.attackMs) .. "ms",
        "Dodge: " .. tostring(fight.dodge) .. " | Attempts: " .. tostring(fight.dodgeCount),
        "Boss hunt: " .. tostring(fight.bosses) .. " | Detected: " .. tostring(fight.bossDetected),
        "Boss attack requests: " .. tostring(fight.bossHits),
        "Current target: " .. tostring(fight.run and fight.run.lockedTarget),
        "Target source: " .. tostring(fight.targetSource),
        "Phase: " .. tostring(fight.lastCombatPhase),
        "Last action: " .. tostring(fight.lastAction),
        "Corrected evasions: " .. tostring(fight.dodgesCorrected),
        "Successful movement attempts (NOT confirmed misses): " .. tostring(fight.shotsDodged),
        "No safe sidestep surfaces: " .. tostring(fight.blockedGrounds),
        "Combat target: " .. tostring(fight.lastEnemyName) .. "/" .. tostring(fight.lastEnemyHp),
        "Attack outcome: " .. tostring(fight.attackStatus),
        "Tower mode: " .. tostring(tower.active()) .. " / " .. tower.source
            .. " | TowerAuto=" .. tostring(state.tower)
            .. " | native=" .. tostring(tower.nativeRequests)
            .. " | taps=" .. tostring(tower.inputRequests)
            .. " | status=" .. tostring(tower.status),
        "Tower dodge: " .. tostring(tower.autoDodge) .. " / " .. tostring(tower.dodgeCount)
            .. " | last " .. tostring(tower.dodgeReason),
        "Tower boss priority: " .. tostring(tower.bossPriority)
            .. " | quick finisher " .. tostring(tower.quickFinisher),
        "Observed enemy HP decreases (not kill credit): " .. tostring(fight.hpConfirmedHits),
        "Observed boss HP decreases: " .. tostring(fight.hpConfirmedBossHits),
        "Total observed enemy HP reduction: " .. tostring(fight.hpDamageDealt),
        "Arena-floor fallbacks: " .. tostring(fight.groundFallbacks),
        "Chase MoveTo fallbacks: " .. tostring(fight.chaseFallbacks),
        "Busy() blocked frames: " .. tostring(fight.attacksBlocked),
        "Nearby projectiles: " .. tostring(fight.seenProjectiles),
        "Projectile radar: " .. tostring(fight.ballistic) .. " / " .. tostring(values.projectileRadius) .. " studs",
        "Dodge cooldown: " .. tostring(values.dodgeMs) .. "ms / Last cue: " .. tostring(fight.dodgeReason),
        "Overdrive attempts: " .. tostring(fight.overdriveAttempts) .. " | Cooldown checks: " .. tostring(fight.cooldownSkips),
        "FIRST STRIKE rushes: " .. tostring(fight.firstStrikeRushes)
            .. " | opening requests: " .. tostring(fight.openingAttackRequests),
        "First Strike status: " .. tostring(fight.lastFirstStrikeStatus),
        "Boss-first mode: " .. tostring(fight.preemptive)
            .. " | windup counter: " .. tostring(fight.windupCounter),
        "Dodges finishing within reach: " .. tostring(fight.dodgedWithoutLeavingRange),
        "Damage over last 3s window: " .. tostring(math.floor(fight.rangedDamageWindow)),
        "V9 threat type: " .. tostring(fight.lastThreatClass),
        "Combat strafes suppressed: " .. tostring(fight.suppressedStrafes),
        "Observed HP lost: " .. tostring(math.floor(fight.healthLost)),
        "WinReady: " .. tostring(player:GetAttribute("WinReady")),
        "BondStage: " .. tostring(player:GetAttribute("BondStage")), "Anti-AFK input calls completed: " .. tostring(afkInputs)}
    for _, key in ipairs({"config", "maps", "training", "data", "encounter", "combat", "stages", "encounters", "combatConfig", "evolutionConfig"}) do
        lines[#lines + 1] = key .. ": " .. (native.modules[key] and "readable" or native.loading[key] and "loading" or "unavailable")
    end
    scanNative()
    local owned = ownedChambers()
    for _, station in ipairs(native.stations) do
        lines[#lines + 1] = "Speaker " .. tostring(station.index) .. " x" .. tostring(station.mult)
            .. " owned=" .. tostring(owned[station.index] == true) .. " world=" .. tostring(station.world)
            .. " pad=" .. station.pad:GetFullName() .. " pos=" .. tostring(station.pad.Position)
    end
    local stats = player:FindFirstChild("leaderstats")
    if stats then
        for _, value in ipairs(stats:GetChildren()) do
            if value:IsA("ValueBase") then lines[#lines + 1] = value.Name .. " = " .. tostring(value.Value) end
        end
    end
    lines[#lines + 1] = "--- ReplicatedStorage remotes (names only; never invoked) ---"
    local count = 0
    for _, item in ipairs(ReplicatedStorage:GetDescendants()) do
        if item:IsA("RemoteEvent") or item:IsA("RemoteFunction") or item:IsA("UnreliableRemoteEvent") then
            count = count + 1
            if count <= 100 then lines[#lines + 1] = item.ClassName .. " " .. item:GetFullName() end
        end
    end
    if count > 100 then lines[#lines + 1] = "Additional remote names omitted: " .. tostring(count - 100) end
    if chosenPrompt and chosenPrompt.Parent then lines[#lines + 1] = "Selected prompt: " .. chosenPrompt:GetFullName() end
    lines[#lines + 1] = "--- Workspace top-level objects ---"
    for index, item in ipairs(workspace:GetChildren()) do
        if index <= 40 then lines[#lines + 1] = item.ClassName .. " " .. item.Name end
    end
    reportText.Text = table.concat(lines, "\n")
    reportFrame.Visible, scroll.Visible = true, false
    notify("Diagnostics are local. Select the text to copy it for troubleshooting.")
end))
note("Standalone source with no remote loader. No infinite Wins, free paid chambers, or server-side damage claims. Game-specific farming is unverified.")

local stop = button(panel, "■  EMERGENCY STOP  /  RESET", function() stopAll() end)
stop.Position, stop.Size = UDim2.new(0, 12, 1, -55), UDim2.new(1, -24, 0, 42)
recolorButton(stop, color.dangerSurface, color.dangerTint, color.danger, color.text)
local bubble = button(screen, "V", function()
    panel.Visible = not panel.Visible
    if panel.Visible then
        panel.Position = panelDefaultPos + UDim2.fromOffset(0, 14)
        panel.BackgroundTransparency = 0.18
        pcall(function()
            TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = panelDefaultPos, BackgroundTransparency = 0,
            }):Play()
        end)
    end
end)
bubble.Name = "OpenMenu"
bubble.Position, bubble.Size = UDim2.fromOffset(12, 12), UDim2.fromOffset(44, 44)
bubble.Font, bubble.TextSize = Enum.Font.GothamBlack, 16
recolorButton(bubble, color.accent, color.purple, color.edge, color.text)
round(bubble, 22)

stopAll = function()
    stopFight()
    stopNative(true)
    if state.progress then stopProgress() end
    for key in pairs(state) do state[key] = false end
    trainingArrived, trainingAttempted = false, false
    endInteractions()
    restoreMotion()
    restoreCollisions()
    refresh()
    notify("All features stopped. Movement settings restored.")
end
cleanup = function()
    if not running then return end
    stopAll()
    running = false
    for _, worker in ipairs(native.workers) do pcall(task.cancel, worker) end
    if characterConnection then characterConnection:Disconnect() end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    gui:Destroy()
end
connect(shutdown.Event, cleanup)
connect(gui.Destroying, cleanup)

local function viewport()
    local size = screen.AbsoluteSize
    return math.max(200, size.X), math.max(160, size.Y)
end
local function fitPanel(center)
    local w, h = viewport()
    local width, height = math.min(384, w - 16), math.min(575, h - 16)
    panel.Size = UDim2.fromOffset(width, height)
    local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
    if center then x, y = (w - width) / 2, (h - height) / 2 end
    panel.Position = UDim2.fromOffset(math.clamp(x, 0, w - width), math.clamp(y, 0, h - height))
    bubble.Position = UDim2.fromOffset(math.clamp(bubble.Position.X.Offset, 0, w - 44), math.clamp(bubble.Position.Y.Offset, 0, h - 44))
end
local dragging, dragStart, panelStart
connect(dragHandle.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, panelStart = input, input.Position, panel.Position
    end
end)
connect(UIS.InputChanged, function(input)
    if not dragging then return end
    if input ~= dragging and not (dragging.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
    local delta = input.Position - dragStart
    panel.Position = UDim2.fromOffset(panelStart.X.Offset + delta.X, panelStart.Y.Offset + delta.Y)
    fitPanel(false)
end)
connect(UIS.InputEnded, function(input)
    if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = nil end
end)
connect(screen:GetPropertyChangedSignal("AbsoluteSize"), function() fitPanel(false) end)
connect(UIS.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then panel.Visible = not panel.Visible end
end)
fitPanel(true)

local function bindCharacter(newCharacter)
    endInteractions()
    resetFightCharacter()
    stopNative(false)
    trainingArrived, trainingAttempted, lastReturn = false, false, -math.huge
    -- Retire old-character overrides before attaching to the new character.
    for h, originals in pairs(motionOriginals) do
        for property, value in pairs(originals) do pcall(function() h[property] = value end) end
    end
    motionOriginals = setmetatable({}, {__mode = "k"})
    restoreCollisions()
    if characterConnection then characterConnection:Disconnect() characterConnection = nil end
    character, humanoid, root = newCharacter, nil, nil
    parts = {}
    characterReadyAt = os.clock() + 2
    for _, item in ipairs(newCharacter:GetDescendants()) do if item:IsA("BasePart") then parts[#parts + 1] = item end end
    characterConnection = newCharacter.DescendantAdded:Connect(function(item)
        if item:IsA("BasePart") then parts[#parts + 1] = item end
    end)
end
connect(player.CharacterAdded, bindCharacter)
if player.Character then bindCharacter(player.Character) end
loadNative()
connect(player.Idled, function()
    if not running or not state.afk then return end
    if antiAfkInput() then notify("Anti-AFK input sent. Total: " .. tostring(afkInputs))
    else state.afk = false refresh() end
end)
connect(RunService.Stepped, function()
    if not running or not state.noclip or not alive() then return end
    for i = #parts, 1, -1 do
        local part = parts[i]
        if not part:IsDescendantOf(character) then
            if collisionOriginals[part] ~= nil then
                pcall(function() part.CanCollide = collisionOriginals[part] end)
                collisionOriginals[part] = nil
            end
            table.remove(parts, i)
        else
            if collisionOriginals[part] == nil then collisionOriginals[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end)

-- V17 Tower dodges also run between the slower input/targeting ticks.
connect(RunService.Heartbeat, function()
    if not running or not state.tower or not alive() then return end
    if not tower.active(os.clock()) then return end
    local now = os.clock()
    local target = tower.target
    if target and target.model and target.model.Parent and target.humanoid.Health > 0 then
        local ok, err = pcall(tower.dodgeStep, now, target, 8)
        if not ok and now - tower.lastDefenseStep > 2 then
            warn("VENOM V18 Tower dodge: " .. tostring(err))
        end
    end
end)

-- PHANTOM defense loop runs independently of the attack/encounter loop.
-- Do not yield here: a late defensive scan cannot delay the next strike.
local lastPhantomStep = -math.huge
connect(RunService.Heartbeat, function()
    if not running or not state.fight or not alive() or (state.tower and tower.active()) then return end
    local phase, folder = fight.lastCombatPhase, fight.lastCombatFolder
    if phase ~= "boss" and phase ~= "waves" and phase ~= "snipers" then return end
    if not folder or not folder.Parent then return end
    local now = os.clock()
    local target, run, reach = fight.lastCombatTarget, fight.run, fight.lastCombatReach
    -- First check for a native strike without waiting for the slower stage-loop.
    -- This does not bypass game cooldowns, and shares a single attack lock.
    if fight.overdrive and run and target and run.lockedTarget == target.model then
        local ok, err = pcall(tryNativeStrike, now, target, reach, run)
        if not ok and now - fight.lastCombatReport > 3 then
            fight.lastCombatReport = now
            warn("VENOM OVERDRIVE: " .. tostring(err))
        end
    end
    if fight.preemptive and run and target and run.lockedTarget == target.model then
        local ok, err = pcall(firstStrikeAdvance, now, target, phase, folder, reach, run)
        if not ok and now - fight.lastCombatReport > 3 then
            fight.lastCombatReport = now
            warn("VENOM FIRST STRIKE: " .. tostring(err))
        end
    end
    if not fight.dodge then return end
    -- Avoid two independent systems repositioning the root in the same frame.
    if fight.run and now - fight.lastMove < 0.055 then return end
    if now - lastPhantomStep < 0.028 then return end
    lastPhantomStep = now
    local ok, err = pcall(evadeFight, now, target, phase, folder, reach)
    if not ok and now - fight.lastCombatReport > 3 then
        fight.lastCombatReport = now
        warn("VENOM PHANTOM defense: " .. tostring(err))
    end
end)

local lastErrorAt, lastHudAt = -10, -math.huge
task.spawn(function()
    while running do
        local ok, err = pcall(function()
            local now = os.clock()
            if toolReleaseAt and now >= toolReleaseAt then endTool() end
            if promptReleaseAt and now >= promptReleaseAt then endPrompt() end
            if character and character.Parent then
                humanoid = character:FindFirstChildOfClass("Humanoid")
                root = character:FindFirstChild("HumanoidRootPart")
            end
            if not alive() then
                endInteractions()
                trainingArrived, trainingAttempted = false, false
                return
            end
            if now - lastHudAt >= 0.25 then
                lastHudAt = now
                local p = progress.latest
                progressStats.Text = "LV " .. tostring(p.level or "?") .. " / " .. tostring(p.goalLevel or "?")
                    .. "    |    WINS " .. tostring(p.wins or "?") .. " / " .. tostring(p.goalWins or "?")
                    .. "    |    EVO " .. tostring(p.evolutions or "?")
                progressStatus.Text = (state.progress and ("ASCENSION " .. progress.mode:upper()) or "ASCENSION OFF")
                    .. "  /  " .. progress.detail
                if state.tower and tower.active(now) then
                    hud.Text = "TOWER ●   |   AUTO " .. (state.tower and "ON" or "OFF")
                        .. "   |   ATTACKS " .. tostring(tower.nativeRequests)
                        .. "   |   DODGE " .. tostring(tower.dodgeCount)
                        .. "   |   TAPS " .. tostring(tower.inputRequests)
                    tower.statusLabel.Text = "MODE: " .. tower.source .. "   /   " .. tower.status
                else
                    hud.Text = state.fight and ("FIGHT ●   |   W" .. tostring(currentWorld() or "?")
                    .. "   |   BOSS " .. (fight.bossDetected and "●" or "--")
                    .. "   |   DODGE " .. tostring(fight.dodgeCount)
                    .. "   |   HP " .. tostring(math.floor(humanoid.Health)))
                    or ("FIGHT OFF   |   TRAIN " .. (state.train and "●" or "--")
                        .. "   |   PHANTOM READY")
                    tower.statusLabel.Text = "TOWER: " .. (state.tower and "ARMED" or "OFF") .. "   /   " .. tower.source
                end
            end
            if state.speed then applyProperty(humanoid, "WalkSpeed", values.speed) end
            if state.jump then
                if humanoid.UseJumpPower then applyProperty(humanoid, "JumpPower", values.jump)
                else applyProperty(humanoid, "JumpHeight", values.jump * values.jump / (2 * math.max(workspace.Gravity, 1))) end
            end
            local towerMode = state.tower and tower.active(now)
            if state.progress and not towerMode then tickProgress(now) end
            local fightsOwnMovement
            if towerMode then
                fightsOwnMovement = tower.tick(now)
            elseif state.fight then
                fightsOwnMovement = tickFight(now)
            end
            if not running or not alive() then return end
            if state.train and not fightsOwnMovement then tickNative(now) end
            if state.hold and not state.train and not state.fight and savedSpot and not state.noclip and now - lastReturn >= 1 then
                local distance = (character:GetPivot().Position - savedSpot.Position).Magnitude
                if distance > 7 then
                    if returnToSpot() then
                        if promptOwner == "train" then endPrompt() end
                        lastReturn, trainingArrived, trainingAttempted = now, true, false
                    end
                end
            end
            if state.tool and now - lastTool >= 0.3 then
                local tool = character:FindFirstChildOfClass("Tool")
                if tool and tool.Enabled then
                    if activeTool and activeTool ~= tool then activeTool:Deactivate() end
                    activeTool = tool
                    tool:Activate()
                    toolReleaseAt, lastTool = now + 0.1, now
                end
            end
            if heldPrompt and promptOwner ~= "portal" and not promptUsable() then
                endPrompt()
            end
            if state.prompt and not state.train and not state.fight and not heldPrompt
                and now - lastPrompt >= values.interval and promptUsable() then
                heldPrompt = chosenPrompt
                promptOwner = "manual"
                heldPrompt:InputHoldBegin()
                promptReleaseAt, lastPrompt = now + math.max(0, heldPrompt.HoldDuration) + 0.1, now
            end
        end)
        if not ok and os.clock() - lastErrorAt >= 5 then
            lastErrorAt = os.clock()
            warn("VENOM: " .. tostring(err))
            notify("Feature error: " .. tostring(err):sub(1, 150))
        end
        task.wait((state.fight or (state.tower and tower.detected)) and 0.05 or 0.1)
    end
end)
refresh()
notify("VENOM V18 BLACKOUT ready | Auto Fights ON | Shield Breaker + Combat Tools ON.")
