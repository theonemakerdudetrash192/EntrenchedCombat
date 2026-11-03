-- SPIDER MOBILE | Roblox Luau LocalScript
-- Camera-aimed webs + rope swing + zip + boost + wall climb.
-- Intended for experiences where client-side movement scripts are allowed.
-- Put in StarterPlayer > StarterPlayerScripts in your own experience,
-- or run in a compatible client Luau environment.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CONFIG = {
    WebRange = 280,
    MinWebDistance = 15,
    SwingAcceleration = 66,
    GravityAssist = 0.12,
    MaxSpeed = 155,
    ClimbSpeed = 31,
    BoostCooldown = 1.0,
    ZipCooldown = 0.45,
}

-- Removing an older UI also makes its heartbeat stop itself.
local oldGui = playerGui:FindFirstChild("SpiderMobileUI_v1")
if oldGui then oldGui:Destroy() end

local state = {
    character = nil,
    humanoid = nil,
    root = nil,
    anchor = nil,
    rope = nil,
    webBeam = nil,
    handAttachment = nil,
    swingForce = nil,
    climbing = false,
    zipActive = false,
    lastBoost = -100,
    lastZip = -100,
    stopped = false,
}
local connections = {}
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpiderMobileUI_v1"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 90
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Controls"
panel.Size = UDim2.fromOffset(181, 219)
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -12, 1, -202)
panel.BackgroundColor3 = Color3.fromRGB(18, 23, 37)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 15)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(85, 126, 185)
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local header = Instance.new("TextLabel")
header.Name = "DragHandle"
header.Size = UDim2.new(1, -37, 0, 31)
header.Position = UDim2.fromOffset(8, 2)
header.BackgroundTransparency = 1
header.Text = "SPIDER MOBILE  ☰"
header.TextColor3 = Color3.fromRGB(238, 244, 255)
header.Font = Enum.Font.GothamBold
header.TextScaled = true
header.TextSize = 13
header.Parent = panel

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(25, 25)
close.Position = UDim2.new(1, -30, 0, 5)
close.BackgroundColor3 = Color3.fromRGB(100, 34, 52)
close.Text = "×"
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBold
close.TextSize = 20
close.Parent = panel
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = close

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 22)
status.Position = UDim2.fromOffset(8, 32)
status.BackgroundTransparency = 1
status.Text = "AIM AT A BUILDING"
status.TextColor3 = Color3.fromRGB(168, 211, 255)
status.TextSize = 11
status.TextScaled = true
status.Font = Enum.Font.GothamSemibold
status.Parent = panel

local buttons = {}
local function makeButton(name, label, x, y, normalColor)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = UDim2.fromOffset(79, 70)
    button.Position = UDim2.fromOffset(x, y)
    button.BackgroundColor3 = normalColor
    button.BorderSizePixel = 0
    button.Text = label
    button.TextWrapped = true
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 15
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true
    button.Parent = panel
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 13)
    corner.Parent = button
    buttons[name] = button
    return button
end
local webButton   = makeButton("Web",   "WEB",        9, 58, Color3.fromRGB(35, 99, 165))
local zipButton   = makeButton("Zip",   "ZIP",       93, 58, Color3.fromRGB(39, 122, 139))
local boostButton = makeButton("Boost", "BOOST",      9, 133, Color3.fromRGB(152, 71, 49))
local climbButton = makeButton("Climb", "CLIMB",     93, 133, Color3.fromRGB(92, 65, 150))

-- Small camera aiming reticle, above the normal mobile buttons.
local reticle = Instance.new("Frame")
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.44)
reticle.Size = UDim2.fromOffset(9, 9)
reticle.BackgroundColor3 = Color3.fromRGB(250, 253, 255)
reticle.BorderSizePixel = 0
reticle.Parent = gui
local crossCorner = Instance.new("UICorner")
crossCorner.CornerRadius = UDim.new(1, 0)
crossCorner.Parent = reticle
local crossStroke = Instance.new("UIStroke")
crossStroke.Color = Color3.fromRGB(24, 33, 49)
crossStroke.Thickness = 1.5
crossStroke.Parent = reticle

local function setStatus(message)
    if status.Parent then status.Text = message end
end
local function getCamera()
    return Workspace.CurrentCamera
end
local function isReady()
    return state.root ~= nil and state.root.Parent ~= nil
       and state.humanoid ~= nil and state.humanoid.Health > 0
end
local function capVelocity(velocity, maxSpeed)
    if velocity.Magnitude > maxSpeed then
        return velocity.Unit * maxSpeed
    end
    return velocity
end
local function horizontalLook()
    local cam = getCamera()
    if not cam then return Vector3.new(0, 0, -1) end
    local look = cam.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    return (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, -1)
end

