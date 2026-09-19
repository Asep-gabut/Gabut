-- ============================================
-- AUTO FARM DUNGEON - MOBILE EDITION (v16)
-- Simple mode: anti-nyangkut tembok
-- ============================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============ KONFIGURASI (SIMPLE) ============
local CONFIG = {
    -- basic
    AttackDistance = 50,
    KeepDistance = 30,
    AttackCooldown = 0.5,
    WalkSpeed = 20,
    AutoUpgrade = true,
    UseShiftlock = true,
    -- anti-stuck (jarang perlu diubah)
    StuckTimeout = 2,
    UnstickAttempts = 3,
}

local State = {
    Running = false,
    Character = nil,
    Humanoid = nil,
    RootPart = nil,
    LastAttack = 0,
    LastUpgrade = 0,
    LastPos = nil,
    StuckTime = 0,
    UnstickCount = 0,
    EnemyFolders = {},
    LastFolderScan = 0,
    -- path
    PathWaypoints = nil,
    PathIndex = 1,
    PathEnemyRef = nil,
    PathTargetPos = nil,
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

-- ============ CHARACTER ============
local function setupCharacter(char)
    State.Character = char
    State.Humanoid = char:WaitForChild("Humanoid")
    State.RootPart = char:WaitForChild("HumanoidRootPart")
end

if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(setupCharacter)

-- ============ WALKSPEED ============
local function applyWalkSpeed()
    if State.Humanoid then
        pcall(function() State.Humanoid.WalkSpeed = CONFIG.WalkSpeed end)
    end
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
        if sl then sl.Value = enabled end
    end)
end

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

-- ============ ANTI-STUCK (SIMPLE & AGRESSIVE) ============
local function resetPath()
    State.PathWaypoints = nil
    State.PathIndex = 1
    State.PathEnemyRef = nil
    State.PathTargetPos = nil
end

local function checkStuck()
    if not State.RootPart then return false end
    local myPos = State.RootPart.Position
    if State.LastPos then
        local moved = (myPos - State.LastPos).Magnitude
        if moved < 0.5 then
            State.StuckTime = State.StuckTime + 0.05
        else
            State.StuckTime = 0
            State.UnstickCount = 0  -- reset kalau udah gerak
        end
    end
    State.LastPos = myPos
    return State.StuckTime >= CONFIG.StuckTimeout
end

local function unstick()
    if not State.Humanoid or not State.RootPart then return end
    
    State.UnstickCount = State.UnstickCount + 1
    local myPos = State.RootPart.Position
    
    -- Strategi bertingkat berdasarkan attempt
    if State.UnstickCount == 1 then
        -- Attempt 1: lompat + jalan random
        State.Humanoid.Jump = true
        task.wait(0.1)
        local angle = math.random() * math.pi * 2
        local offset = Vector3.new(math.cos(angle) * 8, 0, math.sin(angle) * 8)
        State.Humanoid:MoveTo(myPos + offset)
    elseif State.UnstickCount == 2 then
        -- Attempt 2: mundur dikit + lompat
        State.Humanoid.Jump = true
        task.wait(0.1)
        local back = -State.RootPart.CFrame.LookVector * 6
        State.Humanoid:MoveTo(myPos + back)
    else
        -- Attempt 3+: teleport dikit (kalau executor support)
        pcall(function()
            State.RootPart.CFrame = State.RootPart.CFrame + Vector3.new(0, 3, 0)
        end)
        State.Humanoid.Jump = true
        task.wait(0.2)
        local angle = math.random() * math.pi * 2
        local offset = Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
        State.Humanoid:MoveTo(myPos + offset)
        State.UnstickCount = 0  -- reset counter
    end
    
    State.StuckTime = 0
    resetPath()  -- paksa recompute path
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
    
    -- kabur: pakai MoveTo langsung aja
    State.Humanoid:MoveTo(targetPos)
end

-- ============ WALK (SMOOTH, CACHED PATH) ============
local function walkToEnemy(enemy)
    if not State.Humanoid or not State.RootPart then return end
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return end
    
    -- ANTI-STUCK cek dulu
    if checkStuck() then
        unstick()
        return
    end
    
    local myPos = State.RootPart.Position
    local enemyPos = hrp.Position
    
    -- perlu recompute?
    local needRecompute = false
    if not State.PathWaypoints or #State.PathWaypoints == 0 then needRecompute = true end
    if State.PathEnemyRef ~= enemy then needRecompute = true end
    if State.PathWaypoints and State.PathIndex > #State.PathWaypoints then needRecompute = true end
    if State.PathTargetPos then
        local moved = (enemyPos - State.PathTargetPos).Magnitude
        if moved > 8 then needRecompute = true end
    end
    
    -- recompute
    if needRecompute then
        local path = PathfindingService:CreatePath({
            AgentRadius = 3, AgentHeight = 5, AgentCanJump = true,
            AgentJumpHeight = 10, AgentMaxSlope = 45,
        })
        
        local ok = pcall(function()
            path:ComputeAsync(myPos, enemyPos)
        end)
        
        if ok and path.Status == Enum.PathStatus.Success then
            State.PathWaypoints = path:GetWaypoints()
            State.PathIndex = 2
            State.PathTargetPos = enemyPos
            State.PathEnemyRef = enemy
        else
            -- fallback: coba jump + gerak langsung
            State.Humanoid.Jump = true
            State.Humanoid:MoveTo(enemyPos)
            return
        end
    end
    
    -- follow waypoint
    if State.PathWaypoints and State.PathIndex <= #State.PathWaypoints then
        local wp = State.PathWaypoints[State.PathIndex]
        local dist = (myPos - wp.Position).Magnitude
        
        if dist <= 4 then
            State.PathIndex = State.PathIndex + 1
            if State.PathIndex <= #State.PathWaypoints then
                local nextWp = State.PathWaypoints[State.PathIndex]
                State.Humanoid:MoveTo(nextWp.Position)
                if nextWp.Action == Enum.PathWaypointAction.Jump then
                    State.Humanoid.Jump = true
                end
            end
        else
            State.Humanoid:MoveTo(wp.Position)
            if wp.Action == Enum.PathWaypointAction.Jump then
                State.Humanoid.Jump = true
            end
        end
    end
