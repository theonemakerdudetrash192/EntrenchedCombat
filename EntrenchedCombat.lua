-- ENTRENCHED | AIMBOT + ESP
-- Lightweight, no external libraries

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
if not LP then return end

local env = (type(getgenv) == "function" and getgenv()) or _G

-- Stop previous execution
pcall(function()
    if type(env.ENTRENCHED_STOP) == "function" then
        env.ENTRENCHED_STOP()
    end
end)

local active = true
local cfg = {
    Aim = false,
    ESP = true,
    WallCheck = true,
    Head = true,
    ShowFOV = true,
    FOV = 220,
    Smooth = 0.22,
    ESPDistance = 1500
}

local connections = {}
local espObjects = {}
local targetPart = nil
local bindName = "ENTRENCHED_AIM_" .. LP.UserId

local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end

local function make(class, properties, parent)
    local obj = Instance.new(class)
    for k, v in pairs(properties) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

local pg = LP:FindFirstChildOfClass("PlayerGui")
    or LP:WaitForChild("PlayerGui", 10)

if not pg then return end

local gui = make("ScreenGui", {
    Name = "EntrenchedCombatMenu",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999
}, pg)

-- FOV ring
local ring = make("Frame", {
    Name = "FOV",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(440, 440),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 1
}, gui)

make("UICorner", {
    CornerRadius = UDim.new(1, 0)
}, ring)

make("UIStroke", {
    Color = Color3.fromRGB(225, 225, 225),
    Thickness = 1.3,
    Transparency = 0.45
}, ring)

local main = make("Frame", {
    Size = UDim2.fromOffset(300, 355),
    Position = UDim2.fromOffset(18, 90),
    BackgroundColor3 = Color3.fromRGB(19, 19, 22),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 5
}, gui)

make("UICorner", {
    CornerRadius = UDim.new(0, 12)
}, main)

make("UIStroke", {
    Color = Color3.fromRGB(85, 85, 90),
    Transparency = 0.2,
    Thickness = 1
}, main)

local header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundTransparency = 1,
    Active = true,
    ZIndex = 6
}, main)

make("TextLabel", {
    Size = UDim2.new(1, -53, 1, 0),
    Position = UDim2.fromOffset(13, 0),
    BackgroundTransparency = 1,
    Text = "ENTRENCHED  |  COMBAT",
    TextColor3 = Color3.fromRGB(240, 240, 240),
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 7
}, header)

local minimize = make("TextButton", {
    Size = UDim2.fromOffset(34, 30),
    Position = UDim2.new(1, -42, 0, 8),
    BackgroundColor3 = Color3.fromRGB(45, 45, 50),
    Text = "-",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 20,
    Font = Enum.Font.GothamBold,
    ZIndex = 7
}, header)

make("UICorner", {
    CornerRadius = UDim.new(0, 7)
}, minimize)

local scroll = make("ScrollingFrame", {
    Position = UDim2.fromOffset(10, 49),
    Size = UDim2.new(1, -20, 1, -60),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Color3.fromRGB(110, 110, 115),
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 6
}, main)

make("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 7)
}, scroll)

make("UIPadding", {
    PaddingBottom = UDim.new(0, 8)
}, scroll)

local function button(label, action)
    local b = make("TextButton", {
        Size = UDim2.new(1, -8, 0, 38),
        BackgroundColor3 = Color3.fromRGB(40, 40, 45),
        BorderSizePixel = 0,
        TextColor3 = Color3.fromRGB(242, 242, 242),
        Text = label,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        ZIndex = 7
    }, scroll)

    make("UICorner", {
        CornerRadius = UDim.new(0, 8)
    }, b)

    connect(b.MouseButton1Click, function()
        if active then
            action(b)
        end
    end)

    return b
end

local function updateRing()
    ring.Visible = cfg.ShowFOV
    ring.Size = UDim2.fromOffset(cfg.FOV * 2, cfg.FOV * 2)
end

button("AIMBOT : OFF", function(b)
    cfg.Aim = not cfg.Aim
    if not cfg.Aim then targetPart = nil end
    b.Text = "AIMBOT : " .. (cfg.Aim and "ON" or "OFF")
end)