local function clearWeb()
    -- Destroy constraints before their attachments / parts.
    for _, key in ipairs({"rope", "webBeam", "swingForce", "handAttachment", "anchor"}) do
        local object = state[key]
        if object then
            object:Destroy()
            state[key] = nil
        end
    end
    state.zipActive = false
    webButton.Text = "WEB"
    webButton.BackgroundColor3 = Color3.fromRGB(35, 99, 165)
end

local function releaseWeb(launch)
    if not state.anchor then return end
    local root = state.root
    clearWeb()
    if launch and root and root.Parent then
        root.AssemblyLinearVelocity = capVelocity(
            root.AssemblyLinearVelocity + horizontalLook() * 12 + Vector3.new(0, 9, 0),
            CONFIG.MaxSpeed
        )
    end
    setStatus("WEB RELEASED")
end

local function getTarget()
    local camera = getCamera()
    if not camera or not isReady() then return nil end
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {state.character}
    rayParams.IgnoreWater = true

    -- Test the aim direction first, then a few nearby upward shots for phone aim assist.
    local aimRay = camera:ViewportPointToRay(
        camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.44
    )
    local origin = aimRay.Origin
    local forward = aimRay.Direction
    local up = camera.CFrame.UpVector
    local right = camera.CFrame.RightVector
    local rays = {
        forward,
        (forward + up * 0.13).Unit,
        (forward + right * 0.12).Unit,
        (forward - right * 0.12).Unit,
        (forward + up * 0.27).Unit,
    }
    for _, direction in ipairs(rays) do
        local result = Workspace:Raycast(origin, direction * CONFIG.WebRange, rayParams)
        if result then
            local target = result.Position
            local distance = (target - state.root.Position).Magnitude
            if distance >= CONFIG.MinWebDistance and target.Y >= state.root.Position.Y - 5 then
                return target
            end
        end
    end
    return nil
end

local function shootWeb()
    if not isReady() then setStatus("WAIT FOR CHARACTER"); return false end
    if state.anchor then releaseWeb(true); return true end
    local target = getTarget()
    if not target then setStatus("NO BUILDING IN RANGE"); return false end

    state.climbing = false
    climbButton.Text = "CLIMB"
    local root = state.root
    local distance = (target - root.Position).Magnitude

    local anchor = Instance.new("Part")
    anchor.Name = "LocalSpiderWebAnchor"
    anchor.Anchored = true
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.25, 0.25, 0.25)
    anchor.CanCollide = false
    anchor.CanTouch = false
    anchor.CanQuery = false
    anchor.CFrame = CFrame.new(target)
    anchor.Parent = Workspace
    state.anchor = anchor

    local anchorAttachment = Instance.new("Attachment")
    anchorAttachment.Parent = anchor
    local hand = Instance.new("Attachment")
    hand.Name = "SpiderWebOrigin"
    hand.Position = Vector3.new(0.8, 0.1, -0.2)
    hand.Parent = root
    state.handAttachment = hand

    local rope = Instance.new("RopeConstraint")
    rope.Attachment0 = hand
    rope.Attachment1 = anchorAttachment
    rope.Length = math.max(12, distance * 0.97)
    rope.Visible = false
    rope.Restitution = 0.05
    rope.Parent = root
    state.rope = rope

    local beam = Instance.new("Beam")
    beam.Attachment0 = hand
    beam.Attachment1 = anchorAttachment
    beam.Width0 = 0.11
    beam.Width1 = 0.07
    beam.FaceCamera = true
    beam.LightEmission = 0.4
    beam.Color = ColorSequence.new(Color3.fromRGB(243, 250, 255))
    beam.Segments = 2
    beam.Parent = root
    state.webBeam = beam

    local force = Instance.new("VectorForce")
    force.Attachment0 = hand
    force.ApplyAtCenterOfMass = true
    force.RelativeTo = Enum.ActuatorRelativeTo.World
    force.Force = Vector3.zero
    force.Parent = root
    state.swingForce = force

    state.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    root.AssemblyLinearVelocity = capVelocity(
        root.AssemblyLinearVelocity + horizontalLook() * 15 + Vector3.new(0, 17, 0),
        CONFIG.MaxSpeed
    )
    webButton.Text = "RELEASE"
    webButton.BackgroundColor3 = Color3.fromRGB(178, 53, 74)
    setStatus("SWINGING | ZIP FOR SPEED")
    return true
end

