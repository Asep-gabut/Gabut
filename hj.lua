-- ============================================
-- AUTO FARM DUNGEON - KAITUN STYLE (v46)
-- No GUI, auto start, all status on screen
-- ============================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============ CONFIG (HARDCODE) ============
local CONFIG = {
    KeepDistance = 45,
    AttackCooldown = 0.5,
    AutoUpgrade = true,
    UpgradeInterval = 3,
    SkillName = "spellPower",
    WaypointReached = 2,
    TargetMoveThreshold = 10,
    FolderScanInterval = 2,
}

local State = {
    Running = true,
    Character = nil, Humanoid = nil, RootPart = nil,
    LastAttack = 0, LastUpgrade = 0,
    EnemyFolders = {}, LastFolderScan = 0,
    PathWaypoints = nil,
    PathIndex = 1,
    PathTargetPos = nil,
    PathGoalType = nil,
    PathBusy = false,
    LastMoveToPos = nil,
    LockedEnemyPos = nil,
    ShiftlockSaved = nil,
}

local function logStatus(msg, color)
    -- placeholder, bakal di-override pas bikin UI
end

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
    if not State.LockedEnemyPos or not Camera then return end
    local camPos = Camera.CFrame.Position
    local targetPos = State.LockedEnemyPos
    Camera.CFrame = CFrame.new(camPos, Vector3.new(targetPos.X, camPos.Y + 1.5, targetPos.Z))
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
        spend:FireServer(CONFIG.SkillName, 1)
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
    if #State.EnemyFolders == 0 or (now - State.LastFolderScan) >= CONFIG.FolderScanInterval then
        State.EnemyFolders = scanAllEnemyFolders()
        State.LastFolderScan = now
    end
    return State.EnemyFolders
end

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
    elseif State.PathTargetPos and (targetPos - State.PathTargetPos).Magnitude > CONFIG.TargetMoveThreshold then 
        needRecompute = true 
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

local function attackEnemy(enemy)
    local now = tick()
    if now - State.LastAttack < CONFIG.AttackCooldown then return false end
    State.LastAttack = now
    pressQ()
    task.wait(0.08)
    pressE()
    return true
end

-- ============================================
--           STATUS OVERLAY (KAITUN STYLE)
-- ============================================
local function createOverlay()
    if CoreGui:FindFirstChild("AutoFarmOverlay") then
        CoreGui.AutoFarmOverlay:Destroy()
    end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoFarmOverlay"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = CoreGui

    -- Container
    local container = Instance.new("Frame")
    container.Size = UDim2.new(0, 340, 0, 90)
    container.Position = UDim2.new(0, 12, 0, 12)
    container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    container.BackgroundTransparency = 0.4
    container.BorderSizePixel = 0
    container.Active = true
    container.Draggable = true
    container.ZIndex = 5
    container.Parent = screenGui

    local cCorner = Instance.new("UICorner")
    cCorner.CornerRadius = UDim.new(0, 10)
    cCorner.Parent = container

    local cStroke = Instance.new("UIStroke")
    cStroke.Color = Color3.fromRGB(60, 220, 90)
    cStroke.Thickness = 1.5
    cStroke.Transparency = 0.2
    cStroke.Parent = container

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -12, 0, 24)
    title.Position = UDim2.new(0, 8, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = "⚔  AUTO FARM"
    title.TextColor3 = Color3.fromRGB(120, 255, 140)
    title.TextSize = 15
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextStrokeTransparency = 0.6
    title.ZIndex = 6
    title.Parent = container

    -- Divider
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, -16, 0, 1)
    div.Position = UDim2.new(0, 8, 0, 30)
    div.BackgroundColor3 = Color3.fromRGB(60, 220, 90)
    div.BackgroundTransparency = 0.7
    div.BorderSizePixel = 0
    div.ZIndex = 6
    div.Parent = container

    -- Status line
    local statusLbl = Instance.new("TextLabel")
    statusLbl.Name = "Status"
    statusLbl.Size = UDim2.new(1, -16, 0, 20)
    statusLbl.Position = UDim2.new(0, 8, 0, 34)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text = "Initializing..."
    statusLbl.TextColor3 = Color3.fromRGB(230, 230, 240)
    statusLbl.TextSize = 13
    statusLbl.Font = Enum.Font.GothamMedium
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.TextStrokeTransparency = 0.7
    statusLbl.ZIndex = 6
    statusLbl.Parent = container

    -- Info line
    local infoLbl = Instance.new("TextLabel")
    infoLbl.Name = "Info"
    infoLbl.Size = UDim2.new(1, -16, 0, 18)
    infoLbl.Position = UDim2.new(0, 8, 0, 54)
    infoLbl.BackgroundTransparency = 1
    infoLbl.Text = "Menunggu enemy..."
    infoLbl.TextColor3 = Color3.fromRGB(160, 220, 200)
    infoLbl.TextSize = 11
    infoLbl.Font = Enum.Font.Gotham
    infoLbl.TextXAlignment = Enum.TextXAlignment.Left
    infoLbl.TextStrokeTransparency = 0.7
    infoLbl.ZIndex = 6
    infoLbl.Parent = container

    -- Small upgrade label
    local upgLbl = Instance.new("TextLabel")
    upgLbl.Name = "Upgrade"
    upgLbl.Size = UDim2.new(1, -16, 0, 14)
    upgLbl.Position = UDim2.new(0, 8, 0, 71)
    upgLbl.BackgroundTransparency = 1
    upgLbl.Text = "Upgrade: ready"
    upgLbl.TextColor3 = Color3.fromRGB(200, 200, 130)
    upgLbl.TextSize = 10
    upgLbl.Font = Enum.Font.Gotham
    upgLbl.TextXAlignment = Enum.TextXAlignment.Left
    upgLbl.TextStrokeTransparency = 0.7
    upgLbl.ZIndex = 6
    upgLbl.Parent = container

    return {
        ScreenGui = screenGui,
        Container = container,
        Stroke = cStroke,
        Status = statusLbl,
        Info = infoLbl,
        Upgrade = upgLbl,
    }
