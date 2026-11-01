-- ENTRENCHED COMBAT V2 | client-side aim assist + enemy ESP
-- No external UI libraries, HTTP dependencies, or Drawing API.
-- Game-specific weapon/server hit registration is not controlled by this script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local env = (type(getgenv) == "function" and getgenv()) or _G
pcall(function()
    if type(env.ENTRENCHED_STOP) == "function" then
        env.ENTRENCHED_STOP()
    end
end)

local alive = true
local cfg = {
    Aim = false,
    AimAtHead = true,
    WallCheck = true,
    LockTarget = true,
    FOV = 220,             -- screen pixels, measured from viewport center
    AimSpeed = 14,         -- exponential smoothing; frame-rate independent
    MaxDistance = 1400,    -- studs
    Prediction = false,   -- approximate velocity lead, not ballistic prediction
    LeadSeconds = 0.09,
    ESP = true,
    Highlights = true,
    Boxes = true,
    Tracers = false,
    Names = true,
    ShowFOV = true
}

local allConnections = {}
local espByPlayer = {}
local currentTarget = nil
local chosenPart = nil
local lastAcquire = 0
local renderBindName = "ENTRENCHED_COMBAT_V2_" .. LocalPlayer.UserId
local espElapsed = 0
local lockedName = "NONE"
local espCount = 0
local statusLabel

local function listen(signal, fn)
    local c = signal:Connect(fn)
    table.insert(allConnections, c)
    return c
end

local function new(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function rounded(instance, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius) }, instance)
end

local palette = {
    background = Color3.fromRGB(17, 19, 23),
    panel = Color3.fromRGB(29, 32, 39),
    button = Color3.fromRGB(38, 42, 50),
    text = Color3.fromRGB(242, 244, 247),
    muted = Color3.fromRGB(163, 170, 182),
    green = Color3.fromRGB(109, 230, 170),
    red = Color3.fromRGB(255, 106, 118),
    accent = Color3.fromRGB(90, 152, 248)
}

local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    or LocalPlayer:WaitForChild("PlayerGui", 12)
if not playerGui then return end

local gui = new("ScreenGui", {
    Name = "EntrenchedCombatV2",
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    DisplayOrder = 950,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, playerGui)
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)

local ring = new("Frame", {
    Name = "AimFOVRing",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(cfg.FOV * 2, cfg.FOV * 2),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 2
}, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
new("UIStroke", {
    Thickness = 1.35,
    Transparency = 0.35,
    Color = palette.accent
}, ring)

local centerDot = new("Frame", {
    Name = "LockedTargetMarker",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(9, 9),
    BackgroundColor3 = palette.red,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 4
}, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, centerDot)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1 }, centerDot)

local screen = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(400, 700)
local menuHeight = math.min(420, math.max(290, screen.Y - 100))
local menuWidth = math.min(304, math.max(250, screen.X - 25))
local main = new("Frame", {
    Name = "Panel",
    Size = UDim2.fromOffset(menuWidth, menuHeight),
    Position = UDim2.fromOffset(14, 72),
    BackgroundColor3 = palette.background,
    BorderSizePixel = 0,
    Active = true,
    ClipsDescendants = true,
    ZIndex = 10
}, gui)
rounded(main, 12)
new("UIStroke", {
    Color = Color3.fromRGB(75, 80, 91),
    Thickness = 1,
    Transparency = 0.15
}, main)

local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 52),
    BackgroundTransparency = 1,
    Active = true,
    ZIndex = 11
}, main)
new("TextLabel", {
    BackgroundTransparency = 1,
    Text = "ENTRENCHED   /   V2",
    Position = UDim2.fromOffset(12, 5),
    Size = UDim2.new(1, -60, 0, 24),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = palette.text,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    ZIndex = 12
}, header)
statusLabel = new("TextLabel", {
    BackgroundTransparency = 1,
    Text = "AIM OFF  •  ESP 0  •  LOCK NONE",
    Position = UDim2.fromOffset(13, 28),
    Size = UDim2.new(1, -55, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = palette.muted,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 12
}, header)
local collapse = new("TextButton", {
    Size = UDim2.fromOffset(32, 30),
    Position = UDim2.new(1, -42, 0, 11),
    BackgroundColor3 = palette.panel,
    BorderSizePixel = 0,
    Text = "−",
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    TextColor3 = palette.text,
    ZIndex = 13
}, header)
rounded(collapse, 7)

local scroll = new("ScrollingFrame", {
    Position = UDim2.fromOffset(11, 54),
    Size = UDim2.new(1, -22, 1, -64),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = palette.accent,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ZIndex = 11
}, main)
new("UIPadding", {
    PaddingBottom = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 5)
}, scroll)
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6)
}, scroll)

