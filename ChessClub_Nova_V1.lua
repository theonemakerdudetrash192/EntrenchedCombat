-- CHESS CLUB | NOVA V1
-- Game: https://www.roblox.com/games/139394516128799/Chess-Club
-- Chess analysis helper with optional auto-play. Independent implementation.
-- No downloaded Lua libraries, keys, credentials, or webhooks.
-- Requires live Chess Club client interfaces. Remote requests can be rejected.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local env = type(getgenv) == "function" and getgenv() or _G
pcall(function()
    if type(env.CHESSCLUB_NOVA_STOP) == "function" then env.CHESSCLUB_NOVA_STOP() end
end)

local running = true
local cfg = {
    Engine = "AUTO", -- AUTO / SUNFISH / STOCKFISH
    AutoAnalyze = true,
    AutoPlay = false,
    Side = "AUTO", -- AUTO / WHITE / BLACK
    Depth = 12,
    MoveDelay = 1.3,
    ShowBoard = true,
    BoardFlip = false,
}
local state = {
    fen = nil, tableSet = nil, side = nil, suggested = nil,
    suggestionFen = nil, source = nil, evaluation = nil,
    analyzing = false, searchSerial = 0, seenAt = os.clock(),
    submitted = nil, busyMove = false, cooldown = 0,
    cache = {}, message = "Waiting for active chess table...",
}
local connections = {}
local ui = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end
local function new(class, props, parent)
    local o = Instance.new(class)
    for k,v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local C = {
    bg = Color3.fromRGB(17,19,25),
    item = Color3.fromRGB(33,36,47),
    on = Color3.fromRGB(35,67,66),
    border = Color3.fromRGB(76,85,105),
    txt = Color3.fromRGB(240,242,248),
    sub = Color3.fromRGB(175,184,202),
    accent = Color3.fromRGB(102,217,202),
    whiteSq = Color3.fromRGB(236,223,204),
    blackSq = Color3.fromRGB(127,142,151),
    marked = Color3.fromRGB(236,197,90),
}

-- --------------------------- Game integration ---------------------------
local function getActiveTable()
    local events = RS:FindFirstChild("InternalClientEvents")
    local query = events and events:FindFirstChild("GetActiveTableset")
    if not query then return nil end
    local ok, active = pcall(function()
        if query:IsA("BindableFunction") then return query:Invoke() end
        if query:IsA("RemoteFunction") then return query:InvokeServer() end
        return nil
    end)
    if ok and typeof(active) == "Instance" and active.Parent then return active end
    return nil
end

local function readFen(active)
    if not active then return nil end
    local f = active:FindFirstChild("FEN") or active:FindFirstChild("FEN", true)
    if f and f:IsA("StringValue") and type(f.Value) == "string" then
        local fen = f.Value
        if fen:match("^%S+%s+[wb]%s+%S+%s+%S+") then return fen end
    end
    return nil
end

local function occupant(value)
    if not value then return false end
    if value:IsA("ObjectValue") then
        return value.Value == LocalPlayer or (value.Value and value.Value.Name == LocalPlayer.Name)
    end
    if value:IsA("StringValue") then
        return value.Value == LocalPlayer.Name or value.Value == LocalPlayer.DisplayName or value.Value == tostring(LocalPlayer.UserId)
    end
    if value:IsA("IntValue") or value:IsA("NumberValue") then
        return value.Value == LocalPlayer.UserId
    end
    return false
end
local function mySide(active)
    if cfg.Side == "WHITE" then return "w" end
    if cfg.Side == "BLACK" then return "b" end
    if not active then return nil end
    local w = active:FindFirstChild("WhitePlayer") or active:FindFirstChild("WhitePlayer", true)
    local b = active:FindFirstChild("BlackPlayer") or active:FindFirstChild("BlackPlayer", true)
    if occupant(w) then return "w" end
    if occupant(b) then return "b" end
    return nil -- Never guess a seat and play the opponent's move.
end

local function fenTurn(fen)
    return fen and fen:match("^%S+%s+([wb])%s+") or nil
end
local function parseBoard(fen)
    local board = {}
    local placement = fen and fen:match("^(%S+)")
    if not placement then return board end
    local rank = 8
    for row in placement:gmatch("[^/]+") do
        local file = 1
        for i=1,#row do
            local x = row:sub(i,i)
            local count = tonumber(x)
            if count then
                for _=1,count do
                    board[string.char(96+file)..tostring(rank)] = "."
                    file = file + 1
                end
            else
                if file <= 8 then
                    board[string.char(96+file)..tostring(rank)] = x
                end
                file = file + 1
            end
        end
        rank = rank - 1
    end
    return board
