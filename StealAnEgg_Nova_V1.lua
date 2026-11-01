-- STEAL AN EGG | NOVA V1 (original lightweight client UI)
-- Target game: https://www.roblox.com/games/107778070777162
-- No external code, dependencies, webhooks, or hidden remote execution.
-- Actions depend on the game's current remotes and server validation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local global = (type(getgenv) == "function" and getgenv()) or _G
pcall(function()
    if type(global.STEAL_EGG_NOVA_STOP) == "function" then
        global.STEAL_EGG_NOVA_STOP()
    end
end)
local running = true
local cfg = {
    AutoFarm = false,
    AutoPlace = true,
    AutoHatch = true,
    AutoEquip = false,
    AutoTrain = false,
    EggESP = true,
    AntiAFK = true,
    GuardSafety = true,
    ForestOnly = false,
    SortBest = false,
    VisualRange = 900,
}
local statistics = { stolen = 0, placed = 0, hatched = 0, failed = 0 }
local state = { mode = "Ready", working = false, paused = false, plot = nil, pen = nil,
    origin = nil, treadmill = nil, carrying = false, lastHome = nil, selected = nil }
local links, marks = {}, {}
local callCache, remoteCache = {}, {}
local fullStatus = "Loaded. Enable AUTO STEAL to begin."
local netMap = {
    PlotState = { "RF/Homestead/AskState", "Plots: RequestState" },
    FieldSnapshot = { "RF/EggWorld/AskFieldEggSnapshot", "Eggs: RequestAreaEggSnapshot" },
    FieldCarry = { "RF/EggWorld/AskFieldEggCarry", "Eggs: RequestAreaEggCarry" },
    OwnEggs = { "RF/EggWorld/AskLiveSnapshot", "Eggs: RequestRuntimeSnapshot" },
    PlaceEgg = { "RF/EggWorld/AskPlaceEgg", "Eggs: RequestPlaceEgg" },
    HatchEgg = { "RF/EggWorld/AskHatch", "Eggs: RequestHatchEgg" },
    FinishHatch = { "RF/EggWorld/AskFinishHatch", "Eggs: RequestCompleteHatchEgg" },
    EquipPet = { "RF/PenRoster/AskWear", "ActiveAssets: RequestEquip" },
    OfflineSummary = { "RF/AwayEarnings/FetchSummary", "OfflineAssets: GetSummary" },
    OfflineClaim = { "RF/AwayEarnings/AskCollect", "OfflineAssets: Redeem" },
}
local guardSpeeds = {
    Forest=16, Lake=35, Desert=62, Jungle=82, Snow=98,
    Volcano=113, ["Abyss Ocean"]=130, Prehistoric=152, Cosmic=200,
    ["Cherry Blossom"]=222, ["Titan Temple"]=229.5,
}
local colors = {
    bg = Color3.fromRGB(16, 17, 22), panel = Color3.fromRGB(30, 32, 41),
    stroke = Color3.fromRGB(75, 78, 91), fg = Color3.fromRGB(242, 243, 246),
    dim = Color3.fromRGB(157, 164, 178), accent = Color3.fromRGB(120, 195, 255),
    egg = Color3.fromRGB(255, 209, 102), yes = Color3.fromRGB(65, 111, 91),
    danger = Color3.fromRGB(248, 96, 101),
}

local function status(msg)
    fullStatus = tostring(msg or "Ready")
    state.mode = fullStatus
