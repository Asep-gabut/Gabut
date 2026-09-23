-- ╔══════════════════════════════════════════╗
-- ║   AUTO FARM KAITUN v68                    ║
-- ║   Tanpa walkspeed modifier                ║
-- ║   Kite: titik terjauh yang reachable      ║
-- ╚══════════════════════════════════════════╝

local CONFIG = {
    KeepDistance = 45,
    KiteMinDistance = 20,
    KiteMaxDistance = 60,
    KiteDistanceStep = 3,
    KiteAngleCount = 30,
    KiteMaxChecks = 39,         -- batas ComputeAsync biar ga lag
    AttackCooldown = 0.1,
    LoopDelay = 0.03,
    
    WaypointReached = 3,
    WaypointSkip = 0,
    AgentRadius = 2,
    AgentHeight = 6,
    AgentCanJump = true,
    AgentJumpHeight = 15,
    AgentMaxSlope = 30,
    
    AutoUpgrade = true,
    AutoReconnect = true,
    AntiAFK = true,
    
    AntiLag = true,
    AntiLag_HidePlayers = true,
    AntiLag_DisableParticles = true,
    AntiLag_DisableDecals = true,
    AntiLag_LowGraphics = true,
    AntiLag_HideTerrain = true,
    AntiLag_DisableAnimations = true,
    AntiLag_HideAccessories = true,
    
    SkillName = "spellPower",
    UpgradeInterval = 3,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local State = {
    Running = false, Character = nil, Humanoid = nil, RootPart = nil,
    LastAttack = 0, LastUpgrade = 0,
    EnemyFolders = {}, LastFolderScan = 0,
    PathWaypoints = nil, PathIndex = 1, PathTargetPos = nil,
    PathGoalType = nil,
    PathRequestId = 0,
    LockedEnemyPos = nil, ShiftlockSaved = nil,
}

-- ═══════════════════════════════════════════
--              STATUS OVERLAY
-- ═══════════════════════════════════════════
if CoreGui:FindFirstChild("FarmStatus") then CoreGui.FarmStatus:Destroy() end

local statusGui = Instance.new("ScreenGui")
statusGui.Name = "FarmStatus"
statusGui.ResetOnSpawn = false
statusGui.IgnoreGuiInset = true
statusGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
statusGui.Parent = CoreGui

local container = Instance.new("Frame")
container.Size = UDim2.new(0, 400, 0, 62)
container.Position = UDim2.new(0.5, -200, 0, 15)
container.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
container.BorderSizePixel = 0
container.ZIndex = 5
container.Parent = statusGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 14)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(60, 60, 80)
containerStroke.Thickness = 1
containerStroke.Transparency = 0.4
containerStroke.Parent = container

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 25, 35)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(20, 20, 28)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 25, 40)),
})
gradient.Rotation = 45
gradient.Parent = container

local glowBar = Instance.new("Frame")
glowBar.Size = UDim2.new(1, 0, 0, 2)
glowBar.Position = UDim2.new(0, 0, 0, 0)
glowBar.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
glowBar.BorderSizePixel = 0
glowBar.ZIndex = 6
glowBar.Parent = container

local glowCorner = Instance.new("UICorner")
glowCorner.CornerRadius = UDim.new(0, 14)
glowCorner.Parent = glowBar

local glowFix = Instance.new("Frame")
glowFix.Size = UDim2.new(1, 0, 0, 14)
glowFix.Position = UDim2.new(0, 0, 1, -14)
glowFix.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
glowFix.BorderSizePixel = 0
glowFix.ZIndex = 7
glowFix.Parent = container

local iconCircle = Instance.new("Frame")
iconCircle.Size = UDim2.new(0, 44, 0, 44)
iconCircle.Position = UDim2.new(0, 10, 0.5, -22)
iconCircle.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
iconCircle.BackgroundTransparency = 0.85
iconCircle.BorderSizePixel = 0
iconCircle.ZIndex = 8
iconCircle.Parent = container

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(1, 0)
iconCorner.Parent = iconCircle

local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.fromRGB(100, 200, 100)
iconStroke.Thickness = 1.5
iconStroke.Transparency = 0.3
iconStroke.Parent = iconCircle