end
local function isMove(raw)
    return type(raw)=="string" and raw:match("^[a-h][1-8][a-h][1-8][qrbn]?$") ~= nil
end
local function extractMove(raw)
    if type(raw) ~= "string" then return nil end
    local match = raw:lower():match("([a-h][1-8][a-h][1-8][qrbn]?)")
    return isMove(match) and match or nil
end
local function plausiblyLegal(fen, uci)
    if not fen or not isMove(uci) then return false end
    local from, to = uci:sub(1,2), uci:sub(3,4)
    if from == to then return false end
    local b, t = parseBoard(fen), fenTurn(fen)
    local piece = b[from]
    if not piece or piece == "." then return false end
    if (t=="w") ~= (piece==piece:upper()) then return false end
    local dest = b[to]
    if dest and dest ~= "." and ((dest==dest:upper()) == (piece==piece:upper())) then return false end
    -- Full legality and final validation belong to the game server/engine.
    return true
end

-- --------------------------- Analysis engines ---------------------------
local function sunfish(fen)
    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local ai = scripts and scripts:FindFirstChild("AI")
    local moduleScript = ai and ai:FindFirstChild("Sunfish")
    if not (moduleScript and moduleScript:IsA("ModuleScript")) then return nil end
    local ok, result = pcall(function()
        local engine = require(moduleScript)
        if type(engine) == "table" and type(engine.GetBestMove) == "function" then
            return engine:GetBestMove(fen, 3000)
        end
        return nil
    end)
    if not ok then return nil end
    local uci = extractMove(result)
    if plausiblyLegal(fen, uci) then return uci, "Sunfish (local)", nil end
    return nil
end
local function requestUrl(url, method, body)
    local req = (type(syn)=="table" and syn.request) or http_request or request
        or (type(http)=="table" and http.request)
    if type(req) == "function" then
        local options = {Url = url, Method = method or "GET", Headers = {}}
        if body then
            options.Headers["Content-Type"]="application/json"
            options.Body=body
        end
        local ok, response = pcall(req, options)
        if ok and type(response)=="table" then
            local code = tonumber(response.StatusCode or response.Status)
            if (not code or (code >= 200 and code < 300)) and type(response.Body)=="string" then
                return response.Body
            end
        end
    end
    if not body then
        local ok, text = pcall(function() return game:HttpGet(url) end)
        if ok and type(text)=="string" then return text end
    end
    return nil
end
local function decode(text)
    if not text then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
    return ok and type(data)=="table" and data or nil