end
local function bind(signal, fn)
    local conn = signal:Connect(fn)
    links[#links + 1] = conn
    return conn
end
local function inst(kind, props, parent)
    local obj = Instance.new(kind)
    for key, value in pairs(props or {}) do obj[key] = value end
    obj.Parent = parent
    return obj
end
local function character()
    local ch = LocalPlayer.Character
    if not ch or not ch.Parent then return nil end
    local root = ch:FindFirstChild("HumanoidRootPart")
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return nil end
    return ch, root, hum
end
local function resolveRemote(key)
    local cached = remoteCache[key]
    if cached and cached.Parent then return cached end
    local package = ReplicatedStorage:FindFirstChild("Packages")
    local root = (package and package:FindFirstChild("Networking")) or ReplicatedStorage:FindFirstChild("Network")
    if not root then return nil end
    for _, name in ipairs(netMap[key] or {}) do
        local remote = root:FindFirstChild(name) or root:FindFirstChild(name, true)
        if remote and (remote:IsA("RemoteFunction") or remote:IsA("RemoteEvent")) then
            remoteCache[key] = remote
            return remote
        end
    end
    return nil
end
local function request(key, timeout, ...)
    local remote = resolveRemote(key)
    if not remote then return false, "Missing " .. key end
    local args = table.pack(...)
    if remote:IsA("RemoteEvent") then
        local ok, err = pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end)
        return ok, ok and true or err
    end
    local box = { done = false, ok = false, result = nil }
    task.spawn(function()
        local ok, result = pcall(function()
            return remote:InvokeServer(table.unpack(args, 1, args.n))
        end)
        box.ok, box.result, box.done = ok, result, true
    end)
    local started = os.clock()
    while running and not box.done and (os.clock() - started) < (timeout or 6) do
        task.wait(0.08)
    end
    if not box.done then return false, "Timed out: " .. key end
    return box.ok, box.result
end

local function findPlot()
    if state.plot and state.plot.Parent and state.pen and state.pen.Parent then return true end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then status("Workspace.Plots missing") return false end
    local found
    local ok, data = request("PlotState", 5)
    if ok and type(data) == "table" and type(data.OwnersBySlot) == "table" then
        for slot, owner in pairs(data.OwnersBySlot) do
            if tonumber(owner) == LocalPlayer.UserId then
                found = plots:FindFirstChild(tostring(slot))
                break
            end
        end
    end
    if not found then
        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            if sign then
                for _, item in ipairs(sign:GetDescendants()) do
                    if item:IsA("TextLabel") and (item.Text == LocalPlayer.Name or item.Text == LocalPlayer.DisplayName) then
                        found = plot
                        break
                    end
                end
            end
            if found then break end
        end
    end
    if not found then status("Cannot identify your plot yet") return false end
    local node = found:FindFirstChild("ToUpdate")
    local pen = node and node:FindFirstChild("PetArea")
    local origin = found:FindFirstChild("CenterPoint") or pen
    if not pen or not origin then status("Your pen has not loaded") return false end
    state.plot, state.pen, state.origin = found, pen, origin
    state.treadmill = found:FindFirstChild("TreadmillBottom")
    return true
end

local function releaseControls()
    if state.controls then
        pcall(function() state.controls:Enable() end)
        state.controls = nil
    end
end
local function takeControls()
    if state.controls then return end
    local ok, control = pcall(function()
        local module = LocalPlayer.PlayerScripts:FindFirstChild("PlayerModule")
        if not module then return nil end
        local loaded = require(module)
        return loaded:GetControls()
    end)
    if ok and control then
        state.controls = control
        pcall(function() control:Disable() end)
    end
end

local function walkTo(position, tolerance, maxSeconds)
    local _, root, hum = character()
    if not root then return false end
    local distance = (root.Position - position).Magnitude
    local limit = maxSeconds or math.clamp(distance / math.max(8, hum.WalkSpeed) * 2.3 + 8, 12, 100)
    takeControls()
    local start = os.clock()
    local lastPosition = root.Position
    local stuckSince = os.clock()
    while running and cfg.AutoFarm and not state.paused and os.clock() - start < limit do
        local _, currentRoot, currentHum = character()
        if not currentRoot then return false end
        local flatTarget = Vector3.new(position.X, currentRoot.Position.Y, position.Z)
        if (currentRoot.Position - flatTarget).Magnitude < (tolerance or 7) then return true end
        currentHum:MoveTo(flatTarget)
        if (currentRoot.Position - lastPosition).Magnitude > 1.1 then
            lastPosition = currentRoot.Position
            stuckSince = os.clock()
        elseif os.clock() - stuckSince > 3 then
            currentHum.Jump = true
            if os.clock() - stuckSince > 8 then return false end
        end
        task.wait(0.3)
    end
    return false