local function zip()
    if not isReady() then return end
    local now = os.clock()
    if now - state.lastZip < CONFIG.ZipCooldown then return end
    state.lastZip = now
    if not state.anchor and not shootWeb() then return end
    if not state.anchor or not state.rope then return end
    local delta = state.anchor.Position - state.root.Position
    local distance = delta.Magnitude
    if distance < 8 then return end
    state.climbing = false
    state.zipActive = true
    state.rope.WinchEnabled = true
    state.rope.WinchForce = math.max(25000, state.root.AssemblyMass * 2400)
    state.rope.WinchResponsiveness = 50
    state.rope.WinchSpeed = 95
    state.rope.WinchTarget = math.max(7, distance * 0.35)
    state.root.AssemblyLinearVelocity = capVelocity(
        delta.Unit * math.clamp(distance * 1.2, 85, 130) + Vector3.new(0, 8, 0),
        CONFIG.MaxSpeed
    )
    setStatus("WEB ZIP!")
end

local function boost()
    if not isReady() then return end
    local now = os.clock()
    if now - state.lastBoost < CONFIG.BoostCooldown then return end
    state.lastBoost = now
    state.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    state.root.AssemblyLinearVelocity = capVelocity(
        state.root.AssemblyLinearVelocity + horizontalLook() * 51 + Vector3.new(0, 26, 0),
        CONFIG.MaxSpeed
    )
    setStatus("BOOST!")
end

local function findWall()
    if not isReady() then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {state.character}
    local direction = horizontalLook()
    local result = Workspace:Raycast(state.root.Position, direction * 5.5, params)
    if not result then
        result = Workspace:Raycast(state.root.Position, state.root.CFrame.LookVector * 5.5, params)
    end
    return result
end

local function setClimbing(enabled)
    if enabled then
        if not isReady() then setStatus("WAIT FOR CHARACTER"); return end
        if state.anchor then clearWeb() end
        if not findWall() then
            setStatus("FACE A WALL FIRST")
            return
        end
    end
    state.climbing = enabled
    climbButton.Text = enabled and "STOP\nCLIMB" or "CLIMB"
    climbButton.BackgroundColor3 = enabled
        and Color3.fromRGB(149, 89, 208) or Color3.fromRGB(92, 65, 150)
    setStatus(enabled and "WALL CLIMBING" or "AIM AT A BUILDING")
end

connect(webButton.Activated, shootWeb)
connect(zipButton.Activated, zip)
connect(boostButton.Activated, boost)
connect(climbButton.Activated, function() setClimbing(not state.climbing) end)

-- Drag by the title on a touchscreen; buttons stay separate from the drag handle.
local dragInput, dragStart, dragPosition
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
        dragStart = input.Position
        dragPosition = panel.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    if dragInput and input == dragInput and dragStart and dragPosition then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(
            dragPosition.X.Scale, dragPosition.X.Offset + delta.X,
            dragPosition.Y.Scale, dragPosition.Y.Offset + delta.Y
        )
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input == dragInput then dragInput = nil end
end)

local function onCharacter(character)
    clearWeb()
    state.climbing = false
    climbButton.Text = "CLIMB"
    climbButton.BackgroundColor3 = Color3.fromRGB(92, 65, 150)
    state.character = character
    state.root = character:WaitForChild("HumanoidRootPart", 10)
    state.humanoid = character:WaitForChild("Humanoid", 10)
    setStatus("AIM AT A BUILDING")
end
connect(player.CharacterAdded, onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

local function stop()
    if state.stopped then return end
    state.stopped = true
    clearWeb()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    if gui.Parent then gui:Destroy() end
end
connect(close.Activated, stop)

connect(RunService.Heartbeat, function(dt)
    if state.stopped then return end
    if not gui.Parent then stop(); return end
    if not isReady() then return end
    local root = state.root

    if state.climbing then
        local wall = findWall()
        if not wall then
            setClimbing(false)
        else
            state.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
            root.AssemblyLinearVelocity = Vector3.new(0, CONFIG.ClimbSpeed, 0)
                - wall.Normal * 7
        end
    end

    if state.anchor and state.swingForce then
        local delta = state.anchor.Position - root.Position
        local distance = delta.Magnitude
        if distance < 8 or distance > CONFIG.WebRange + 80 then
            releaseWeb(false)
            if distance < 8 then
                root.AssemblyLinearVelocity = capVelocity(
                    root.AssemblyLinearVelocity + horizontalLook() * 18 + Vector3.new(0, 20, 0),
                    CONFIG.MaxSpeed
                )
            end
            return
        end
        local move = state.humanoid.MoveDirection
        local desired = move.Magnitude > 0.08 and move.Unit or horizontalLook()
        local mass = root.AssemblyMass
        local accel = desired * CONFIG.SwingAcceleration
            + Vector3.new(0, Workspace.Gravity * CONFIG.GravityAssist, 0)
        state.swingForce.Force = accel * mass
        if root.AssemblyLinearVelocity.Magnitude > CONFIG.MaxSpeed then
            root.AssemblyLinearVelocity = root.AssemblyLinearVelocity.Unit * CONFIG.MaxSpeed
        end
    end
end)
