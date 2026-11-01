-- MM2 NOVA V1 | Role Scanner + Through-Wall ESP + Sheriff Assist
-- Mobile friendly; no fetched dependencies or external libraries.
-- Role selection is controlled by the MM2 server; this script cannot force Murderer.
-- Gun automation is experimental and is only attempted with a real equipped gun.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local global = (type(getgenv) == "function" and getgenv()) or _G
pcall(function()
    if type(global.MM2_NOVA_STOP) == "function" then
        global.MM2_NOVA_STOP()
    end
end)

local alive = true
local settings = {
    RoleESP = true,
    InnocentESP = false,
    GunESP = true,
    AimAssist = false,
    AutoShoot = false,
    AutoEquip = true,
    Fullbright = false,
    FOV = 180,
    AimSpeed = 15,
    Lead = 0.07,
    MaxDistance = 1500,
    WallCheck = true,
}
local links = {}
local tracked = {}
local roleInfo = {}
local latestRoleTime = 0
local lastShot = 0
local shotBusy = false
local roleRemote = nil
local statusMessage = "Checking game data..."
local currentTarget = nil
local dropItem = nil
local lightOriginal = {
    Brightness = Lighting.Brightness,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    GlobalShadows = Lighting.GlobalShadows,
    ClockTime = Lighting.ClockTime,
}

local palette = {
    Red = Color3.fromRGB(255, 72, 88),
    Blue = Color3.fromRGB(60, 155, 255),
    Yellow = Color3.fromRGB(255, 209, 83),
    Green = Color3.fromRGB(104, 226, 154),
    Grey = Color3.fromRGB(140, 145, 158),
    Text = Color3.fromRGB(239, 241, 247),
    Muted = Color3.fromRGB(160, 165, 177),
    Surface = Color3.fromRGB(18, 20, 27),
    Panel = Color3.fromRGB(30, 33, 43),
    Stroke = Color3.fromRGB(66, 72, 88),
}

local function bind(signal, fn)
    local link = signal:Connect(fn)
    table.insert(links, link)
    return link
end

local function new(class, props, parent)
    local obj = Instance.new(class)
    for name, value in pairs(props or {}) do
        obj[name] = value
    end
    obj.Parent = parent
    return obj
end

local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 15)
if not playerGui then return end
local old = playerGui:FindFirstChild("MM2NovaHub")
if old then old:Destroy() end

local gui = new("ScreenGui", {
    Name = "MM2NovaHub", ResetOnSpawn = false,
    DisplayOrder = 990, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local fovRing = new("Frame", {
    Size = UDim2.fromOffset(settings.FOV * 2, settings.FOV * 2),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    Visible = false, ZIndex = 1,
}, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fovRing)
new("UIStroke", {
    Color = palette.Blue, Thickness = 1.3, Transparency = 0.42,
}, fovRing)

local main = new("Frame", {
    Name = "Panel", Size = UDim2.fromOffset(306, 432),
    Position = UDim2.fromOffset(15, 76), Active = true,
    BackgroundColor3 = palette.Surface, BorderSizePixel = 0,
    ZIndex = 10,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 13) }, main)
new("UIStroke", { Color = palette.Stroke, Thickness = 1.3 }, main)

local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 49), BackgroundTransparency = 1,
    Active = true, ZIndex = 12,
}, main)
new("TextLabel", {
    Size = UDim2.new(1, -61, 0, 27),
    Position = UDim2.fromOffset(14, 6),
    BackgroundTransparency = 1, Text = "MM2  /  NOVA HUB",
    Font = Enum.Font.GothamBold, TextSize = 16,
    TextColor3 = palette.Text, TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 13,
}, header)
new("TextLabel", {
    Size = UDim2.new(1, -61, 0, 17),
    Position = UDim2.fromOffset(14, 29),
    BackgroundTransparency = 1, Text = "ROLE SCANNER  •  COMBAT  •  ESP",
    Font = Enum.Font.GothamMedium, TextSize = 9,
    TextColor3 = palette.Muted, TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 13,
}, header)
local closeButton = new("TextButton", {
    Size = UDim2.fromOffset(31, 29), Position = UDim2.new(1, -39, 0, 10),
    BackgroundColor3 = palette.Panel, BorderSizePixel = 0,
    Text = "−", TextSize = 21, Font = Enum.Font.GothamBold,
    TextColor3 = palette.Text, ZIndex = 13,
}, header)
new("UICorner", { CornerRadius = UDim.new(0, 7) }, closeButton)