end

local function getSnapshot()
    local ok, value = request("FieldSnapshot", 6)
    if ok and type(value) == "table" and type(value.Records) == "table" then return value.Records end
    return {}
end
local function ownRecords()
    local result = {}
    local ok, snap = request("OwnEggs", 7)
    if not ok or type(snap) ~= "table" then return result end
    for _, bucket in pairs(snap) do
        if type(bucket) == "table" and tonumber(bucket.OwnerUserId) == LocalPlayer.UserId then
            for uid, value in pairs(bucket.Records or {}) do result[uid] = value end
        end
    end
    return result
end

local function carryingEgg()
    -- Character visual carry marker varies with game builds.
    local ch = LocalPlayer.Character
    if not ch then return false end
    for _, desc in ipairs(ch:GetChildren()) do
        local name = desc.Name:lower()
        if (name:find("carry", 1, true) or name:find("heldegg", 1, true)) and desc ~= ch then return true end
    end
    return state.carrying
end

local function nearestEggs(snapshot)
    local _, root, hum = character()
    if not root then return {} end
    local found = {}
    for _, rec in pairs(snapshot) do
        if type(rec) == "table" and rec.State == "Slot" and typeof(rec.BottomCFrame) == "CFrame" then
            local area = tostring(rec.AreaId or "")
            local guard = guardSpeeds[area]
            local safe = area == "Forest" or (guard and hum.WalkSpeed >= guard * 1.05)
            if (not cfg.GuardSafety or safe) and (not cfg.ForestOnly or area == "Forest") then
                local distance = (root.Position - rec.BottomCFrame.Position).Magnitude
                found[#found + 1] = { record=rec, distance=distance,
                    weight=tonumber(rec.AssetScale or rec.Scale) or 1 }
            end
        end
    end
    table.sort(found, function(a, b)
        if cfg.SortBest and a.weight ~= b.weight then return a.weight > b.weight end
        return a.distance < b.distance
    end)
    return found
end

local function nearbyPrompt(position)
    local closest, best = nil, 25
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("ProximityPrompt") and object.Name == "CarryAreaEgg" then
            local part = object.Parent
            if part and part:IsA("BasePart") then
                local distance = (part.Position - position).Magnitude
                if distance < best then closest, best = object, distance end
            end
        end
    end
    return closest
end

local function attemptSteal(target)
    local egg = target.record
    if not egg.Uid then status("Egg has no UID") return false end
    status("Approaching " .. tostring(egg.AssetCategory or egg.AreaId or "egg"))
    if not walkTo(egg.BottomCFrame.Position + Vector3.new(0, 2.5, 0), 7) then
        statistics.failed = statistics.failed + 1
        status("Could not reach egg")
        return false
    end
    status("Picking up egg...")
    local ok, accepted = request("FieldCarry", 6, { Uid = egg.Uid })
    if not ok or accepted == false then
        local prompt = nearbyPrompt(egg.BottomCFrame.Position)
        if prompt then
            pcall(function()
                if type(fireproximityprompt) == "function" then
                    fireproximityprompt(prompt)
                else
                    prompt:InputHoldBegin()
                    task.wait(math.max(0.2, prompt.HoldDuration + 0.1))
                    prompt:InputHoldEnd()
                end
            end)
        end
    end
    task.wait(0.65)
    -- Remote accepts a request but only the game server can complete a pickup.
    -- The returning remote result is indicative, not conclusive.
    if ok and accepted then
        state.carrying = true
        statistics.stolen = statistics.stolen + 1
        return true
    end
    statistics.failed = statistics.failed + 1
    status("Pickup not verified")
    return false
end

local function returnHome()
    if not findPlot() then return false end
    status("Returning to your pen")
    local goal = state.pen.Position + Vector3.new(0, state.pen.Size.Y / 2 + 2, 0)
    if not walkTo(goal, 6) then status("Return path failed") return false end
    local before = os.clock()
    while running and cfg.AutoFarm and os.clock() - before < 4 do task.wait(0.2) end
    state.carrying = false
    return true
