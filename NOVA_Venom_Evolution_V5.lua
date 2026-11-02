-- NOVA VENOM | V5 PROJECTILE DEFENSE + BOSS PRESSURE + CONTINUOUS COMBAT
-- Target: https://www.roblox.com/games/116448925875915/1-Venom-Evolution
-- Copy this ENTIRE file into your client Lua runner while inside the game.
-- No downloads, keys, remote loaders, fake Wins, or invented server remotes.
-- Not tested in the live game. Server checks may reject movement/interactions.
--
-- AUTO TRAIN: finds SoundChamber models and their Pad parts in the live map.
-- Uses the player's Chambers ownership attribute and actual chamber multipliers.
-- Rechecks unlocks automatically. It never uses a manual bookmark for training.
-- Runtime interfaces are validated; live-game compatibility is still unverified.
-- AUTO FIGHTS: uses EncounterController/CombatController for repeat fights.
-- QUICK STRIKE: checks native cooldown frequently and prioritizes wounded enemies.
-- V5 AUTO DODGE: trajectory-based nearby projectile detection, shorter reaction delays,
-- readable enemy attack wind-ups, evasive flanks, and low health retreat.
-- V5 BOSS OFFENSE: still attacks after dodges instead of canceling the entire attack tick.
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
local state = {speed = false, jump = false, noclip = false, hold = false, tool = false, prompt = false, train = false, fight = false, afk = false}
local values = {speed = 32, jump = 80, interval = 2, stageLimit = 0, attackMs = 50, dodgeRange = 10, retreatHealth = 28, dodgeMs = 180, projectileRadius = 28}
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
local stopAll, cleanup
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
    lastAttackTarget = nil, lastHitHealth = 0, lastHitAt = -math.huge, lastAggro = -math.huge}
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

