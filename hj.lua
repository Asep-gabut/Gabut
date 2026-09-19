-- ============================================
-- AUTO FARM DUNGEON - MOBILE EDITION (v43)
-- Clean: 1 jarak setting + smooth pathfinder + camera lock
-- ============================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============ KONFIGURASI ============
local CONFIG = {
    KeepDistance = 60,        -- ⭐ satu-satunya setting jarak
    AttackCooldown = 0.5,
    AutoUpgrade = true,
    WaypointReached = 4,
    TargetMoveThreshold = 6,
}

local State = {
    Running = true, Character = nil, Humanoid = nil, RootPart = nil,
    LastAttack = 0, LastUpgrade = 0,
    EnemyFolders = {}, LastFolderScan = 0,
    -- path
    PathWaypoints = nil,
    PathIndex = 1,
    PathTargetPos = nil,
    PathGoalType = nil,
    PathBusy = false,
    LastMoveToPos = nil,
    -- camera lock
    LockedEnemyPos = nil,
    ShiftlockSaved = nil,
}

setStatus = function() end

local KEY_Q = 0x51
local KEY_E = 0x45

local function pressQ()
    pcall(function() keypress(KEY_Q) end)
    task.wait(0.05)
    pcall(function() keyrelease(KEY_Q) end)
end
local function pressE()
    pcall(function() keypress(KEY_E) end)
    task.wait(0.05)
    pcall(function() keyrelease(KEY_E) end)
end

-- ============ SHIFTLOCK ============
local function setShiftlock(enabled)
    pcall(function()
        local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
        if not sl then
            for _, obj in ipairs(LocalPlayer:GetDescendants()) do
                if obj.Name:lower():find("shiftlock") then sl = obj break end
            end
        end
        if sl then
            if State.ShiftlockSaved == nil then
                State.ShiftlockSaved = sl.Value
            end
            sl.Value = enabled
        end
    end)
end

-- ============ CAMERA LOCK ============
RunService.RenderStepped:Connect(function()
    if not State.Running then return end
    if not State.LockedEnemyPos then return end
    if not Camera then return end
    
    local camPos = Camera.CFrame.Position
    local tp = State.LockedEnemyPos
    Camera.CFrame = CFrame.new(camPos, Vector3.new(tp.X, camPos.Y + 1.5, tp.Z))
end)

-- ============ CHARACTER ============
local function setupCharacter(char)
    State.Character = char
    State.Humanoid = char:WaitForChild("Humanoid")
    State.RootPart = char:WaitForChild("HumanoidRootPart")
end

if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(setupCharacter)

-- ============ REMOTES ============
local function startGame()
    local remotes = ReplicatedStorage:FindFirstChild("remotes")
    if not remotes then return end
    local change = remotes:FindFirstChild("changeStartValue")
    if change then change:FireServer() end
end

local function upgradeSpell()
    if not CONFIG.AutoUpgrade then return end
    local remotes = ReplicatedStorage:FindFirstChild("remotes")
    if not remotes then return end
    local spend = remotes:FindFirstChild("spendSkillPoint")
    if spend then
        spend:FireServer("spellPower", 1)
        State.LastUpgrade = tick()
    end
end

-- ============ ENEMY FOLDER ============
local function scanAllEnemyFolders()
    local folders = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("Folder") or obj:IsA("Model")) 
            and obj.Name:lower():find("enemyfolder") then
            table.insert(folders, obj)
        end
    end
    return folders
end

local function getEnemyFolders()
    local now = tick()
    if #State.EnemyFolders == 0 or (now - State.LastFolderScan) >= 2 then
        State.EnemyFolders = scanAllEnemyFolders()
        State.LastFolderScan = now
    end
    return State.EnemyFolders
end