local summary = new("Frame", {
    Position = UDim2.fromOffset(10, 52), Size = UDim2.new(1, -20, 0, 71),
    BackgroundColor3 = palette.Panel, BorderSizePixel = 0, ZIndex = 11,
}, main)
new("UICorner", { CornerRadius = UDim.new(0, 9) }, summary)
local info1 = new("TextLabel", {
    Position = UDim2.fromOffset(9, 7), Size = UDim2.new(1, -18, 0, 19),
    BackgroundTransparency = 1, Text = "MURDERER: scanning...",
    TextColor3 = palette.Red, Font = Enum.Font.GothamBold, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12,
}, summary)
local info2 = new("TextLabel", {
    Position = UDim2.fromOffset(9, 27), Size = UDim2.new(1, -18, 0, 19),
    BackgroundTransparency = 1, Text = "SHERIFF: scanning...",
    TextColor3 = palette.Blue, Font = Enum.Font.GothamBold, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12,
}, summary)
local info3 = new("TextLabel", {
    Position = UDim2.fromOffset(9, 49), Size = UDim2.new(1, -18, 0, 15),
    BackgroundTransparency = 1, Text = "YOUR ROLE: unknown",
    TextColor3 = palette.Muted, Font = Enum.Font.GothamMedium, TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12,
}, summary)

local scroll = new("ScrollingFrame", {
    Position = UDim2.fromOffset(10, 132), Size = UDim2.new(1, -20, 1, -164),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 4, ScrollBarImageColor3 = palette.Grey,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.fromOffset(0, 0),
    ZIndex = 12,
}, main)
new("UIListLayout", {
    Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder,
}, scroll)
new("UIPadding", { PaddingBottom = UDim.new(0, 10) }, scroll)

local status = new("TextLabel", {
    Position = UDim2.new(0, 13, 1, -26), Size = UDim2.new(1, -26, 0, 20),
    BackgroundTransparency = 1, Text = "Loading...",
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    TextSize = 10, Font = Enum.Font.GothamMedium,
    TextColor3 = palette.Muted, ZIndex = 12,
}, main)

local bubble = new("TextButton", {
    Size = UDim2.fromOffset(58, 41),
    Position = UDim2.new(0, 12, 0.42, 0),
    BackgroundColor3 = palette.Surface, Text = "MM2",
    Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = palette.Blue, BorderSizePixel = 0,
    Visible = false, ZIndex = 20,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 11) }, bubble)
new("UIStroke", { Color = palette.Blue, Thickness = 1.4 }, bubble)

local function refreshFOV()
    fovRing.Visible = settings.AimAssist or settings.AutoShoot
    fovRing.Size = UDim2.fromOffset(settings.FOV * 2, settings.FOV * 2)
end

local function addButton(text, handler, enabledFn)
    local button = new("TextButton", {
        Size = UDim2.new(1, -7, 0, 35),
        BackgroundColor3 = palette.Panel, BorderSizePixel = 0,
        Text = text, TextColor3 = palette.Text,
        Font = Enum.Font.GothamMedium, TextSize = 12, ZIndex = 13,
    }, scroll)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
    bind(button.MouseButton1Click, function()
        if not alive then return end
        local ok, err = pcall(handler, button)
        if not ok then
            statusMessage = "Action failed: " .. tostring(err):sub(1, 65)
        end
        if enabledFn then
            button.BackgroundColor3 = enabledFn() and Color3.fromRGB(35, 59, 76) or palette.Panel
        end
    end)
    if enabledFn then
        button.BackgroundColor3 = enabledFn() and Color3.fromRGB(35, 59, 76) or palette.Panel
    end
    return button