end

-- ============ ATTACK ============
local function attackEnemy(enemy)
    local now = tick()
    if now - State.LastAttack < CONFIG.AttackCooldown then return end
    State.LastAttack = now
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
        if State.Humanoid.WalkSpeed ~= CONFIG.WalkSpeed then
            applyWalkSpeed()
        end

        -- auto upgrade
        if CONFIG.AutoUpgrade and (tick() - State.LastUpgrade) >= 3 then
            upgradeSpell()
        end

        local enemy, count, roomInfo = findNearestEnemy()

        if enemy then
            if CONFIG.UseShiftlock then
                local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
                if sl and sl.Value == false then setShiftlock(true) end
            end
            
            local _, ehrp = getHumanoidAndHRP(enemy)
            if ehrp then
                local dist = (ehrp.Position - State.RootPart.Position).Magnitude
                local kiteThreshold = CONFIG.KeepDistance - 3
                
                local roomStr = ""
                if roomInfo and #roomInfo > 0 then
                    roomStr = " [" .. table.concat(roomInfo, ", ") .. "]"
                end

                if dist < kiteThreshold then
                    setStatus(string.format("Kiting (%.1f) | %d%s", dist, count, roomStr))
                    resetPath()
                    task.spawn(function() attackEnemy(enemy) end)
                    kiteAway(enemy)
                elseif dist <= CONFIG.AttackDistance then
                    attackEnemy(enemy)
                    resetPath()
                    setStatus(string.format("Attacking (%.1f) | %d%s", dist, count, roomStr))
                else
                    setStatus(string.format("Approaching (%.1f) | %d%s", dist, count, roomStr))
                    walkToEnemy(enemy)
                end
            end
        else
            State.StuckTime = 0
            resetPath()
            setStatus(string.format("No enemy | %d rooms", #State.EnemyFolders))
        end
    end
end

-- ============================================
--      UI
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

    -- STATUS OVERLAY
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

    -- FLOATING BUTTON
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

    -- SETTINGS PANEL
    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 300, 0, 480)
    main.Position = UDim2.new(0.5, -150, 0.5, -240)
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

    -- setting minimalis
    createInput("Attack Distance", CONFIG.AttackDistance, 1, function(v) CONFIG.AttackDistance = v end)
    createInput("Keep Distance", CONFIG.KeepDistance, 2, function(v) CONFIG.KeepDistance = v end)
    createInput("Attack Cooldown", CONFIG.AttackCooldown, 3, function(v) CONFIG.AttackCooldown = v end)
    createInput("Walk Speed", CONFIG.WalkSpeed, 4, function(v) 
        CONFIG.WalkSpeed = v
        applyWalkSpeed()
    end)
    createToggle("Auto Upgrade", CONFIG.AutoUpgrade, 5, function(v) CONFIG.AutoUpgrade = v end)
    createToggle("Use Shiftlock", CONFIG.UseShiftlock, 6, function(v) 
        CONFIG.UseShiftlock = v
        if v then setShiftlock(true) else setShiftlock(false) end
    end)

    local startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(1, 0, 0, 55)
    startBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
    startBtn.Text = "▶  START FARM"
    startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    startBtn.TextSize = 17
    startBtn.Font = Enum.Font.GothamBold
    startBtn.BorderSizePixel = 0
    startBtn.LayoutOrder = 7
    startBtn.ZIndex = 11
    startBtn.Parent = scroll

    local startCorner = Instance.new("UICorner")
    startCorner.CornerRadius = UDim.new(0, 10)
    startCorner.Parent = startBtn

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, 0, 0, 20)
    footer.BackgroundTransparency = 1
    footer.Text = "Simple Mode v16"
    footer.TextColor3 = Color3.fromRGB(120, 120, 130)
    footer.TextSize = 11
    footer.Font = Enum.Font.Gotham
    footer.LayoutOrder = 8
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
                if CONFIG.AutoUpgrade then
                    upgradeSpell()
                    task.wait(0.5)
                end
                if CONFIG.UseShiftlock then setShiftlock(true) end
                applyWalkSpeed()
                setStatus("Running")
                mainLoop()
            end)
        end
    end)

    setStatus("Idle - tap ⚙")
end

-- ============ INIT ============
createUI()
print("[AutoFarm Mobile v16] Loaded - simple mode")