-- ============ HUMANOID ============
local function getHumanoidAndHRP(enemy)
    if not enemy or not enemy.Parent then return nil, nil end
    local hum = enemy:FindFirstChildOfClass("Humanoid") 
        or enemy:FindFirstChildWhichIsA("Humanoid", true)
    if not hum then return nil, nil end
    if hum.Health <= 0 then return nil, nil end
    local ok, st = pcall(function() return hum:GetState() end)
    if ok and st == Enum.HumanoidStateType.Dead then return nil, nil end
    local hrp = enemy:FindFirstChild("HumanoidRootPart")
        or enemy:FindFirstChild("HumanoidRootPart", true)
        or enemy.PrimaryPart
        or enemy:FindFirstChild("Torso", true)
        or enemy:FindFirstChild("UpperTorso", true)
        or enemy:FindFirstChild("Head", true)
    if not hrp then return nil, nil end
    return hum, hrp
end

local function findNearestEnemy()
    local folders = getEnemyFolders()
    if #folders == 0 or not State.RootPart then return nil, 0, nil end
    local nearest, nearestDist = nil, math.huge
    local totalCount = 0
    local roomInfo = {}
    for _, folder in ipairs(folders) do
        if folder and folder.Parent then
            local roomName = folder.Parent and folder.Parent.Name or "?"
            local roomCount = 0
            for _, enemy in ipairs(folder:GetChildren()) do
                if enemy:IsA("Model") or enemy:IsA("Folder") then
                    local hum, hrp = getHumanoidAndHRP(enemy)
                    if hum and hrp then
                        roomCount = roomCount + 1
                        totalCount = totalCount + 1
                        local dist = (hrp.Position - State.RootPart.Position).Magnitude
                        if dist < nearestDist then
                            nearestDist = dist
                            nearest = enemy
                        end
                    end
                end
            end
            if roomCount > 0 then
                table.insert(roomInfo, roomName .. ":" .. roomCount)
            end
        end
    end
    if totalCount == 0 then State.LastFolderScan = 0 end
    return nearest, totalCount, roomInfo
end

-- ============ PATH ============
local function resetPath()
    State.PathWaypoints = nil
    State.PathIndex = 1
    State.PathTargetPos = nil
    State.PathGoalType = nil
    State.LastMoveToPos = nil
end

local function requestPath(targetPos, goalType)
    if not State.Humanoid or not State.RootPart then return end
    if not targetPos then return end
    if State.PathBusy then return end
    
    local needRecompute = false
    if not State.PathWaypoints then needRecompute = true
    elseif State.PathGoalType ~= goalType then needRecompute = true
    elseif State.PathIndex > #State.PathWaypoints then needRecompute = true
    elseif State.PathTargetPos and (targetPos - State.PathTargetPos).Magnitude > CONFIG.TargetMoveThreshold then needRecompute = true
    end
    
    if not needRecompute then return end
    
    State.PathBusy = true
    task.spawn(function()
        local myPos = State.RootPart.Position
        local path = PathfindingService:CreatePath({
            AgentRadius = 3, AgentHeight = 5, AgentCanJump = true,
            AgentJumpHeight = 10, AgentMaxSlope = 45,
        })
        local ok = pcall(function() path:ComputeAsync(myPos, targetPos) end)
        
        if ok and path.Status == Enum.PathStatus.Success then
            State.PathWaypoints = path:GetWaypoints()
            State.PathIndex = 2
            State.PathTargetPos = targetPos
            State.PathGoalType = goalType
            State.LastMoveToPos = nil
        else
            State.PathWaypoints = nil
            State.PathTargetPos = targetPos
            State.PathGoalType = goalType
            State.LastMoveToPos = nil
        end
        State.PathBusy = false
    end)
end

