-- ============================================
-- AUTO FARM DUNGEON - MOBILE EDITION (v13)
-- Multi-room support
-- ============================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============ KONFIGURASI ============
local CONFIG = {
    AttackDistance = 50,
    KeepDistance = 30,
    DistanceTolerance = 3,
    AttackCooldown = 0.5,
    WalkSpeed = 32,
    SkillName = "spellPower",
    AutoUpgrade = true,
    UpgradeInterval = 3,
    UseShiftlock = true,
    UseTouchToFace = true,
    StuckTimeout = 1.0,
    PathRecomputeDelay = 0.3,
    FolderScanInterval = 2,  -- scan semua room tiap 2 detik
}

local State = {
    Running = false,
    Character = nil,
    Humanoid = nil,
    RootPart = nil,
    LastAttack = 0,
    LastUpgrade = 0,
    LastPathCompute = 0,
    LastPos = nil,
    StuckTime = 0,
    EnemyFolders = {},       -- ⭐ list semua enemyFolder
    LastFolderScan = 0,
    CurrentEnemy = nil,
    ShiftlockSaved = nil,
    WalkSpeedSaved = nil,
    CurrentRoom = nil,
}

setStatus = function() end

-- ============ KEYPRESS ============
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

-- ============ CHARACTER SETUP ============
local function setupCharacter(char)
    State.Character = char
    State.Humanoid = char:WaitForChild("Humanoid")
    State.RootPart = char:WaitForChild("HumanoidRootPart")
    
    if State.WalkSpeedSaved == nil and State.Humanoid then
        State.WalkSpeedSaved = State.Humanoid.WalkSpeed
    end
end