end

local function addToggle(caption, key, onChange)
    return addButton(caption .. ": " .. (settings[key] and "ON" or "OFF"), function(button)
        settings[key] = not settings[key]
        button.Text = caption .. ": " .. (settings[key] and "ON" or "OFF")
        if onChange then onChange() end
    end, function() return settings[key] end)
end

local function getHumanoid(character)
    if not character then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then return hum end
end

local function getHead(character)
    if not character then return nil end
    return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
end

local function findTool(player, namePart, equippedOnly)
    local char = player.Character
    local containers = { char }
    if not equippedOnly then
        table.insert(containers, player:FindFirstChildOfClass("Backpack"))
    end
    for _, container in ipairs(containers) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") and string.find(string.lower(child.Name), namePart, 1, true) then
                    return child
                end
            end
        end
    end
end

local function roleOf(player)
    if latestRoleTime > 0 and (os.clock() - latestRoleTime) < 5 then
        local data = roleInfo[player.Name]
        if data then
            if data.Dead or data.Killed then return "Dead", true end
            return data.Role, true
        end
    end
    if findTool(player, "knife", false) then return "Murderer", false end
    if findTool(player, "gun", false) or findTool(player, "revolver", false) then
        return "Sheriff", false
    end
    return "Unknown", false
end

local function colorForRole(role)
    if role == "Murderer" then return palette.Red end
    if role == "Sheriff" then return palette.Blue end
    if role == "Hero" then return palette.Yellow end
    if role == "Innocent" then return palette.Green end
    return palette.Grey
end

local function clearPlayer(p)
    local item = tracked[p]
    if not item then return end
    if item.highlight then item.highlight:Destroy() end
    if item.billboard then item.billboard:Destroy() end
    tracked[p] = nil
end

local function createPlayerESP(p, char, head)
    local highlight = new("Highlight", {
        Name = "MM2NovaHighlight", Adornee = char,
        FillTransparency = 0.72, OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        FillColor = palette.Grey, OutlineColor = palette.Grey,
    }, char)
    local label = new("BillboardGui", {
        Name = "MM2NovaLabel", Adornee = head,
        AlwaysOnTop = true, Size = UDim2.fromOffset(202, 39),
        StudsOffsetWorldSpace = Vector3.new(0, 2.45, 0),
        MaxDistance = settings.MaxDistance, Enabled = true,
    }, gui)
    local textLabel = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Text = "", TextColor3 = palette.Grey,
        TextStrokeTransparency = 0.25, TextSize = 12,
        Font = Enum.Font.GothamBold, TextWrapped = true,
    }, label)
    tracked[p] = { char = char, head = head, highlight = highlight,
        billboard = label, text = textLabel }
end

local function validGunDrop(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") or inst:IsA("Tool") then
        return inst:FindFirstChildWhichIsA("BasePart", true)
    end
end

local gunMark = nil
local function clearGunMark()
    if gunMark then
        if gunMark.highlight then gunMark.highlight:Destroy() end
        if gunMark.billboard then gunMark.billboard:Destroy() end
        gunMark = nil
    end
end

local function updateGunESP()
    if not settings.GunESP then clearGunMark() return end
    local found = Workspace:FindFirstChild("GunDrop", true)
    local part = validGunDrop(found)
    if not part then clearGunMark() return end
    if gunMark and gunMark.part == part then return end
    clearGunMark()
    local h = new("Highlight", {
        Name = "MM2NovaGunHighlight", Adornee = found,
        FillColor = palette.Yellow, OutlineColor = palette.Yellow,
        FillTransparency = 0.36, OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }, found)
    local bill = new("BillboardGui", {
        Adornee = part, AlwaysOnTop = true,
        Size = UDim2.fromOffset(150, 30),
        StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0),
        MaxDistance = settings.MaxDistance,
    }, gui)
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Text = "DROPPED GUN", TextColor3 = palette.Yellow,
        TextStrokeTransparency = 0.15,
        Font = Enum.Font.GothamBold, TextSize = 13,
    }, bill)
    gunMark = { highlight = h, billboard = bill, part = part }