-- ============ FOLLOW PATH (smooth, no stutter) ============
local function followPath()
    if not State.Humanoid or not State.RootPart then return end
    if not State.PathWaypoints then
        if State.PathTargetPos then
            if not State.LastMoveToPos 
                or (State.LastMoveToPos - State.PathTargetPos).Magnitude > 0.5 then
                State.Humanoid:MoveTo(State.PathTargetPos)
                State.LastMoveToPos = State.PathTargetPos
            end
        end
        return
    end
    
    if State.PathIndex > #State.PathWaypoints then return end
    
    local myPos = State.RootPart.Position
    local wp = State.PathWaypoints[State.PathIndex]
    local distToWp = (myPos - wp.Position).Magnitude
    
    if distToWp <= CONFIG.WaypointReached then
        State.PathIndex = State.PathIndex + 1
        State.LastMoveToPos = nil
        return
    end
    
    if not State.LastMoveToPos 
        or (State.LastMoveToPos - wp.Position).Magnitude > 0.5 then
        State.Humanoid:MoveTo(wp.Position)
        State.LastMoveToPos = wp.Position
        if wp.Action == Enum.PathWaypointAction.Jump then
            State.Humanoid.Jump = true
        end
    end
end

-- ============ SAFE POINT ============
local function findSafePointAroundEnemy(enemyPos, myPos)
    local bestPoint = nil
    local bestDist = math.huge
    local samples = 16
    for i = 0, samples - 1 do
        local angle = (i / samples) * math.pi * 2
        local offset = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local point = Vector3.new(
            enemyPos.X + offset.X * CONFIG.KeepDistance,
            myPos.Y,
            enemyPos.Z + offset.Z * CONFIG.KeepDistance
        )
        local d = (point - myPos).Magnitude
        if d < bestDist then
            bestDist = d
            bestPoint = point
        end
    end
    return bestPoint
end

-- ============ ATTACK ============
local function attackEnemy(enemy)
    local now = tick()
    if now - State.LastAttack < CONFIG.AttackCooldown then return false end
    State.LastAttack = now
    pressQ()
    task.wait(0.08)
    pressE()
    return true
end

