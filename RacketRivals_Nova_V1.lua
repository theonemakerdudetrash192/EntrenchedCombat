-- RACKET RIVALS | NOVA V1
-- Game: https://www.roblox.com/games/90906407195271/Racket-Rivals
-- Original, dependency-free client utility. No external loaders or webhooks.
-- Experimental: in-game input emulation, ball visibility and physical movement
-- may differ per server and executor. This does not override server hit checks.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer
if not LP then return end

local env = (type(getgenv) == "function" and getgenv()) or _G
pcall(function()
    if type(env.RR_NOVA_STOP) == "function" then env.RR_NOVA_STOP() end
end)

local active = true
local cfg = {
    AutoSwing = false,
    AutoFollow = false,
    AutoDash = false,
    BallESP = true,
    LandingGuide = true,
    CameraTrack = false,
    SpeedBoost = false,
    AntiAFK = false,
    SwingRadius = 17,
    SwingCooldown = 0.82,
    HoldDuration = 0.06,
    ChaseRadius = 65,
    Speed = 32,
}

local C = {
    bg = Color3.fromRGB(17, 19, 24),
    panel = Color3.fromRGB(31, 34, 42),
    border = Color3.fromRGB(68, 73, 86),
    text = Color3.fromRGB(237, 240, 247),
    muted = Color3.fromRGB(161, 168, 182),
    blue = Color3.fromRGB(90, 180, 255),
    aqua = Color3.fromRGB(111, 244, 219),
    red = Color3.fromRGB(255, 115, 135),
}

local connections = {}
local candidates = {}
local bestBall = nil
local lastSwing = -100
local lastDash = -100
local lastFollow = -100
local lastCheck = 0
local busySwing = false
local mouseIsDown = false
local mouseBackend = nil
local originalHumanoid = nil
local originalSpeed = nil
local uiStatus = "Checking input capabilities..."
local ballStatus = "BALL: scanning..."
local inputStatus = "Input: checking..."

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end

local function create(className, props, parent)
    local instance = Instance.new(className)
    for k, v in pairs(props or {}) do instance[k] = v end
    instance.Parent = parent
    return instance
end

local function note(message)
    uiStatus = tostring(message)
end

local function getRoot()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if hum and hum.Health > 0 and root then return hum, root end
    return nil, nil
end

-- Some executors expose mouse1press/release or keypress/release. Other
-- environments may expose VirtualInputManager, but game acceptance varies.
local vim = nil
pcall(function() vim = game:GetService("VirtualInputManager") end)

local function executorFunction(name)
    local v = type(env) == "table" and rawget(env, name)
    if type(v) == "function" then return v end
    local fallback = type(_G) == "table" and rawget(_G, name)
    if type(fallback) == "function" then return fallback end
    return nil
end

local function mouseClickState(down)
    local callable = executorFunction(down and "mouse1press" or "mouse1release")
    if callable then
        local ok = pcall(callable)
        if ok then return true, "executor mouse" end
    end
    if vim then
        local cam = Workspace.CurrentCamera
        local size = cam and cam.ViewportSize or Vector2.new(900, 600)
        local ok = pcall(function()
            vim:SendMouseButtonEvent(size.X * 0.5, size.Y * 0.5, 0, down, game, 0)
        end)
        if ok then return true, "virtual mouse" end
    end
    return false, "no compatible mouse input"
end

local function releaseMouse()
    if not mouseIsDown then return end
    mouseIsDown = false
    mouseClickState(false)
end