end
local function parseResponse(data)
    if not data then return nil end
    local options = {}
    for _, value in ipairs({data.move or "", data.bestmove or "", data.uci or ""}) do
        if value ~= "" then options[#options+1] = value end
    end
    if type(data.from)=="string" and type(data.to)=="string" then
        options[#options+1] = data.from..data.to..tostring(data.promotion or "")
    end
    if type(data.continuationArr)=="table" and #data.continuationArr>0 then
        local m = data.continuationArr[1]
        if type(m)=="table" then
            options[#options+1] = m.move or m.uci
        else
            options[#options+1] = m
        end
    end
    if type(data.continuation)=="string" then options[#options+1] = data.continuation end
    if type(data.bestmove)=="string" then options[#options+1]=data.bestmove end
    for _,v in pairs(options) do
        local move = extractMove(v)
        if move then
            return move, tonumber(data.eval or data.evaluation or data.score)
        end
    end
    return nil
end
local function stockfish(fen)
    local payload = HttpService:JSONEncode({fen=fen,depth=math.min(cfg.Depth,18),variants=1})
    local data = decode(requestUrl("https://chess-api.com/v1", "POST", payload))
    local move, eval = parseResponse(data)
    if plausiblyLegal(fen, move) then return move, "Chess API", eval end
    local url = "https://stockfish.online/api/s/v2.php?fen="..HttpService:UrlEncode(fen).."&depth="..math.min(cfg.Depth,15)
    data = decode(requestUrl(url, "GET"))
    move, eval = parseResponse(data)
    if plausiblyLegal(fen, move) then return move, "Stockfish Online", eval end
    return nil
end
local openings = {
    ["rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]="e2e4",
    ["rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]="e7e5",
    ["rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"]="g1f3",
}
local function engineMove(fen)
    if cfg.Engine == "SUNFISH" then return sunfish(fen) end
    if cfg.Engine == "STOCKFISH" then return stockfish(fen) end
    local move, source, evaluation = sunfish(fen)
    if move then return move, source, evaluation end
    move, source, evaluation = stockfish(fen)
    if move then return move, source, evaluation end
    if openings[fen] and plausiblyLegal(fen, openings[fen]) then
        return openings[fen], "Opening book (limited)", nil
    end
    return nil
end

-- --------------------------- Responsive UI ---------------------------
local playerGui = LocalPlayer:WaitForChild("PlayerGui",10)
if not playerGui then return end
local previous = playerGui:FindFirstChild("ChessClubNova")
if previous then previous:Destroy() end
local gui = new("ScreenGui",{
    Name="ChessClubNova",ResetOnSpawn=false,IgnoreGuiInset=true,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=997,
},playerGui)
local main = new("Frame",{
    Size=UDim2.fromOffset(318,535), Position=UDim2.fromOffset(12,64),
    BackgroundColor3=C.bg,BorderSizePixel=0,Active=true,ZIndex=9,
},gui)
new("UICorner",{CornerRadius=UDim.new(0,12)},main)
new("UIStroke",{Color=C.border,Thickness=1},main)
local header = new("Frame",{
    Size=UDim2.new(1,0,0,46),BackgroundTransparency=1,Active=true,ZIndex=10,
},main)
new("TextLabel",{
    Size=UDim2.new(1,-60,0,27),Position=UDim2.fromOffset(12,4),
    BackgroundTransparency=1,Text="CHESS CLUB  /  NOVA",
    Font=Enum.Font.GothamBold,TextSize=15,TextColor3=C.txt,
    TextXAlignment=Enum.TextXAlignment.Left,ZIndex=11,
},header)
new("TextLabel",{
    Size=UDim2.new(1,-60,0,13),Position=UDim2.fromOffset(12,29),
    BackgroundTransparency=1,Text="ENGINE  •  BOARD  •  AUTO PLAY",
    Font=Enum.Font.GothamMedium,TextSize=9,TextColor3=C.sub,
    TextXAlignment=Enum.TextXAlignment.Left,ZIndex=11,
},header)
local hide = new("TextButton",{
    Size=UDim2.fromOffset(32,28), Position=UDim2.new(1,-39,0,9),
    BackgroundColor3=C.item, Text="–",TextColor3=C.txt,
    Font=Enum.Font.GothamBold,TextSize=20,ZIndex=11,
},header)
new("UICorner",{CornerRadius=UDim.new(0,7)},hide)
local statusBox = new("Frame",{
    Position=UDim2.fromOffset(10,49), Size=UDim2.new(1,-20,0,69),
    BackgroundColor3=C.item,BorderSizePixel=0,ZIndex=10,
},main)
new("UICorner",{CornerRadius=UDim.new(0,9)},statusBox)
local function label(y,height,text,color,fontSize)
    return new("TextLabel",{
        Position=UDim2.fromOffset(8,y),Size=UDim2.new(1,-16,0,height),
        BackgroundTransparency=1,Text=text,TextColor3=color or C.txt,
        Font=Enum.Font.GothamMedium,TextSize=fontSize or 11,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=11,
    },statusBox)
end
local turnLabel = label(5,18,"No active board",C.txt,12)
local moveLabel = label(25,18,"Best move: —",C.accent,12)
local infoLabel = label(46,15,"Waiting for board...",C.sub,10)
local scroll = new("ScrollingFrame",{
    Position=UDim2.fromOffset(10,124), Size=UDim2.new(1,-20,1,-156),
    BackgroundTransparency=1,BorderSizePixel=0,
    ScrollBarThickness=4,ScrollBarImageColor3=C.border,
    AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.fromOffset(0,0),ZIndex=10,
},main)
new("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder},scroll)
new("UIPadding",{PaddingBottom=UDim.new(0,9)},scroll)
local status = new("TextLabel",{
    Position=UDim2.new(0,12,1,-28),Size=UDim2.new(1,-24,0,21),
    BackgroundTransparency=1,Text="Loading...",TextColor3=C.sub,
    TextSize=10,Font=Enum.Font.GothamMedium,
    TextXAlignment=Enum.TextXAlignment.Left,
    TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=11,
},main)
local bubble = new("TextButton",{
    Size=UDim2.fromOffset(65,40),Position=UDim2.new(0,8,0.42,0),
    BackgroundColor3=C.bg,Text="CHESS",Font=Enum.Font.GothamBold,
    TextSize=12,TextColor3=C.accent,Visible=false,ZIndex=21,
},gui)
new("UICorner",{CornerRadius=UDim.new(0,10)},bubble)
new("UIStroke",{Color=C.accent,Thickness=1},bubble)

local boardFrame = new("Frame",{
    Size=UDim2.fromOffset(250,250),BackgroundTransparency=1,
    BorderSizePixel=0,LayoutOrder=0,ZIndex=12,
},scroll)
local squareSide = 29
local boardSide = squareSide*8
local squares = {}
local chars = {
    K="♔",Q="♕",R="♖",B="♗",N="♘",P="♙",
    k="♚",q="♛",r="♜",b="♝",n="♞",p="♟︎",
}
for i=0,63 do
    local row,col=math.floor(i/8),i%8
    local bg = new("Frame",{
        Size=UDim2.fromOffset(squareSide,squareSide),
        Position=UDim2.fromOffset(9+col*squareSide,5+row*squareSide),
        BackgroundColor3=(row+col)%2==0 and C.whiteSq or C.blackSq,
        BorderSizePixel=0,ZIndex=13,
    },boardFrame)
    local text = new("TextLabel",{
        Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
        Text="",TextScaled=true,TextColor3=Color3.fromRGB(14,19,22),
        TextStrokeTransparency=0.84,Font=Enum.Font.SourceSansBold,
        ZIndex=14,
    },bg)
    squares[i+1]={back=bg,label=text,row=row,col=col}
end

local function updateBoard()
    boardFrame.Visible=cfg.ShowBoard
    boardFrame.Size=UDim2.fromOffset(250,cfg.ShowBoard and 245 or 0)
    local position=parseBoard(state.fen)
    local from=state.suggestionFen==state.fen and state.suggested and state.suggested:sub(1,2)
    local to=state.suggestionFen==state.fen and state.suggested and state.suggested:sub(3,4)
    for _,item in ipairs(squares) do
        local x,y=item.col,item.row
        local file=cfg.BoardFlip and (8-x) or (x+1)
        local rank=cfg.BoardFlip and (y+1) or (8-y)
        local coord=string.char(96+file)..tostring(rank)
        local piece=position[coord]
        item.label.Text=chars[piece] or ""
        if piece and piece==piece:upper() then
            item.label.TextColor3=Color3.fromRGB(252,251,240)
            item.label.TextStrokeColor3=Color3.fromRGB(36,39,42)
            item.label.TextStrokeTransparency=0.17
        else
            item.label.TextColor3=Color3.fromRGB(23,24,28)
            item.label.TextStrokeColor3=Color3.fromRGB(230,230,230)
            item.label.TextStrokeTransparency=0.55
        end
        item.back.BackgroundColor3=(coord==from or coord==to)
            and C.marked or ((x+y)%2==0 and C.whiteSq or C.blackSq)
    end
end

local order = 1
local function addButton(initial, action, enabled)
    local button = new("TextButton",{
        Size=UDim2.new(1,-8,0,36),BackgroundColor3=C.item,
        BorderSizePixel=0,Text=initial,TextColor3=C.txt,
        Font=Enum.Font.GothamMedium,TextSize=12,LayoutOrder=order,ZIndex=12,
    },scroll)
    order=order+1
    new("UICorner",{CornerRadius=UDim.new(0,8)},button)
    local function recolor()
        if enabled then button.BackgroundColor3=enabled() and C.on or C.item end
    end
    connect(button.MouseButton1Click,function()
        if not running then return end
        local ok,err=pcall(action,button)
        if not ok then state.message="Button error: "..tostring(err):sub(1,40) end
        recolor()
    end)
    recolor()
    return button
end
local function toggle(title,key,onChange)
    return addButton(title..": "..(cfg[key] and "ON" or "OFF"),function(b)
        cfg[key]=not cfg[key]
        b.Text=title..": "..(cfg[key] and "ON" or "OFF")
        if onChange then onChange() end
    end,function() return cfg[key] end)
end

local function redrawStatus()
    local turn=fenTurn(state.fen)
    local side=mySide(state.tableSet)
    state.side=side
    if state.fen then
        turnLabel.Text=(turn=="w" and "WHITE" or "BLACK").." TO MOVE    |    YOU: "..(side=="w" and "WHITE" or side=="b" and "BLACK" or "UNKNOWN")
    else
        turnLabel.Text="NO ACTIVE CHESS BOARD"
    end
    moveLabel.Text="BEST MOVE: "..(state.suggestionFen==state.fen and state.suggested or "—")
    local source=state.suggestionFen==state.fen and state.source or "No analysis"
    if state.analyzing then source="Analyzing position..." end
    infoLabel.Text="Engine: "..source
    status.Text=state.message
end

local analyze
analyze=function()
    if not running or state.analyzing or not state.fen then return end
    local targetFen=state.fen
    local cached=state.cache[targetFen]
    if cached then
        state.suggested=cached.move
        state.suggestionFen=targetFen
        state.source=cached.source
        state.evaluation=cached.eval
        updateBoard()
        redrawStatus()
        return
    end
    state.analyzing=true
    state.searchSerial=state.searchSerial+1
    local serial=state.searchSerial
    task.spawn(function()
        local ok,move,source,eval=pcall(engineMove,targetFen)
        if not running or serial~=state.searchSerial then return end
        state.analyzing=false
        if state.fen~=targetFen then return end
        if ok and plausiblyLegal(targetFen,move) then
            state.suggested=move
            state.suggestionFen=targetFen
            state.source=source
            state.evaluation=eval
            state.cache[targetFen]={move=move,source=source,eval=eval}
            state.message="Suggested "..move.." ("..source..")"
        else
            state.suggested=nil
            state.suggestionFen=nil
            state.source=nil
            state.message="No engine move; try another engine or enable HTTP"
        end
        updateBoard()
        redrawStatus()
    end)
end

local function playSuggested()
    if state.busyMove or not running then return end
    if not state.fen or not state.suggested or state.suggestionFen~=state.fen then
        state.message="Analyze a live position first";return
    end
    local own=mySide(state.tableSet)
    if not own then state.message="Set YOUR COLOR to White or Black first";return end
    if fenTurn(state.fen)~=own then state.message="Not your turn";return end
    if not plausiblyLegal(state.fen,state.suggested) then
        state.message="Engine move not valid for this position";return
    end
    if state.submitted==state.fen then
        state.message="Move already attempted for this position";return
    end
    local chess=RS:FindFirstChild("Chess")
    local submit=chess and chess:FindFirstChild("SubmitMove")
    if not submit or not submit:IsA("RemoteFunction") then
        state.message="Chess.SubmitMove remote not available";return
    end
    state.busyMove=true
    local oldFen,move=state.fen,state.suggested
    state.submitted=oldFen
    state.message="Submitting "..move.."..."
    task.spawn(function()
        local ok,result=pcall(function() return submit:InvokeServer(move) end)
        if not running then return end
        if not ok or result==false then
            state.message="Move request rejected/failed"
        else
            state.message="Move requested — awaiting board update"
        end
        state.busyMove=false
        redrawStatus()
    end)
end

addButton("ANALYZE POSITION",function()
    if not state.fen then state.message="Join a chess table first";return end
    analyze()
end)
addButton("PLAY SUGGESTED MOVE",playSuggested)
toggle("AUTO ANALYZE","AutoAnalyze")
toggle("AUTO PLAY","AutoPlay",function()
    if cfg.AutoPlay then
        state.message="Auto-play ON (requires verified player side)"
    else
        state.message="Auto-play OFF"
    end
end)
addButton("ENGINE: "..cfg.Engine,function(b)
    local arr={"AUTO","SUNFISH","STOCKFISH"}
    local i=table.find(arr,cfg.Engine) or 1
    cfg.Engine=arr[i%#arr+1]
    b.Text="ENGINE: "..cfg.Engine
    state.cache={}
    state.suggested=nil
    state.suggestionFen=nil
end)
addButton("YOUR COLOR: "..cfg.Side,function(b)
    local arr={"AUTO","WHITE","BLACK"}
    local i=table.find(arr,cfg.Side) or 1
    cfg.Side=arr[i%#arr+1]
    b.Text="YOUR COLOR: "..cfg.Side
    redrawStatus()
end)
addButton("SEARCH DEPTH: "..cfg.Depth,function(b)
    local arr={8,12,15,18}
    local i=table.find(arr,cfg.Depth) or 1
    cfg.Depth=arr[i%#arr+1]
    b.Text="SEARCH DEPTH: "..cfg.Depth
    state.cache={}
    state.suggested=nil
    state.suggestionFen=nil
end)
addButton("AUTO PLAY DELAY: "..cfg.MoveDelay.."s",function(b)
    local arr={0.4,1.3,2.5,4}
    local i=table.find(arr,cfg.MoveDelay) or 1
    cfg.MoveDelay=arr[i%#arr+1]
    b.Text="AUTO PLAY DELAY: "..cfg.MoveDelay.."s"
end)
toggle("SHOW BOARD","ShowBoard",updateBoard)
toggle("FLIP BOARD","BoardFlip",updateBoard)
addButton("COPY FEN",function()
    if not state.fen then state.message="No FEN available";return end
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,state.fen)
        state.message=ok and "FEN copied" or "Clipboard unavailable"
    else state.message="Executor does not support setclipboard" end
end)

local function unload()
    if not running then return end
    running=false
    state.searchSerial=state.searchSerial+1
    for _,link in ipairs(connections) do pcall(function() link:Disconnect() end) end
    gui:Destroy()
    if env.CHESSCLUB_NOVA_STOP==unload then env.CHESSCLUB_NOVA_STOP=nil end
end
env.CHESSCLUB_NOVA_STOP=unload
addButton("UNLOAD SCRIPT",unload)

-- Touch and mouse dragging via title bar.
local moving,dragStart,initial,dragInput=false,nil,nil,nil
connect(header.InputBegan,function(input)
    local k=input.UserInputType
    if k==Enum.UserInputType.Touch or k==Enum.UserInputType.MouseButton1 then
        moving=true;dragStart=input.Position;initial=main.Position;dragInput=input
    end
end)
connect(UIS.InputChanged,function(input)
    if not moving or not dragInput then return end
    local mouse=dragInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement
    if input~=dragInput and not mouse then return end
    local d=input.Position-dragStart
    local camera=workspace.CurrentCamera
    local vp=camera and camera.ViewportSize or Vector2.new(1000,650)
    main.Position=UDim2.fromOffset(
        math.clamp(initial.X.Offset+d.X,0,math.max(0,vp.X-main.AbsoluteSize.X)),
        math.clamp(initial.Y.Offset+d.Y,0,math.max(0,vp.Y-main.AbsoluteSize.Y))
    )
end)
connect(UIS.InputEnded,function(input)
    if input==dragInput then moving=false;dragInput=nil end
end)
local minimized=false
local function setHidden(value)
    minimized=value
    main.Visible=not minimized
    bubble.Visible=minimized
end
connect(hide.MouseButton1Click,function()setHidden(true)end)
connect(bubble.MouseButton1Click,function()setHidden(false)end)
connect(UIS.InputBegan,function(input,processed)
    if not processed and input.KeyCode==Enum.KeyCode.RightShift then setHidden(not minimized)end
end)

-- Poll the visible client's own board only, and never submit the same FEN twice.
task.spawn(function()
    while running do
        local active=getActiveTable()
        local fen=readFen(active)
        state.tableSet=active
        if fen~=state.fen then
            state.fen=fen
            state.suggested=nil
            state.suggestionFen=nil
            state.source=nil
            state.evaluation=nil
            state.seenAt=os.clock()
            state.searchSerial=state.searchSerial+1
            state.analyzing=false
            state.submitted=nil
            state.message=fen and "Board detected; analyzing..." or "Join a Chess Club table to begin"
            updateBoard()
        end
        if fen and (cfg.AutoAnalyze or cfg.AutoPlay) and not state.analyzing and state.suggestionFen~=fen then
            analyze()
        end
        local own=mySide(active)
        if fen and cfg.AutoPlay and not state.busyMove and own and fenTurn(fen)==own
            and state.suggestionFen==fen and state.suggested and state.submitted~=fen
            and os.clock()-state.seenAt>=cfg.MoveDelay then
            playSuggested()
        end
        redrawStatus()
        task.wait(1.0)
    end
end)

updateBoard()
redrawStatus()
if game.PlaceId~=139394516128799 then
    state.message="Different place ID. Designed for Aureus Chess Club."
end
print("[CHESS CLUB NOVA] Loaded. Auto-play OFF. Requires live Chess Club FEN and client engine/API.")