-- ============ MAIN LOOP ============
local function mainLoop()
    while State.Running do
        task.wait(0.05)
        if not State.Character or not State.Character.Parent then task.wait(0.5) continue end
        if State.Humanoid.Health <= 0 then task.wait(1) continue end
        if CONFIG.AutoUpgrade and (tick() - State.LastUpgrade) >= 3 then upgradeSpell() end

        -- pastiin shiftlock ON
        local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
        if sl and sl.Value == false then setShiftlock(true) end

        local enemy, count, roomInfo = findNearestEnemy()
        if enemy then
            local _, ehrp = getHumanoidAndHRP(enemy)
            if ehrp then
                local myPos = State.RootPart.Position
                local enemyPos = ehrp.Position
                local dist = (enemyPos - myPos).Magnitude
                
                -- ⭐ lock camera ke enemy
                State.LockedEnemyPos = enemyPos
                
                local roomStr = ""
                if roomInfo and #roomInfo > 0 then
                    roomStr = " [" .. table.concat(roomInfo, ", ") .. "]"
                end

                -- ⭐ 1 setting jarak: KeepDistance
                if dist > CONFIG.KeepDistance then
                    -- MAJU + attack
                    setStatus(string.format("Approaching (%.1f) | %d%s", dist, count, roomStr))
                    requestPath(enemyPos, "approach")
                    followPath()
                    attackEnemy(enemy)
                else
                    -- MUNDUR ke titik aman + attack
                    setStatus(string.format("Kiting (%.1f) | %d%s", dist, count, roomStr))
                    local safePoint = findSafePointAroundEnemy(enemyPos, myPos)
                    if safePoint then
                        requestPath(safePoint, "retreat")
                        followPath()
                    end
                    attackEnemy(enemy)
                end
            end
        else
            State.LockedEnemyPos = nil
            resetPath()
            setStatus(string.format("No enemy | %d rooms", #State.EnemyFolders))
        end
    end
end

-- ============================================
--              UI
-- ============================================
local function createUI()
    if CoreGui:FindFirstChild("AutoFarmUI") then CoreGui.AutoFarmUI:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoFarmUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = CoreGui

    local statusOverlay = Instance.new("TextLabel")
    statusOverlay.Size = UDim2.new(0, 420, 0, 32)
    statusOverlay.Position = UDim2.new(0.5, -210, 0, 10)
    statusOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    statusOverlay.BackgroundTransparency = 0.4
    statusOverlay.Text = "⚔ Idle"
    statusOverlay.TextColor3 = Color3.fromRGB(180, 255, 180)
    statusOverlay.TextSize = 16
    statusOverlay.Font = Enum.Font.GothamBold
    statusOverlay.TextStrokeTransparency = 0.5
    statusOverlay.ZIndex = 5
    statusOverlay.Parent = screenGui
    local soCorner = Instance.new("UICorner")
    soCorner.CornerRadius = UDim.new(0, 8)
    soCorner.Parent = statusOverlay
    local soStroke = Instance.new("UIStroke")
    soStroke.Color = Color3.fromRGB(100, 200, 100)
    soStroke.Thickness = 1.5
    soStroke.Transparency = 0.3
    soStroke.Parent = statusOverlay

    setStatus = function(msg)
        pcall(function() statusOverlay.Text = "⚔ " .. msg end)
    end

    local floatBtn = Instance.new("TextButton")
    floatBtn.Size = UDim2.new(0, 55, 0, 55)
    floatBtn.Position = UDim2.new(0, 15, 0.5, -27)
    floatBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
    floatBtn.Text = "⚙"
    floatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    floatBtn.TextSize = 24
    floatBtn.Font = Enum.Font.GothamBold
    floatBtn.BorderSizePixel = 0
    floatBtn.Active = true
    floatBtn.Draggable = true
    floatBtn.ZIndex = 5
    floatBtn.Parent = screenGui
    local fbCorner = Instance.new("UICorner")
    fbCorner.CornerRadius = UDim.new(1, 0)
    fbCorner.Parent = floatBtn
    local fbStroke = Instance.new("UIStroke")
    fbStroke.Color = Color3.fromRGB(255, 255, 255)
    fbStroke.Thickness = 2
    fbStroke.Transparency = 0.3
    fbStroke.Parent = floatBtn

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 300, 0, 420)
    main.Position = UDim2.new(0.5, -150, 0.5, -210)
    main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Visible = false
    main.ZIndex = 10
    main.Parent = screenGui
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 14)
    mainCorner.Parent = main
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(80, 120, 255)
    mainStroke.Thickness = 2
    mainStroke.Parent = main

    local title = Instance.new("Frame")
    title.Size = UDim2.new(1, 0, 0, 45)
    title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    title.BorderSizePixel = 0
    title.ZIndex = 11
    title.Parent = main
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 14)
    titleCorner.Parent = title
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 15)
    titleFix.Position = UDim2.new(0, 0, 1, -15)
    titleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    titleFix.BorderSizePixel = 0
    titleFix.ZIndex = 11
    titleFix.Parent = title

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -100, 1, 0)
    titleText.Position = UDim2.new(0, 15, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "⚙ SETTINGS"
    titleText.TextColor3 = Color3.fromRGB(200, 220, 255)
    titleText.TextSize = 17
    titleText.Font = Enum.Font.GothamBold
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.ZIndex = 12
    titleText.Parent = title

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 60, 0, 34)
    closeBtn.Position = UDim2.new(1, -68, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 18
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.ZIndex = 12
    closeBtn.Parent = title
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 8)
    closeCorner.Parent = closeBtn
    closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -20, 1, -60)
    scroll.Position = UDim2.new(0, 10, 0, 50)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ZIndex = 11
    scroll.Parent = main
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll

    local function createInput(labelText, defaultVal, order, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 45)
        row.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.ZIndex = 11
        row.Parent = scroll
        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 8)
        rowCorner.Parent = row
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.5, -10, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
        lbl.TextSize = 14
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 12
        lbl.Parent = row
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0.45, -15, 0, 32)
        box.Position = UDim2.new(0.5, 0, 0, 6)
        box.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        box.Text = tostring(defaultVal)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.TextSize = 14
        box.Font = Enum.Font.Gotham
        box.BorderSizePixel = 0
        box.ClearTextOnFocus = false
        box.ZIndex = 12
        box.Parent = row
        local boxCorner = Instance.new("UICorner")
        boxCorner.CornerRadius = UDim.new(0, 6)
        boxCorner.Parent = box
        box.FocusLost:Connect(function()
            local val = tonumber(box.Text)
            if val then callback(val) end
        end)
    end

    local function createToggle(labelText, defaultVal, order, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 45)
        row.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.ZIndex = 11
        row.Parent = scroll
        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 8)
        rowCorner.Parent = row
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.6, -10, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
        lbl.TextSize = 14
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 12
        lbl.Parent = row
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 70, 0, 32)
        btn.Position = UDim2.new(1, -82, 0, 6)
        btn.BackgroundColor3 = defaultVal and Color3.fromRGB(60, 180, 90) or Color3.fromRGB(80, 80, 90)
        btn.Text = defaultVal and "ON" or "OFF"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 13
        btn.Font = Enum.Font.GothamBold
        btn.BorderSizePixel = 0
        btn.ZIndex = 12
        btn.Parent = row
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn
        local state = defaultVal
        btn.MouseButton1Click:Connect(function()
            state = not state
            btn.Text = state and "ON" or "OFF"
            btn.BackgroundColor3 = state and Color3.fromRGB(60, 180, 90) or Color3.fromRGB(80, 80, 90)
            callback(state)
        end)
    end

    createInput("Keep Distance", CONFIG.KeepDistance, 1, function(v) CONFIG.KeepDistance = v end)
    createInput("Attack Cooldown", CONFIG.AttackCooldown, 2, function(v) CONFIG.AttackCooldown = v end)
    createInput("Waypoint Reached", CONFIG.WaypointReached, 3, function(v) CONFIG.WaypointReached = v end)
    createInput("Target Move Threshold", CONFIG.TargetMoveThreshold, 4, function(v) CONFIG.TargetMoveThreshold = v end)
    createToggle("Auto Upgrade", CONFIG.AutoUpgrade, 5, function(v) CONFIG.AutoUpgrade = v end)

    local startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(1, 0, 0, 55)
    startBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
    startBtn.Text = "▶  START FARM"
    startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    startBtn.TextSize = 17
    startBtn.Font = Enum.Font.GothamBold
    startBtn.BorderSizePixel = 0
    startBtn.LayoutOrder = 6
    startBtn.ZIndex = 11
    startBtn.Parent = scroll
    local startCorner = Instance.new("UICorner")
    startCorner.CornerRadius = UDim.new(0, 10)
    startCorner.Parent = startBtn

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, 0, 0, 20)
    footer.BackgroundTransparency = 1
    footer.Text = "v43 - final clean"
    footer.TextColor3 = Color3.fromRGB(120, 120, 130)
    footer.TextSize = 11
    footer.Font = Enum.Font.Gotham
    footer.LayoutOrder = 7
    footer.ZIndex = 11
    footer.Parent = scroll

    floatBtn.MouseButton1Click:Connect(function()
        main.Visible = not main.Visible
    end)

    startBtn.MouseButton1Click:Connect(function()
        if State.Running then
            State.Running = false
            startBtn.Text = "▶  START FARM"
            startBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
            floatBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
            soStroke.Color = Color3.fromRGB(100, 200, 100)
            setStatus("Idle")
            resetPath()
            State.LockedEnemyPos = nil
            if State.ShiftlockSaved ~= nil then setShiftlock(State.ShiftlockSaved) end
        else
            State.Running = true
            startBtn.Text = "■  STOP FARM"
            startBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            floatBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            soStroke.Color = Color3.fromRGB(255, 100, 100)
            setStatus("Starting...")
            task.spawn(function()
                startGame()
                task.wait(1.5)
                if CONFIG.AutoUpgrade then upgradeSpell() task.wait(0.5) end
                setStatus("Running")
                mainLoop()
            end)
        end
    end)
    setStatus("Idle - tap ⚙")
end

createUI()
print("[AutoFarm Mobile v43] Loaded - clean")