local function doSwing(force)
    if not active or busySwing then return false end
    if not force and os.clock() - lastSwing < cfg.SwingCooldown then return false end
    busySwing = true
    lastSwing = os.clock()
    task.spawn(function()
        local ok, method = mouseClickState(true)
        if ok then
            mouseIsDown = true
            mouseBackend = method
            inputStatus = "Input: " .. method
            task.wait(cfg.HoldDuration)
            releaseMouse()
            note("Swing input sent (hit not verified)")
        else
            -- Tool activation is a fallback for games that expose a Tool.
            local tool = LP.Character and LP.Character:FindFirstChildWhichIsA("Tool")
            local fallbackOK = false
            if tool then fallbackOK = pcall(function() tool:Activate() end) end
            inputStatus = fallbackOK and "Input: Tool.Activate" or "Input: unavailable"
            note(fallbackOK and "Tool activation requested" or "No usable swing input; check executor")
        end
        busySwing = false
    end)
    return true
end

local function keyInput(keyCode, hexCode, down)
    local functionName = down and "keypress" or "keyrelease"
    local callable = executorFunction(functionName)
    if callable then
        local ok = pcall(callable, hexCode)
        if ok then return true, "executor keyboard" end
    end
    if vim then
        local ok = pcall(function() vim:SendKeyEvent(down, keyCode, false, game) end)
        if ok then return true, "virtual keyboard" end
    end
    return false, "no compatible keyboard input"
end

local function tapKey(keyCode, hexCode, name)
    if not active then return end
    task.spawn(function()
        local ok, method = keyInput(keyCode, hexCode, true)
        if not ok then
            note(name .. ": no supported key input")
            inputStatus = "Input: unavailable"
            return
        end
        task.wait(0.06)
        keyInput(keyCode, hexCode, false)
        inputStatus = "Input: " .. method
        note(name .. " input sent (game acceptance unverified)")
    end)
end

local function looksLikeBall(part)
    if not part:IsA("BasePart") then return false end
    local name = part.Name:lower()
    local parentName = (part.Parent and part.Parent.Name or ""):lower()
    local recognized = name == "ball" or name == "shuttle" or name == "shuttlecock"
        or name == "birdie" or name == "projectile"
        or name:find("shuttle", 1, true) ~= nil
        or name:find("birdie", 1, true) ~= nil
        or (name == "main" and (parentName:find("shuttle", 1, true) or parentName:find("ball", 1, true)))
        or (name == "hitbox" and (parentName:find("shuttle", 1, true) or parentName:find("ball", 1, true)))
    if not recognized then return false end
    if part:FindFirstAncestorOfClass("Tool") then return false end
    local model = part:FindFirstAncestorOfClass("Model")
    if model and model:FindFirstChildOfClass("Humanoid") then return false end
    return true
end

local function indexPart(instance)
    if instance:IsA("BasePart") and looksLikeBall(instance) then
        candidates[instance] = true
    end
end

local function scanBalls()
    for _, d in ipairs(Workspace:GetDescendants()) do
        indexPart(d)
    end
end

local function findBall(root)
    local nearest, score = nil, math.huge
    for part in pairs(candidates) do
        if not part.Parent or not part:IsDescendantOf(Workspace) or not looksLikeBall(part) then
            candidates[part] = nil
        else
            local dist = root and (part.Position - root.Position).Magnitude or 0
            -- Prefer nearby fast-moving visible shuttle parts over generic stationary balls.
            local movingBonus = math.min(part.AssemblyLinearVelocity.Magnitude, 150) * 0.06
            local exactBonus = (part.Name:lower() == "shuttle" or part.Name:lower() == "shuttlecock") and 10 or 0
            local value = dist - movingBonus - exactBonus
            if value < score then nearest, score = part, value end
        end
    end
    return nearest
end

local function landingPoint(part)
    local p, v = part.Position, part.AssemblyLinearVelocity
    local g = Workspace.Gravity
    if v.Magnitude < 0.2 then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character or part, part }
    params.IgnoreWater = true
    local t = 0
    while t < 3 do
        local t1 = t + 0.14
        local a = p + v * t + Vector3.new(0, -0.5 * g * t * t, 0)
        local b = p + v * t1 + Vector3.new(0, -0.5 * g * t1 * t1, 0)
        local hit = Workspace:Raycast(a, b - a, params)
        if hit and hit.Normal.Y > 0.45 then return hit.Position + Vector3.new(0, 0.15, 0) end
        t = t1
    end
    return nil
