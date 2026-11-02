--[[
NOVA / +1 Venom Evolution / 0.1 experimental client build
Single readable file. No downloads, keys, webhooks, or third-party UI library.

SETUP
  1. Open the game. Run this file in your existing Lua execution environment.
  2. Equip a combat Tool, or use Bind > Record, perform ONE ordinary attack,
     review the captured FireServer samples, and explicitly bind the right one.
  3. Configure Farm. Training needs its own selected Tool or recorded binding.
  4. Travel lists loaded entrance prompts; unlock requirements still apply.
  5. Info > Copy report provides diagnostics when the game uses another system.

LIMITS
  This is a generic, unverified adapter for this game's client, not a tested
  game-specific exploit. It cannot guarantee kills, dodges, cross-world travel,
  fast training, or shield damage. One-hit kills, god mode, shield bypasses and
  damage multipliers are NOT implemented. Normal server cooldowns still apply.
  Farm only sees streamed-in NPCs. Teleporting into another place requires a
  fresh execution. No unknown remote is guessed or fired automatically.
  Recorded actions are session-only and require explicit review and binding.
  Target instances/positions can be remapped; opaque IDs cannot be inferred.

CONTROLS
  Touch/click the eye badge to reopen. Drag the header. Scroll each page.
  RightControl: show/hide. F6 or red STOP button: stop all automation.
  Info > Unload: disconnect the controller and remove its interface.
]]

local VERSION = "0.1 experimental"
local PLACE_ID, UNIVERSE_ID = 116448925875915, 10769464063
local SESSION_KEY, BROKER_KEY = "__NOVA_VENOM_SESSION_V1", "__NOVA_VENOM_CAPTURE_V1"
local Env = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then Env = result end
end
if type(Env[SESSION_KEY]) == "table" and type(Env[SESSION_KEY].Close) == "function" then
    pcall(Env[SESSION_KEY].Close)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
assert(player, "NOVA must run on a Roblox client.")
local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "NOVA: PlayerGui was not available. Rejoin and try again.")
local allowed = game.PlaceId == PLACE_ID or game.GameId == UNIVERSE_ID
local unpackArgs = table.unpack or unpack
local function pack(...) return {n = select("#", ...), ...} end
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function contains(s, part) return string.find(string.lower(s), part, 1, true) ~= nil end
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < 1e15 end
local function path(instance)
    local ok, value = pcall(function() return instance:GetFullName() end)
    return ok and value or "<removed>"
end
local function live(instance)
    return typeof(instance) == "Instance" and instance:IsDescendantOf(game)
end
local function attr(instance, name)
    local ok, value = pcall(function() return instance:GetAttribute(name) end)
    if ok then return value end
end