local iconText = Instance.new("TextLabel")
iconText.Size = UDim2.new(1, 0, 1, 0)
iconText.BackgroundTransparency = 1
iconText.Text = "⚔"
iconText.TextColor3 = Color3.fromRGB(100, 200, 100)
iconText.TextSize = 24
iconText.Font = Enum.Font.GothamBold
iconText.ZIndex = 9
iconText.Parent = iconCircle

local mainStatus = Instance.new("TextLabel")
mainStatus.Size = UDim2.new(1, -130, 0, 22)
mainStatus.Position = UDim2.new(0, 66, 0, 10)
mainStatus.BackgroundTransparency = 1
mainStatus.Text = "Idle"
mainStatus.TextColor3 = Color3.fromRGB(240, 240, 250)
mainStatus.TextSize = 17
mainStatus.Font = Enum.Font.GothamBold
mainStatus.TextXAlignment = Enum.TextXAlignment.Left
mainStatus.ZIndex = 8
mainStatus.Parent = container

local subStatus = Instance.new("TextLabel")
subStatus.Size = UDim2.new(1, -130, 0, 16)
subStatus.Position = UDim2.new(0, 66, 0, 34)
subStatus.BackgroundTransparency = 1
subStatus.Text = "menunggu"
subStatus.TextColor3 = Color3.fromRGB(140, 140, 160)
subStatus.TextSize = 12
subStatus.Font = Enum.Font.GothamMedium
subStatus.TextXAlignment = Enum.TextXAlignment.Left
subStatus.ZIndex = 8
subStatus.Parent = container

local dotFrame = Instance.new("Frame")
dotFrame.Size = UDim2.new(0, 8, 0, 8)
dotFrame.Position = UDim2.new(1, -20, 0.5, -4)
dotFrame.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
dotFrame.BorderSizePixel = 0
dotFrame.ZIndex = 8
dotFrame.Parent = container

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dotFrame

local dotGlow = Instance.new("UIStroke")
dotGlow.Color = Color3.fromRGB(100, 200, 100)
dotGlow.Thickness = 3
dotGlow.Transparency = 0.5
dotGlow.Parent = dotFrame

task.spawn(function()
    while dotFrame.Parent do
        pcall(function()
            TweenService:Create(dotGlow, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Transparency = 0.9
            }):Play()
        end)
        task.wait(1)
        pcall(function()
            TweenService:Create(dotGlow, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Transparency = 0.3
            }):Play()
        end)
        task.wait(1)
    end
end)

local lastMain = ""
local lastColor = nil

setStatus = function(msg, color)
    pcall(function()
        msg = tostring(msg)
        local mainText = "Idle"
        local subText = ""
        
        if msg:find("Approaching") then
            local dist = msg:match("(%d+%.%d+)") or "?"
            local count = msg:match("|%s*(%d+)%s*enemy") or "?"
            local wp = msg:match("wp%s*(%d+/%d+)") or ""
            mainText = "Approaching"
            subText = string.format("%s stud  •  %s enemy  %s", dist, count, wp)
            color = color or Color3.fromRGB(100, 180, 255)
        elseif msg:find("Kiting") then
            local dist = msg:match("(%d+%.%d+)") or "?"
            local count = msg:match("|%s*(%d+)%s*enemy") or "?"
            local wp = msg:match("wp%s*(%d+/%d+)") or ""
            mainText = "Kiting"
            subText = string.format("%s stud  •  %s enemy  %s", dist, count, wp)
            color = color or Color3.fromRGB(255, 180, 100)
        elseif msg:find("No enemy") then
            mainText = "Scanning"
            subText = "mencari musuh..."
            color = color or Color3.fromRGB(160, 160, 180)
        elseif msg:find("Idle") then
            mainText = "Idle"
            subText = "menunggu"
            color = color or Color3.fromRGB(120, 120, 140)
        elseif msg:find("Starting") then
            mainText = "Starting"
            subText = "menyiapkan..."
            color = color or Color3.fromRGB(255, 220, 100)
        elseif msg:find("Running") then
            mainText = "Running"
            subText = "auto farm aktif"
            color = color or Color3.fromRGB(100, 220, 100)
        else
            mainText = msg
            subText = ""
        end
        
        if mainText ~= lastMain then
            lastMain = mainText
            mainStatus.Text = mainText
        end
        if subText then
            subStatus.Text = subText
        end
        
        if color and color ~= lastColor then
            lastColor = color
            TweenService:Create(glowBar, TweenInfo.new(0.3), {BackgroundColor3 = color}):Play()
            TweenService:Create(iconCircle, TweenInfo.new(0.3), {BackgroundColor3 = color}):Play()
            TweenService:Create(iconStroke, TweenInfo.new(0.3), {Color = color}):Play()
            TweenService:Create(iconText, TweenInfo.new(0.3), {TextColor3 = color}):Play()
            TweenService:Create(dotFrame, TweenInfo.new(0.3), {BackgroundColor3 = color}):Play()
            TweenService:Create(dotGlow, TweenInfo.new(0.3), {Color = color}):Play()
        end
    end)
