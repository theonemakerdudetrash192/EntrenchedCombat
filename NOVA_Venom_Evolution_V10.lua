-- NOVA VENOM | V10 RIPPER FIX / GROUNDED PURSUIT / TRUE DAMAGE TRACKING / PROJECTILE ANTICIPATION
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
    warn("NOVA VENOM needs a client Lua context.")
    return
end
local playerGui = player:WaitForChild("PlayerGui", 15)
if not playerGui then warn("NOVA VENOM: PlayerGui not ready; try again after loading.") return end

local GUI_NAME = "NOVA_VENOM_V1"
local previous = playerGui:FindFirstChild(GUI_NAME)
if previous then
    local shutdown = previous:FindFirstChild("Shutdown")
    if shutdown and shutdown:IsA("BindableEvent") then shutdown:Fire() end
    previous:Destroy()
end

local running = true
local connections = {}
local state = {speed = false, jump = false, noclip = false, hold = false, tool = false, prompt = false, train = false, fight = false, afk = false, progress = false}
local values = {speed = 32, jump = 80, interval = 2, stageLimit = 0, attackMs = 50, dodgeRange = 13, retreatHealth = 28, dodgeMs = 120, projectileRadius = 85, targetLevel = 0, targetWins = 0}
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
    detail = "Off", advance = true, repeatRuns = true, rapid = true, finishWeak = true,
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
    lastEnemyHp = nil, lastEnemyName = "None"}
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

