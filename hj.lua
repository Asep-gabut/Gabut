-- ╔══════════════════════════════════════════════╗
-- ║   AUTO FARM KAITUN - Anti Lag Edition       ║
-- ║   No GUI - Config di script aja              ║
-- ║   Auto START saat execute                    ║
-- ╚══════════════════════════════════════════════╝

-- ============================================
--           ⚙️ KONFIGURASI - EDIT DI SINI
-- ============================================
local CONFIG = {
    -- Jarak
    KeepDistance = 60,          -- jarak ideal ke musuh
    
    -- Combat
    AttackCooldown = 0.5,       -- jeda antar attack Q+E
    
    -- Loop
    LoopDelay = 0.05,           -- delay main loop (0.05 = 20x/detik)
    
    -- WalkSpeed
    UseWalkSpeed = true,
    WalkSpeed = 20,
    
    -- Pathfinding
    WaypointReached = 4,
    TargetMoveThreshold = 4,
    
    -- Auto Features
    AutoUpgrade = true,         -- auto upgrade spellPower
    AutoReconnect = true,       -- auto reconnect kalau disconnect
    AntiAFK = true,             -- anti kick karena idle
    
    -- Anti Lag
    AntiLag = true,
    AntiLag_HidePlayers = true,    -- sembunyiin player lain
    AntiLag_DisableParticles = true,-- matiin particle effects
    AntiLag_DisableDecals = true,   -- matiin decal/texture
    AntiLag_LowGraphics = true,     -- graphics minimal
    AntiLag_HideTerrain = true,    -- sembunyiin terrain
    AntiLag_DisableAnimations = true, -- matiin animasi player lain
    AntiLag_HideAccessories = true,-- sembunyiin aksesoris player lain
    
    -- Skill
    SkillName = "spellPower",
    UpgradeInterval = 3,
}

-- ============================================
--              SCRIPT (JANGAN EDIT)
-- ============================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local State = {
    Running = false, Character = nil, Humanoid = nil, RootPart = nil,
    LastAttack = 0, LastUpgrade = 0,
    EnemyFolders = {}, LastFolderScan = 0,
    PathWaypoints = nil, PathIndex = 1, PathTargetPos = nil,
    PathGoalType = nil, PathBusy = false, LastMoveToPos = nil,
    LockedEnemyPos = nil, ShiftlockSaved = nil, OriginalWalkSpeed = nil,
}

-- ============================================
--               ANTI LAG
-- ============================================
local AntiLag = {}

function AntiLag.setup()
    if not CONFIG.AntiLag then return end
    
    -- 1. Low graphics
    if CONFIG.AntiLag_LowGraphics then
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 100000
            Lighting.Brightness = 1
            Lighting.EnvironmentDiffuseScale = 0
            Lighting.EnvironmentSpecularScale = 0
            Lighting.Ambient = Color3.fromRGB(128, 128, 128)
            Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            
            for _, effect in ipairs(Lighting:GetChildren()) do
                if effect:IsA("BlurEffect") or effect:IsA("SunRaysEffect")
                    or effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect")
                    or effect:IsA("DepthOfFieldEffect") then
                    effect.Enabled = false
                end
            end
        end)
    end
    
    -- 2. Hide terrain (opsional)
    if CONFIG.AntiLag_HideTerrain then
        pcall(function()
            workspace.Terrain.WaterWaveSize = 0
            workspace.Terrain.WaterWaveSpeed = 0
            workspace.Terrain.WaterReflectance = 0
            workspace.Terrain.WaterTransparency = 1
        end)
    end
    
    -- 3. Handle existing instances
    AntiLag.processInstance(workspace)
end

function AntiLag.processInstance(container)
    if not CONFIG.AntiLag then return end
    
    for _, obj in ipairs(container:GetDescendants()) do
        AntiLag.cleanInstance(obj)
    end
    
    -- watch for new instances
    container.DescendantAdded:Connect(function(obj)
        task.wait(0.1)
        AntiLag.cleanInstance(obj)
    end)
end