local order = 0
local function section(title)
    order = order + 1
    return new("TextLabel", {
        LayoutOrder = order,
        BackgroundTransparency = 1,
        Text = title,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = palette.accent,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        Size = UDim2.new(1, -6, 0, 22),
        ZIndex = 12
    }, scroll)
end

local function actionButton(labelFunction, callback)
    order = order + 1
    local b = new("TextButton", {
        LayoutOrder = order,
        BackgroundColor3 = palette.button,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -6, 0, 35),
        TextColor3 = palette.text,
        Text = labelFunction(),
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        ZIndex = 12
    }, scroll)
    rounded(b, 7)
    listen(b.MouseButton1Click, function()
        if not alive then return end
        callback()
        b.Text = labelFunction()
    end)
    return b
end

local function toggle(label, key)
    local b = actionButton(function()
        return label .. ": " .. (cfg[key] and "ON" or "OFF")
    end, function()
        cfg[key] = not cfg[key]
        if key == "Aim" and not cfg.Aim then
            currentTarget, chosenPart = nil, nil
        end
    end)
    return b
end

section("AIM ASSIST")
toggle("AIM ASSIST", "Aim")
toggle("VISIBILITY CHECK", "WallCheck")
toggle("TARGET LOCK", "LockTarget")
actionButton(function() return "HITBOX: " .. (cfg.AimAtHead and "HEAD" or "BODY") end, function()
    cfg.AimAtHead = not cfg.AimAtHead
    currentTarget, chosenPart = nil, nil
end)
actionButton(function() return "FOV RADIUS: " .. cfg.FOV .. " PX" end, function()
    local values = { 130, 180, 220, 300, 390 }
    for i, v in ipairs(values) do
        if cfg.FOV == v then
            cfg.FOV = values[(i % #values) + 1]
            break
        end
    end
end)
actionButton(function() return "AIM SPEED: " .. cfg.AimSpeed end, function()
    local values = { 8, 14, 22, 35 }
    for i, v in ipairs(values) do
        if cfg.AimSpeed == v then
            cfg.AimSpeed = values[(i % #values) + 1]
            break
        end
    end
end)
actionButton(function() return "MAX RANGE: " .. cfg.MaxDistance .. " STUDS" end, function()
    local values = { 650, 1000, 1400, 2200 }
    for i, v in ipairs(values) do
        if cfg.MaxDistance == v then
            cfg.MaxDistance = values[(i % #values) + 1]
            break
        end
    end
end)
toggle("VELOCITY LEAD (EXPERIMENTAL)", "Prediction")

section("VISUAL ESP")
toggle("ENEMY ESP", "ESP")
toggle("WALL HIGHLIGHTS", "Highlights")
toggle("2D BOXES", "Boxes")
toggle("SNAPLINES", "Tracers")
toggle("NAME / HP / RANGE", "Names")
toggle("FOV CIRCLE", "ShowFOV")

section("CONTROLS")
actionButton(function() return "CLOSE SCRIPT / UNLOAD" end, function()
    if type(env.ENTRENCHED_STOP) == "function" then
        env.ENTRENCHED_STOP()
    end
end)

local openButton = new("TextButton", {
    Name = "OpenMenu",
    Size = UDim2.fromOffset(52, 33),
    Position = UDim2.fromOffset(14, 75),
    Text = "ENT",
    TextColor3 = palette.text,
    BackgroundColor3 = palette.panel,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    Visible = false,
    ZIndex = 21
}, gui)
rounded(openButton, 9)
new("UIStroke", { Color = palette.accent, Thickness = 1 }, openButton)

local menuOpen = true
local function setMenuOpen(value)
    menuOpen = value
    main.Visible = value
    openButton.Visible = not value
end
listen(collapse.MouseButton1Click, function() setMenuOpen(false) end)
listen(openButton.MouseButton1Click, function() setMenuOpen(true) end)

-- Drag by header (mouse and touch). The scrolling area remains freely scrollable.
local dragging = false
local draggingInput = nil
local startInputPosition = nil
local startMenuPosition = nil
listen(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        draggingInput = input
        startInputPosition = input.Position
        startMenuPosition = main.Position
    end
end)
listen(UserInputService.InputChanged, function(input)
    if not dragging or not startInputPosition then return end
    if draggingInput.UserInputType == Enum.UserInputType.Touch then
        if input ~= draggingInput then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end

    local offset = input.Position - startInputPosition
    local cam = Workspace.CurrentCamera
    local viewport = cam and cam.ViewportSize or Vector2.new(420, 800)
    local x = math.clamp(startMenuPosition.X.Offset + offset.X, 0, math.max(0, viewport.X - main.AbsoluteSize.X))
    local y = math.clamp(startMenuPosition.Y.Offset + offset.Y, 0, math.max(0, viewport.Y - main.AbsoluteSize.Y))
    main.Position = UDim2.fromOffset(x, y)
end)
listen(UserInputService.InputEnded, function(input)
    if not dragging then return end
    if input == draggingInput or (
        draggingInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1
    ) then
        dragging = false
        draggingInput = nil
    end
end)
listen(UserInputService.InputBegan, function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setMenuOpen(not menuOpen)
    end
end)

local function isEnemy(player)
    if not player or player == LocalPlayer or player.Parent ~= Players then return false end
    if LocalPlayer.Team and player.Team and LocalPlayer.Team == player.Team then return false end
    if not LocalPlayer.Neutral and not player.Neutral and
        LocalPlayer.TeamColor == player.TeamColor then
        return false
    end
    return true
end

local function livingCharacter(player)
    local char = player and player.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return char, hum
end

local function aimPart(char)
    if cfg.AimAtHead then
        return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Head")
end

local function projectedPoint(camera, worldPoint)
    local screenPosition, onScreen = camera:WorldToViewportPoint(worldPoint)
    return Vector2.new(screenPosition.X, screenPosition.Y), onScreen and screenPosition.Z > 0
end

local function predictedPosition(part)
    local p = part.Position
    if cfg.Prediction then
        p = p + part.AssemblyLinearVelocity * cfg.LeadSeconds
    end
    return p
end

local function inSight(camera, char, position)
    if not cfg.WallCheck then return true end
    local start = camera.CFrame.Position
    local direction = position - start
    if direction.Magnitude < 0.05 then return true end
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character or camera, camera }
    rayParams.IgnoreWater = true
    local result = Workspace:Raycast(start, direction, rayParams)
    return not result or result.Instance:IsDescendantOf(char)
end

local function targetInfo(player, camera)
    if not isEnemy(player) then return nil end
    local character = livingCharacter(player)
    if not character then return nil end
    local part = aimPart(character)
    if not part or not part:IsA("BasePart") then return nil end
    local point = predictedPosition(part)
    if (camera.CFrame.Position - point).Magnitude > cfg.MaxDistance then return nil end
    local onView, visibleOnScreen = projectedPoint(camera, point)
    if not visibleOnScreen then return nil end
    local radius = (onView - camera.ViewportSize / 2).Magnitude
    if radius > cfg.FOV then return nil end
    if not inSight(camera, character, point) then return nil end
    return { player = player, part = part, point = point, score = radius }
end

local function findTarget(camera)
    local best = nil
    for _, p in ipairs(Players:GetPlayers()) do
        local entry = targetInfo(p, camera)
        if entry and (not best or entry.score < best.score) then
            best = entry
        end
    end
    if cfg.LockTarget and currentTarget then
        local current = targetInfo(currentTarget, camera)
        if current and (not best or current.score <= best.score * 1.35 + 12) then
            return current
        end
    end
    return best
end

local function removeESP(player)
    local record = espByPlayer[player]
    if not record then return end
    for _, object in ipairs({ record.highlight, record.billboard, record.box, record.tracer }) do
        if object then pcall(function() object:Destroy() end) end
    end
    espByPlayer[player] = nil
end

local function createESP(player, char, head)
    local highlight = new("Highlight", {
        Name = "EntrenchedEnemyGlowV2",
        Adornee = char,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        FillColor = palette.red,
        OutlineColor = Color3.fromRGB(255, 212, 114),
        FillTransparency = 0.78,
        OutlineTransparency = 0,
        Enabled = true
    }, char)
    local billboard = new("BillboardGui", {
        Name = "EntrenchedEnemyTagV2",
        Adornee = head,
        AlwaysOnTop = true,
        Size = UDim2.fromOffset(205, 35),
        StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0),
        MaxDistance = cfg.MaxDistance
    }, playerGui)
    local label = new("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        TextColor3 = palette.red,
        TextStrokeColor3 = Color3.fromRGB(8, 9, 11),
        TextStrokeTransparency = 0.1,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Text = "",
    }, billboard)
    local box = new("Frame", {
        Name = "EnemyBoxV2",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 3
    }, gui)
    new("UIStroke", { Color = palette.red, Thickness = 1.4 }, box)
    local tracer = new("Frame", {
        Name = "EnemySnaplineV2",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = palette.red,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(1, 1),
        Visible = false,
        ZIndex = 2
    }, gui)
    espByPlayer[player] = {
        character = char,
        highlight = highlight,
        billboard = billboard,
        label = label,
        box = box,
        tracer = tracer
    }
    return espByPlayer[player]
end

local function refreshESP(camera)
    espCount = 0
    for player in pairs(espByPlayer) do
        if not cfg.ESP or not isEnemy(player) then removeESP(player) end
    end
    if not cfg.ESP then return end

    local origin = camera.CFrame.Position
    local viewport = camera.ViewportSize
    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) then
            local char, hum = livingCharacter(player)
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local head = char and (char:FindFirstChild("Head") or root)
            local dist = root and (origin - root.Position).Magnitude or math.huge
            if not root or not head or dist > cfg.MaxDistance then
                removeESP(player)
            else
                espCount = espCount + 1
                local rec = espByPlayer[player]
                if rec and rec.character ~= char then
                    removeESP(player)
                    rec = nil
                end
                if not rec then rec = createESP(player, char, head) end
                rec.highlight.Enabled = cfg.Highlights
                rec.billboard.Enabled = cfg.Names
                rec.billboard.Adornee = head
                rec.billboard.MaxDistance = cfg.MaxDistance
                if cfg.Names then
                    rec.label.Text = string.format("%s  |  %d HP  |  %d studs",
                        player.DisplayName, math.floor(hum.Health + 0.5), math.floor(dist + 0.5))
                end

                local headScreen, headVisible = projectedPoint(camera, head.Position + Vector3.new(0, 0.5, 0))
                local footScreen, footVisible = projectedPoint(camera, root.Position - Vector3.new(0, 3, 0))
                local rootScreen, rootVisible = projectedPoint(camera, root.Position)
                local canDraw = headVisible and footVisible and rootVisible
                if cfg.Boxes and canDraw then
                    local height = math.clamp(math.abs(footScreen.Y - headScreen.Y), 12, viewport.Y * 0.85)
                    local width = height * 0.52
                    rec.box.Size = UDim2.fromOffset(width, height)
                    rec.box.Position = UDim2.fromOffset(rootScreen.X - width / 2, headScreen.Y)
                    rec.box.Visible = true
                else
                    rec.box.Visible = false
                end

                if cfg.Tracers and rootVisible then
                    local start = Vector2.new(viewport.X * 0.5, viewport.Y - 7)
                    local delta = rootScreen - start
                    rec.tracer.Position = UDim2.fromOffset(start.X, start.Y)
                    rec.tracer.Size = UDim2.fromOffset(delta.Magnitude, 1.5)
                    rec.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                    rec.tracer.Visible = true
                else
                    rec.tracer.Visible = false
                end
            end
        end
    end
end

listen(Players.PlayerRemoving, function(player)
    removeESP(player)
    if currentTarget == player then currentTarget, chosenPart = nil, nil end
end)

local function unload()
    if not alive then return end
    alive = false
    RunService:UnbindFromRenderStep(renderBindName)
    for _, c in ipairs(allConnections) do c:Disconnect() end
    for player in pairs(espByPlayer) do removeESP(player) end
    gui:Destroy()
    currentTarget, chosenPart = nil, nil
    if env.ENTRENCHED_STOP == unload then env.ENTRENCHED_STOP = nil end
end
env.ENTRENCHED_STOP = unload

local frames = 0
local elapsed = 0
RunService:BindToRenderStep(renderBindName, Enum.RenderPriority.Camera.Value + 2, function(dt)
    if not alive then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end
    dt = math.clamp(dt, 0, 0.1)
    ring.Visible = cfg.ShowFOV
    ring.Size = UDim2.fromOffset(cfg.FOV * 2, cfg.FOV * 2)
    centerDot.Visible = false

    elapsed = elapsed + dt
    if cfg.Aim and livingCharacter(LocalPlayer) then
        lastAcquire = lastAcquire + dt
        if lastAcquire > 0.085 then
            lastAcquire = 0
            local best = findTarget(camera)
            currentTarget = best and best.player or nil
            chosenPart = best and best.part or nil
        end
        if currentTarget and chosenPart and chosenPart:IsDescendantOf(Workspace) then
            local point = predictedPosition(chosenPart)
            local hit, isOnScreen = projectedPoint(camera, point)
            if isOnScreen then
                centerDot.Position = UDim2.fromOffset(hit.X, hit.Y)
                centerDot.Visible = true
                local origin = camera.CFrame.Position
                if (point - origin).Magnitude > 0.05 then
                    local goal = CFrame.lookAt(origin, point)
                    local alpha = 1 - math.exp(-cfg.AimSpeed * dt)
                    camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(alpha, 0, 1))
                end
            end
        end
    else
        currentTarget, chosenPart = nil, nil
        lastAcquire = 0
    end

    espElapsed = espElapsed + dt
    if espElapsed >= 0.115 then
        espElapsed = 0
        refreshESP(camera)
        lockedName = currentTarget and currentTarget.DisplayName or "NONE"
        statusLabel.Text = string.format("AIM %s  •  ESP %d  •  LOCK %s",
            cfg.Aim and "ON" or "OFF", espCount, lockedName)
    end
end)

print("[ENTRENCHED V2] Loaded. RightShift toggles menu; ENT button reopens it.")