end

-- ═══════════════════════════════════════════
--              ANTI LAG
-- ═══════════════════════════════════════════
local AntiLag = {}

function AntiLag.setup()
    if not CONFIG.AntiLag then return end
    if CONFIG.AntiLag_LowGraphics then
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 100000
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
    if CONFIG.AntiLag_HideTerrain then
        pcall(function()
            workspace.Terrain.WaterWaveSize = 0
            workspace.Terrain.WaterWaveSpeed = 0
            workspace.Terrain.WaterReflectance = 0
            workspace.Terrain.WaterTransparency = 1
        end)
    end
    AntiLag.processInstance(workspace)
end

function AntiLag.processInstance(container)
    if not CONFIG.AntiLag then return end
    for _, obj in ipairs(container:GetDescendants()) do
        AntiLag.cleanInstance(obj)
    end
    container.DescendantAdded:Connect(function(obj)
        task.defer(function() AntiLag.cleanInstance(obj) end)
    end)
end

function AntiLag.cleanInstance(obj)
    pcall(function()
        if CONFIG.AntiLag_DisableParticles then
            if obj:IsA("ParticleEmitter") then
                obj.Enabled = false
                obj.Rate = 0
            end
            if obj:IsA("Trail") or obj:IsA("Smoke") 
                or obj:IsA("Fire") or obj:IsA("Sparkles") 
                or obj:IsA("Beam") then
                obj.Enabled = false
            end
        end
        if CONFIG.AntiLag_DisableDecals then
            if obj:IsA("Decal") or obj:IsA("Texture") then
                obj.Transparency = 1
            end
        end
        if CONFIG.AntiLag_DisableAnimations then
            if obj:IsA("Animator") and obj.Parent then
                local char = LocalPlayer.Character
                if char and not obj:IsDescendantOf(char) then
                    pcall(function() obj:Destroy() end)
                end
            end
        end
        if CONFIG.AntiLag_HideAccessories then
            if obj:IsA("Accessory") or obj:IsA("Hat") then
                if obj.Parent then
                    local char = LocalPlayer.Character
                    if char and not obj:IsDescendantOf(char) then
                        pcall(function() obj:Destroy() end)
                    end
                end
            end
        end
    end)
end

function AntiLag.hideOtherPlayers()
    if not CONFIG.AntiLag_HidePlayers then return end
    local function hideChar(char)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") or part:IsA("Decal") then
                part.Transparency = 1
            end
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            hideChar(player.Character)
        end
    end
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(char)
            task.wait(1)
            hideChar(char)
        end)
    end)
end