function AntiLag.cleanInstance(obj)
    pcall(function()
        -- Particle effects
        if CONFIG.AntiLag_DisableParticles then
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") 
                or obj:IsA("Smoke") or obj:IsA("Fire") 
                or obj:IsA("Sparkles") or obj:IsA("Explosion") then
                obj.Enabled = false
                if obj:IsA("ParticleEmitter") then
                    obj.Rate = 0
                end
            end
            if obj:IsA("Beam") then obj.Enabled = false end
        end
        
        -- Decals / textures
        if CONFIG.AntiLag_DisableDecals then
            if obj:IsA("Decal") or obj:IsA("Texture") then
                obj.Transparency = 1
            end
        end
        
        -- Animations (player lain)
        if CONFIG.AntiLag_DisableAnimations then
            if obj:IsA("Animation") or obj:IsA("Animator") then
                -- skip animasi sendiri
                if obj.Parent then
                    local char = LocalPlayer.Character
                    if char and not obj:IsDescendantOf(char) then
                        if obj:IsA("Animator") then
                            pcall(function() obj:Destroy() end)
                        end
                    end
                end
            end
        end
        
        -- Accessories
        if CONFIG.AntiLag_HideAccessories then
            if obj:IsA("Accessory") or obj:IsA("Hat") then
                if obj.Parent then
                    local char = LocalPlayer.Character
                    if char and not obj:IsDescendantOf(char) then
                        obj:Destroy()
                    end
                end
            end
        end
    end)
end

function AntiLag.hideOtherPlayers()
    if not CONFIG.AntiLag_HidePlayers then return end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            for _, part in ipairs(player.Character:GetDescendants()) do
                if part:IsA("BasePart") or part:IsA("Decal") then
                    part.Transparency = 1
                end
            end
        end
    end
    
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(char)
            task.wait(1)
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") or part:IsA("Decal") then
                    part.Transparency = 1
                end
            end
        end)
    end)
end