local color = {
    bg = Color3.fromRGB(18, 19, 22), card = Color3.fromRGB(32, 34, 39),
    muted = Color3.fromRGB(164, 168, 177), text = Color3.fromRGB(237, 239, 243),
    edge = Color3.fromRGB(57, 60, 68), on = Color3.fromRGB(111, 232, 159),
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
        Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = true,
    }, parent)
    round(b, 8)
    if callback then
        connect(b.Activated, function()
            if not running then return end
            local ok, err = pcall(callback)
            if not ok then warn("NOVA VENOM button: " .. tostring(err)) end
        end)
    end
    return b
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
    Size = UDim2.fromOffset(350, 490), Position = UDim2.fromOffset(20, 40),
    BackgroundColor3 = color.bg, BorderSizePixel = 0, ClipsDescendants = true,
}, screen)
round(panel, 14)
make("UIStroke", {Color = color.edge, Thickness = 1}, panel)
local dragHandle = make("TextLabel", {
    Size = UDim2.new(1, -94, 0, 48), Position = UDim2.fromOffset(14, 0),
    BackgroundTransparency = 1, Active = true, Text = "N  /  VENOM NOVA V4",
    Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = color.text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
local minimize = button(panel, "-", function() panel.Visible = false end)
minimize.Size, minimize.Position = UDim2.fromOffset(30, 30), UDim2.new(1, -76, 0, 9)
local close = button(panel, "X", function() cleanup() end)
close.Size, close.Position = UDim2.fromOffset(30, 30), UDim2.new(1, -40, 0, 9)
local status = label(panel, "Ready. Features start OFF.", 12)
status.Position, status.Size = UDim2.fromOffset(14, 48), UDim2.new(1, -28, 0, 46)
status.TextColor3 = color.muted
local function notify(message)
    if running then status.Text = tostring(message) end
end
local scroll = make("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 100), Size = UDim2.new(1, -24, 1, -158),
    BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
    ScrollBarThickness = 5, ScrollBarImageColor3 = color.muted,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
make("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, scroll)
local layout = make("UIListLayout", {Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder}, scroll)
local order = 0
local function ordered(object)
    order = order + 1
    object.LayoutOrder = order
    return object
end
local function section(text)
    local l = ordered(label(scroll, text, 11))
    l.TextColor3, l.Size = color.muted, UDim2.new(1, 0, 0, 25)
end
local function note(text)
    local l = ordered(label(scroll, text, 11))
    l.TextColor3, l.Size = color.muted, UDim2.new(1, 0, 0, 52)
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
        b.Text = text .. (state[key] and "  |  ON" or "  |  OFF")
        b.TextColor3 = state[key] and color.on or color.text
    end
end
local function stepper(text, key, low, high, step)
    local row = ordered(make("Frame", {
        Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = color.card, BorderSizePixel = 0,
    }, scroll))
    round(row, 8)
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
end
resetFightCharacter = function()
    if state.fight and fight.run and not fight.run.won then fight.defeats = fight.defeats + 1 end
    fight.run, fight.waitUntil = nil, os.clock() + 5
    fight.releasingTraining, fight.releaseStartedAt = false, nil
    fight.lastHealth, fight.lastHurtAt = nil, -math.huge
    if state.fight and fight.defeats >= 3 then
        state.fight = false refresh()
        notify("Auto fights stopped after 3 defeats. Train or evolve before trying again.")
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
local function fightGround(position, folder, reward, outside)
    local cf, size = stageZone(folder)
    if not cf then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local ignored = {character}
    for _, enemy in ipairs(CollectionService:GetTagged("VenomEnemy")) do ignored[#ignored + 1] = enemy end
    local height = math.max(16, math.min(128, size.Y * 0.5 + 12))
    local origin = position + Vector3.new(0, height, 0)
    for _ = 1, 12 do
        params.FilterDescendantsInstances = ignored
        local result = workspace:Raycast(origin, Vector3.new(0, -math.min(512, size.Y + height + 80), 0), params)
        if not result then return nil end
        local part = result.Instance
        if not part:IsA("BasePart") or blockedSurface(part, outside and workspace or folder, reward) then return nil end
        if part.CanCollide and result.Normal.Y >= 0.75 then
            local point = cf:PointToObjectSpace(result.Position)
            if not outside and (math.abs(point.X) > size.X * 0.5 + 2 or math.abs(point.Z) > size.Z * 0.5 + 2) then return nil end
            if outside and number(nativeCall(native.modules.maps, "WorldAt", false, result.Position)) ~= stageWorld(fight.run.stage) then return nil end
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
-- Identify bosses without assuming every boss uses the ordinary enemy tag.
local function isStageBoss(model)
    if not model or not model:IsA("Model") then return false end
    if CollectionService:HasTag(model, "VenomBoss") or CollectionService:HasTag(model, "Boss") then return true end
    for _, key in ipairs({"Boss", "IsBoss", "BossEnemy", "StageBoss", "EnemyBoss"}) do
        if model:GetAttribute(key) == true then return true end
    end
    return model.Name:lower():find("boss", 1, true) ~= nil
end
local function bossCandidates(stage, phase, folder, now)
    if phase ~= "boss" or not fight.bosses then return {} end
    if fight.previousStage == stage and now - fight.lastBossScan < 0.4 then
        return fight.cachedBosses
    end
    local bosses, seen = {}, {}
    local function add(model)
        if model and model:IsA("Model") and not seen[model] and model:IsDescendantOf(workspace)
            and isStageBoss(model) then
            seen[model] = true
            bosses[#bosses + 1] = model
        end
    end
    for _, tag in ipairs({"VenomBoss", "Boss"}) do
        for _, model in ipairs(CollectionService:GetTagged(tag)) do add(model) end
    end
    -- Stage-local fallback for boss models without CollectionService tags.
    if folder then
        for _, model in ipairs(folder:GetDescendants()) do
            if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and isStageBoss(model) then
                add(model)
            end
        end
    end
    fight.cachedBosses, fight.lastBossScan, fight.previousStage = bosses, now, stage
    return bosses
end
local function fightEnemies(stage, phase, folder, now)
    local target, bestScore, count, total = nil, math.huge, 0, 0
    local seen = {}
    fight.bossDetected = false
    local function consider(model, bossOnly)
        if typeof(model) ~= "Instance" or not model:IsA("Model") or seen[model]
            or not model:IsDescendantOf(workspace) then return end
        seen[model] = true
        local stageValue = number(model:GetAttribute("Stage"))
        if stageValue and stageValue ~= stage then return end
        if not stageValue and (not folder or not model:IsDescendantOf(folder)) then return end
        local boss = isStageBoss(model)
        if bossOnly and not boss then return end
        if not boss and (model:GetAttribute("Bonus") ~= nil or model:GetAttribute("Tower") ~= nil) then return end
        if model:GetAttribute("Dead") == true or model:GetAttribute("KilledBy") ~= nil then return end
        local h = model:FindFirstChildOfClass("Humanoid")
        local r = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        if not h or not r or not r:IsA("BasePart") or h.Health <= 0 then return end
        local brain = nativeCall(native.modules.encounter, "Brain", true, model)
        if type(brain) == "table" and type(brain.stage) == "table"
            and number(brain.stage.index) ~= stage then return end
        if type(brain) == "table" and brain.state == "dead" then return end
        -- Ordinary stage enemies require the native brain; named boss fallbacks
        -- are allowed only in the active boss phase and inside the stage arena.
        -- During the boss phase, some boss humanoids are not tagged and have
        -- no explicit "Boss" in their name; permit a stage-owned NPC fallback.
        if not boss and (type(brain) ~= "table" or type(brain.stage) ~= "table") then
            if not (phase == "boss" and folder and model:IsDescendantOf(folder)
                and stageValue == stage and Players:GetPlayerFromCharacter(model) == nil) then return end
            boss = true
        end
        if boss and phase ~= "boss" and type(brain) ~= "table" then return end
        count, total = count + 1, total + h.Health
        if boss then fight.bossDetected = true end
        if model:GetAttribute("Finishing") == true or model:GetAttribute("Pulled") == true then return end
        local dist = (r.Position - root.Position).Magnitude
        local score = dist
        if fight.finishWeak and dist <= 30 and h.MaxHealth > 0 then
            local ratio = math.clamp(h.Health / h.MaxHealth, 0, 1)
            if ratio < 0.5 then score = score * 0.68 - (1 - ratio) * 5 end
        end
        if fight.run and fight.run.lockedTarget == model then score = score - 5 end
        if boss and phase == "boss" and fight.bosses then score = score - 1000 end
        if score < bestScore then
            bestScore = score
            target = {model = model, root = r, humanoid = h, brain = brain, boss = boss}
        end
    end
    for _, model in ipairs(CollectionService:GetTagged("VenomEnemy")) do consider(model, false) end
    for _, model in ipairs(bossCandidates(stage, phase, folder, now)) do consider(model, true) end
    if phase == "boss" and not target and folder then
        -- Explicit stage NPC fallbacks only: never select player characters.
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid")
                and number(obj:GetAttribute("Stage")) == stage
                and Players:GetPlayerFromCharacter(obj) == nil then
                consider(obj, false)
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
            for _, name in ipairs({"attack", "strike", "windup", "lunge", "slam", "cast", "charge"}) do
                if value:find(name, 1, true) then return true end
            end
        end
    end
    return false
end
-- V5 defensive radar: evaluates whether moving projectiles will enter the
-- player's collision envelope in the coming fraction of a second. This avoids
-- dodging every stationary decoration merely because its name says "bullet".
local projectileNames = {"projectile", "missile", "bullet", "fireball", "spit", "acidball",
    "enemyhitbox", "attackhitbox", "shockwave", "rocket", "grenade", "arrow",
    "laser", "bolt", "plasma", "shard", "orb", "bomb", "shot", "throw",
    "spear", "knife", "blast", "cannonball", "poisonball", "energyball"}
local function hostileProjectile(part)
    if not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then return false end
    if part:IsDescendantOf(character) or (part.Transparency >= 1 and not part.CanTouch) then return false end
    local owner = part:GetAttribute("OwnerUserId") or part:GetAttribute("ShooterUserId")
    if owner == player.UserId then return false end
    local projectile = part:GetAttribute("Projectile") == true or part:GetAttribute("IsProjectile") == true
        or part:GetAttribute("EnemyAttack") == true or part:GetAttribute("Hostile") == true
    if not projectile then
        local name = part.Name:lower()
        local parent = part.Parent
        local parentName = parent and parent.Name:lower() or ""
        for _, word in ipairs(projectileNames) do
            if name:find(word, 1, true) or parentName:find(word, 1, true) then
                projectile = true
                break
            end
        end
    end
    return projectile
end
local function nearbyThreat(now)
    -- Fast but bounded. Physics/projectile snapshots aren't available in every
    -- game build, so this detector is heuristic, not a hitscan defense.
    if now - fight.lastDefensiveScan < 0.055 then return fight.cachedThreat end
    fight.lastDefensiveScan = now
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.MaxParts = 110
    local scanRadius = math.max(12, values.projectileRadius)
    local ok, nearby = pcall(function()
        return workspace:GetPartBoundsInRadius(root.Position, scanRadius, params)
    end)
    if not ok or type(nearby) ~= "table" then fight.cachedThreat = nil return nil end
    local choice, score = nil, math.huge
    for _, part in ipairs(nearby) do
        if hostileProjectile(part) then
            local offset = part.Position - root.Position
            local velocity = part.AssemblyLinearVelocity
            local relative = velocity - root.AssemblyLinearVelocity * 0.6
            local speed2 = relative:Dot(relative)
            local dist = offset.Magnitude
            local timeTo = speed2 > 16 and math.clamp(-offset:Dot(relative) / speed2, 0, 0.8) or 0
            local nearest = offset + relative * timeTo
            local radius = math.max(3.5, math.min(9, 2.8 + part.Size.Magnitude * 0.28))
            local imminence = nearest.Magnitude <= radius and timeTo <= 0.75
            local close = dist <= math.max(4, radius + 1)
            -- Even slow stationary AoE hitboxes can be hazardous when touching.
            if (imminence and speed2 > 16) or close then
                local priority = timeTo * 10 + nearest.Magnitude * 0.55 + dist * 0.04
                if priority < score then
                    score = priority
                    choice = {part = part, position = part.Position, velocity = velocity,
                        intercept = part.Position + velocity * timeTo, time = timeTo, distance = dist}
                end
            end
        end
    end
    fight.cachedThreat = choice
    if choice and (fight.lastThreatInstance ~= choice.part or now - fight.lastThreatAt > 0.5) then
        fight.seenProjectiles = fight.seenProjectiles + 1
        fight.lastThreatInstance, fight.lastThreatAt = choice.part, now
    end
    return choice
end
local function enemyRanged(target)
    if not target then return false end
    local m = target.model
    if m:GetAttribute("Ranged") == true or m:GetAttribute("Shooter") == true
        or m:GetAttribute("Sniper") == true then return true end
    for _, word in ipairs({"gun", "sniper", "rifle", "archer", "caster", "throw", "ranged", "turret"}) do
        if m.Name:lower():find(word, 1, true) then return true end
    end
    return false
end
local function evadeFight(now, target, phase, folder, reach)
    if not fight.dodge or not root or not humanoid or humanoid.Health <= 0 then return false end
    reach = reach or 7
    local previous, health = fight.lastHealth, humanoid.Health
    fight.lastHealth = health
    if previous and health < previous then
        fight.lastHurtAt = now
        fight.healthLost = fight.healthLost + (previous - health)
    end
    local threat = fight.ballistic and nearbyThreat(now) or nil
    local enemyPos = target and target.root and target.root.Position or nil
    local dist = enemyPos and (enemyPos - root.Position).Magnitude or math.huge
    local attackTell = target and dist < math.max(35, reach * 3)
        and hasAttackTelegraph(target) or false
    local rangedTell = target and (phase == "snipers" or enemyRanged(target)) and attackTell
    local justHit = now - fight.lastHurtAt < 0.48
    local retreat = fight.retreat and humanoid.MaxHealth > 0
        and health / humanoid.MaxHealth <= values.retreatHealth / 100
        and now - fight.lastRetreat > 2.5
    -- Use less frequent footwork when there is no attack cue. Constantly
    -- running away on a boss fight prevents successful melee hits.
    local bossFootwork = target and phase == "boss" and target.boss and dist < math.max(12, reach + 4)
        and now - fight.lastDodge > 0.65
    -- A gun may be hitscan (no moving bullet part). Strafe occasionally
    -- against recognized ranged enemies without waiting for a projectile.
    local rangedLane = target and (phase == "snipers" or enemyRanged(target))
        and dist <= 38 and now - fight.lastDodge > 0.42
    local reason = threat and "projectile" or rangedTell and "ranged wind-up"
        or attackTell and "attack wind-up" or justHit and "recent damage"
        or retreat and "low health" or rangedLane and "ranged firing lane"
        or bossFootwork and "boss pressure" or nil
    if not reason then return false end
    local cooldown = threat and 0.13 or (attackTell and 0.18 or (justHit and 0.23 or values.dodgeMs / 1000))
    if now - fight.lastDodge < cooldown then return false end
    local threatPos = threat and threat.intercept or enemyPos
    if not threatPos then return false end
    local heading = threatPos - root.Position
    heading = Vector3.new(heading.X, 0, heading.Z)
    if heading.Magnitude < 0.1 then heading = Vector3.new(root.CFrame.LookVector.Z, 0, -root.CFrame.LookVector.X) end
    if heading.Magnitude < 0.1 then heading = Vector3.new(0, 0, 1) end
    heading = heading.Unit
    local side = Vector3.new(-heading.Z, 0, heading.X)
    local sign = (fight.dodgeCount % 2 == 0) and 1 or -1
    -- Keep light footwork in melee reach; only use full dodge distance for
    -- actual projectiles, telegraphed attacks, damage, or an emergency retreat.
    local urgent = threat or attackTell or justHit or retreat
    local len = urgent and values.dodgeRange or math.min(values.dodgeRange, math.max(3.2, reach * 0.55))
    local origin = root.Position
    local candidates = {
        origin + side * len * sign,
        origin - side * len * sign,
        origin + (side * sign - heading * 0.4).Unit * len,
        origin + (-side * sign - heading * 0.4).Unit * len,
    }
    if retreat then candidates[#candidates + 1] = origin - heading * (len + 4) end
    local best, bestScore = nil, -math.huge
    for _, proposed in ipairs(candidates) do
        local point = fightGround(proposed, folder, false)
        if point then
            local score = 0
            if threat then
                -- Prefer landing points farther from the projectile's future path.
                local soon = threat.position + threat.velocity * math.clamp(threat.time + 0.16, 0, 0.7)
                score = score + math.min((point - soon).Magnitude, 26) * 1.3
            end
            if enemyPos then
                local rangeAfter = (point - enemyPos).Magnitude
                -- Preserve striking distance unless a projectile is about to hit.
                if not retreat then
                    local desired = math.max(3, reach * 0.83)
                    score = score - math.abs(rangeAfter - desired) * (threat and 0.6 or 2.2)
                    if rangeAfter > reach + 3 then score = score - (rangeAfter - reach - 3) * 1.7 end
                else
                    score = score + math.min(rangeAfter, 30)
                end
            end
            if point and score > bestScore then best, bestScore = point, score end
        end
    end
    if not best then return false end
    -- Short local evasive step. Does not change health or bypass server damage.
    moveRoot(best)
    fight.lastDodge, fight.dodgeCount, fight.dodgeReason = now, fight.dodgeCount + 1, reason
    if retreat then fight.lastRetreat = now end
    -- Suppress repeated status spam, preserving a responsive combat loop.
    if now - fight.lastCombatReport >= 0.6 then
        fight.lastCombatReport = now
        fightNotice("Evading " .. reason .. " | " .. tostring(fight.dodgeCount) .. " steps")
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
        fight.cachedBosses, fight.lastBossScan = {}, -math.huge
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
                fight.cachedBosses, fight.lastBossScan = {}, -math.huge
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
    if now - run.progressAt > 45 then failFight("No combat progress for 45 seconds. Train or inspect diagnostics.") return false end
    if not target then
        -- Projectiles and AoE hazards can remain when enemies momentarily
        -- disappear from the native roster (notably boss transitions).
        evadeFight(now, nil, phase, folder, 7)
        fightNotice("Stage " .. tostring(run.stage) .. ": waiting for enemy target.")
        return true
    end
    -- Chase targets even while an attack animation is active. The native
    -- combat controller still determines whether another strike is permitted.
    if run.lockedTarget ~= target.model then run.lockedTarget = target.model end
    local moves = native.modules.combatConfig and native.modules.combatConfig.Moves
    local move = moves and moves.Bite
    if moves and type(moves.ClawR) == "table" and (number(player:GetAttribute("BondStage")) or 0) >= (number(moves.ClawR.level) or math.huge) then
        move = moves.ClawR
    end
    local reach = type(move) == "table" and number(move.reach) or 7
    reach = math.max(1, math.min(100, (reach or 7) - 0.25))
    -- Defensive movement is independent of native attack readiness. Dodging
    -- must never cancel an eligible boss attack that is still in reach.
    local dodged = evadeFight(now, target, phase, folder, reach)
    local distance = (target.root.Position - root.Position).Magnitude
    if distance > reach then
        if not dodged and now - fight.lastMove >= 0.18 then
            local delta = root.Position - target.root.Position
            local direction = Vector3.new(delta.X, 0, delta.Z)
            direction = direction.Magnitude > 0.01 and direction.Unit or Vector3.new(0, 0, 1)
            local point = fightGround(target.root.Position + direction * math.min(4, reach * 0.6), folder, false)
            if not point then fightNotice("Waiting for a supported path to the stage enemy.") return true end
            moveRoot(point) fight.lastMove = now
        end
        return true
    end
    local face = Vector3.new(target.root.Position.X, root.Position.Y, target.root.Position.Z)
    if (face - root.Position).Magnitude > 0.01 then
        root.CFrame = CFrame.lookAt(root.Position, face)
    end
    -- Even on a dodge tick, continue with the game's normal attack controller.
    local busyOK, busy = fightCall(native.modules.combat, "Busy", true)
    if not busyOK then
        fightNotice("Waiting for native combat readiness.")
        return true
    end
    if busy then return true end
    local interval = fight.rapid and math.max(0.05, values.attackMs / 1000) or 0.20
    if now - fight.lastAttack >= interval then
        fight.lastAttack = now
        local attacked, accepted = fightCall(native.modules.combat, "Attack", true)
        if not running or not state.fight then return true end
        if not attacked then failFight("The native attack call failed. Open diagnostics.") return true end
        fight.attacks = fight.attacks + 1
        if accepted ~= false then
            fight.accepted = fight.accepted + 1
            if target.boss then fight.bossHits = fight.bossHits + 1 end
        end
        fightNotice(accepted == false and "Native attack cooling down (server damage unchanged)."
            or "Quick strike | Stage " .. tostring(run.stage) .. " | Enemies: " .. tostring(count))
    end
    return true
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
    fight.dodgeCount, fight.bossHits, fight.healthLost, fight.seenProjectiles = 0, 0, 0, 0
    fight.lastHealth, fight.lastHurtAt, fight.lastDodge = humanoid.Health, -math.huge, -math.huge
    fight.lastAttack, fight.lastMove = -math.huge, -math.huge
    fight.lastDefensiveScan, fight.cachedThreat = -math.huge, nil
    fight.lastCombatReport, fight.dodgeReason = -math.huge, "None"
    return true
end)
note("V5: fast trajectory-based projectile defense, anti-ranged telegraph dodges, and combat that continues while dodging bosses.")
section("BOSS HUNTER + DODGE")
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
stepper("Dodge distance (studs)", "dodgeRange", 6, 18, 2)
stepper("Dodge cooldown (ms)", "dodgeMs", 120, 600, 30)
stepper("Projectile scan radius", "projectileRadius", 12, 40, 4)
stepper("Retreat below HP (%)", "retreatHealth", 10, 50, 5)
note("Evasive steps can still be corrected by the server. Gun hitscan may have no visible projectile to dodge; zero-damage mode is unavailable.")
local rapidButton, finishButton
rapidButton = ordered(button(scroll, "", function() fight.rapid = not fight.rapid refresh() end))
finishButton = ordered(button(scroll, "", function() fight.finishWeak = not fight.finishWeak refresh() end))
refreshers[#refreshers + 1] = function()
    rapidButton.Text = "QUICK STRIKE attempts  |  " .. (fight.rapid and "ON" or "OFF")
    finishButton.Text = "Focus weakened enemies  |  " .. (fight.finishWeak and "ON" or "OFF")
end
stepper("Strike check interval (ms)", "attackMs", 50, 350, 30)
note("Boss attack fix: dodging does not stop native attacks in range. Quick Strike and target finishers use the game's legal combat timings. Real one-hit kill is not available from client-side edits.")
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
    local lines = {"NOVA VENOM v5 - Fast Projectile Defense + Boss Offense", "Place: " .. tostring(game.PlaceId), "Universe: " .. tostring(game.GameId),
        "Auto train: " .. native.detail, "Level: " .. tostring(player:GetAttribute("Level")),
        "World: " .. tostring(player:GetAttribute("World")), "Chambers: " .. tostring(player:GetAttribute("Chambers")),
        "Native training active: " .. tostring(nativeActive()), "Venom: " .. tostring(readVenom()),
        "Auto fights: " .. fight.detail, "Fight stage: " .. tostring(fight.run and fight.run.stage),
        "Fight defeats: " .. tostring(fight.defeats), "Strike attempts: " .. tostring(fight.attacks),
        "Native strike requests: " .. tostring(fight.accepted),
        "Rapid strike: " .. tostring(fight.rapid) .. " / " .. tostring(values.attackMs) .. "ms",
        "Dodge: " .. tostring(fight.dodge) .. " | Attempts: " .. tostring(fight.dodgeCount),
        "Boss hunt: " .. tostring(fight.bosses) .. " | Detected: " .. tostring(fight.bossDetected),
        "Boss attack requests: " .. tostring(fight.bossHits),
        "Nearby projectiles: " .. tostring(fight.seenProjectiles),
        "Projectile radar: " .. tostring(fight.ballistic) .. " / " .. tostring(values.projectileRadius) .. " studs",
        "Dodge cooldown: " .. tostring(values.dodgeMs) .. "ms / Last cue: " .. tostring(fight.dodgeReason),
        "Observed HP lost: " .. tostring(math.floor(fight.healthLost)),
        "WinReady: " .. tostring(player:GetAttribute("WinReady")),
        "BondStage: " .. tostring(player:GetAttribute("BondStage")), "Anti-AFK input calls completed: " .. tostring(afkInputs)}
    for _, key in ipairs({"config", "maps", "training", "data", "encounter", "combat", "stages", "encounters", "combatConfig"}) do
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

local stop = button(panel, "STOP ALL + RESTORE MOVEMENT", function() stopAll() end)
stop.Position, stop.Size = UDim2.new(0, 12, 1, -50), UDim2.new(1, -24, 0, 38)
local bubble = button(screen, "N", function() panel.Visible = not panel.Visible end)
bubble.Name = "OpenMenu"
bubble.Position, bubble.Size = UDim2.fromOffset(12, 12), UDim2.fromOffset(44, 44)
bubble.Font, bubble.TextSize = Enum.Font.GothamBlack, 23
round(bubble, 22)

stopAll = function()
    stopFight()
    stopNative(true)
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
    local width, height = math.min(350, w - 20), math.min(490, h - 20)
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

local lastErrorAt = -10
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
            if state.speed then applyProperty(humanoid, "WalkSpeed", values.speed) end
            if state.jump then
                if humanoid.UseJumpPower then applyProperty(humanoid, "JumpPower", values.jump)
                else applyProperty(humanoid, "JumpHeight", values.jump * values.jump / (2 * math.max(workspace.Gravity, 1))) end
            end
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
        task.wait(state.fight and fight.rapid and 0.05 or 0.1)
    end
end)
refresh()
notify("NOVA VENOM V5 ready. Projectile radar and boss offense ON; enable Auto Fights to begin.")