end

local function placeEggs()
    if not cfg.AutoPlace or not findPlot() then return end
    local records = ownRecords()
    local occupied = {}
    for _, rec in pairs(records) do
        if rec.Placement and typeof(rec.Placement.LocalCFrame) == "CFrame" then
            occupied[#occupied + 1] = (state.origin.CFrame * rec.Placement.LocalCFrame).Position
        end
    end
    for uid, rec in pairs(records) do
        if not running or not cfg.AutoPlace then break end
        if not rec.Placement then
            local spot = nil
            for _ = 1, 18 do
                local x = (math.random() - 0.5) * math.max(3, state.pen.Size.X - 9)
                local z = (math.random() - 0.5) * math.max(3, state.pen.Size.Z - 9)
                local candidate = (state.pen.CFrame * CFrame.new(x, state.pen.Size.Y / 2 + 1, z)).Position
                local free = true
                for _, prev in ipairs(occupied) do
                    if (candidate - prev).Magnitude < 5 then free = false break end
                end
                if free then spot = candidate break end
            end
            if spot then
                local localFrame = state.origin.CFrame:ToObjectSpace(CFrame.new(spot))
                local ok, value = request("PlaceEgg", 6, {Uid=uid, LocalCFrame=localFrame})
                if ok and value then
                    occupied[#occupied + 1] = spot
                    statistics.placed = statistics.placed + 1
                end
                task.wait(0.2)
            end
        end
    end
end

local hatchCooldown = {}
local function hatchReady()
    if not cfg.AutoHatch then return end
    local records = ownRecords()
    for uid, rec in pairs(records) do
        if not running or not cfg.AutoHatch then break end
        if rec.Placement and (os.clock() - (hatchCooldown[uid] or -999)) > 20 then
            hatchCooldown[uid] = os.clock()
            local ok, result = request("HatchEgg", 6, uid)
            if ok and result then
                task.wait(0.9)
                local done, accepted = request("FinishHatch", 6, uid)
                if done and accepted then statistics.hatched = statistics.hatched + 1 end
            end
            task.wait(0.2)
        end
    end
end

local function autoEquip()
    if not cfg.AutoEquip then return end
    local bag = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not bag then return end
    for _, tool in ipairs(bag:GetChildren()) do
        if not running or not cfg.AutoEquip then return end
        if tool:IsA("Tool") and tool:GetAttribute("ItemType") == "Asset" then
            local uid = tool:GetAttribute("UID")
            if uid then request("EquipPet", 5, uid) task.wait(0.15) end
        end
    end
end

local function autoTrain(seconds)
    if not cfg.AutoTrain or not findPlot() or not state.treadmill then return end
    status("Training Speed on your treadmill")
    walkTo(state.treadmill.Position + Vector3.new(0, 3.5, 0), 5, 40)
    local start = os.clock()
    while running and cfg.AutoFarm and cfg.AutoTrain and not state.paused and os.clock() - start < (seconds or 12) do
        task.wait(0.25)
    end
end

-- UI
local guiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 12)
if not guiParent then return end
local gui = inst("ScreenGui", {
    Name = "StealAnEggNova", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)
local main = inst("Frame", {
    Position=UDim2.fromOffset(14, 90), Size=UDim2.fromOffset(298, 445),
    BackgroundColor3=colors.bg, BorderSizePixel=0, Active=true, ZIndex=5,
}, gui)
inst("UICorner", { CornerRadius=UDim.new(0, 13) }, main)
inst("UIStroke", { Color=colors.stroke, Thickness=1.2 }, main)
local header = inst("Frame", {Size=UDim2.new(1, 0, 0, 52), BackgroundTransparency=1, Active=true, ZIndex=6}, main)
inst("TextLabel", {
    Position=UDim2.fromOffset(13, 5),Size=UDim2.new(1,-57,0,23),BackgroundTransparency=1,
    Text="STEAL AN EGG  |  NOVA",TextColor3=colors.fg,Font=Enum.Font.GothamBold,
    TextSize=15,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=7,
}, header)
inst("TextLabel", {
    Position=UDim2.fromOffset(13, 28), Size=UDim2.new(1,-57,0,17), BackgroundTransparency=1,
    Text="AUTO FARM  •  EGGS  •  PROGRESS", TextColor3=colors.dim,
    Font=Enum.Font.GothamMedium,TextSize=9,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=7,
}, header)
local hide = inst("TextButton", {
    Position=UDim2.new(1,-42,0,9),Size=UDim2.fromOffset(32,30),Text="−",
    TextColor3=colors.fg,Font=Enum.Font.GothamBold,TextSize=21,
    BackgroundColor3=colors.panel, BorderSizePixel=0,ZIndex=8,
}, header)
inst("UICorner", {CornerRadius=UDim.new(0,7)},hide)
local stats = inst("TextLabel", {
    Position=UDim2.fromOffset(12,54), Size=UDim2.new(1,-24,0,47),
    BackgroundColor3=colors.panel,BorderSizePixel=0,
    Text="Loading...",TextColor3=colors.egg,Font=Enum.Font.GothamMedium,
    TextWrapped=true,TextSize=11,ZIndex=6,
}, main)
inst("UICorner", {CornerRadius=UDim.new(0,8)},stats)
local list = inst("ScrollingFrame", {
    Position=UDim2.fromOffset(10,108),Size=UDim2.new(1,-20,1,-145),
    BackgroundTransparency=1,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.fromScale(0,0),ScrollBarThickness=4,
    ScrollBarImageColor3=colors.dim,ZIndex=6,
},main)
inst("UIListLayout", {Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},list)
inst("UIPadding", {PaddingBottom=UDim.new(0,8)},list)
local footer = inst("TextLabel", {
    Position=UDim2.new(0,12,1,-31),Size=UDim2.new(1,-24,0,25),
    Text="Ready",TextColor3=colors.dim,BackgroundTransparency=1,
    Font=Enum.Font.GothamMedium,TextSize=10,TextTruncate=Enum.TextTruncate.AtEnd,
    TextXAlignment=Enum.TextXAlignment.Left,ZIndex=7,
},main)
local bubble = inst("TextButton",{
    Position=UDim2.new(0,12,0.42,0),Size=UDim2.fromOffset(60,42),
    Text="EGG",Font=Enum.Font.GothamBold,TextColor3=colors.egg,
    BackgroundColor3=colors.bg,BorderSizePixel=0,TextSize=14,Visible=false,ZIndex=15,
},gui)
inst("UICorner",{CornerRadius=UDim.new(0,9)},bubble)
inst("UIStroke",{Color=colors.egg,Thickness=1.1},bubble)

local function button(label, fn, getOn)
    local b = inst("TextButton",{
        Size=UDim2.new(1,-7,0,36),BackgroundColor3=colors.panel,BorderSizePixel=0,
        Text=label,TextColor3=colors.fg,Font=Enum.Font.GothamMedium,
        TextSize=12,ZIndex=7,
    },list)
    inst("UICorner",{CornerRadius=UDim.new(0,8)},b)
    local function recolor()
        if getOn then b.BackgroundColor3 = getOn() and colors.yes or colors.panel end
    end
    bind(b.MouseButton1Click,function()
        if not running then return end
        local ok, err = pcall(fn,b)
        if not ok then status("Button error: "..tostring(err):sub(1,80)) end
        recolor()
    end)
    recolor()
    return b
end
local function toggle(label, key, callback)
    return button(label .. ": " .. (cfg[key] and "ON" or "OFF"),function(b)
        cfg[key] = not cfg[key]
        b.Text = label .. ": " .. (cfg[key] and "ON" or "OFF")
        if callback then callback() end
    end,function() return cfg[key] end)
end

toggle("AUTO STEAL + RETURN", "AutoFarm", function()
    if not cfg.AutoFarm then releaseControls() status("Farm paused") else status("Farm enabled") end
end)
toggle("AUTO PLACE EGGS", "AutoPlace")
toggle("AUTO HATCH", "AutoHatch")
toggle("AUTO EQUIP PETS", "AutoEquip")
toggle("AUTO TRAIN SPEED", "AutoTrain")
toggle("EGG ESP / WALL MARKERS", "EggESP")
toggle("GUARD SPEED SAFETY", "GuardSafety")
toggle("FOREST EGGS ONLY", "ForestOnly")
toggle("ANTI AFK", "AntiAFK")
toggle("PREFER BIG EGGS", "SortBest")
button("CLAIM OFFLINE CASH",function()
    task.spawn(function()
        local ok, summary = request("OfflineSummary",6)
        if not ok then status("Offline cash unavailable") return end
        if type(summary)=="table" and (tonumber(summary.ClaimableAmount) or 0) <= 0 then
            status("No offline cash to claim") return
        end
        local done, accepted = request("OfflineClaim",6)
        status(done and accepted and "Offline claim requested" or "Claim rejected")
    end)
end)
button("RETURN TO PEN",function()
    task.spawn(function()
        if cfg.AutoFarm then returnHome() else status("Enable AUTO STEAL for auto-movement") end
    end)
end)
button("PAUSE / RESUME",function()
    state.paused = not state.paused
    if state.paused then releaseControls() end
    status(state.paused and "Paused" or "Resumed")
end)

local function clearMark(key)
    local data = marks[key]
    if data then
        for _, obj in ipairs(data) do pcall(function() obj:Destroy() end) end
    end
    marks[key] = nil
end
local function refreshEggESP(snapshot)
    if not cfg.EggESP then
        for key in pairs(marks) do clearMark(key) end
        return
    end
    local _, root = character()
    local wanted = {}
    local count = 0
    for _, rec in pairs(snapshot) do
        if type(rec)=="table" and rec.State=="Slot" and typeof(rec.BottomCFrame)=="CFrame" then
            local pos = rec.BottomCFrame.Position
            local dist = root and (root.Position-pos).Magnitude or math.huge
            if dist <= cfg.VisualRange and count < 60 then
                local key = tostring(rec.Uid or rec)
                wanted[key] = true
                count = count + 1
                if not marks[key] then
                    local marker = inst("Part",{
                        Name="EggNovaMarker",Anchored=true,CanCollide=false,CanTouch=false,
                        CanQuery=false,Transparency=1,Size=Vector3.new(1,1,1),
                        CFrame=CFrame.new(pos),
                    },Workspace)
                    local label = inst("BillboardGui",{
                        Adornee=marker,AlwaysOnTop=true,Size=UDim2.fromOffset(182,42),
                        StudsOffsetWorldSpace=Vector3.new(0,2.5,0),MaxDistance=cfg.VisualRange,
                    },gui)
                    local txt = inst("TextLabel",{
                        Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
                        Text=tostring(rec.AssetCategory or "EGG").."\n"..tostring(rec.AreaId or ""),
                        TextColor3=colors.egg,TextStrokeTransparency=0.25,
                        Font=Enum.Font.GothamBold,TextSize=12,TextWrapped=true,
                    },label)
                    marks[key] = {marker,label,txt}
                else
                    local data = marks[key]
                    if data[1] then data[1].CFrame=CFrame.new(pos) end
                end
            end
        end
    end
    for key in pairs(marks) do if not wanted[key] then clearMark(key) end end
end

local hidden = false
local function setHidden(on)
    hidden = on
    main.Visible = not on
    bubble.Visible = on
end
bind(hide.MouseButton1Click,function() setHidden(true) end)
bind(bubble.MouseButton1Click,function() setHidden(false) end)
bind(UserInputService.InputBegan,function(input,processed)
    if not processed and input.KeyCode==Enum.KeyCode.RightShift then setHidden(not hidden) end
end)
local dragging, dragInput, dragStart, startPos = false,nil,nil,nil
bind(header.InputBegan,function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, dragInput, dragStart, startPos = true, input, input.Position, main.Position
    end
end)
bind(UserInputService.InputChanged,function(input)
    if not dragging or not dragStart or not startPos then return end
    local mouse = dragInput and dragInput.UserInputType==Enum.UserInputType.MouseButton1
        and input.UserInputType==Enum.UserInputType.MouseMovement
    if input~=dragInput and not mouse then return end
    local delta=input.Position-dragStart
    local cam=Workspace.CurrentCamera
    local size=cam and cam.ViewportSize or Vector2.new(800,600)
    main.Position=UDim2.fromOffset(
        math.clamp(startPos.X.Offset+delta.X,0,math.max(0,size.X-main.AbsoluteSize.X)),
        math.clamp(startPos.Y.Offset+delta.Y,0,math.max(0,size.Y-main.AbsoluteSize.Y))
    )
end)
bind(UserInputService.InputEnded,function(input)
    if input==dragInput then dragging=false dragInput=nil end
end)

local function unload()
    if not running then return end
    running=false
    cfg.AutoFarm=false
    releaseControls()
    for _, connection in ipairs(links) do pcall(function() connection:Disconnect() end) end
    for key in pairs(marks) do clearMark(key) end
    pcall(function() gui:Destroy() end)
    if global.STEAL_EGG_NOVA_STOP==unload then global.STEAL_EGG_NOVA_STOP=nil end
end
global.STEAL_EGG_NOVA_STOP=unload
button("UNLOAD SCRIPT",unload)

bind(LocalPlayer.Idled,function()
    if cfg.AntiAFK and running then
        pcall(function()
            local virtualUser=game:GetService("VirtualUser")
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0,0))
        end)
    end
end)