if LocalPlayer.Character then
    setupCharacter(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(setupCharacter)

-- ============ WALKSPEED ============
local function applyWalkSpeed()
    if State.Humanoid then
        pcall(function()
            State.Humanoid.WalkSpeed = CONFIG.WalkSpeed
        end)
    end
end

local function restoreWalkSpeed()
    if State.Humanoid and State.WalkSpeedSaved then
        pcall(function()
            State.Humanoid.WalkSpeed = State.WalkSpeedSaved
        end)
    end
end

-- ============ SHIFTLOCK ============
local function setShiftlock(enabled)
    pcall(function()
        local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
        if not sl then
            for _, obj in ipairs(LocalPlayer:GetDescendants()) do
                if obj.Name:lower():find("shiftlock") then
                    sl = obj
                    break
                end
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

local function enableShiftlock() setShiftlock(true) end
local function restoreShiftlock()
    pcall(function()
        local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
        if sl and State.ShiftlockSaved ~= nil then
            sl.Value = State.ShiftlockSaved
        end
    end)
end

-- ============ REMOTES ============
local function startGame()
    local remotes = ReplicatedStorage:FindFirstChild("remotes")
    if not remotes then return end
    local change = remotes:FindFirstChild("changeStartValue")
    if change then
        change:FireServer()
        setStatus("Game started")
    end
end

local function upgradeSpell()
    if not CONFIG.AutoUpgrade then return end
    local remotes = ReplicatedStorage:FindFirstChild("remotes")
    if not remotes then return end
    local spend = remotes:FindFirstChild("spendSkillPoint")
    if spend then
        spend:FireServer(CONFIG.SkillName, 1)
        State.LastUpgrade = tick()
    end
end

-- ============ ENEMY FOLDER SCANNER (MULTI-ROOM) ⭐ ============
-- Scan SEMUA folder bernama "enemyFolder" di workspace
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

local function getEnemyFolders(force)
    local now = tick()
    -- rescan kalau belum pernah, force, atau udah lewat interval
    if force 
        or #State.EnemyFolders == 0 
        or (now - State.LastFolderScan) >= CONFIG.FolderScanInterval then
        State.EnemyFolders = scanAllEnemyFolders()
        State.LastFolderScan = now
    end
    return State.EnemyFolders
end

-- ============ HUMANOID & HRP ROBUST ============
local function getHumanoidAndHRP(enemy)
    if not enemy or not enemy.Parent then return nil, nil end
    
    local hum = enemy:FindFirstChildOfClass("Humanoid") 
        or enemy:FindFirstChildWhichIsA("Humanoid", true)
    if not hum then return nil, nil end
    
    local hp = hum.Health
    local attrHp = enemy:GetAttribute("Health") or enemy:GetAttribute("health")
    if attrHp then hp = attrHp end
    if not hp or hp <= 0 then return nil, nil end
    
    local ok, st = pcall(function() return hum:GetState() end)
    if ok and st == Enum.HumanoidStateType.Dead then return nil, nil end
    
    local hrp = enemy:FindFirstChild("HumanoidRootPart")
        or enemy:FindFirstChild("HumanoidRootPart", true)
        or enemy.PrimaryPart
        or enemy:FindFirstChild("Torso")
        or enemy:FindFirstChild("Torso", true)
        or enemy:FindFirstChild("UpperTorso")
        or enemy:FindFirstChild("UpperTorso", true)
        or enemy:FindFirstChild("Head")
        or enemy:FindFirstChild("Head", true)
    
    if not hrp then return nil, nil end
    return hum, hrp
end

-- ============ FIND ENEMY DI SEMUA ROOM ⭐ ============
local function findNearestEnemy()
    local folders = getEnemyFolders(false)
    if #folders == 0 then
        setStatus("No enemyFolder found")
        return nil, 0, nil
    end
    if not State.RootPart then return nil, 0, nil end

    local nearest, nearestDist = nil, math.huge
    local nearestFolder = nil
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
                            nearestFolder = folder
                        end
                    end
                end
            end
            
            if roomCount > 0 then
                table.insert(roomInfo, string.format("%s:%d", roomName, roomCount))
            end
        end
    end
    
    -- simpan folder tempat enemy berada
    State.CurrentRoom = nearestFolder
    
    -- kalau 0 enemy, force rescan next loop
    if totalCount == 0 then
        State.LastFolderScan = 0
    end
    
    return nearest, totalCount, roomInfo
end

-- ============ FACE ENEMY (SendTouchEvent) ============
local function touchFacing(enemy)
    if not CONFIG.UseTouchToFace then return false end
    if not enemy or not Camera then return false end
    
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return false end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
    if not onScreen then return false end
    
    local tapX = math.floor(screenPos.X)
    local tapY = math.floor(screenPos.Y)
    
    local ok = pcall(function()
        VirtualInputManager:SendTouchEvent(tapX, tapY, Enum.UserInputState.Begin, false, game)
        task.wait(0.02)
        VirtualInputManager:SendTouchEvent(tapX, tapY, Enum.UserInputState.End, false, game)
    end)
    
    if not ok then
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(tapX, tapY, 0, true, game, 0)
            task.wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(tapX, tapY, 0, false, game, 0)
        end)
    end
    
    return true
end

local function faceEnemyCFrame(enemy)
    if not enemy or not State.RootPart then return end
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return end
    local myPos = State.RootPart.Position
    local targetPos = Vector3.new(hrp.Position.X, myPos.Y, hrp.Position.Z)
    State.RootPart.CFrame = CFrame.lookAt(myPos, targetPos)
end

local function faceEnemy(enemy)
    local ok = false
    if CONFIG.UseTouchToFace then
        ok = touchFacing(enemy)
    end
    if not ok then
        faceEnemyCFrame(enemy)
    end
end

-- ============ ANTI-STUCK ============
local function checkStuck()
    if not State.RootPart then return false end
    local myPos = State.RootPart.Position
    if State.LastPos then
        local moved = (myPos - State.LastPos).Magnitude
        if moved < 0.5 then
            State.StuckTime = State.StuckTime + 0.05
        else
            State.StuckTime = 0
        end
    end
    State.LastPos = myPos
    return State.StuckTime >= CONFIG.StuckTimeout
end

local function unstick()
    if not State.Humanoid then return end
    State.Humanoid.Jump = true
    task.wait(0.05)
    local myPos = State.RootPart.Position
    local offset = Vector3.new(
        (math.random() - 0.5) * 8,
        0,
        (math.random() - 0.5) * 8
    )
    State.Humanoid:MoveTo(myPos + offset)
    State.StuckTime = 0
end

-- ============ KITING ============
local function kiteAway(enemy)
    if not State.Humanoid or not State.RootPart then return end
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return end
    
    local myPos = State.RootPart.Position
    local awayDir = (myPos - hrp.Position)
    awayDir = Vector3.new(awayDir.X, 0, awayDir.Z).Unit
    local targetPos = myPos + awayDir * (CONFIG.KeepDistance * 0.5)
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 3, AgentHeight = 5, AgentCanJump = true,
        AgentJumpHeight = 10, AgentMaxSlope = 45,
    })
    
    local ok = pcall(function()
        path:ComputeAsync(myPos, targetPos)
    end)
    
    if ok and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        if #waypoints >= 2 then
            local wp = waypoints[2]
            State.Humanoid:MoveTo(wp.Position)
            if wp.Action == Enum.PathWaypointAction.Jump then
                State.Humanoid.Jump = true
            end
        end
    else
        State.Humanoid:MoveTo(targetPos)
    end
