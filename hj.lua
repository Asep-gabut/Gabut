-- ============================================
-- AUTO FARM DUNGEON - MOBILE EDITION (v7)
-- Shiftlock (AlignOrientation) + Robust enemy detect
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

-- ============ KONFIGURASI ============
local CONFIG = {
    AttackRange = 30,
    WalkDistance = 20,
    MinDistance = 10,
    KiteDistance = 20,
    AttackCooldown = 0.5,
    SkillName = "spellPower",
    AutoUpgrade = true,
    UpgradeInterval = 3,
    FaceEnemy = true,
    Kiting = true,
    LockCamera = true,
}

local State = {
    Running = false,
    Character = nil,
    Humanoid = nil,
    RootPart = nil,
    LastAttack = 0,
    LastUpgrade = 0,
    EnemyFolder = nil,
    Orientation = nil,
    OrientationAttachment = nil,
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

-- ============ SHIFTLOCK SETUP (AlignOrientation) ============
local function setupOrientation()
    if not State.RootPart then return end
    
    -- hapus yang lama
    if State.Orientation then State.Orientation:Destroy() end
    if State.OrientationAttachment then State.OrientationAttachment:Destroy() end
    
    -- auto rotate OFF biar AO yang atur
    if State.Humanoid then
        State.Humanoid.AutoRotate = false
    end
    
    local attach = Instance.new("Attachment")
    attach.Name = "EnemyLockAttach"
    attach.Parent = State.RootPart
    State.OrientationAttachment = attach
    
    local ao = Instance.new("AlignOrientation")
    ao.Name = "EnemyLockAO"
    ao.Attachment0 = attach
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.MaxTorque = 100000
    ao.MaxAngularVelocity = 100000
    ao.Responsiveness = 30
    ao.Parent = State.RootPart
    State.Orientation = ao
end

local function lockToEnemy(enemy)
    if not CONFIG.FaceEnemy then return end
    if not State.Orientation or not State.RootPart then return end
    
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return end
    
    -- target posisi horizontal (y = my y) biar karakter gak miring
    local myPos = State.RootPart.Position
    local enemyPos = hrp.Position
    local targetPos = Vector3.new(enemyPos.X, myPos.Y, enemyPos.Z)
    
    -- CFrame lookAt → AO akan smooth rotate karakter ke sini
    State.Orientation.CFrame = CFrame.lookAt(myPos, targetPos)
end

-- ============ CHARACTER SETUP ============
local function setupCharacter(char)
    State.Character = char
    State.Humanoid = char:WaitForChild("Humanoid")
    State.RootPart = char:WaitForChild("HumanoidRootPart")
    
    task.wait(0.5)
    setupOrientation()
end

if LocalPlayer.Character then
    setupCharacter(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(setupCharacter)

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

-- ============ ENEMY FOLDER (DIRECT SCAN + CACHE) ============
local function findEnemyFolder()
    -- pakai cache kalau masih valid
    if State.EnemyFolder and State.EnemyFolder.Parent then
        return State.EnemyFolder
    end
    
    -- scan seluruh workspace
    for _, obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("Folder") or obj:IsA("Model")) 
            and obj.Name:lower():find("enemyfolder") then
            State.EnemyFolder = obj
            return obj
        end
    end
    return nil
end

-- ============ HUMANOID & HRP ROBUST ============
local function getHumanoidAndHRP(enemy)
    if not enemy or not enemy.Parent then return nil, nil end
    
    local hum = enemy:FindFirstChildOfClass("Humanoid") 
        or enemy:FindFirstChildWhichIsA("Humanoid", true)
    if not hum then return nil, nil end
    
    -- cek health (fallback ke attribute)
    local hp = hum.Health
    local attrHp = enemy:GetAttribute("Health") 
        or enemy:GetAttribute("health")
        or hum:GetAttribute("Health")
    if attrHp then hp = attrHp end
    
    if not hp or hp <= 0 then return nil, nil end
    
    -- cek state Dead
    local ok, state = pcall(function() return hum:GetState() end)
    if ok and state == Enum.HumanoidStateType.Dead then return nil, nil end
    
    -- cari HRP
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

local function findNearestEnemy()
    local folder = findEnemyFolder()
    if not folder then
        setStatus("enemyFolder not found")
        return nil, 0
    end
    if not State.RootPart then return nil, 0 end

    local nearest, nearestDist = nil, math.huge
    local count = 0
    
    for _, enemy in ipairs(folder:GetChildren()) do
        if enemy:IsA("Model") or enemy:IsA("Folder") then
            local hum, hrp = getHumanoidAndHRP(enemy)
            if hum and hrp then
                count = count + 1
                local dist = (hrp.Position - State.RootPart.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = enemy
                end
            end
        end
    end
    
    -- refresh folder cache kalau 0 enemy (mungkin ganti room)
    if count == 0 then
        State.EnemyFolder = nil
    end
    
    return nearest, count
end

-- ============ KITING ============
local function kiteAway(enemy)
    if not State.Humanoid or not State.RootPart then return end
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return end
    
    local myPos = State.RootPart.Position
    local awayDir = (myPos - hrp.Position)
    awayDir = Vector3.new(awayDir.X, 0, awayDir.Z).Unit
    
    local targetPos = myPos + awayDir * CONFIG.KiteDistance
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 3,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentJumpHeight = 10,
        AgentMaxSlope = 45,
    })
    
    local ok = pcall(function()
        path:ComputeAsync(myPos, targetPos)
    end)
    
    if ok and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for i, wp in ipairs(waypoints) do
            if not State.Running then return end
            if i == 1 then continue end
            State.Humanoid:MoveTo(wp.Position)
            if wp.Action == Enum.PathWaypointAction.Jump then
                State.Humanoid.Jump = true
            end
            local _, curHrp = getHumanoidAndHRP(enemy)
            if curHrp and State.RootPart then
                local d = (curHrp.Position - State.RootPart.Position).Magnitude
                if d >= CONFIG.KiteDistance then break end
            end
            State.Humanoid.MoveToFinished:Wait()
        end
    else
        State.Humanoid:MoveTo(targetPos)
    end