-- Background monitor: passive ESP + info, one snapshot every 3 seconds.
task.spawn(function()
    while running do
        local ok, err = pcall(function()
            local snap=getSnapshot()
            refreshEggESP(snap)
            local _,_,hum=character()
            stats.Text=string.format("STOLEN %d   •   PLACED %d   •   HATCHED %d\nFAILED %d   |   SPEED %d",statistics.stolen,statistics.placed,statistics.hatched,statistics.failed,hum and math.floor(hum.WalkSpeed) or 0)
            footer.Text=fullStatus
        end)
        if not ok then status("Monitor: "..tostring(err):sub(1,60)) end
        task.wait(3)
    end
end)

-- Base management can operate even while auto farm is disabled.
task.spawn(function()
    while running do
        if not state.working and (cfg.AutoPlace or cfg.AutoHatch or cfg.AutoEquip) then
            pcall(function()
                placeEggs()
                hatchReady()
                autoEquip()
            end)
        end
        task.wait(13)
    end
end)

-- Farm loop intentionally uses walking; instantaneous CFrame teleports
-- have been reported to kill/reset the character in this game.
task.spawn(function()
    while running do
        if cfg.AutoFarm and not state.paused then
            state.working=true
            local ok, err=pcall(function()
                if not findPlot() then task.wait(2) return end
                local _,root=character()
                if not root then status("Waiting for character") task.wait(2) return end
                local eggs=nearestEggs(getSnapshot())
                if #eggs==0 then
                    status("No accessible eggs. Waiting / training...")
                    autoTrain(10)
                    task.wait(2)
                    return
                end
                if attemptSteal(eggs[1]) then
                    if returnHome() then
                        placeEggs()
                        hatchReady()
                        autoEquip()
                    else
                        statistics.failed=statistics.failed+1
                    end
                end
            end)
            if not ok then status("Farm error: "..tostring(err):sub(1,90)) end
            state.working=false
            releaseControls()
            task.wait(1.5)
        else
            releaseControls()
            task.wait(0.5)
        end
    end
end)

if game.PlaceId ~= 107778070777162 then
    status("Wrong game? Script is designed for Steal an Egg.")
end
print("[EGG NOVA] Loaded. Auto farm OFF by default; open the menu to enable it.")