button("ENEMY ESP : ON", function(b)
    cfg.ESP = not cfg.ESP
    b.Text = "ENEMY ESP : " .. (cfg.ESP and "ON" or "OFF")
end)

button("WALL CHECK : ON", function(b)
    cfg.WallCheck = not cfg.WallCheck
    b.Text = "WALL CHECK : " .. (cfg.WallCheck and "ON" or "OFF")
end)

button("TARGET : HEAD", function(b)
    cfg.Head = not cfg.Head
    b.Text = "TARGET : " .. (cfg.Head and "HEAD" or "BODY")
    targetPart = nil
end)

button("FOV : 220", function(b)
    if cfg.FOV == 140 then
        cfg.FOV = 220
    elseif cfg.FOV == 220 then
        cfg.FOV = 320
    else
        cfg.FOV = 140
    end
    b.Text = "FOV : " .. cfg.FOV
    updateRing()
end)

button("SMOOTHNESS : 0.22", function(b)
    if cfg.Smooth == 0.22 then
        cfg.Smooth = 0.38
    elseif cfg.Smooth == 0.38 then
        cfg.Smooth = 0.65
    else
        cfg.Smooth = 0.22
    end
    b.Text = "SMOOTHNESS : " .. cfg.Smooth
end)

button("FOV CIRCLE : ON", function(b)
    cfg.ShowFOV = not cfg.ShowFOV
    b.Text = "FOV CIRCLE : " .. (cfg.ShowFOV and "ON" or "OFF")
    updateRing()
end)

local function enemy(p)
    if p == LP then return false end
    if LP.Team and p.Team and LP.Team == p.Team then
        return false
    end
    return true
end

local function getCharacter(p)
    local char = p.Character
    if not char then return nil end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return nil
    end
    return char, hum
end

local function getPart(char)
    if cfg.Head then
        return char:FindFirstChild("Head")
            or char:FindFirstChild("HumanoidRootPart")
    end

    return char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Head")
end

local function visible(camera, char, part)
    if not cfg.WallCheck then return true end

    local origin = camera.CFrame.Position
    local direction = part.Position - origin
    if direction.Magnitude < 0.01 then return true end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    params.FilterDescendantsInstances = {
        LP.Character or camera,
        camera
    }

    local result = Workspace:Raycast(origin, direction, params)

    return not result
        or result.Instance:IsDescendantOf(char)
end

local function findTarget(camera)
    local closest = cfg.FOV
    local best = nil
    local center = camera.ViewportSize / 2

    for _, p in ipairs(Players:GetPlayers()) do
        if enemy(p) then
            local char = getCharacter(p)
            if char then
                local part = getPart(char)
                if part then
                    local pos, onScreen =
                        camera:WorldToViewportPoint(part.Position)

                    if onScreen and pos.Z > 0 then
                        local d = (
                            Vector2.new(pos.X, pos.Y) - center
                        ).Magnitude

                        if d < closest and visible(camera, char, part) then
                            closest = d
                            best = part
                        end
                    end
                end
            end
        end
    end

    return best
end

local function destroyESP(p)
    local item = espObjects[p]
    if not item then return end

    if item.highlight then
        item.highlight:Destroy()
    end
    if item.billboard then
        item.billboard:Destroy()
    end

    espObjects[p] = nil
end

local function createESP(p, char, head)
    local h = make("Highlight", {
        Name = "ClientEnemyHighlight",
        Adornee = char,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        FillColor = Color3.fromRGB(255, 65, 80),
        OutlineColor = Color3.fromRGB(255, 100, 100),
        FillTransparency = 0.68,
        OutlineTransparency = 0
    }, char)

    local billboard = make("BillboardGui", {
        Name = "ClientEnemyLabel",
        Adornee = head,
        Size = UDim2.fromOffset(190, 32),
        StudsOffsetWorldSpace = Vector3.new(0, 2, 0),
        AlwaysOnTop = true,
        MaxDistance = cfg.ESPDistance
    }, pg)

    local txt = make("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(255, 125, 135),
        TextStrokeTransparency = 0.25,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextScaled = false
    }, billboard)

    espObjects[p] = {
        char = char,
        highlight = h,
        billboard = billboard,
        label = txt
    }