end

local function updateESP()
    local ownRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    for p in pairs(tracked) do
        if p.Parent ~= Players then clearPlayer(p) end
    end
    if not settings.RoleESP then
        for p in pairs(tracked) do clearPlayer(p) end
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local char = p.Character
            local hum = getHumanoid(char)
            local head = getHead(char)
            local role, verified = roleOf(p)
            local display = role ~= "Innocent" or settings.InnocentESP
            if role == "Unknown" then display = settings.InnocentESP end
            local distance = (ownRoot and head) and (ownRoot.Position - head.Position).Magnitude or math.huge
            if not hum or not head or not display or distance > settings.MaxDistance then
                clearPlayer(p)
            else
                if tracked[p] and (tracked[p].char ~= char or tracked[p].head ~= head) then
                    clearPlayer(p)
                end
                if not tracked[p] then createPlayerESP(p, char, head) end
                local item = tracked[p]
                local shade = colorForRole(role)
                item.highlight.FillColor = shade
                item.highlight.OutlineColor = shade
                item.billboard.MaxDistance = settings.MaxDistance
                item.text.TextColor3 = shade
                item.text.Text = string.format("%s  |  %s%s\n%d studs", p.DisplayName,
                    string.upper(role), verified and "" or " (?)", math.floor(distance))
            end
        end
    end
end

local function hasLineOfSight(camera, targetCharacter, part)
    if not settings.WallCheck then return true end
    local start = camera.CFrame.Position
    local delta = part.Position - start
    if delta.Magnitude < 0.01 then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    params.FilterDescendantsInstances = { LocalPlayer.Character or camera, camera }
    local hit = Workspace:Raycast(start, delta, params)
    return not hit or hit.Instance:IsDescendantOf(targetCharacter)
end

local function murdererPlayer()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local role = roleOf(p)
            if role == "Murderer" and getHumanoid(p.Character) then
                return p
            end
        end
    end
end

local function getTarget(camera)
    local p = murdererPlayer()
    if not p then return nil end
    local char = p.Character
    local part = getHead(char)
    if not part then return nil end
    local speed = part.AssemblyLinearVelocity
    local lead = Vector3.new(speed.X, 0, speed.Z) * settings.Lead
    local point = part.Position + lead
    local projected, visible = camera:WorldToViewportPoint(point)
    if not visible or projected.Z <= 0 then return nil end
    local screenDist = (Vector2.new(projected.X, projected.Y) - camera.ViewportSize / 2).Magnitude
    if screenDist > settings.FOV then return nil end
    if (camera.CFrame.Position - part.Position).Magnitude > settings.MaxDistance then return nil end
    if not hasLineOfSight(camera, char, part) then return nil end
    return { player = p, part = part, position = point, screenDistance = screenDist }
end

local function equippedGun()
    return findTool(LocalPlayer, "gun", true) or findTool(LocalPlayer, "revolver", true)
end

local function ensureGun()
    local tool = equippedGun()
    if tool then return tool end
    if not settings.AutoEquip then return nil end
    local stored = findTool(LocalPlayer, "gun", false) or findTool(LocalPlayer, "revolver", false)
    local hum = getHumanoid(LocalPlayer.Character)
    if stored and hum then
        pcall(function() hum:EquipTool(stored) end)
    end
    return equippedGun()
end