local state = {
    running = true, npcs = {}, projectiles = {}, prompts = {}, connections = {},
    queue = {}, queued = {}, queueHead = 1, queueTail = 0, ignored = {},
    farm = false, attack = false, dodge = false, train = false, fastTrain = false,
    antiAfk = false, retreat = false, healing = false, filter = "All", textFilter = "",
    order = "Nearest", attackInterval = 0.25, trainInterval = 0.4, distance = 5,
    target = nil, targetHealth = nil, targetProgress = 0, observedDefeats = 0,
    attackBinding = nil, trainBinding = nil, attackTool = nil, trainTool = nil,
    samples = {}, sampleIndex = 1, recording = false, recordUntil = 0,
    recordSource = nil, captureQueue = {}, captureCount = 0, replaying = false,
    status = allowed and "Equip a combat Tool or bind an action first." or "Wrong game: automation is disabled.",
    statusUntil = math.huge, lastAttack = 0, lastTrain = 0, lastDodge = -10,
    lastMove = -10, movementProbe = nil, correctionCount = 0, evadeUntil = 0,
    safeSpot = nil, promptIndex = 1, highlight = nil, lastError = "none", log = {},
    retreatMessage = false, manualUntil = 0, heldPrompt = nil, broker = nil,
}
local App = {}
Env[SESSION_KEY] = App
local UI = {refreshers = {}, pages = {}, tabs = {}, activeTab = "Farm"}
local function connect(signal, fn)
    local connection = signal:Connect(fn)
    state.connections[#state.connections + 1] = connection
    return connection
end
local function note(message, seconds)
    state.status, state.statusUntil = tostring(message), os.clock() + (seconds or 5)
    state.log[#state.log + 1] = tostring(message)
    if #state.log > 10 then table.remove(state.log, 1) end
end
local function ownCharacter()
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
        return character, humanoid, root
    end
end
local function clearTarget()
    state.target, state.targetHealth, state.targetProgress = nil, nil, 0
    if state.highlight then state.highlight.Adornee = nil end
end
local function stopAll(message)
    state.farm, state.attack, state.dodge, state.train = false, false, false, false
    state.antiAfk, state.retreat, state.healing, state.recording = false, false, false, false
    state.movementProbe, state.manualUntil = nil, 0
    if state.heldPrompt then
        pcall(function() state.heldPrompt:InputHoldEnd() end)
        state.heldPrompt = nil
    end
    clearTarget()
    note(message or "All automation stopped.")
end
function App.Close()
    if not state.running then return end
    stopAll("Unloaded.")
    state.running = false
    if state.broker and state.broker.owner == App then
        state.broker.observer, state.broker.owner = nil, nil
    end
    for _, connection in ipairs(state.connections) do pcall(function() connection:Disconnect() end) end
    if state.highlight then state.highlight:Destroy() end
    if UI.gui then UI.gui:Destroy() end
    if Env[SESSION_KEY] == App then Env[SESSION_KEY] = nil end
end

-- Candidate discovery uses streamed-in instances only. Player characters,
-- obvious pets and service NPCs are excluded. Classification is heuristic.
local function playerModel(model)
    local cursor = model
    while cursor and cursor ~= Workspace do
        if cursor:IsA("Model") and Players:GetPlayerFromCharacter(cursor) then return true end
        cursor = cursor.Parent
    end
    return false
end
local function rootOf(model)
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        or model:FindFirstChild("RootPart") or model:FindFirstChild("Torso")
        or model:FindFirstChildWhichIsA("BasePart", true)
    if root and root:IsA("BasePart") then return root end
end
local function numberHealth(model, wanted)
    for _, name in ipairs(wanted) do
        local value = attr(model, name)
        if finite(value) then return value end
        local child = model:FindFirstChild(name)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) and finite(child.Value) then
            return child.Value
        end
    end
end
local function healthOf(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then return humanoid.Health, humanoid.MaxHealth end
    return numberHealth(model, {"Health", "HP", "health"}),
        numberHealth(model, {"MaxHealth", "MaxHP", "maxHealth"})
end
local function discoverModel(model)
    if not model or not model:IsA("Model") or not model:IsDescendantOf(Workspace) then return end
    if playerModel(model) then state.npcs[model] = nil; return end
    local full = string.lower(path(model))
    if attr(model, "IsEnemy") == false or attr(model, "Friendly") == true
        or contains(full, ".pets.") or contains(full, ".pets") then
        state.npcs[model] = nil; return
    end
    for _, word in ipairs({"shop", "merchant", "vendor", "trainingdummy", "questgiver", "decoration"}) do
        if contains(full, word) then state.npcs[model] = nil; return end
    end
    local hp = healthOf(model)
    local root = rootOf(model)
    if not root or not finite(hp) then return end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local hostile = humanoid ~= nil or contains(full, "enem") or contains(full, "boss")
        or contains(full, "mob") or attr(model, "IsEnemy") == true
    if not hostile then return end
    local old = state.npcs[model]
    state.npcs[model] = {
        model = model, root = root, full = full,
        boss = contains(full, "boss") or attr(model, "IsBoss") == true,
        health = hp, maxHealth = select(2, healthOf(model)),
        previous = old and old.previous or hp,
    }
end
local function enqueue(model)
    if model and model:IsA("Model") and not state.queued[model] then
        state.queued[model] = true
        state.queueTail = state.queueTail + 1
        state.queue[state.queueTail] = model
    end
end
local function classifyInstance(instance)
    if instance:IsA("Model") then enqueue(instance) end
    local parent = instance.Parent
    if parent and parent:IsA("Model") then enqueue(parent) end
    if instance:IsA("ProximityPrompt") then
        local full = string.lower(path(instance) .. " " .. instance.ActionText .. " " .. instance.ObjectText)
        if contains(full, "portal") or contains(full, "world") or contains(full, "stage")
            or contains(full, "area") or contains(full, "enter") or contains(full, "travel") then
            state.prompts[instance] = true
        end
    elseif instance:IsA("BasePart") then
        local lower = string.lower(instance.Name .. " " .. (parent and parent.Name or ""))
        if contains(lower, "bullet") or contains(lower, "projectile") or contains(lower, "missile")
            or contains(lower, "fireball") or contains(lower, "rocket") then
            state.projectiles[instance] = {position = instance.Position, time = os.clock()}
        end
    end
end
local function eligible(entry, origin)
    if not live(entry.model) or not live(entry.root) or playerModel(entry.model) then return false end
    local hp = healthOf(entry.model)
    entry.health = hp
    if not finite(hp) or hp <= 0 then return false end
    if (state.ignored[entry.model] or 0) > os.clock() then return false end
    if state.filter == "Bosses" and not entry.boss then return false end
    if state.filter == "Enemies" and entry.boss then return false end
    if state.textFilter ~= "" and not contains(path(entry.model), state.textFilter) then return false end
    return not origin or (entry.root.Position - origin).Magnitude < 100000
end
local function chooseTarget(origin, maxDistance)
    local best, score
    for _, entry in pairs(state.npcs) do
        if eligible(entry, origin) and (not maxDistance or (entry.root.Position - origin).Magnitude <= maxDistance) then
            local nextScore = (entry.root.Position - origin).Magnitude
            if state.order == "Lowest HP" then nextScore = entry.health + nextScore / 1000000 end
            if state.order == "Boss first" and entry.boss then nextScore = nextScore - 1000000 end
            if not score or nextScore < score then best, score = entry, nextScore end
        end
    end
    return best
end
local function shielded(model)
    if model:FindFirstChildOfClass("ForceField") then return true end
    for _, name in ipairs({"Shield", "ShieldHealth", "ShieldHP", "Invulnerable", "Shielded"}) do
        local value = attr(model, name)
        if value == true or (finite(value) and value > 0) then return true end
        local child = model:FindFirstChild(name)
        if child and ((child:IsA("BoolValue") and child.Value)
            or ((child:IsA("IntValue") or child:IsA("NumberValue")) and child.Value > 0)) then
            return true
        end
    end
    return false
end

-- Bounded, explicit action recording. Nothing is selected just because its
-- name resembles Attack/Train. Only a reviewed sample can be replayed.
local Hook = hookmetamethod or Env.hookmetamethod
local Namecall = getnamecallmethod or Env.getnamecallmethod
local NewClosure = newcclosure or Env.newcclosure
local function snapshot(value, seen, depth, budget)
    if type(value) ~= "table" then return value end
    if depth > 6 or seen[value] then error("Cyclic/deep action arguments are unsupported.") end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        budget.n = budget.n + 1
        if budget.n > 256 then error("Action arguments exceed the capture limit.") end
        copy[snapshot(key, seen, depth + 1, budget)] = snapshot(child, seen, depth + 1, budget)
    end
    seen[value] = nil
    return copy
end
local function installRecorder()
    local broker = Env[BROKER_KEY]
    if type(broker) == "table" and broker.installed then state.broker = broker; return true end
    if type(Hook) ~= "function" or type(Namecall) ~= "function" then return false end
    broker = {installed = false}
    local original
    local function intercept(remote, ...)
        local method = Namecall()
        if method == "FireServer" and broker.observer then
            pcall(broker.observer, remote, pack(...))
        end
        return original(remote, ...)
    end
    local closure = type(NewClosure) == "function" and NewClosure(intercept) or intercept
    local ok, result = pcall(function() return Hook(game, "__namecall", closure) end)
    if not ok or type(result) ~= "function" then return false end
    original, broker.installed = result, true
    broker.original, broker.closure = original, closure
    Env[BROKER_KEY], state.broker = broker, broker
    return true
end
local function sampleSummary(args, includeStrings)
    local parts = {}
    for i = 1, math.min(args.n or #args, 8) do
        local value, label = args[i], typeof(args[i])
        if label == "Instance" then label = value.ClassName .. ":" .. value.Name end
        if includeStrings and type(value) == "string" then label = '"' .. string.sub(value, 1, 22) .. '"' end
        parts[#parts + 1] = label
    end
    return table.concat(parts, ", ")
end
local function startRecording()
    if not allowed then note("Open +1 Venom Evolution first."); return end
    if not installRecorder() then
        note("Action capture is unavailable here. Use a Tool, or copy the report.", 8)
        return
    end
    stopAll("Recording for 6 seconds. Perform ONE attack OR training action.")
    local _, _, root = ownCharacter()
    state.recordSource = root and chooseTarget(root.Position) or nil
    state.samples, state.captureQueue, state.captureCount, state.sampleIndex = {}, {}, 0, 1
    state.recording, state.recordUntil = true, os.clock() + 6
    local broker = state.broker
    broker.owner = App
    broker.observer = function(remote, args)
        if not state.running or not state.recording or state.replaying or os.clock() > state.recordUntil then return end
        if state.captureCount >= 48 then return end
        local ok, copied = pcall(snapshot, args, {}, 0, {n = 0})
        if not ok then state.lastError = tostring(copied); return end
        local source = state.recordSource
        if source and live(source.root) then
            source = {model = source.model, root = source.root, basis = source.root.CFrame}
        else source = nil end
        state.captureCount = state.captureCount + 1
        state.captureQueue[state.captureCount] = {remote = remote, args = copied, source = source}
    end
end
local function collectSamples()
    if not state.recording then return end
    for index, item in pairs(state.captureQueue) do
        if typeof(item.remote) == "Instance" and item.remote:IsA("RemoteEvent") then
            local signature = path(item.remote) .. " | " .. sampleSummary(item.args, true)
            local duplicate
            for _, sample in ipairs(state.samples) do
                if sample.signature == signature then sample.count = sample.count + 1; duplicate = true; break end
            end
            if not duplicate and #state.samples < 16 then
                item.signature, item.count = signature, 1
                state.samples[#state.samples + 1] = item
            end
        end
        state.captureQueue[index] = nil
    end
    if os.clock() >= state.recordUntil then
        state.recording = false
        note("Captured " .. #state.samples .. " distinct samples. Review one before binding.", 9)
    end
end

local TOKEN = {}
local function makeTemplate(value, source, seen, depth, budget)
    local kind = typeof(value)
    if source and kind == "Instance" and (value == source.model or value:IsDescendantOf(source.model)) then
        local segments, cursor = {}, value
        while cursor ~= source.model do
            table.insert(segments, 1, cursor.Name)
            cursor = cursor.Parent
            if not cursor then error("Recorded target was removed. Record again.") end
        end
        return {[TOKEN] = "instance", segments = segments}, 1
    end
    if source and source.basis and (kind == "Vector3" or kind == "CFrame") then
        local position = kind == "CFrame" and value.Position or value
        if (position - source.basis.Position).Magnitude <= 10 then
            if kind == "CFrame" then
                return {[TOKEN] = "cframe", offset = source.basis:ToObjectSpace(value)}, 1
            end
            return {[TOKEN] = "vector", offset = value - source.basis.Position}, 1
        end
    end
    if type(value) ~= "table" then return value, 0 end
    if depth > 6 or seen[value] then error("Cyclic/deep action arguments are unsupported.") end
    seen[value] = true
    local out, mapped = {}, 0
    for key, child in pairs(value) do
        budget.n = budget.n + 1
        if budget.n > 256 then error("Action arguments exceed the mapping limit.") end
        local mappedKey, kc = makeTemplate(key, source, seen, depth + 1, budget)
        local mappedChild, vc = makeTemplate(child, source, seen, depth + 1, budget)
        out[mappedKey], mapped = mappedChild, mapped + kc + vc
    end
    seen[value] = nil
    return out, mapped
end
local function resolveTemplate(template, target)
    if type(template) ~= "table" then
        if typeof(template) == "Instance" and not live(template) then error("An action reference expired. Record again.") end
        return template
    end
    local token = template[TOKEN]
    if token then
        if not target or not live(target.model) or not live(target.root) then error("The action needs a live target.") end
        if token == "vector" then return target.root.Position + template.offset end
        if token == "cframe" then return target.root.CFrame * template.offset end
        local instance = target.model
        for _, segment in ipairs(template.segments) do
            instance = instance:FindFirstChild(segment)
            if not instance then error("Target structure differs; action mapping stopped.") end
        end
        return instance
    end
    local out = {}
    for key, value in pairs(template) do out[resolveTemplate(key, target)] = resolveTemplate(value, target) end
    return out
end
local function bindSelected(kind)
    if state.recording then note("Wait until recording finishes before binding."); return end
    local sample = state.samples[state.sampleIndex]
    if not sample or not live(sample.remote) then note("Record an action, then select a sample."); return end
    local source = kind == "attack" and sample.source or nil
    local ok, template, mapped = pcall(makeTemplate, sample.args, source, {}, 0, {n = 0})
    if not ok then note(template, 8); return end
    state[kind .. "Binding"] = {remote = sample.remote, template = template, mapped = mapped}
    note("Bound " .. kind .. ": " .. sample.remote.Name .. ". Mapped target fields: " .. mapped .. ".", 8)
end
local function availableTools()
    local tools = {}
    for _, container in ipairs({player.Character or playerGui, player:FindFirstChildOfClass("Backpack") or playerGui}) do
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then tools[#tools + 1] = child end
        end
    end
    table.sort(tools, function(a, b) return a.Name < b.Name end)
    return tools
end
local function selectedTool(kind)
    local selected = state[kind .. "Tool"]
    local backpack = player:FindFirstChildOfClass("Backpack")
    if selected and live(selected) and (selected.Parent == player.Character or selected.Parent == backpack) then return selected end
    if kind == "attack" and player.Character then return player.Character:FindFirstChildOfClass("Tool") end
end
local function canAct(kind)
    local binding = state[kind .. "Binding"]
    return (binding and live(binding.remote)) or selectedTool(kind) ~= nil
end
local function perform(kind, target)
    local binding = state[kind .. "Binding"]
    if binding then
        if not live(binding.remote) then error("Bound remote expired. Record the action again.") end
        local args = resolveTemplate(binding.template, target)
        state.replaying = true
        local ok, reason = pcall(function() binding.remote:FireServer(unpackArgs(args, 1, args.n or #args)) end)
        state.replaying = false
        if not ok then error(reason) end
        return
    end
    local tool = selectedTool(kind)
    if not tool then error("No " .. kind .. " action. Select a Tool or record and bind an action.") end
    local character, humanoid = ownCharacter()
    if not character then return end
    if tool.Parent ~= character then humanoid:EquipTool(tool) end
    if not tool.Enabled then return end
    if tool.RequiresHandle and not tool:FindFirstChild("Handle") then error("Selected Tool has no required Handle.") end
    tool:Activate()
    -- Deactivation is paired with activation; nothing remains held on unload.
    tool:Deactivate()
end

-- Movement never edits enemy health, deletes shields, or ignores server
-- corrections. The intended landing point must have a walkable floor.
local function landing(position, character, target)
    local parameters = RaycastParams.new()
    parameters.FilterType = Enum.RaycastFilterType.Exclude
    local excluded = {character}
    if target and live(target.model) then excluded[#excluded + 1] = target.model end
    parameters.FilterDescendantsInstances = excluded
    parameters.RespectCanCollide = true
    parameters.IgnoreWater = false
    local result = Workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -45, 0), parameters)
    if not result or result.Normal.Y < 0.6 or result.Material == Enum.Material.Water then return end
    local _, humanoid, root = ownCharacter()
    local height = humanoid and root and math.max(2.5, humanoid.HipHeight + root.Size.Y / 2) or 3
    local point = result.Position + Vector3.new(0, height + 0.15, 0)
    if Workspace:Raycast(point, Vector3.new(0, 3, 0), parameters) then return end
    return point, parameters
end
local function teleportNear(position, face, target, requireClearPath)
    local character, _, root = ownCharacter()
    if not character then return false end
    local point, parameters = landing(position, character, target)
    if not point then return false end
    if requireClearPath then
        local hit = Workspace:Raycast(root.Position, point - root.Position, parameters)
        if hit then return false end
    end
    local look = face and Vector3.new(face.X, point.Y, face.Z) or point + root.CFrame.LookVector
    if (look - point).Magnitude < 0.01 then look = point + Vector3.new(0, 0, -1) end
    -- Set the root CFrame rather than assuming the model pivot equals its root.
    root.CFrame = CFrame.lookAt(point, look)
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    state.lastMove = os.clock()
    state.movementProbe = {position = point, time = os.clock() + 0.65}
    return true
end
local function moveToTarget(entry)
    local _, _, root = ownCharacter()
    if not root or os.clock() - state.lastMove < 0.65 then return false end
    if (entry.root.Position - root.Position).Magnitude <= state.distance + 2 then return true end
    local behind = entry.root.Position - entry.root.CFrame.LookVector * state.distance
    if teleportNear(behind, entry.root.Position, entry, false) then return true end
    for _, side in ipairs({-1, 1}) do
        if teleportNear(entry.root.Position + entry.root.CFrame.RightVector * state.distance * side,
            entry.root.Position, entry, false) then return true end
    end
    return false
end
local function projectileThreat(root, now)
    local best, bestTime, bestVelocity
    local checked = 0
    for part, history in pairs(state.projectiles) do
        if not live(part) then state.projectiles[part] = nil
        elseif (player.Character and part:IsDescendantOf(player.Character)) or attr(part, "OwnerUserId") == player.UserId then
            -- Ignore recognized projectiles that belong to the local player.
        else
            checked = checked + 1
            if checked <= 512 then
                local position = part.Position
                local relative = position - root.Position
                local dt = now - history.time
                local velocity = part.AssemblyLinearVelocity
                if velocity.Magnitude < 0.5 and dt > 0.005 and dt < 1 then
                    velocity = (position - history.position) / dt
                end
                history.position, history.time = position, now
                velocity = velocity - root.AssemblyLinearVelocity
                local speedSquared = velocity:Dot(velocity)
                if relative.Magnitude < 90 and speedSquared > 4 and relative:Dot(velocity) < 0 then
                    local time = clamp(-relative:Dot(velocity) / speedSquared, 0, 0.65)
                    local miss = (relative + velocity * time).Magnitude
                    local radius = 3 + math.min(part.Size.Magnitude / 2, 5)
                    if miss < radius and (not bestTime or time < bestTime) then
                        best, bestTime, bestVelocity = part, time, velocity
                    end
                end
            end
        end
    end
    return best, bestVelocity
end
local function dodgeTick(now, root)
    if not state.dodge or now - state.lastDodge < 0.45 then return false end
    local threat, velocity = projectileThreat(root, now)
    if not threat then return false end
    local direction = Vector3.new(-velocity.Z, 0, velocity.X)
    if direction.Magnitude < 0.01 then direction = root.CFrame.RightVector end
    direction = direction.Unit
    for _, side in ipairs({1, -1}) do
        local candidate = root.Position + direction * 9 * side
        if teleportNear(candidate, state.target and state.target.root.Position, state.target, true) then
            state.lastDodge, state.evadeUntil = now, now + 0.5
            note("Evade move for a detected projectile.", 1)
            return true
        end
    end
    return false
end
local function promptList()
    local list = {}
    for prompt in pairs(state.prompts) do
        if live(prompt) then list[#list + 1] = prompt else state.prompts[prompt] = nil end
    end
    table.sort(list, function(a, b) return path(a) < path(b) end)
    return list
end
local function promptPosition(prompt)
    local parent = prompt.Parent
    if parent:IsA("Attachment") then return parent.WorldPosition end
    if parent:IsA("BasePart") then return parent.Position end
    if parent:IsA("Model") then local root = rootOf(parent); return root and root.Position end
end
local function selectedPrompt()
    local list = promptList()
    state.promptIndex = clamp(state.promptIndex, 1, math.max(1, #list))
    return list[state.promptIndex], #list
end
local function travelToPrompt()
    if not allowed then note("Wrong game."); return end
    local prompt = selectedPrompt()
    if not prompt then note("No loaded entrance prompt detected."); return end
    local position = promptPosition(prompt)
    if not position then note("Entrance has no usable position."); return end
    stopAll("Moving to the selected entrance. Use its prompt to enter.")
    local _, _, root = ownCharacter()
    local offset = root and root.Position - position or Vector3.new(0, 0, 1)
    offset = Vector3.new(offset.X, 0, offset.Z)
    if offset.Magnitude < 0.01 then offset = Vector3.new(0, 0, 1) end
    if not teleportNear(position + offset.Unit * math.min(3, math.max(1, prompt.MaxActivationDistance / 2)),
        position, nil, false) then note("No walkable landing point beside this entrance.") end
end
local function holdPrompt()
    if not allowed or state.recording then note("Finish recording first, in the correct game."); return end
    if state.heldPrompt then note("An entrance prompt is already being held."); return end
    local prompt = selectedPrompt()
    local _, _, root = ownCharacter()
    if not prompt or not root or not prompt.Enabled then note("Selected entrance is unavailable."); return end
    local position = promptPosition(prompt)
    if not position or (root.Position - position).Magnitude > prompt.MaxActivationDistance then
        note("Move within the entrance's activation distance first."); return
    end
    state.manualUntil = os.clock() + prompt.HoldDuration + 0.3
    state.heldPrompt = prompt
    local ok, reason = pcall(function() prompt:InputHoldBegin() end)
    if not ok then state.heldPrompt, state.manualUntil = nil, 0; note("Prompt input unavailable: " .. tostring(reason)); return end
    task.delay(prompt.HoldDuration + 0.1, function()
        if state.heldPrompt ~= prompt then return end
        pcall(function() prompt:InputHoldEnd() end)
        state.heldPrompt = nil
        if state.running then note("Prompt input sent. Entry still depends on the game's unlock rules.") end
    end)
end

-- Native, responsive interface. Every page scrolls independently; no external
-- assets are needed for the geometric eye logo.
local C = {
    bg = Color3.fromRGB(15, 16, 19), panel = Color3.fromRGB(25, 27, 32),
    raised = Color3.fromRGB(36, 39, 45), line = Color3.fromRGB(55, 59, 65),
    text = Color3.fromRGB(239, 242, 245), sub = Color3.fromRGB(158, 166, 177),
    green = Color3.fromRGB(178, 255, 79), red = Color3.fromRGB(255, 99, 112),
}
local function new(class, properties, parent)
    local instance = Instance.new(class)
    for name, value in pairs(properties or {}) do instance[name] = value end
    instance.Parent = parent
    return instance
end
local function round(instance, radius) new("UICorner", {CornerRadius = UDim.new(0, radius or 12)}, instance) end
local function stroke(instance, color) return new("UIStroke", {Color = color or C.line, Thickness = 1}, instance) end
local function label(parent, text, position, size, fontSize, color)
    return new("TextLabel", {BackgroundTransparency = 1, Text = text,
        Position = position, Size = size, Font = Enum.Font.Gotham,
        TextSize = fontSize or 13, TextColor3 = color or C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
        TextWrapped = true, RichText = false}, parent)
end
local function button(parent, text, position, size, callback, accent)
    local item = new("TextButton", {Text = text, Position = position, Size = size,
        BackgroundColor3 = accent and C.green or C.raised, BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextWrapped = true,
        TextColor3 = accent and C.bg or C.text, AutoButtonColor = true}, parent)
    round(item, 9)
    connect(item.Activated, function()
        if not state.running then return end
        local ok, reason = pcall(callback)
        if not ok then state.lastError = tostring(reason); note("Action stopped: " .. tostring(reason), 8) end
        if UI.refresh then UI.refresh() end
    end)
    return item
end
local function logo(parent, position, size)
    local icon = new("Frame", {BackgroundColor3 = C.raised, BorderSizePixel = 0,
        Position = position, Size = size, ClipsDescendants = true}, parent)
    round(icon, 10)
    local left = new("Frame", {BorderSizePixel = 0, BackgroundColor3 = C.green,
        Size = UDim2.fromScale(0.32, 0.18), Position = UDim2.fromScale(0.15, 0.37), Rotation = 22}, icon)
    local right = new("Frame", {BorderSizePixel = 0, BackgroundColor3 = C.green,
        Size = UDim2.fromScale(0.32, 0.18), Position = UDim2.fromScale(0.53, 0.37), Rotation = -22}, icon)
    round(left, 3); round(right, 3)
    return icon
end
UI.gui = new("ScreenGui", {Name = "NOVA_Venom", ResetOnSpawn = false, DisplayOrder = 900,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = false}, playerGui)
local surface = new("Frame", {Name = "Surface", BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1)}, UI.gui)
UI.window = new("Frame", {Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 560),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true}, surface)
round(UI.window, 18); stroke(UI.window)
local header = new("Frame", {Name = "DragHeader", BackgroundTransparency = 1,
    Size = UDim2.new(1, -98, 0, 76), Active = true}, UI.window)
logo(header, UDim2.fromOffset(16, 16), UDim2.fromOffset(44, 44))
local title = label(header, "NOVA", UDim2.fromOffset(72, 13), UDim2.new(1, -72, 0, 27), 21)
title.Font = Enum.Font.GothamBold
label(header, "+1 VENOM EVOLUTION", UDim2.fromOffset(72, 39), UDim2.new(1, -72, 0, 21), 10, C.sub)
button(UI.window, "Hide", UDim2.new(1, -92, 0, 23), UDim2.fromOffset(76, 30), function() UI.window.Visible = false end)
local badge = button(surface, "", UDim2.new(0, 12, 1, -64), UDim2.fromOffset(48, 48), function()
    UI.window.Visible = not UI.window.Visible
end)
logo(badge, UDim2.fromOffset(4, 4), UDim2.fromOffset(40, 40)).Active = false
local panic = button(surface, "STOP", UDim2.new(1, -84, 1, -58), UDim2.fromOffset(72, 40), function() stopAll() end)
panic.TextColor3 = C.red

local stats = new("Frame", {BackgroundColor3 = C.panel, BorderSizePixel = 0,
    Position = UDim2.fromOffset(14, 76), Size = UDim2.new(1, -28, 0, 56)}, UI.window)
round(stats, 12)
UI.stats = label(stats, "NPCs 0    |    HP --    |    Defeats 0", UDim2.fromOffset(12, 4), UDim2.new(1, -24, 0, 23), 12)
UI.target = label(stats, "Target: none", UDim2.fromOffset(12, 28), UDim2.new(1, -24, 0, 21), 11, C.sub)
local tabs = new("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 142),
    Size = UDim2.new(1, -28, 0, 34)}, UI.window)
local content = new("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 186),
    Size = UDim2.new(1, -28, 1, -237), ClipsDescendants = true}, UI.window)
UI.status = label(UI.window, state.status, UDim2.new(0, 18, 1, -43), UDim2.new(1, -36, 0, 35), 11, C.green)

local function page(name, index)
    local frame = new("ScrollingFrame", {Name = name, BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
        ScrollBarImageColor3 = C.line, ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = name == "Farm"}, content)
    new("UIListLayout", {Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder}, frame)
    new("UIPadding", {PaddingRight = UDim.new(0, 7), PaddingBottom = UDim.new(0, 9)}, frame)
    UI.pages[name] = frame
    UI.tabs[name] = button(tabs, name, UDim2.new((index - 1) / 5, 0, 0, 0),
        UDim2.new(1 / 5, -5, 1, 0), function()
            UI.activeTab = name
            for key, item in pairs(UI.pages) do item.Visible = key == name end
        end)
    return frame
end
local pages = {}
for index, name in ipairs({"Farm", "Train", "Travel", "Bind", "Info"}) do pages[name] = page(name, index) end
local cardOrder = 0
local function card(parent, height)
    cardOrder = cardOrder + 1
    local item = new("Frame", {BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height), LayoutOrder = cardOrder}, parent)
    round(item, 12)
    return item
end
local function paragraph(parent, text, height, color)
    local item = card(parent, height)
    label(item, text, UDim2.fromOffset(13, 8), UDim2.new(1, -26, 1, -16), 12, color or C.sub)
    return item
end
local function toggle(parent, name, description, key, guard)
    local item = card(parent, 84)
    label(item, name, UDim2.fromOffset(13, 8), UDim2.new(1, -108, 0, 24), 14)
    label(item, description, UDim2.fromOffset(13, 33), UDim2.new(1, -108, 0, 43), 11, C.sub)
    local control = button(item, "OFF", UDim2.new(1, -86, 0.5, -17), UDim2.fromOffset(72, 34), function()
        if not allowed then note("Wrong game: automation is disabled."); return end
        if state.recording then note("Recording pauses automation. Wait until it finishes."); return end
        if not state[key] and guard and not guard() then return end
        state[key] = not state[key]
        if key == "farm" then clearTarget() end
        if key == "retreat" and not state[key] then state.healing = false end
        note(name .. (state[key] and " enabled." or " disabled."))
    end)
    UI.refreshers[#UI.refreshers + 1] = function()
        control.Text = state[key] and "ON" or "OFF"
        control.BackgroundColor3 = state[key] and C.green or C.raised
        control.TextColor3 = state[key] and C.bg or C.sub
    end
end
local function actionCard(parent, name, description, text, callback)
    local item = card(parent, 116)
    label(item, name, UDim2.fromOffset(13, 6), UDim2.new(1, -26, 0, 25), 14)
    label(item, description, UDim2.fromOffset(13, 31), UDim2.new(1, -26, 0, 37), 11, C.sub)
    return button(item, text, UDim2.fromOffset(13, 74), UDim2.new(1, -26, 0, 31), callback)
end
local function cycleCard(parent, name, choices, key)
    local item = card(parent, 70)
    label(item, name, UDim2.fromOffset(13, 4), UDim2.new(1, -26, 0, 24), 12, C.sub)
    local control = button(item, "", UDim2.fromOffset(13, 31), UDim2.new(1, -26, 0, 29), function()
        local current = 0
        for index, choice in ipairs(choices) do if choice == state[key] then current = index end end
        state[key] = choices[current % #choices + 1]
        if key == "filter" or key == "order" then clearTarget() end
    end)
    UI.refreshers[#UI.refreshers + 1] = function() control.Text = tostring(state[key]) .. "   >" end
    return control
end
local function attackGuard()
    if not canAct("attack") then note("Equip a combat Tool, or record and bind an attack in Bind.", 8); return false end
    return true
end
paragraph(pages.Farm, "EXPERIMENTAL CLIENT ADAPTER\nLoaded NPCs only. Actual damage and progression remain controlled by the game.", 72)
toggle(pages.Farm, "Teleport farm", "Chooses a living NPC, lands nearby, and uses your attack action.", "farm", attackGuard)
toggle(pages.Farm, "Auto attack", "Uses your bound attack or equipped combat Tool at normal damage.", "attack", attackGuard)
toggle(pages.Farm, "Projectile dodge", "Attempts sideways moves away from recognized moving projectiles. No AoE guarantee.", "dodge")
toggle(pages.Farm, "Low HP retreat", "Returns to your saved safe spot below 30% HP; resumes at 80%.", "retreat", function()
    if not state.safeSpot then note("Save a safe spot in Travel first."); return false end
    return true
end)
cycleCard(pages.Farm, "Target type", {"All", "Bosses", "Enemies"}, "filter")
cycleCard(pages.Farm, "Target priority", {"Nearest", "Boss first", "Lowest HP"}, "order")
cycleCard(pages.Farm, "Attack interval (seconds)", {0.5, 0.25, 0.125}, "attackInterval")
cycleCard(pages.Farm, "Distance from target (studs)", {4, 5, 7, 10}, "distance")
local filterCard = card(pages.Farm, 87)
label(filterCard, "World / stage / NPC path filter", UDim2.fromOffset(13, 5), UDim2.new(1, -26, 0, 23), 12, C.sub)
local filterBox = new("TextBox", {BackgroundColor3 = C.raised, BorderSizePixel = 0,
    Position = UDim2.fromOffset(13, 35), Size = UDim2.new(1, -26, 0, 36),
    PlaceholderText = "Blank = all loaded areas", Text = "", ClearTextOnFocus = false,
    TextColor3 = C.text, PlaceholderColor3 = C.sub, TextSize = 12,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left}, filterCard)
round(filterBox, 8)
connect(filterBox.FocusLost, function()
    state.textFilter = string.lower(string.sub(filterBox.Text, 1, 100)); clearTarget()
end)

paragraph(pages.Train, "Select a training Tool, or record ONE manual training action in Bind. Training pauses during combat and retreat.", 70)
toggle(pages.Train, "Auto train", "Repeats only the training action you explicitly select or bind.", "train", function()
    if not canAct("train") then note("Select a training Tool below, or bind training in Bind."); return false end
    return true
end)
toggle(pages.Train, "Fast repeat", "Requests up to 10 training actions per second. Server limits still apply.", "fastTrain")
cycleCard(pages.Train, "Normal training interval (seconds)", {1, 0.4, 0.2}, "trainInterval")
local function toolCard(parent, kind)
    local control = actionCard(parent, kind == "attack" and "Combat Tool" or "Training Tool",
        "Cycles through your current Tools. A bound remote takes priority over a Tool.", "Select Tool", function()
            local tools = availableTools()
            if #tools == 0 then state[kind .. "Tool"] = nil; note("No Tools found. Try action recording in Bind."); return end
            local index = 0
            for i, tool in ipairs(tools) do if tool == state[kind .. "Tool"] then index = i end end
            state[kind .. "Tool"] = tools[index % #tools + 1]
        end)
    UI.refreshers[#UI.refreshers + 1] = function()
        local tool = selectedTool(kind)
        control.Text = tool and (tool.Name .. "   >") or "No Tool selected   >"
    end
end
toolCard(pages.Train, "train")
toggle(pages.Train, "Anti AFK attempt", "Uses idle input if your environment permits it; turns off if input fails.", "antiAfk")

paragraph(pages.Travel, "Entrances are discovered from loaded ProximityPrompts. Locked areas stay locked. After a place/server change, run the file again.", 78)
local travelSelect = actionCard(pages.Travel, "World / stage / portal entrance", "Select an entrance from the current scene.", "No entrances", function()
    local _, count = selectedPrompt()
    state.promptIndex = state.promptIndex % math.max(1, count) + 1
end)
UI.refreshers[#UI.refreshers + 1] = function()
    local prompt, count = selectedPrompt()
    travelSelect.Text = prompt and (state.promptIndex .. "/" .. count .. "  " .. string.sub(path(prompt), -65)) or "No loaded entrance prompts"
end
actionCard(pages.Travel, "Move to entrance", "Stops automation and attempts a walkable landing beside the selected entrance.", "Move to selected entrance", travelToPrompt)
actionCard(pages.Travel, "Use entrance prompt", "Requires proximity and a usable prompt. The game still checks unlocks.", "Hold selected prompt", holdPrompt)
actionCard(pages.Travel, "Safe spot", "Save a safe, walkable location for low HP retreat and manual return.", "Save current safe spot", function()
    local _, _, root = ownCharacter()
    if root then state.safeSpot = root.CFrame; note("Safe spot saved for this session.") end
end)
actionCard(pages.Travel, "Return to safe spot", "Stops automation before moving. Save a safe spot first.", "Return", function()
    if not allowed then note("Wrong game."); return end
    if not state.safeSpot then note("Save a safe spot first."); return end
    stopAll("Returning to safe spot.")
    if not teleportNear(state.safeSpot.Position, state.safeSpot.Position + state.safeSpot.LookVector, nil, false) then
        note("The safe spot no longer has a walkable landing.")
    end
end)

paragraph(pages.Bind, "1  Stop moving and stand by your target.\n2  Record, then do ONE attack OR training action.\n3  Review the actual remote + arguments. Bind only the matching sample. Other background events can also appear.", 110)
local recordButton = actionCard(pages.Bind, "Record outgoing action", "Capture lasts 6 seconds and pauses all automation. Some environments do not support recording.", "Record 6 seconds", startRecording)
local sampleCard = card(pages.Bind, 147)
UI.sample = label(sampleCard, "No recorded sample.", UDim2.fromOffset(13, 8), UDim2.new(1, -26, 0, 91), 11, C.sub)
button(sampleCard, "Previous", UDim2.fromOffset(13, 106), UDim2.new(0.5, -19, 0, 29), function()
    state.sampleIndex = (state.sampleIndex - 2) % math.max(1, #state.samples) + 1
end)
button(sampleCard, "Next", UDim2.new(0.5, 6, 0, 106), UDim2.new(0.5, -19, 0, 29), function()
    state.sampleIndex = state.sampleIndex % math.max(1, #state.samples) + 1
end)
actionCard(pages.Bind, "Use as attack", "Remaps target instances and nearby target positions. Opaque target IDs stay unchanged and may need a tailored adapter.", "Bind selected sample as ATTACK", function() bindSelected("attack") end)
actionCard(pages.Bind, "Use as training", "Repeats the recorded arguments unchanged. Avoid purchase, reward, upgrade, or unrelated samples.", "Bind selected sample as TRAIN", function() bindSelected("train") end)
toolCard(pages.Bind, "attack")
actionCard(pages.Bind, "Clear bindings", "Deletes the attack and training bindings from memory and stops automation.", "Clear both bindings", function()
    stopAll(); state.attackBinding, state.trainBinding = nil, nil; note("Bindings cleared.")
end)
UI.refreshers[#UI.refreshers + 1] = function()
    recordButton.Text = state.recording and ("RECORDING  " .. math.max(0, math.ceil(state.recordUntil - os.clock())) .. "s") or "Record 6 seconds"
    local sample = state.samples[state.sampleIndex]
    UI.sample.Text = sample and ("Sample " .. state.sampleIndex .. "/" .. #state.samples .. "  |  Seen " .. sample.count .. "x\n"
        .. path(sample.remote) .. "\n(" .. sampleSummary(sample.args, true) .. ")\nSource NPC: "
        .. (sample.source and sample.source.model.Name or "none")) or "No samples. Perform the action during recording. Direct calls and InvokeServer are not captured."
end

local function diagnostics()
    local npcCount, bulletCount, npcLines, remoteLines = 0, 0, {}, {}
    for model, entry in pairs(state.npcs) do
        if live(model) then
            npcCount = npcCount + 1
            if #npcLines < 20 then npcLines[#npcLines + 1] = path(model) .. " | HP=" .. tostring(healthOf(model)) end
        end
    end
    for part in pairs(state.projectiles) do if live(part) then bulletCount = bulletCount + 1 end end
    for _, sample in ipairs(state.samples) do
        remoteLines[#remoteLines + 1] = path(sample.remote) .. " (" .. sampleSummary(sample.args, false) .. ")"
    end
    local _, promptCount = selectedPrompt()
    local lines = {"NOVA VENOM REPORT / " .. VERSION, "PlaceId=" .. tostring(game.PlaceId),
        "GameId=" .. tostring(game.GameId), "Recorder=" .. tostring(type(Hook) == "function" and type(Namecall) == "function"),
        "NPC candidates=" .. npcCount, "Projectile parts=" .. bulletCount, "Entrance prompts=" .. promptCount,
        "Attack bound=" .. tostring(state.attackBinding ~= nil), "Training bound=" .. tostring(state.trainBinding ~= nil),
        "Last local error=" .. state.lastError, "NPC paths:", table.concat(npcLines, "\n"),
        "Recorded action types (no argument values):", table.concat(remoteLines, "\n"),
        "Recent status:", table.concat(state.log, "\n"),
        "Limits: generic client adapter; no guaranteed kill/shield bypass/one-hit/cross-place support."}
    return table.concat(lines, "\n")
end
local function showReport()
    if UI.report then UI.report:Destroy() end
    local overlay = new("Frame", {Name = "Report", BackgroundColor3 = C.bg, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = 20}, UI.window)
    UI.report = overlay
    local caption = label(overlay, "SESSION REPORT", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 30), 16)
    caption.ZIndex = 21
    local close = button(overlay, "Close report", UDim2.new(0, 16, 1, -50), UDim2.new(1, -32, 0, 34), function()
        overlay:Destroy(); UI.report = nil
    end)
    close.ZIndex = 21
    local reportScroll = new("ScrollingFrame", {Position = UDim2.fromOffset(16, 55),
        Size = UDim2.new(1, -32, 1, -117), BackgroundColor3 = C.panel, BorderSizePixel = 0,
        ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 21}, overlay)
    round(reportScroll, 8)
    local text = new("TextBox", {Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -24, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = diagnostics(),
        TextSize = 11, TextColor3 = C.text, Font = Enum.Font.Code, TextWrapped = true,
        MultiLine = true, ClearTextOnFocus = false, TextEditable = false,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 22}, reportScroll)
    local clipboard = setclipboard or toclipboard or Env.setclipboard or Env.toclipboard
    local ok = type(clipboard) == "function" and pcall(clipboard, text.Text)
    note(ok and "Report copied. No data was uploaded." or "Report opened. Select and copy its text if supported.", 7)
end
paragraph(pages.Info, "BUILD  " .. VERSION .. "\nThis file has no live Roblox validation. The controls describe attempted client behavior, not guaranteed game outcomes.", 80)
paragraph(pages.Info, "ONE-HIT / SHIELD BYPASS / GOD MODE\nNot implemented. A local health or shield edit would not establish a real server-side kill. Normal attacks continue if a shield is detected.", 98)
paragraph(pages.Info, "PROJECTILE DETECTION\nUses named, moving projectile parts and predicted closest approach. Hidden hitboxes, instant attacks, AoE and custom damage systems need a game-specific adapter.", 98)
actionCard(pages.Info, "Diagnostics", "Copies game object paths, counts, capabilities and argument types. No account credentials or outgoing uploads.", "Copy / open session report", showReport)
actionCard(pages.Info, "Emergency stop", "F6 or the floating red STOP button also pauses every automated action.", "STOP ALL", function() stopAll() end)
actionCard(pages.Info, "Unload NOVA", "Removes the interface and disconnects events. A reusable recorder hook remains dormant and forwards calls unchanged.", "Unload", App.Close)

function UI.refresh()
    if not state.running then return end
    for _, fn in ipairs(UI.refreshers) do fn() end
    for name, control in pairs(UI.tabs) do
        control.BackgroundColor3 = UI.activeTab == name and C.green or C.raised
        control.TextColor3 = UI.activeTab == name and C.bg or C.sub
    end
    local count = 0
    for _, entry in pairs(state.npcs) do if eligible(entry) then count = count + 1 end end
    local _, humanoid = ownCharacter()
    UI.stats.Text = "NPCs " .. count .. "    |    HP " .. (humanoid and math.ceil(humanoid.Health) or "--")
        .. "    |    Defeats " .. state.observedDefeats
    local target = state.target
    UI.target.Text = target and (target.model.Name .. "  |  HP " .. tostring(healthOf(target.model))
        .. (shielded(target.model) and "  |  Shield detected" or "")) or "Target: none"
    if state.statusUntil < os.clock() then
        state.status = state.healing and "Retreating / waiting for HP recovery."
            or (state.farm and "Farming loaded NPCs with your configured attack.")
            or (state.train and "Repeating your configured training action.")
            or (state.attack and "Attacking nearby selected NPCs.") or "Ready. Bind actions before farming."
    end
    UI.status.Text = state.status
end

local drag, dragInput, dragStart, dragCenter
local function fitWindow()
    local viewport = surface.AbsoluteSize
    if viewport.X < 10 or viewport.Y < 10 then
        viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
    end
    local width, height = math.min(600, math.max(260, viewport.X - 20)), math.min(600, math.max(290, viewport.Y - 26))
    UI.window.Size = UDim2.fromOffset(width, height)
    local center = UI.window.AbsolutePosition + UI.window.AbsoluteSize / 2 - surface.AbsolutePosition
    center = Vector2.new(clamp(center.X, width / 2 + 5, math.max(width / 2 + 5, viewport.X - width / 2 - 5)),
        clamp(center.Y, height / 2 + 5, math.max(height / 2 + 5, viewport.Y - height / 2 - 5)))
    UI.window.Position = UDim2.fromOffset(center.X, center.Y)
end
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        drag, dragInput, dragStart = true, input, input.Position
        dragCenter = UI.window.AbsolutePosition + UI.window.AbsoluteSize / 2 - surface.AbsolutePosition
    end
end)
connect(Input.InputChanged, function(input)
    if drag and (input == dragInput or (dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local delta = input.Position - dragStart
        UI.window.Position = UDim2.fromOffset(dragCenter.X + delta.X, dragCenter.Y + delta.Y)
        fitWindow()
    end
end)
connect(Input.InputEnded, function(input)
    if input == dragInput then drag, dragInput = false, nil end
end)
connect(Input.InputBegan, function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then UI.window.Visible = not UI.window.Visible end
    if input.KeyCode == Enum.KeyCode.F6 then stopAll(); UI.refresh() end
end)
connect(surface:GetPropertyChangedSignal("AbsoluteSize"), fitWindow)
task.defer(function() if state.running then fitWindow() end end)

-- World subscriptions, respawn handling and one bounded heartbeat controller.
state.highlight = new("Highlight", {Name = "NOVA_Target", FillTransparency = 0.92,
    FillColor = C.green, OutlineColor = C.green, OutlineTransparency = 0.15,
    DepthMode = Enum.HighlightDepthMode.Occluded}, Workspace)
connect(Workspace.DescendantAdded, classifyInstance)
connect(Workspace.DescendantRemoving, function(instance)
    state.npcs[instance], state.prompts[instance], state.projectiles[instance] = nil, nil, nil
    state.ignored[instance] = nil
    if state.target and instance == state.target.model then clearTarget() end
end)
connect(player.CharacterAdded, function()
    clearTarget(); state.healing, state.movementProbe, state.correctionCount = false, nil, 0
    state.attackTool, state.trainTool, state.safeSpot = nil, nil, nil
    -- Character-specific recorded arguments expire on respawn. Clear both so
    -- old character references are never replayed by accident.
    state.attackBinding, state.trainBinding, state.farm, state.attack, state.train = nil, nil, false, false, false
    note("Respawn detected. Rebind actions and save a new safe spot.", 8)
end)
connect(player.Idled, function()
    if not state.running or not state.antiAfk or not allowed then return end
    local ok, reason = pcall(function()
        local virtualUser = game:GetService("VirtualUser")
        virtualUser:CaptureController()
        virtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
        virtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    end)
    if not ok then state.antiAfk = false; note("Anti AFK input unavailable: " .. tostring(reason), 7) end
end)

local function automationTick()
    local now = os.clock()
    collectSamples()
    for _ = 1, 30 do
        if state.queueHead > state.queueTail then break end
        local model = state.queue[state.queueHead]
        state.queue[state.queueHead], state.queued[model] = nil, nil
        state.queueHead = state.queueHead + 1
        discoverModel(model)
    end
    if state.queueHead > state.queueTail then state.queueHead, state.queueTail, state.queue = 1, 0, {} end
    if not allowed or state.recording or now < state.manualUntil then return end
    local character, humanoid, root = ownCharacter()
    if not character then clearTarget(); return end
    if state.movementProbe and now >= state.movementProbe.time then
        if (root.Position - state.movementProbe.position).Magnitude > 18
            and humanoid.MoveDirection.Magnitude < 0.1 and root.AssemblyLinearVelocity.Magnitude < 25 then
            state.correctionCount = state.correctionCount + 1
        else state.correctionCount = 0 end
        state.movementProbe = nil
        if state.correctionCount >= 3 then
            stopAll("Movement repeatedly failed or was corrected. Automation stopped."); return
        end
    end
    if state.retreat and state.safeSpot and humanoid.MaxHealth > 0 then
        if humanoid.Health / humanoid.MaxHealth < 0.3 then state.healing = true end
        if state.healing and humanoid.Health / humanoid.MaxHealth >= 0.8 then
            state.healing = false; state.retreatMessage = false; note("HP recovered. Resuming.")
        end
        if state.healing then
            clearTarget()
            if now - state.lastMove > 1.2 and (root.Position - state.safeSpot.Position).Magnitude > 5 then
                local moved = teleportNear(state.safeSpot.Position, nil, nil, false)
                if not moved and not state.retreatMessage then
                    note("Safe spot landing failed. Combat remains paused; move to safety manually.", 8)
                    state.retreatMessage = true
                end
            end
            return
        end
    end
    if dodgeTick(now, root) or now < state.evadeUntil then return end
    if state.farm or state.attack then
        local target = state.target
        if target then
            local hp = healthOf(target.model)
            if finite(hp) and hp <= 0 and (state.targetHealth or 0) > 0 then
                state.observedDefeats = state.observedDefeats + 1
            end
            if finite(hp) and state.targetHealth and hp < state.targetHealth then state.targetProgress = now end
            state.targetHealth = hp
            if not eligible(target, root.Position)
                or (not state.farm and (target.root.Position - root.Position).Magnitude > math.max(14, state.distance + 3)) then
                clearTarget(); target = nil
            end
        end
        if not target then
            local maxDistance = not state.farm and math.max(14, state.distance + 3) or nil
            target = chooseTarget(root.Position, maxDistance)
            state.target, state.targetHealth, state.targetProgress = target, target and target.health, now
            state.highlight.Adornee = target and target.model or nil
        end
        if target then
            local distance = (target.root.Position - root.Position).Magnitude
            if state.farm and distance > state.distance + 2 then
                if not moveToTarget(target) and now - state.targetProgress > 10 then
                    state.ignored[target.model] = now + 30; clearTarget(); note("Target landing failed; trying another NPC.")
                end
                return
            end
            if distance <= math.max(14, state.distance + 3) and now - state.lastAttack >= state.attackInterval then
                if not canAct("attack") then state.farm, state.attack = false, false; note("Attack action unavailable. Rebind or equip a Tool."); return end
                state.lastAttack = now
                local ok, reason = pcall(perform, "attack", target)
                if not ok then
                    state.farm, state.attack = false, false; state.lastError = tostring(reason); clearTarget()
                    note("Attack stopped: " .. tostring(reason), 8); return
                end
            end
            if now - state.targetProgress > 25 then
                state.ignored[target.model] = now + 30
                clearTarget(); note("No observed damage for 25s. Skipping this NPC for 30s.", 6)
            end
            -- Training never steals the selected combat Tool mid-fight.
            return
        end
    else clearTarget() end
    if state.train and now - state.lastTrain >= (state.fastTrain and 0.1 or state.trainInterval) then
        state.lastTrain = now
        local ok, reason = pcall(perform, "train", nil)
        if not ok then state.train = false; state.lastError = tostring(reason); note("Training stopped: " .. tostring(reason), 8) end
    end
end
local accumulated, uiAccumulated = 0, 0
connect(RunService.Heartbeat, function(dt)
    if not state.running then return end
    accumulated, uiAccumulated = accumulated + dt, uiAccumulated + dt
    if accumulated >= 0.07 then
        accumulated = 0
        local ok, reason = pcall(automationTick)
        if not ok then state.lastError = tostring(reason); stopAll("Controller stopped: " .. tostring(reason)) end
    end
    if uiAccumulated >= 0.35 then
        uiAccumulated = 0
        local ok, reason = pcall(UI.refresh)
        if not ok then state.lastError = tostring(reason) end
    end
end)
task.spawn(function()
    local descendants = Workspace:GetDescendants()
    for index, instance in ipairs(descendants) do
        if not state.running then return end
        classifyInstance(instance)
        if index % 300 == 0 then task.wait() end
    end
    note(allowed and "Ready. Equip a Tool, or record and bind your actions in Bind." or "Wrong game: automation is disabled.", 9)
end)
UI.refresh()