end

local guiParent = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 12)
if not guiParent then return end
local old = guiParent:FindFirstChild("RacketRivalsNova")
if old then old:Destroy() end

local gui = create("ScreenGui", {
    Name = "RacketRivalsNova", IgnoreGuiInset = true,
    ResetOnSpawn = false, DisplayOrder = 991,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

local panel = create("Frame", {
    Name = "MainPanel", Position = UDim2.fromOffset(16, 75),
    Size = UDim2.fromOffset(306, 461), Active = true,
    BackgroundColor3 = C.bg, BorderSizePixel = 0, ZIndex = 10,
}, gui)
create("UICorner", { CornerRadius = UDim.new(0, 13) }, panel)
create("UIStroke", { Color = C.border, Thickness = 1.2 }, panel)

local header = create("Frame", {
    Size = UDim2.new(1, 0, 0, 51),
    BackgroundTransparency = 1, Active = true, ZIndex = 12,
}, panel)
create("TextLabel", {
    Position = UDim2.fromOffset(13, 5), Size = UDim2.new(1, -58, 0, 26),
    BackgroundTransparency = 1, Text = "RACKET RIVALS  /  NOVA",
    TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13,
}, header)
create("TextLabel", {
    Position = UDim2.fromOffset(13, 29), Size = UDim2.new(1, -60, 0, 16),
    BackgroundTransparency = 1, Text = "BALL TRACKING  •  SWING ASSIST  •  MOBILE",
    TextColor3 = C.muted, Font = Enum.Font.GothamMedium, TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13,
}, header)
local minimize = create("TextButton", {
    Size = UDim2.fromOffset(31, 29), Position = UDim2.new(1, -40, 0, 9),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "−",
    TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 20, ZIndex = 13,
}, header)
create("UICorner", { CornerRadius = UDim.new(0, 7) }, minimize)

local infoPanel = create("Frame", {
    Position = UDim2.fromOffset(10, 52), Size = UDim2.new(1, -20, 0, 76),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 11,
}, panel)
create("UICorner", { CornerRadius = UDim.new(0, 9) }, infoPanel)
local ballLabel = create("TextLabel", {
    Position = UDim2.fromOffset(9, 7), Size = UDim2.new(1, -18, 0, 20),
    BackgroundTransparency = 1, Text = "BALL: scanning...",
    TextColor3 = C.aqua, Font = Enum.Font.GothamBold, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12,
}, infoPanel)
local inputLabel = create("TextLabel", {
    Position = UDim2.fromOffset(9, 29), Size = UDim2.new(1, -18, 0, 18),
    BackgroundTransparency = 1, Text = "Input: checking...",
    TextColor3 = C.blue, Font = Enum.Font.GothamMedium, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12,
}, infoPanel)
local rangeLabel = create("TextLabel", {
    Position = UDim2.fromOffset(9, 50), Size = UDim2.new(1, -18, 0, 18),
    BackgroundTransparency = 1, Text = "AUTO SWING: OFF",
    TextColor3 = C.muted, Font = Enum.Font.GothamMedium, TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12,
}, infoPanel)

local scroll = create("ScrollingFrame", {
    Position = UDim2.fromOffset(10, 136), Size = UDim2.new(1, -20, 1, -168),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 4, ScrollBarImageColor3 = C.muted,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.fromOffset(0, 0), ZIndex = 12,
}, panel)
create("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
create("UIPadding", { PaddingBottom = UDim.new(0, 10) }, scroll)

local statusLabel = create("TextLabel", {
    Position = UDim2.new(0, 12, 1, -27), Size = UDim2.new(1, -24, 0, 22),
    BackgroundTransparency = 1, Text = "Loading...",
    TextColor3 = C.muted, Font = Enum.Font.GothamMedium,
    TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13,
}, panel)

local bubble = create("TextButton", {
    Size = UDim2.fromOffset(60, 43),
    Position = UDim2.new(0, 12, 0.42, 0),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
    Text = "RR", Font = Enum.Font.GothamBold, TextSize = 15,
    TextColor3 = C.blue, Visible = false, ZIndex = 20,
}, gui)
create("UICorner", { CornerRadius = UDim.new(0, 11) }, bubble)
create("UIStroke", { Color = C.blue, Thickness = 1.4 }, bubble)

local function addButton(label, action, check)
    local b = create("TextButton", {
        Size = UDim2.new(1, -7, 0, 37),
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
        TextColor3 = C.text, Text = label,
        Font = Enum.Font.GothamMedium, TextSize = 12, ZIndex = 13,
    }, scroll)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
    local function recolor()
        b.BackgroundColor3 = (check and check()) and Color3.fromRGB(32, 62, 79) or C.panel
    end
    recolor()
    connect(b.MouseButton1Click, function()
        if not active then return end
        local ok, err = pcall(action, b)
        if not ok then note("UI error: " .. tostring(err):sub(1, 55)) end
        recolor()
    end)
    return b
end

local function addToggle(title, key, onChanged)
    return addButton(title .. ": " .. (cfg[key] and "ON" or "OFF"), function(b)
        cfg[key] = not cfg[key]
        b.Text = title .. ": " .. (cfg[key] and "ON" or "OFF")
        if onChanged then onChanged(cfg[key]) end
    end, function() return cfg[key] end)
end

local guide = create("Part", {
    Name = "RR_Nova_LandingGuide", Anchored = true,
    CanCollide = false, CanTouch = false, CanQuery = false,
    Shape = Enum.PartType.Ball,
    Size = Vector3.new(1.6, 1.6, 1.6),
    Color = C.aqua, Material = Enum.Material.Neon,
    Transparency = 0.35, CastShadow = false,
    Position = Vector3.new(0, -3000, 0),
}, Workspace)
local ballHighlight = create("Highlight", {
    Name = "RR_Nova_BallESP", Enabled = false,
    FillColor = C.blue, OutlineColor = C.aqua,
    FillTransparency = 0.52, OutlineTransparency = 0.05,
    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
}, gui)
local ballBillboard = create("BillboardGui", {
    Name = "RR_Nova_BallLabel", AlwaysOnTop = true,
    Size = UDim2.fromOffset(140, 30),
    StudsOffsetWorldSpace = Vector3.new(0, 2, 0),
    MaxDistance = 500, Enabled = false,
}, gui)
local ballText = create("TextLabel", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    Text = "SHUTTLE", TextColor3 = C.aqua,
    Font = Enum.Font.GothamBold, TextSize = 12,
    TextStrokeTransparency = 0.25,
}, ballBillboard)

local function renderBall(ball, root, landing)
    local show = cfg.BallESP and ball ~= nil
    ballHighlight.Enabled = show
    ballHighlight.Adornee = show and ball or nil
    ballBillboard.Enabled = show
    ballBillboard.Adornee = show and ball or nil
    if show and root then
        ballText.Text = ("SHUTTLE | %d studs"):format(math.floor((ball.Position - root.Position).Magnitude))
    end
    guide.Transparency = cfg.LandingGuide and landing and 0.35 or 1
    if landing then guide.Position = landing + Vector3.new(0, 0.6, 0) end
end

local function resetSpeed()
    if originalHumanoid and originalHumanoid.Parent and originalSpeed then
        pcall(function() originalHumanoid.WalkSpeed = originalSpeed end)
    end
    originalHumanoid, originalSpeed = nil, nil
end

local function updateSpeed(hum)
    if not cfg.SpeedBoost then
        if originalHumanoid then resetSpeed() end
        return
    end
    if not hum then return end
    if originalHumanoid ~= hum then
        originalHumanoid, originalSpeed = hum, hum.WalkSpeed
    end
    if hum.WalkSpeed ~= cfg.Speed then
        pcall(function() hum.WalkSpeed = cfg.Speed end)
    end
end

addToggle("AUTO SWING", "AutoSwing", function(on)
    note(on and "Auto Swing enabled; waiting for a nearby shuttle" or "Auto Swing disabled")
end)
addToggle("AUTO FOLLOW BALL", "AutoFollow")
addToggle("AUTO DASH TO BALL", "AutoDash")
addToggle("BALL WALL ESP", "BallESP")
addToggle("LANDING GUIDE (ESTIMATE)", "LandingGuide")
addToggle("CAMERA TRACK BALL", "CameraTrack")
addToggle("SPEED BOOST", "SpeedBoost", function(on)
    if not on then resetSpeed() end
end)
addButton("RUN SPEED: " .. cfg.Speed, function(b)
    local speeds = { 32, 40, 56, 24 }
    local i = table.find(speeds, cfg.Speed) or 0
    cfg.Speed = speeds[i % #speeds + 1]
    b.Text = "RUN SPEED: " .. cfg.Speed
    note("Requested speed " .. cfg.Speed .. " (may reset server-side)")
end)
addButton("SWING RANGE: " .. cfg.SwingRadius, function(b)
    local ranges = { 17, 24, 32, 12 }
    local i = table.find(ranges, cfg.SwingRadius) or 0
    cfg.SwingRadius = ranges[i % #ranges + 1]
    b.Text = "SWING RANGE: " .. cfg.SwingRadius
end)
addButton("POWER CHARGE: SHORT", function(b)
    local values = { 0.06, 0.20, 0.42 }
    local i = table.find(values, cfg.HoldDuration) or 0
    cfg.HoldDuration = values[i % #values + 1]
    local label = cfg.HoldDuration == 0.06 and "SHORT" or (cfg.HoldDuration == 0.20 and "MEDIUM" or "LONG")
    b.Text = "POWER CHARGE: " .. label
end)
addToggle("ANTI-AFK", "AntiAFK")
addButton("SWING NOW", function() doSwing(true) end)
addButton("DASH NOW (Q)", function() tapKey(Enum.KeyCode.Q, 0x51, "Dash") end)
addButton("SET NOW (E)", function() tapKey(Enum.KeyCode.E, 0x45, "Set") end)
addButton("USE ABILITY (1)", function() tapKey(Enum.KeyCode.One, 0x31, "Ability") end)
addButton("AWAKENING (2)", function() tapKey(Enum.KeyCode.Two, 0x32, "Awakening") end)

local function unload()
    if not active then return end
    active = false
    releaseMouse()
    resetSpeed()
    pcall(function() ballHighlight:Destroy() end)
    pcall(function() ballBillboard:Destroy() end)
    pcall(function() guide:Destroy() end)
    for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep("RR_NOVA_CAMERA") end)
    gui:Destroy()
    if env.RR_NOVA_STOP == unload then env.RR_NOVA_STOP = nil end
end

env.RR_NOVA_STOP = unload
addButton("UNLOAD NOVA", unload)

local minimized = false
local function hideMenu(hidden)
    minimized = hidden
    panel.Visible = not hidden
    bubble.Visible = hidden
end
connect(minimize.MouseButton1Click, function() hideMenu(true) end)
connect(bubble.MouseButton1Click, function() hideMenu(false) end)
connect(UserInputService.InputBegan, function(input, focused)
    if not focused and input.KeyCode == Enum.KeyCode.RightShift then
        hideMenu(not minimized)
    end
end)

local dragging = false
local dragInput, dragStart, startPosition
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, dragInput, dragStart, startPosition = true, input, input.Position, panel.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    if not dragging or not dragStart then return end
    local byMouse = dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement
    if input ~= dragInput and not byMouse then return end
    local delta = input.Position - dragStart
    local cam = Workspace.CurrentCamera
    local view = cam and cam.ViewportSize or Vector2.new(1000, 700)
    panel.Position = UDim2.fromOffset(
        math.clamp(startPosition.X.Offset + delta.X, 0, math.max(0, view.X - panel.AbsoluteSize.X)),
        math.clamp(startPosition.Y.Offset + delta.Y, 0, math.max(0, view.Y - panel.AbsoluteSize.Y))
    )
end)
connect(UserInputService.InputEnded, function(input)
    if input == dragInput then dragging, dragInput = false, nil end
end)

connect(LP.Idled, function()
    if not active or not cfg.AntiAFK then return end
    pcall(function()
        local user = game:GetService("VirtualUser")
        user:CaptureController()
        local cam = Workspace.CurrentCamera
        user:ClickButton2(Vector2.new(), cam and cam.CFrame or CFrame.new())
    end)
end)

connect(Workspace.DescendantAdded, indexPart)
connect(Workspace.DescendantRemoving, function(inst)
    candidates[inst] = nil
    if inst == bestBall then bestBall = nil end
end)

scanBalls()
local tickAccumulator = 0
local landingAccumulator = 0
local lastLanding = nil
connect(RunService.Heartbeat, function(dt)
    if not active then return end
    tickAccumulator = tickAccumulator + dt
    landingAccumulator = landingAccumulator + dt
    if tickAccumulator < 0.13 then return end
    tickAccumulator = 0
    local ok, err = pcall(function()
        local hum, root = getRoot()
        updateSpeed(hum)
        local ball = findBall(root)
        bestBall = ball
        if ball and root then
            local distance = (ball.Position - root.Position).Magnitude
            ballStatus = string.format("BALL: %d studs | %s", math.floor(distance), ball.Name)
            if landingAccumulator > 0.30 then
                landingAccumulator = 0
                lastLanding = landingPoint(ball)
            end
            renderBall(ball, root, lastLanding)
            if cfg.AutoSwing and distance <= cfg.SwingRadius then
                doSwing(false)
            end
            if cfg.AutoFollow and hum and distance <= cfg.ChaseRadius then
                local destination = lastLanding or ball.Position
                local horizontal = Vector3.new(destination.X, root.Position.Y, destination.Z)
                if (horizontal - root.Position).Magnitude > 6 and os.clock() - lastFollow > 0.38 then
                    hum:MoveTo(horizontal)
                    lastFollow = os.clock()
                end
            end
            if cfg.AutoDash and cfg.AutoFollow and distance > 20
                and distance < cfg.ChaseRadius and os.clock() - lastDash > 3.0 then
                lastDash = os.clock()
                tapKey(Enum.KeyCode.Q, 0x51, "Auto Dash")
            end
        else
            lastLanding = nil
            ballStatus = "BALL: not detected"
            renderBall(nil, nil, nil)
        end
        ballLabel.Text = ballStatus
        inputLabel.Text = inputStatus
        rangeLabel.Text = cfg.AutoSwing and ("AUTO SWING: ON | RANGE " .. cfg.SwingRadius) or "AUTO SWING: OFF"
        statusLabel.Text = uiStatus
    end)
    if not ok then note("Update error: " .. tostring(err):sub(1, 60)) end
end)

RunService:BindToRenderStep("RR_NOVA_CAMERA", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not active or not cfg.CameraTrack then return end
    local cam = Workspace.CurrentCamera
    if cam and bestBall and bestBall.Parent then
        local c = cam.CFrame
        local desired = CFrame.lookAt(c.Position, bestBall.Position)
        cam.CFrame = c:Lerp(desired, 1 - math.exp(-7 * math.min(dt, 0.15)))
    end
end)

if game.PlaceId ~= 90906407195271 then
    note("Not the main Racket Rivals place; modes may have another PlaceId")
else
    note("Ready. Toggle Auto Swing when you join a rally")
end
inputStatus = (executorFunction("mouse1press") or vim) and "Input: supported interface detected" or "Input: limited / not detected"
print("[RACKET RIVALS NOVA V1] Loaded. Swing and auto-hit depend on game input acceptance.")