local function shootAt(target, manually)
    if shotBusy or not target then return false end
    if not manually and not settings.AutoShoot then return false end
    if (os.clock() - lastShot) < 1.65 then return false end
    local gun = ensureGun()
    if not gun then
        statusMessage = "Need Sheriff's gun to shoot"
        return false
    end
    local role = roleOf(LocalPlayer)
    if role == "Murderer" then return false end
    local cam = Workspace.CurrentCamera
    if not cam or not hasLineOfSight(cam, target.player.Character, target.part) then
        statusMessage = "Shot blocked by a wall"
        return false
    end
    lastShot = os.clock()
    shotBusy = true
    local aimPosition = target.position
    local remote = gun:FindFirstChild("ShootGun", true)
    task.spawn(function()
        -- MM2 builds have used ShootGun(1, worldPosition, 'AH').
        -- If that interface is absent, use normal Tool activation.
        local ok = false
        if remote and remote:IsA("RemoteFunction") then
            ok = pcall(function() remote:InvokeServer(1, aimPosition, "AH") end)
            statusMessage = ok and "ShootGun request sent (hit unverified)" or "Remote shot failed"
        end
        if not ok then
            ok = pcall(function() gun:Activate() end)
            statusMessage = ok and "Gun activated (hit unverified)" or "Gun activation failed"
        end
        shotBusy = false
    end)
    return true
end

local function setFullbright(enabled)
    if enabled then
        Lighting.Brightness = 3
        Lighting.Ambient = Color3.fromRGB(185, 185, 185)
        Lighting.OutdoorAmbient = Color3.fromRGB(185, 185, 185)
        Lighting.GlobalShadows = false
        Lighting.ClockTime = 14
    else
        for key, value in pairs(lightOriginal) do
            Lighting[key] = value
        end
    end
end

addToggle("ROLE / WALL ESP", "RoleESP", updateESP)
addToggle("SHOW INNOCENTS", "InnocentESP", updateESP)
addToggle("DROPPED GUN ESP", "GunESP", updateGunESP)
addToggle("SHERIFF AIM ASSIST", "AimAssist", refreshFOV)
addToggle("AUTO SHOOT MURDERER", "AutoShoot", refreshFOV)
addToggle("AUTO EQUIP GUN", "AutoEquip")
addToggle("WALL CHECK (BLOCK SHOTS)", "WallCheck")
addButton("AIM FOV: " .. tostring(settings.FOV), function(button)
    if settings.FOV == 180 then settings.FOV = 260
    elseif settings.FOV == 260 then settings.FOV = 340
    else settings.FOV = 180 end
    button.Text = "AIM FOV: " .. tostring(settings.FOV)
    refreshFOV()
end)
addButton("AIM SPEED: " .. tostring(settings.AimSpeed), function(button)
    if settings.AimSpeed == 15 then settings.AimSpeed = 24
    elseif settings.AimSpeed == 24 then settings.AimSpeed = 9
    else settings.AimSpeed = 15 end
    button.Text = "AIM SPEED: " .. tostring(settings.AimSpeed)
end)
addToggle("FULLBRIGHT", "Fullbright", function() setFullbright(settings.Fullbright) end)
addButton("SHOOT MURDERER NOW", function()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local target = getTarget(cam)
    if target then
        shootAt(target, true)
    else
        statusMessage = "No visible Murderer inside FOV"
    end
end)

local function destroy()
    if not alive then return end
    alive = false
    for _, c in ipairs(links) do pcall(function() c:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep("MM2_NOVA_CAMERA") end)
    for p in pairs(tracked) do clearPlayer(p) end
    clearGunMark()
    setFullbright(false)
    gui:Destroy()
    if global.MM2_NOVA_STOP == destroy then global.MM2_NOVA_STOP = nil end
end

global.MM2_NOVA_STOP = destroy
addButton("UNLOAD NOVA HUB", destroy)

local minimized = false
local function setHidden(hidden)
    minimized = hidden
    main.Visible = not hidden
    bubble.Visible = hidden
end
bind(closeButton.MouseButton1Click, function() setHidden(true) end)
bind(bubble.MouseButton1Click, function() setHidden(false) end)
bind(UserInputService.InputBegan, function(input, focused)
    if focused then return end
    if input.KeyCode == Enum.KeyCode.RightShift then setHidden(not minimized) end
end)