end

-- ESP updates are throttled for performance
local espTime = 0
connect(RunService.Heartbeat, function(dt)
    if not active then return end

    espTime = espTime + dt
    if espTime < 0.35 then return end
    espTime = 0

    for p in pairs(espObjects) do
        if not cfg.ESP or not p.Parent or not enemy(p) then
            destroyESP(p)
        end
    end

    if not cfg.ESP then return end

    for _, p in ipairs(Players:GetPlayers()) do
        if enemy(p) then
            local char, hum = getCharacter(p)
            local head = char and (
                char:FindFirstChild("Head")
                or char:FindFirstChild("HumanoidRootPart")
            )

            local root = LP.Character
                and LP.Character:FindFirstChild("HumanoidRootPart")

            local dist = math.huge
            if root and head then
                dist = (root.Position - head.Position).Magnitude
            end

            if not char or not head or dist > cfg.ESPDistance then
                destroyESP(p)
            else
                local item = espObjects[p]

                if item and item.char ~= char then
                    destroyESP(p)
                    item = nil
                end

                if not item then
                    createESP(p, char, head)
                    item = espObjects[p]
                end

                if item then
                    item.label.Text = string.format(
                        "%s | %d studs | %d HP",
                        p.DisplayName,
                        math.floor(dist),
                        math.floor(hum.Health)
                    )
                end
            end
        end
    end
end)

-- Aimbot runs after Roblox camera update
local aimTimer = 0

RunService:BindToRenderStep(
    bindName,
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if not active or not cfg.Aim then
            targetPart = nil
            return
        end

        local cam = Workspace.CurrentCamera
        if not cam or not getCharacter(LP) then
            targetPart = nil
            return
        end

        aimTimer = aimTimer + dt
        if aimTimer >= 0.10 then
            aimTimer = 0
            targetPart = findTarget(cam)
        end

        if targetPart and targetPart:IsDescendantOf(Workspace) then
            local origin = cam.CFrame.Position
            local direction = targetPart.Position - origin

            if direction.Magnitude > 0.01 then
                local goal = CFrame.lookAt(origin, targetPart.Position)
                cam.CFrame = cam.CFrame:Lerp(goal, cfg.Smooth)
            end
        end
    end
)

-- Draggable menu (mouse and touch)
local dragging = false
local dragInput
local dragStart
local startPos

connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragInput = input
        dragStart = input.Position
        startPos = main.Position
    end
end)

connect(UIS.InputChanged, function(input)
    if not dragging then return end

    local mouseMove =
        dragInput
        and dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement

    if input ~= dragInput and not mouseMove then return end

    local delta = input.Position - dragStart
    local cam = Workspace.CurrentCamera
    local view = cam and cam.ViewportSize or Vector2.new(1000, 700)

    local x = math.clamp(
        startPos.X.Offset + delta.X,
        0, math.max(0, view.X - main.AbsoluteSize.X)
    )
    local y = math.clamp(
        startPos.Y.Offset + delta.Y,
        0, math.max(0, view.Y - main.AbsoluteSize.Y)
    )

    main.Position = UDim2.fromOffset(x, y)
end)

connect(UIS.InputEnded, function(input)
    if input == dragInput then
        dragging = false
        dragInput = nil
    end
end)

local minimized = false
connect(minimize.MouseButton1Click, function()
    minimized = not minimized
    scroll.Visible = not minimized
    main.Size = UDim2.fromOffset(300, minimized and 46 or 355)
    minimize.Text = minimized and "+" or "-"
end)

local function stop()
    if not active then return end
    active = false

    RunService:UnbindFromRenderStep(bindName)

    for _, c in ipairs(connections) do
        c:Disconnect()
    end

    for p in pairs(espObjects) do
        destroyESP(p)
    end

    gui:Destroy()
    targetPart = nil

    if env.ENTRENCHED_STOP == stop then
        env.ENTRENCHED_STOP = nil
    end
end

env.ENTRENCHED_STOP = stop

button("UNLOAD SCRIPT", function()
    stop()
end)

updateRing()
print("[ENTRENCHED] Aimbot + ESP loaded")