-- FROST: light, high-contrast surfaces for outdoor/daytime game maps.
-- Keep these colors centralized; no gameplay behavior depends on the theme.
local color = {
    bg = Color3.fromRGB(237, 245, 255), deep = Color3.fromRGB(219, 234, 255),
    card = Color3.fromRGB(255, 255, 255), cardTint = Color3.fromRGB(242, 248, 255),
    muted = Color3.fromRGB(76, 101, 129), text = Color3.fromRGB(21, 41, 70),
    edge = Color3.fromRGB(163, 193, 229), on = Color3.fromRGB(7, 112, 88),
    accent = Color3.fromRGB(34, 91, 198), purple = Color3.fromRGB(115, 70, 181),
    danger = Color3.fromRGB(172, 47, 68),
    active = Color3.fromRGB(221, 250, 240), activeTint = Color3.fromRGB(238, 255, 249),
    hud = Color3.fromRGB(210, 231, 255), section = Color3.fromRGB(220, 234, 255),
    dangerSurface = Color3.fromRGB(255, 231, 235), dangerTint = Color3.fromRGB(255, 243, 246),
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
    if callback then
        connect(b.Activated, function()
            if not running then return end
            local ok, err = pcall(callback)
            if not ok then warn("NOVA VENOM button: " .. tostring(err)) end
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
make("UIStroke", {Color = color.accent, Thickness = 1.7, Transparency = 0.18}, panel)
make("UIGradient", {Color = ColorSequence.new(color.bg, color.deep), Rotation = 85}, panel)
local accentBar = make("Frame", {Size = UDim2.new(1, -28, 0, 3), Position = UDim2.fromOffset(14, 48),
    BorderSizePixel = 0, BackgroundColor3 = color.accent}, panel)
round(accentBar, 2)
make("UIGradient", {Color = ColorSequence.new(color.accent, color.purple), Rotation = 0}, accentBar)
local dragHandle = make("TextLabel", {
    Size = UDim2.new(1, -100, 0, 47), Position = UDim2.fromOffset(15, 0),
    BackgroundTransparency = 1, Active = true, Text = "NOVA  /  VENOM    V10  FROST",
    Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = color.accent,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
local minimize = button(panel, "-", function() panel.Visible = false end)
minimize.Size, minimize.Position = UDim2.fromOffset(30, 30), UDim2.new(1, -76, 0, 9)
recolorButton(minimize, Color3.fromRGB(227, 240, 255), Color3.fromRGB(210, 229, 255), color.edge, color.accent)
local close = button(panel, "X", function() cleanup() end)
close.Size, close.Position = UDim2.fromOffset(30, 30), UDim2.new(1, -40, 0, 9)
recolorButton(close, color.dangerSurface, color.dangerTint, Color3.fromRGB(237, 166, 180), color.danger)
local status = label(panel, "PHANTOM SYSTEM ONLINE  /  Auto Fights off", 12)
status.Position, status.Size = UDim2.fromOffset(15, 56), UDim2.new(1, -30, 0, 44)
status.TextColor3 = color.muted
local hud = label(panel, "FIGHTS OFF   |   BOSS --   |   DODGES 0", 11)
hud.Position, hud.Size = UDim2.fromOffset(16, 100), UDim2.new(1, -32, 0, 27)
hud.TextColor3 = color.accent
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
            recolorButton(tab.button, color.card, color.cardTint, color.edge, color.accent)
        end
    end
end
for _, item in ipairs({{"EVOLVE", "EVOLUTION AUTOPILOT"}, {"COMBAT", "AUTO FIGHTS"}, {"DEFENSE", "PHANTOM DEFENSE"}, {"TRAIN", "AUTO TRAIN"}, {"TOOLS", "MOVEMENT"}}) do
    local navButton = button(nav, item[1], function()
        jump(item[2])
        markNav(item[1])
    end)
    navButton.Size = UDim2.new(0.20, -5, 1, 0)
    navButton.TextSize = 11
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
    l.TextColor3, l.Size = color.accent, UDim2.new(1, 0, 0, 32)
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
    }
    if state.fight then
        paths.encounter = {player, {"PlayerScripts", "Client", "Controllers", "EncounterController"}}
        paths.combat = {player, {"PlayerScripts", "Client", "Controllers", "CombatController"}}
        paths.stages = {ReplicatedStorage, {"Shared", "Config", "Stages"}}
        paths.encounters = {ReplicatedStorage, {"Shared", "Config", "Encounters"}}
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
local function stageAvailable(stage)
    local m = native.modules
    if not m.stages.List[stage] or not m.encounters.Stages[stage] then return false end
    local world = stageWorld(stage)
    local currentWorld = number(nativeCall(m.maps, "WorldAt", false, root.Position))
        or number(player:GetAttribute("World"))
    if not world or not currentWorld or world ~= currentWorld then return false end
    if type(m.maps.Released) == "function" and nativeCall(m.maps, "Released", false, world) ~= true then return false end
    if world > 1 then
        local best = number(nativeCall(m.data, "Get", true, "BestStage"))
        if nativeCall(m.maps, "Open", false, player, world, best) ~= true then return false end
    end
    if player:GetAttribute("AllStages") == true then return true end
    if stage == 1 then
        return (number(player:GetAttribute("BondStage")) or 0) >= (number(m.encounters.Stage1Form) or 1)
    end
    if world > 1 and type(m.maps.FirstStage) == "table" and m.maps.FirstStage[world] == stage then return true end
    local ready = player:GetAttribute("WinReady")
    return type(ready) == "string" and ready:find("," .. tostring(stage - 1) .. ",", 1, true) ~= nil
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
    local best, bestWaiting, reason
    local cap = values.stageLimit > 0 and values.stageLimit or 1000
    if state.progress and progress.safeFarm and progress.safeStageCap then
        cap = math.min(cap, progress.safeStageCap)
    end
    for stage in pairs(native.modules.stages.List) do
        if type(stage) == "number" and stage % 1 == 0 and stage >= 1 and stage <= cap and stageAvailable(stage) then
            local message, advice = stageAdvice(stage)
            if advice == "ready" and (not best or stage > best) then best = stage end
            if not bestWaiting or stage > bestWaiting then bestWaiting, reason = stage, message end
        end
    end
    return best, reason or "Unlock the first combat form or complete the previous stage."
end
local function stageFolder(stage)
    local folder = nativeCall(native.modules.maps, "StageFolder", false, stage)
    if typeof(folder) == "Instance" and folder:IsDescendantOf(workspace) then return folder end
end
local function stageZone(folder)
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
    if not cf then return nil end
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
    if not cf then return false end
    local point = cf:PointToObjectSpace(position)
    local dx, dz = math.max(0, math.abs(point.X) - size.X * 0.5), math.max(0, math.abs(point.Z) - size.Z * 0.5)
    return math.sqrt(dx * dx + dz * dz) > (number(native.modules.encounters.LeaveRange) or 130) + 5
end
local function fightExit(folder)
    local cf, size = stageZone(folder)
    if not cf then return nil end
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
                    if zone then
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
        and now - fight.stageNPCAt < 0.32 then return fight.stageNPCs end
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
            local zone, dimensions = folder and stageZone(folder)
            if not zone then return end
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
        if zone then
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
    if now - fight.lastDefensiveScan < 0.03 then return fight.cachedThreat end
    fight.lastDefensiveScan = now
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.MaxParts = 225
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
    local rangedLane = ranged and target and dist <= reach + 1.5
        and now - fight.lastDodge > 0.5
    local bossFootwork = target and phase == "boss" and target.boss
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
    local cooldown = threat and 0.10 or (firingLane and 0.40 or (attackTell and 0.16
        or (justHit and 0.22 or math.min(0.40, values.dodgeMs / 1000))))
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
    local len = evasive and values.dodgeRange or math.min(values.dodgeRange, math.max(3.5, reach * 0.6))
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
                    score = score - math.abs(rangeAfter - desired) * (far and 3.4 or threat and 0.35 or 1.9)
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
tickFight = function(now)
    loadNative()
    if not fightModulesReady() then fightNotice("Auto fights: waiting for native combat controllers.") return false end
    fightReceipt()
    if player:GetAttribute("Tower") ~= nil or playerGui:FindFirstChild("IntroCutscene") or playerGui:FindFirstChild("GooCutscene") then
        fightNotice("Auto fights paused during Tower mode or a cutscene.") return true
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
    end
    local hpNow = target.humanoid.Health
    if run.targetHp and hpNow < run.targetHp then
        local dealt = run.targetHp - hpNow
        fight.hpDamageDealt = fight.hpDamageDealt + dealt
        fight.hpConfirmedHits = fight.hpConfirmedHits + 1 -- observed damage events, not every swing
        if target.boss then fight.hpConfirmedBossHits = fight.hpConfirmedBossHits + 1 end
        fight.lastConfirmedDamageAt = now
        run.targetDamageAt = now
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
    local dodged = false
    -- The independent Heartbeat defense already performs critical reactions.
    -- Only run the combat-loop dodge when approaching or escaping a real threat.
    if not inRange then
        dodged = evadeFight(now, target, phase, folder, reach)
    end
    local distance = (target.root.Position - root.Position).Magnitude
    if not inRange and distance > reach then
        local since = now - fight.lastMove
        -- IMPORTANT: V5 skipped chasing after every dodge. Gun bosses therefore
        -- never got into melee reach. V6 keeps closing with short intervals.
        if since >= 0.12 and (not dodged or distance > reach + 5) then
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
    -- Preserve an uninterrupted attack window while not threatened by an actual bullet.
    fight.attackWindowUntil = now + 0.25
    local face = Vector3.new(target.root.Position.X, root.Position.Y, target.root.Position.Z)
    if (face - root.Position).Magnitude > 0.01 then
        root.CFrame = CFrame.lookAt(root.Position, face)
    end
    -- Even on a dodge tick, continue with the game's normal attack controller.
    local busyOK, busy = fightCall(native.modules.combat, "Busy", true)
    if not busyOK then
        fight.attackStatus = "Native Busy() unavailable"
        fightNotice("Waiting for native combat readiness.")
        return true
    end
    if busy then
        fight.attacksBlocked = fight.attacksBlocked + 1
        fight.attackStatus = "Combat Busy() = true"
        return true
    end
    local interval = fight.rapid and math.max(0.05, values.attackMs / 1000) or 0.20
    if now - fight.lastAttack >= interval then
        fight.lastAttack = now
        local attacked, accepted = fightCall(native.modules.combat, "Attack", true)
        if not running or not state.fight then return true end
        if not attacked then failFight("The native attack call failed. Open diagnostics.") return true end
        fight.attacks = fight.attacks + 1
        run.targetAttackRequests = (run.targetAttackRequests or 0) + 1
        if accepted ~= false then
            fight.accepted = fight.accepted + 1
            -- Request acceptance is not proof of damage; verified HP is tracked above.
        end
        fight.attackStatus = accepted == false and "Rejected (cooldown)" or "Attack requested (HP unverified)"
        fight.lastAction = "Attack " .. target.model.Name .. (accepted == false and " / cooldown" or " / sent")
        fightNotice(accepted == false and "Attack cooling down; keeping pressure on " .. target.model.Name
            or "PHANTOM STRIKE | " .. target.model.Name .. " | Stage " .. tostring(run.stage))
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
progressStats.TextColor3 = color.accent
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
    return true
end)
note("V9: reduced dodge/chase oscillation, attack-priority windows, and fast unlabeled-bullet tracking. Hits and damage remain server controlled.")
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
stepper("Dodge cooldown (ms)", "dodgeMs", 90, 480, 30)
stepper("Projectile scan radius", "projectileRadius", 25, 85, 5)
stepper("Retreat below HP (%)", "retreatHealth", 10, 50, 5)
note("PHANTOM forecasts moving projectiles (including tweened shots) and strafes against lined-up guns. Hitscan/lag/server hits may still connect.")
local rapidButton, finishButton
rapidButton = ordered(button(scroll, "", function() fight.rapid = not fight.rapid refresh() end))
finishButton = ordered(button(scroll, "", function() fight.finishWeak = not fight.finishWeak refresh() end))
refreshers[#refreshers + 1] = function()
    rapidButton.Text = "QUICK STRIKE attempts  |  " .. (fight.rapid and "ON" or "OFF")
    finishButton.Text = "Focus weakened enemies  |  " .. (fight.finishWeak and "ON" or "OFF")
end
stepper("Strike check interval (ms)", "attackMs", 50, 350, 30)
note("V10 RIPPER FIX: improved arena-floor search, boss chase fallback, and adaptive reach when attacks do no damage. Check diagnostics for observed enemy HP drops (not proof of your kill credit). No one-hit / invincibility bypass is possible by simply editing a client script.")
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
    local lines = {"NOVA VENOM v8 ASCENSION - FROST UI + EVOLUTION AUTOPILOT + PHANTOM DEFENSE", "Place: " .. tostring(game.PlaceId), "Universe: " .. tostring(game.GameId),
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
        "Auto fights: " .. fight.detail, "Fight stage: " .. tostring(fight.run and fight.run.stage),
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
        "Observed enemy HP decreases (not kill credit): " .. tostring(fight.hpConfirmedHits),
        "Observed boss HP decreases: " .. tostring(fight.hpConfirmedBossHits),
        "Total observed enemy HP reduction: " .. tostring(fight.hpDamageDealt),
        "Arena-floor fallbacks: " .. tostring(fight.groundFallbacks),
        "Chase MoveTo fallbacks: " .. tostring(fight.chaseFallbacks),
        "Busy() blocked frames: " .. tostring(fight.attacksBlocked),
        "Nearby projectiles: " .. tostring(fight.seenProjectiles),
        "Projectile radar: " .. tostring(fight.ballistic) .. " / " .. tostring(values.projectileRadius) .. " studs",
        "Dodge cooldown: " .. tostring(values.dodgeMs) .. "ms / Last cue: " .. tostring(fight.dodgeReason),
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
recolorButton(stop, color.dangerSurface, color.dangerTint, Color3.fromRGB(223, 113, 132), color.danger)
local bubble = button(screen, "V", function() panel.Visible = not panel.Visible end)
bubble.Name = "OpenMenu"
bubble.Position, bubble.Size = UDim2.fromOffset(12, 12), UDim2.fromOffset(44, 44)
bubble.Font, bubble.TextSize = Enum.Font.GothamBlack, 23
recolorButton(bubble, color.accent, color.purple, color.accent, Color3.fromRGB(255, 255, 255))
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

-- PHANTOM defense loop runs independently of the attack/encounter loop.
-- Do not yield here: a late defensive scan cannot delay the next strike.
local lastPhantomStep = -math.huge
connect(RunService.Heartbeat, function()
    if not running or not state.fight or not fight.dodge or not alive() then return end
    local phase, folder = fight.lastCombatPhase, fight.lastCombatFolder
    if phase ~= "boss" and phase ~= "waves" and phase ~= "snipers" then return end
    if not folder or not folder.Parent then return end
    local now = os.clock()
    -- Avoid two independent systems repositioning the root in the same frame.
    if fight.run and now - fight.lastMove < 0.065 then return end
    if now - lastPhantomStep < 0.035 then return end
    lastPhantomStep = now
    local ok, err = pcall(evadeFight, now, fight.lastCombatTarget, phase, folder, fight.lastCombatReach)
    if not ok and now - fight.lastCombatReport > 3 then
        fight.lastCombatReport = now
        warn("NOVA PHANTOM defense: " .. tostring(err))
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
                hud.Text = state.fight and ("FIGHT ●   |   BOSS " .. (fight.bossDetected and "●" or "--")
                    .. "   |   DODGE " .. tostring(fight.dodgeCount)
                    .. "   |   HP " .. tostring(math.floor(humanoid.Health))
                    .. "   |   DMG " .. tostring(fight.hpConfirmedHits))
                    or ("FIGHT OFF   |   TRAIN " .. (state.train and "●" or "--")
                        .. "   |   PHANTOM READY")
            end
            if state.speed then applyProperty(humanoid, "WalkSpeed", values.speed) end
            if state.jump then
                if humanoid.UseJumpPower then applyProperty(humanoid, "JumpPower", values.jump)
                else applyProperty(humanoid, "JumpHeight", values.jump * values.jump / (2 * math.max(workspace.Gravity, 1))) end
            end
            if state.progress then tickProgress(now) end
            local fightsOwnMovement = state.fight and tickFight(now)
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
            if heldPrompt and not promptUsable() then
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
            warn("NOVA VENOM: " .. tostring(err))
            notify("Feature error: " .. tostring(err):sub(1, 150))
        end
        task.wait(state.fight and 0.05 or 0.1)
    end
end)
refresh()
notify("NOVA VENOM V10 ready. Smarter Ripper pursuit, HP-verified strikes, predictive sidesteps.")