local dragging = false
local dragStart = nil
local startPos = nil
local dragInput = nil
bind(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragInput = input
        dragStart = input.Position
        startPos = main.Position
    end
end)
bind(UserInputService.InputChanged, function(input)
    if not dragging or not dragStart or not startPos then return end
    local mouse = dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement
    if input ~= dragInput and not mouse then return end
    local d = input.Position - dragStart
    local cam = Workspace.CurrentCamera
    local size = cam and cam.ViewportSize or Vector2.new(1100, 650)
    main.Position = UDim2.fromOffset(
        math.clamp(startPos.X.Offset + d.X, 0, math.max(0, size.X - main.AbsoluteSize.X)),
        math.clamp(startPos.Y.Offset + d.Y, 0, math.max(0, size.Y - main.AbsoluteSize.Y))
    )
end)
bind(UserInputService.InputEnded, function(input)
    if input == dragInput then
        dragging = false
        dragInput = nil
    end
end)

-- Query the game's actual role information when that RemoteFunction exists.
-- Weapon inference is a fallback, and is marked (?) on the ESP label.
task.spawn(function()
    while alive do
        if not roleRemote or not roleRemote.Parent then
            local found = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
            roleRemote = found and found:IsA("RemoteFunction") and found or nil
        end
        if roleRemote then
            local success, data = pcall(function() return roleRemote:InvokeServer() end)
            if success and type(data) == "table" then
                local nextRoles = {}
                for username, entry in pairs(data) do
                    if type(entry) == "table" and type(entry.Role) == "string" then
                        nextRoles[tostring(username)] = {
                            Role = entry.Role,
                            Dead = entry.Dead == true,
                            Killed = entry.Killed == true,
                        }
                    end
                end
                roleInfo = nextRoles
                latestRoleTime = os.clock()
            end
        end
        task.wait(1.25)
    end
end)

local espAccumulator = 0
bind(RunService.Heartbeat, function(dt)
    if not alive then return end
    espAccumulator = espAccumulator + dt
    if espAccumulator < 0.4 then return end
    espAccumulator = 0
    local ok, err = pcall(function()
        updateESP()
        updateGunESP()
        local murderer, sheriff = "Unknown", "Unknown"
        for _, p in ipairs(Players:GetPlayers()) do
            local role = roleOf(p)
            if role == "Murderer" then murderer = p.DisplayName end
            if role == "Sheriff" then sheriff = p.DisplayName end
        end
        local myRole, verified = roleOf(LocalPlayer)
        info1.Text = "MURDERER: " .. murderer
        info2.Text = "SHERIFF: " .. sheriff
        info3.Text = "YOUR ROLE: " .. myRole:upper() .. (verified and "" or " (unconfirmed)")
        status.Text = statusMessage
    end)
    if not ok then statusMessage = "ESP update error: " .. tostring(err):sub(1, 35) end
end)

RunService:BindToRenderStep("MM2_NOVA_CAMERA", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not alive then return end
    if not settings.AimAssist and not settings.AutoShoot then return end
    local cam = Workspace.CurrentCamera
    if not cam or not getHumanoid(LocalPlayer.Character) then return end
    if not equippedGun() and not (settings.AutoShoot and settings.AutoEquip) then return end
    local target = getTarget(cam)
    currentTarget = target
    if not target then return end
    local goal = CFrame.lookAt(cam.CFrame.Position, target.position)
    local k = 1 - math.exp(-settings.AimSpeed * math.min(dt, 0.15))
    if settings.AimAssist or settings.AutoShoot then
        cam.CFrame = cam.CFrame:Lerp(goal, k)
    end
    if settings.AutoShoot and target.screenDistance <= 22 then
        shootAt(target, false)
    end
end)

bind(Players.PlayerRemoving, function(player)
    clearPlayer(player)
    roleInfo[player.Name] = nil
end)

refreshFOV()
statusMessage = "Role info: remote if available / tool fallback"
print("[MM2 NOVA] Loaded. Reopen via MM2 bubble or RightShift. Role selection is server-controlled.")