end

-- ============ WALK (NON-BLOCKING) ============
local function walkToEnemy(enemy)
    if not State.Humanoid or not State.RootPart then return end
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return end
    
    if checkStuck() then
        unstick()
        return
    end
    
    local now = tick()
    if now - State.LastPathCompute < CONFIG.PathRecomputeDelay then
        return
    end
    State.LastPathCompute = now
    
    local myPos = State.RootPart.Position
    local path = PathfindingService:CreatePath({
        AgentRadius = 3, AgentHeight = 5, AgentCanJump = true,
        AgentJumpHeight = 10, AgentMaxSlope = 45,
        Costs = { Water = 20 },
    })
    
    local ok = pcall(function()
        path:ComputeAsync(myPos, hrp.Position)
    end)
    
    if ok and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        if #waypoints >= 2 then
            local wp = waypoints[2]
            State.Humanoid:MoveTo(wp.Position)
            if wp.Action == Enum.PathWaypointAction.Jump then
                State.Humanoid.Jump = true
            end
        end
    else
        State.Humanoid:MoveTo(hrp.Position)
    end
end

-- ============ ATTACK ============
local function attackEnemy(enemy)
    local now = tick()
    if now - State.LastAttack < CONFIG.AttackCooldown then return end
    State.LastAttack = now

    faceEnemy(enemy)
    pressQ()
    task.wait(0.08)
    pressE()
end