end

-- ============ ATTACK ============
local function attackEnemy(enemy)
    local now = tick()
    if now - State.LastAttack < CONFIG.AttackCooldown then return end
    State.LastAttack = now

    lockToEnemy(enemy)
    pressQ()
    task.wait(0.08)
    pressE()
end

-- ============ WALK ============
local function walkToEnemy(enemy)
    if not enemy or not State.Humanoid or not State.RootPart then return end
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return end

    local myPos = State.RootPart.Position
    local dist = (hrp.Position - myPos).Magnitude

    if dist <= CONFIG.WalkDistance then
        State.Humanoid:MoveTo(myPos)
        return
    end

    local path = PathfindingService:CreatePath({
        AgentRadius = 3,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentJumpHeight = 10,
        AgentMaxSlope = 45,
    })

    local ok = pcall(function()
        path:ComputeAsync(myPos, hrp.Position)
    end)

    if ok and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for i, wp in ipairs(waypoints) do
            if not State.Running then return end
            if i == 1 then continue end
            local _, curHrp = getHumanoidAndHRP(enemy)
            if curHrp and State.RootPart then
                local d = (curHrp.Position - State.RootPart.Position).Magnitude
                if d <= CONFIG.WalkDistance then break end
            end
            State.Humanoid:MoveTo(wp.Position)
            if wp.Action == Enum.PathWaypointAction.Jump then
                State.Humanoid.Jump = true
            end
            State.Humanoid.MoveToFinished:Wait()
        end
    else
        State.Humanoid:MoveTo(hrp.Position)
    end
end

-- ============ CAMERA LOCK ============
local function updateCamera()
    if not CONFIG.LockCamera then return end
    if not State.Running then return end
    if not State.RootPart then return end
    
    local enemy = State.CurrentEnemy
    if not enemy then return end
    
    local _, hrp = getHumanoidAndHRP(enemy)
    if not hrp then return end
    
    local camPos = Camera.CFrame.Position
    Camera.CFrame = CFrame.new(camPos, hrp.Position)
end