if CONFIG.AntiAFK then
    pcall(function()
        LocalPlayer.Idled:Connect(function()
            local VirtualUser = game:GetService("VirtualUser")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

if CONFIG.AutoReconnect then
    pcall(function()
        game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then
                task.wait(3)
                game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
            end
        end)
    end)
end

-- ═══════════════════════════════════════════
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

RunService.RenderStepped:Connect(function()
    if not State.Running then return end
    if not State.LockedEnemyPos then return end
    if not Camera then return end
    local camPos = Camera.CFrame.Position
    local tp = State.LockedEnemyPos
    Camera.CFrame = CFrame.new(camPos, Vector3.new(tp.X, camPos.Y + 1.5, tp.Z))
end)

local function setupCharacter(char)
    State.Character = char
    State.Humanoid = char:WaitForChild("Humanoid")
    State.RootPart = char:WaitForChild("HumanoidRootPart")
    task.wait(1)
    if CONFIG.AntiLag_HidePlayers then AntiLag.hideOtherPlayers() end
end

if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(setupCharacter)

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

local function resetPath()
    State.PathWaypoints = nil
    State.PathIndex = 1
    State.PathTargetPos = nil
    State.PathGoalType = nil
end

-- ⭐ REQUEST PATH (async) - buat approach
local function requestPath(targetPos, goalType)
    if not State.Humanoid or not State.RootPart then return end
    if not targetPos then return end
    
    State.PathTargetPos = targetPos
    State.PathGoalType = goalType
    State.PathRequestId = State.PathRequestId + 1
    local myRequestId = State.PathRequestId
    
    local myPos = State.RootPart.Position
    
    task.spawn(function()
        local path = PathfindingService:CreatePath({
            AgentRadius = CONFIG.AgentRadius,
            AgentHeight = CONFIG.AgentHeight,
            AgentCanJump = CONFIG.AgentCanJump,
            AgentJumpHeight = CONFIG.AgentJumpHeight,
            AgentMaxSlope = CONFIG.AgentMaxSlope,
            Costs = { Water = 50 },
        })
        
        local ok = pcall(function()
            path:ComputeAsync(myPos, targetPos)
        end)
        
        if myRequestId ~= State.PathRequestId then return end
        
        if ok and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            if CONFIG.WaypointSkip > 0 and #waypoints > 2 + CONFIG.WaypointSkip then
                local newWaypoints = {}
                table.insert(newWaypoints, waypoints[1])
                for i = 2 + CONFIG.WaypointSkip, #waypoints, CONFIG.WaypointSkip do
                    table.insert(newWaypoints, waypoints[i])
                end
                if newWaypoints[#newWaypoints] ~= waypoints[#waypoints] then
                    table.insert(newWaypoints, waypoints[#waypoints])
                end
                waypoints = newWaypoints
            end
            State.PathWaypoints = waypoints
            State.PathIndex = 2
        else
            State.PathWaypoints = nil
        end
    end)
end

-- ⭐ FOLLOW PATH
local function followPath()
    if not State.Humanoid or not State.RootPart then return end
    if not State.PathWaypoints then return end
    if State.PathIndex > #State.PathWaypoints then return end
    
    local myPos = State.RootPart.Position
    local wp = State.PathWaypoints[State.PathIndex]
    local distToWp = (myPos - wp.Position).Magnitude
    
    while distToWp <= CONFIG.WaypointReached and State.PathIndex < #State.PathWaypoints do
        State.PathIndex = State.PathIndex + 1
        wp = State.PathWaypoints[State.PathIndex]
        distToWp = (myPos - wp.Position).Magnitude
    end
    
    State.Humanoid:MoveTo(wp.Position)
    if wp.Action == Enum.PathWaypointAction.Jump then
        State.Humanoid.Jump = true
    end
end

-- ⭐ TRY COMPUTE PATH (sync) - validasi reachable + dapet waypoints sekalian
local function tryComputePath(fromPos, toPos)
    local path = PathfindingService:CreatePath({
        AgentRadius = CONFIG.AgentRadius,
        AgentHeight = CONFIG.AgentHeight,
        AgentCanJump = CONFIG.AgentCanJump,
        AgentJumpHeight = CONFIG.AgentJumpHeight,
        AgentMaxSlope = CONFIG.AgentMaxSlope,
        Costs = { Water = 50 },
    })
    local ok = pcall(function() path:ComputeAsync(fromPos, toPos) end)
    if ok and path.Status == Enum.PathStatus.Success then
        return path:GetWaypoints()
    end
    return nil
end

-- ⭐ SAFE POINT - pilih titik TERJAUH dari enemy yang REACHABLE
--                urutan: ring terluar → dalam, tiap ring 16 sudut
--                max KiteMaxChecks kali compute biar ga lag
local function findSafePointAroundEnemy(enemyPos, myPos)
    local step = math.max(1, CONFIG.KiteDistanceStep)
    local angleCount = math.max(4, CONFIG.KiteAngleCount)
    local maxChecks = math.max(1, CONFIG.KiteMaxChecks)
    local checked = 0
    
    local radius = CONFIG.KiteMaxDistance
    while radius >= CONFIG.KiteMinDistance - 0.01 do
        for ai = 0, angleCount - 1 do
            if checked >= maxChecks then break end
            checked = checked + 1
            
            local angle = (ai / angleCount) * math.pi * 2
            local offset = Vector3.new(math.cos(angle), 0, math.sin(angle))
            local point = Vector3.new(
                enemyPos.X + offset.X * radius,
                myPos.Y,
                enemyPos.Z + offset.Z * radius
            )
            
            local waypoints = tryComputePath(myPos, point)
            if waypoints then
                return point, waypoints
            end
        end
        if checked >= maxChecks then break end
        radius = radius - step
    end
    
    -- Fallback: arah menjauh dari enemy di ring terjauh, biar pathfinder yang coba
    local dir = Vector3.new(myPos.X - enemyPos.X, 0, myPos.Z - enemyPos.Z)
    if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
    dir = dir.Unit
    local point = Vector3.new(
        enemyPos.X + dir.X * CONFIG.KiteMaxDistance,
        myPos.Y,
        enemyPos.Z + dir.Z * CONFIG.KiteMaxDistance
    )
    local waypoints = tryComputePath(myPos, point)
    return point, waypoints
end

local function attackEnemy(enemy)
    local now = tick()
    if now - State.LastAttack < CONFIG.AttackCooldown then return false end
    State.LastAttack = now
    task.spawn(function()
        pressQ()
        task.wait(0.08)
        pressE()
    end)
    return true
end

local function mainLoop()
    while State.Running do
        task.wait(CONFIG.LoopDelay)
        if not State.Character or not State.Character.Parent then task.wait(0.5) continue end
        if State.Humanoid.Health <= 0 then task.wait(1) continue end
        
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
                
                attackEnemy(enemy)
                
                if dist > CONFIG.KeepDistance then
                    -- APPROACH
                    requestPath(enemyPos, "approach")
                    followPath()
                    
                    setStatus(
                        string.format("Approaching (%.1f) | %d enemy | wp %d/%d", 
                            dist, count, State.PathIndex, 
                            State.PathWaypoints and #State.PathWaypoints or 0),
                        Color3.fromRGB(100, 180, 255)
                    )
                else
                    -- KITE: titik terjauh yang reachable
                    local safePoint, waypoints = findSafePointAroundEnemy(enemyPos, myPos)
                    if safePoint and waypoints then
                        State.PathWaypoints = waypoints
                        State.PathIndex = 2
                        State.PathTargetPos = safePoint
                        State.PathGoalType = "retreat"
                        followPath()
                    end
                    
                    setStatus(
                        string.format("Kiting (%.1f) | %d enemy | wp %d/%d", 
                            dist, count, State.PathIndex, 
                            State.PathWaypoints and #State.PathWaypoints or 0),
                        Color3.fromRGB(255, 180, 100)
                    )
                end
            end
        else
            State.LockedEnemyPos = nil
            resetPath()
            setStatus("No enemy | scanning...", Color3.fromRGB(160, 160, 180))
        end
    end
end

task.spawn(function()
    AntiLag.setup()
    if CONFIG.AntiLag_HidePlayers then AntiLag.hideOtherPlayers() end
    
    print("╔════════════════════════════════════╗")
    print("║   AUTO FARM KAITUN v68 - LOADED    ║")
    print("║   Tanpa walkspeed modifier         ║")
    print("║   Kite: titik terjauh reachable    ║")
    print("╚════════════════════════════════════╝")
    
    setStatus("Starting...", Color3.fromRGB(255, 220, 100))
    
    State.Running = true
    task.wait(3)
    
    startGame()
    task.wait(2)
    
    if CONFIG.AutoUpgrade then 
        upgradeSpell()
        task.wait(0.5) 
    end
    
    setShiftlock(true)
    
    setStatus("Running", Color3.fromRGB(100, 220, 100))
    print("[KAITUN] Started auto farm...")
    mainLoop()
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(2)
    if State.Running then
        setShiftlock(true)
    end
end)