-- ============ MAIN LOOP ============
local function mainLoop()
    while State.Running do
        task.wait(0.05)

        if not State.Character or not State.Character.Parent then
            task.wait(0.5)
            continue
        end

        if State.Humanoid.Health <= 0 then
            task.wait(1)
            continue
        end

        -- walkspeed reapply
        if CONFIG.WalkSpeed ~= 16 and State.Humanoid.WalkSpeed ~= CONFIG.WalkSpeed then
            applyWalkSpeed()
        end

        -- auto upgrade
        if CONFIG.AutoUpgrade and (tick() - State.LastUpgrade) >= CONFIG.UpgradeInterval then
            upgradeSpell()
        end

        -- find enemy di SEMUA room
        local enemy, count, roomInfo = findNearestEnemy()
        State.CurrentEnemy = enemy

        if enemy then
            if CONFIG.UseShiftlock then
                local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
                if sl and sl.Value == false then
                    enableShiftlock()
                end
            end
            
            local _, ehrp = getHumanoidAndHRP(enemy)
            if ehrp then
                local dist = (ehrp.Position - State.RootPart.Position).Magnitude
                local kiteThreshold = CONFIG.KeepDistance - CONFIG.DistanceTolerance
                
                -- room info string
                local roomStr = ""
                if roomInfo and #roomInfo > 0 then
                    roomStr = " [" .. table.concat(roomInfo, ", ") .. "]"
                end

                if dist < kiteThreshold then
                    setStatus(string.format("Kiting (%.1f) | %d%s", dist, count or 0, roomStr))
                    task.spawn(function() attackEnemy(enemy) end)
                    kiteAway(enemy)
                elseif dist <= CONFIG.AttackDistance then
                    attackEnemy(enemy)
                    setStatus(string.format("Attacking (%.1f) | %d%s", dist, count or 0, roomStr))
                else
                    setStatus(string.format("Approaching (%.1f) | %d%s", dist, count or 0, roomStr))
                    walkToEnemy(enemy)
                end
            end
        else
            State.CurrentEnemy = nil
            State.StuckTime = 0
            setStatus(string.format("No enemy | %d rooms scanned", #State.EnemyFolders))
        end
    end
    
    if CONFIG.UseShiftlock then restoreShiftlock() end
    restoreWalkSpeed()
end

-- ============================================
--              MOBILE UI
-- ============================================
local function createUI()
    if CoreGui:FindFirstChild("AutoFarmUI") then
        CoreGui.AutoFarmUI:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoFarmUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = CoreGui

    local floatBtn = Instance.new("TextButton")
    floatBtn.Name = "FloatBtn"
    floatBtn.Size = UDim2.new(0, 60, 0, 60)
    floatBtn.Position = UDim2.new(0, 15, 0.5, -30)
    floatBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
    floatBtn.Text = "⚔"
    floatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    floatBtn.TextSize = 26
    floatBtn.Font = Enum.Font.GothamBold
    floatBtn.BorderSizePixel = 0
    floatBtn.Active = true
    floatBtn.Draggable = true
    floatBtn.Parent = screenGui

    local fbCorner = Instance.new("UICorner")
    fbCorner.CornerRadius = UDim.new(1, 0)
    fbCorner.Parent = floatBtn

    local fbStroke = Instance.new("UIStroke")
    fbStroke.Color = Color3.fromRGB(255, 255, 255)
    fbStroke.Thickness = 2
    fbStroke.Parent = floatBtn

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 300, 0, 580)
    main.Position = UDim2.new(0.5, -150, 0.5, -290)
    main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Visible = false
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
    title.Parent = main

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 14)
    titleCorner.Parent = title

    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 15)
    titleFix.Position = UDim2.new(0, 0, 1, -15)
    titleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    titleFix.BorderSizePixel = 0
    titleFix.Parent = title

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -100, 1, 0)
    titleText.Position = UDim2.new(0, 15, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "⚔ AUTO FARM v13"
    titleText.TextColor3 = Color3.fromRGB(200, 220, 255)
    titleText.TextSize = 17
    titleText.Font = Enum.Font.GothamBold
    titleText.TextXAlignment = Enum.TextXAlignment.Left
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
    closeBtn.Parent = title

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 8)
    closeCorner.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        main.Visible = false
        floatBtn.Visible = true
    end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -20, 1, -60)
    scroll.Position = UDim2.new(0, 10, 0, 50)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
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
        row.Parent = scroll

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 8)
        rowCorner.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.45, -10, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
        lbl.TextSize = 14
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0.5, -15, 0, 32)
        box.Position = UDim2.new(0.48, 0, 0, 6)
        box.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        box.Text = tostring(defaultVal)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.TextSize = 14
        box.Font = Enum.Font.Gotham
        box.BorderSizePixel = 0
        box.ClearTextOnFocus = false
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

    createInput("Attack Distance", CONFIG.AttackDistance, 1, function(v) CONFIG.AttackDistance = v end)
    createInput("Keep Distance", CONFIG.KeepDistance, 2, function(v) CONFIG.KeepDistance = v end)
    createInput("Distance Tolerance", CONFIG.DistanceTolerance, 3, function(v) CONFIG.DistanceTolerance = v end)
    createInput("Attack Cooldown", CONFIG.AttackCooldown, 4, function(v) CONFIG.AttackCooldown = v end)
    createInput("Walk Speed", CONFIG.WalkSpeed, 5, function(v) 
        CONFIG.WalkSpeed = v
        applyWalkSpeed()
    end)
    createInput("Stuck Timeout", CONFIG.StuckTimeout, 6, function(v) CONFIG.StuckTimeout = v end)
    createInput("Folder Scan Interval", CONFIG.FolderScanInterval, 7, function(v) CONFIG.FolderScanInterval = v end)
    createInput("Skill Name", CONFIG.SkillName, 8, function(v) CONFIG.SkillName = v end)
    createInput("Upgrade Interval", CONFIG.UpgradeInterval, 9, function(v) CONFIG.UpgradeInterval = v end)
    createToggle("Auto Upgrade", CONFIG.AutoUpgrade, 10, function(v) CONFIG.AutoUpgrade = v end)
    createToggle("Use Shiftlock", CONFIG.UseShiftlock, 11, function(v) 
        CONFIG.UseShiftlock = v
        if v then enableShiftlock() else restoreShiftlock() end
    end)
    createToggle("Touch Face", CONFIG.UseTouchToFace, 12, function(v) CONFIG.UseTouchToFace = v end)

    local startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(1, 0, 0, 55)
    startBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
    startBtn.Text = "▶  START FARM"
    startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    startBtn.TextSize = 17
    startBtn.Font = Enum.Font.GothamBold
    startBtn.BorderSizePixel = 0
    startBtn.LayoutOrder = 13
    startBtn.Parent = scroll

    local startCorner = Instance.new("UICorner")
    startCorner.CornerRadius = UDim.new(0, 10)
    startCorner.Parent = startBtn

    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(1, 0, 0, 40)
    statusLbl.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    statusLbl.Text = "Status: Idle"
    statusLbl.TextColor3 = Color3.fromRGB(180, 220, 180)
    statusLbl.TextSize = 13
    statusLbl.Font = Enum.Font.GothamMedium
    statusLbl.BorderSizePixel = 0
    statusLbl.LayoutOrder = 14
    statusLbl.Parent = scroll

    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 8)
    statusCorner.Parent = statusLbl

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, 0, 0, 20)
    footer.BackgroundTransparency = 1
    footer.Text = "Multi-room v13"
    footer.TextColor3 = Color3.fromRGB(120, 120, 130)
    footer.TextSize = 11
    footer.Font = Enum.Font.Gotham
    footer.LayoutOrder = 15
    footer.Parent = scroll

    setStatus = function(msg)
        pcall(function()
            statusLbl.Text = "Status: " .. msg
        end)
    end

    floatBtn.MouseButton1Click:Connect(function()
        main.Visible = not main.Visible
        floatBtn.Visible = false
    end)

    startBtn.MouseButton1Click:Connect(function()
        if State.Running then
            State.Running = false
            startBtn.Text = "▶  START FARM"
            startBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
            floatBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
            setStatus("Stopped")
            if CONFIG.UseShiftlock then restoreShiftlock() end
            restoreWalkSpeed()
        else
            State.Running = true
            startBtn.Text = "■  STOP FARM"
            startBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            floatBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            setStatus("Starting...")

            task.spawn(function()
                startGame()
                task.wait(1.5)
                if CONFIG.AutoUpgrade then
                    upgradeSpell()
                    task.wait(0.5)
                end
                if CONFIG.UseShiftlock then enableShiftlock() end
                applyWalkSpeed()
                setStatus("Running")
                mainLoop()
            end)
        end
    end)

    setStatus("Tap ⚔ untuk buka")
end

-- ============ INIT ============
createUI()
print("[AutoFarm Mobile v13] Loaded - multi-room support")