RunService.RenderStepped:Connect(function()
    if State.Running and CONFIG.LockCamera then
        pcall(updateCamera)
    end
end)

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

        -- AUTO UPGRADE
        if CONFIG.AutoUpgrade and (tick() - State.LastUpgrade) >= CONFIG.UpgradeInterval then
            upgradeSpell()
        end

        -- FIND ENEMY
        local enemy, count = findNearestEnemy()
        State.CurrentEnemy = enemy
        
        if enemy then
            local _, ehrp = getHumanoidAndHRP(enemy)
            if ehrp then
                local dist = (ehrp.Position - State.RootPart.Position).Magnitude

                if CONFIG.Kiting and dist <= CONFIG.MinDistance then
                    setStatus(string.format("Kiting! (%.1f) | %d enemies", dist, count or 0))
                    task.spawn(function() attackEnemy(enemy) end)
                    kiteAway(enemy)
                elseif dist <= CONFIG.AttackRange then
                    attackEnemy(enemy)
                    setStatus(string.format("Attacking (%.1f) | %d enemies", dist, count or 0))
                else
                    walkToEnemy(enemy)
                    setStatus(string.format("Walking (%.1f) | %d enemies", dist, count or 0))
                end
            end
        else
            State.CurrentEnemy = nil
            setStatus("Scanning... 0 enemies")
        end
    end
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
    titleText.Text = "⚔ AUTO FARM v7"
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

    createInput("Attack Range", CONFIG.AttackRange, 1, function(v) CONFIG.AttackRange = v end)
    createInput("Walk Distance", CONFIG.WalkDistance, 2, function(v) CONFIG.WalkDistance = v end)
    createInput("Min Distance", CONFIG.MinDistance, 3, function(v) CONFIG.MinDistance = v end)
    createInput("Kite Distance", CONFIG.KiteDistance, 4, function(v) CONFIG.KiteDistance = v end)
    createInput("Attack Cooldown", CONFIG.AttackCooldown, 5, function(v) CONFIG.AttackCooldown = v end)
    createInput("Skill Name", CONFIG.SkillName, 6, function(v) CONFIG.SkillName = v end)
    createInput("Upgrade Interval", CONFIG.UpgradeInterval, 7, function(v) CONFIG.UpgradeInterval = v end)
    createToggle("Auto Upgrade", CONFIG.AutoUpgrade, 8, function(v) CONFIG.AutoUpgrade = v end)
    createToggle("Face Enemy", CONFIG.FaceEnemy, 9, function(v) 
        CONFIG.FaceEnemy = v
        if not v and State.Orientation then
            State.Orientation:Destroy()
            State.Orientation = nil
        elseif v and State.RootPart then
            setupOrientation()
        end
    end)
    createToggle("Kiting", CONFIG.Kiting, 10, function(v) CONFIG.Kiting = v end)
    createToggle("Lock Camera", CONFIG.LockCamera, 11, function(v) CONFIG.LockCamera = v end)

    local startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(1, 0, 0, 55)
    startBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
    startBtn.Text = "▶  START FARM"
    startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    startBtn.TextSize = 17
    startBtn.Font = Enum.Font.GothamBold
    startBtn.BorderSizePixel = 0
    startBtn.LayoutOrder = 12
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
    statusLbl.LayoutOrder = 13
    statusLbl.Parent = scroll

    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 8)
    statusCorner.Parent = statusLbl

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, 0, 0, 20)
    footer.BackgroundTransparency = 1
    footer.Text = "Shiftlock v7 | Q+E | Kite mode"
    footer.TextColor3 = Color3.fromRGB(120, 120, 130)
    footer.TextSize = 11
    footer.Font = Enum.Font.Gotham
    footer.LayoutOrder = 14
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
            -- restore rotation
            if State.Humanoid then State.Humanoid.AutoRotate = true end
            if State.Orientation then State.Orientation:Destroy() State.Orientation = nil end
            setStatus("Stopped")
        else
            State.Running = true
            startBtn.Text = "■  STOP FARM"
            startBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            floatBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            setStatus("Starting...")

            if State.RootPart then setupOrientation() end

            task.spawn(function()
                startGame()
                task.wait(1.5)
                if CONFIG.AutoUpgrade then
                    upgradeSpell()
                    task.wait(0.5)
                end
                setStatus("Running")
                mainLoop()
            end)
        end
    end)

    setStatus("Tap ⚔ untuk buka")
end

-- ============ INIT ============
createUI()
print("[AutoFarm Mobile v7] Loaded")