-- ============================================
--              ANTI AFK
-- ============================================
local function setupAntiAFK()
    if not CONFIG.AntiAFK then return end
    
    pcall(function()
        LocalPlayer.Idled:Connect(function()
            local VirtualUser = game:GetService("VirtualUser")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

-- ============================================
--              AUTO RECONNECT
-- ============================================
local function setupAutoReconnect()
    if not CONFIG.AutoReconnect then return end
    
    pcall(function()
        game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then
                -- coba reconnect
                task.wait(3)
                game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
            end
        end)
    end)
end

-- ============================================
--              KEYPRESS
-- ============================================
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

-- ============================================
--              SHIFTLOCK
-- ============================================
local function setShiftlock(enabled)
    pcall(function()
        local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
        if not sl then
            for _, obj in ipairs(LocalPlayer:GetDescendants()) do
                if obj.Name:lower():find("shiftlock") then sl = obj break end
            end
        end
        if sl then
            if State.ShiftlockSaved == nil then State.ShiftlockSaved = sl.Value end
            sl.Value = enabled
        end
    end)
end

-- ============================================
--              WALKSPEED
-- ============================================
local function applyWalkSpeed()
    if not CONFIG.UseWalkSpeed then return end
    if State.Humanoid then
        pcall(function() State.Humanoid.WalkSpeed = CONFIG.WalkSpeed end)
    end
end

-- ============================================
--              CAMERA LOCK
-- ============================================
RunService.RenderStepped:Connect(function()
    if not State.Running then return end
    if not State.LockedEnemyPos then return end
    if not Camera then return end
    local camPos = Camera.CFrame.Position
    local tp = State.LockedEnemyPos
    Camera.CFrame = CFrame.new(camPos, Vector3.new(tp.X, camPos.Y + 1.5, tp.Z))
end)

-- ============================================
--              CHARACTER
-- ============================================
local function setupCharacter(char)
    State.Character = char
    State.Humanoid = char:WaitForChild("Humanoid")
    State.RootPart = char:WaitForChild("HumanoidRootPart")
    if State.OriginalWalkSpeed == nil and State.Humanoid then
        State.OriginalWalkSpeed = State.Humanoid.WalkSpeed
    end
    task.wait(0.5)
    applyWalkSpeed()
    if CONFIG.AntiLag_HidePlayers then AntiLag.hideOtherPlayers() end
end

if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(setupCharacter)

-- ============================================
--              REMOTES
-- ============================================
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

-- ============================================
--              ENEMY FOLDER
-- ============================================
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

-- ============================================
--              HUMANOID
-- ============================================
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
    if #folders == 0 or not State.RootPart then return nil, 0 end
    local nearest, nearestDist = nil, math.huge
    local totalCount = 0
    for _, folder in ipairs(folders) do
        if folder and folder.Parent then
            for _, enemy in ipairs(folder:GetChildren()) do
                if enemy:IsA("Model") or enemy:IsA("Folder") then
                    local hum, hrp = getHumanoidAndHRP(enemy)
                    if hum and hrp then
                        totalCount = totalCount + 1
                        local dist = (hrp.Position - State.RootPart.Position).Magnitude
                        if dist < nearestDist then
                            nearestDist = dist
                            nearest = enemy
                        end
                    end
                end
            end
        end
    end
    if totalCount == 0 then State.LastFolderScan = 0 end
    return nearest, totalCount
end

-- ============================================
--              PATH
-- ============================================
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
    
    if State.PathBusy then
        if not State.PathWaypoints then
            if not State.LastMoveToPos 
                or (State.LastMoveToPos - targetPos).Magnitude > 2 then
                State.Humanoid:MoveTo(targetPos)
                State.LastMoveToPos = targetPos
            end
        end
        return
    end
    
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
    
    if State.PathIndex > #State.PathWaypoints then
        if State.PathTargetPos then
            if not State.LastMoveToPos 
                or (State.LastMoveToPos - State.PathTargetPos).Magnitude > 0.5 then
                State.Humanoid:MoveTo(State.PathTargetPos)
                State.LastMoveToPos = State.PathTargetPos
            end
        end
        return
    end
    
    local myPos = State.RootPart.Position
    local wp = State.PathWaypoints[State.PathIndex]
    local distToWp = (myPos - wp.Position).Magnitude
    
    if distToWp <= CONFIG.WaypointReached then
        State.PathIndex = State.PathIndex + 1
        State.LastMoveToPos = nil
        if State.PathIndex <= #State.PathWaypoints then
            local nextWp = State.PathWaypoints[State.PathIndex]
            State.Humanoid:MoveTo(nextWp.Position)
            State.LastMoveToPos = nextWp.Position
            if nextWp.Action == Enum.PathWaypointAction.Jump then
                State.Humanoid.Jump = true
            end
        end
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
--              MAIN LOOP
-- ============================================
local function mainLoop()
    while State.Running do
        task.wait(CONFIG.LoopDelay)
        if not State.Character or not State.Character.Parent then task.wait(0.5) continue end
        if State.Humanoid.Health <= 0 then task.wait(1) continue end
        
        if CONFIG.UseWalkSpeed and State.Humanoid.WalkSpeed ~= CONFIG.WalkSpeed then
            applyWalkSpeed()
        end
        
        if CONFIG.AutoUpgrade and (tick() - State.LastUpgrade) >= CONFIG.UpgradeInterval then 
            upgradeSpell() 
        end

        local sl = LocalPlayer:FindFirstChild("shiftlockMobile")
        if sl and sl.Value == false then setShiftlock(true) end

        local enemy, count = findNearestEnemy()
        if enemy then
            local _, ehrp = getHumanoidAndHRP(enemy)
            if ehrp then
                local myPos = State.RootPart.Position
                local enemyPos = ehrp.Position
                local dist = (enemyPos - myPos).Magnitude
                
                State.LockedEnemyPos = enemyPos
                
                if dist > CONFIG.KeepDistance then
                    requestPath(enemyPos, "approach")
                    followPath()
                    attackEnemy(enemy)
                else
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
        end
    end
end

-- ============================================
--              INIT
-- ============================================
task.spawn(function()
    -- 1. Anti Lag
    AntiLag.setup()
    if CONFIG.AntiLag_HidePlayers then AntiLag.hideOtherPlayers() end
    
    -- 2. Anti AFK
    setupAntiAFK()
    
    -- 3. Auto Reconnect
    setupAutoReconnect()
    
    -- 4. Notifikasi console
    print("╔════════════════════════════════════╗")
    print("║   AUTO FARM KAITUN - LOADED        ║")
    print("║   Anti-Lag: " .. (CONFIG.AntiLag and "ON" or "OFF") .. "                     ║")
    print("║   Anti-AFK: " .. (CONFIG.AntiAFK and "ON" or "OFF") .. "                     ║")
    print("║   Auto-Reconnect: " .. (CONFIG.AutoReconnect and "ON" or "OFF") .. "             ║")
    print("║   Auto Upgrade: " .. (CONFIG.AutoUpgrade and "ON" or "OFF") .. "               ║")
    print("║   WalkSpeed: " .. (CONFIG.UseWalkSpeed and CONFIG.WalkSpeed or "OFF") .. "                  ║")
    print("╚════════════════════════════════════╝")
    
    -- 5. AUTO START
    State.Running = true
    
    task.wait(3) -- tunggu game load
    
    -- start game
    startGame()
    task.wait(2)
    
    -- upgrade pertama
    if CONFIG.AutoUpgrade then 
        upgradeSpell()
        task.wait(0.5) 
    end
    
    -- apply walkspeed
    applyWalkSpeed()
    
    -- enable shiftlock
    setShiftlock(true)
    
    print("[KAITUN] Started auto farm...")
    
    -- start main loop
    mainLoop()
end)

-- Kalau character respawn, karakter baru bakal tetep farm karena State.Running = true
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(2)
    if State.Running then
        applyWalkSpeed()
        setShiftlock(true)
    end
end)