end

local UI = createOverlay()

local function setStatus(msg)
    pcall(function()
        UI.Status.Text = msg
    end)
end

local function setInfo(msg)
    pcall(function()
        UI.Info.Text = msg
    end)
end

local function setUpgrade(msg)
    pcall(function()
        UI.Upgrade.Text = msg
    end)
end

local function setBorderColor(color)
    pcall(function()
        UI.Stroke.Color = color
    end)
end

-- ============================================
--              MAIN LOOP (AUTO START)
-- ============================================
local function mainLoop()
    setStatus("Starting...")
    setInfo("Init game...")
    setBorderColor(Color3.fromRGB(255, 200, 60))
    
    startGame()
    task.wait(2)
    
    if CONFIG.AutoUpgrade then
        setStatus("Upgrading spell...")
        upgradeSpell()
        task.wait(0.5)
    end
    
    setBorderColor(Color3.fromRGB(60, 220, 90))
    setUpgrade("Upgrade: running tiap 3s")
    
    while State.Running do
        task.wait(0.05)
        
        if not State.Character or not State.Character.Parent then 
            setStatus("Respawn...")
            task.wait(0.5) 
            continue 
        end
        if State.Humanoid.Health <= 0 then 
            setStatus("Dead, tunggu respawn...")
            task.wait(1) 
            continue 
        end

        -- shiftlock auto ON
        local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
        if sl and sl.Value == false then setShiftlock(true) end

        -- auto upgrade
        if CONFIG.AutoUpgrade and (tick() - State.LastUpgrade) >= CONFIG.UpgradeInterval then
            upgradeSpell()
            setUpgrade("Upgrade: OK tiap " .. CONFIG.UpgradeInterval .. "s")
        end

        local enemy, count, roomInfo = findNearestEnemy()
        if enemy then
            local _, ehrp = getHumanoidAndHRP(enemy)
            if ehrp then
                local myPos = State.RootPart.Position
                local enemyPos = ehrp.Position
                local dist = (enemyPos - myPos).Magnitude
                
                State.LockedEnemyPos = enemyPos
                
                local roomStr = ""
                if roomInfo and #roomInfo > 0 then
                    roomStr = " | " .. table.concat(roomInfo, ", ")
                end
                
                setInfo(string.format("Enemy: %d%s", count, roomStr))

                local R = CONFIG.KeepDistance

                if dist > R then
                    setStatus(string.format("⚔ Approaching (%.1f)", dist))
                    requestPath(enemyPos, "approach")
                    followPath()
                    attackEnemy(enemy)
                else
                    setStatus(string.format("⚔ Attacking (%.1f)", dist))
                    resetPath()
                    State.Humanoid:MoveTo(myPos)
                    attackEnemy(enemy)
                end
            end
        else
            State.LockedEnemyPos = nil
            resetPath()
            setStatus("⚔ Scanning enemy...")
            setInfo(string.format("Rooms: %d | No enemy", #State.EnemyFolders))
        end
    end
end

-- ============ AUTO START ============
task.spawn(mainLoop)
print("[Kaitun v46] Loaded - auto start, status on screen")