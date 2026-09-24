-- // Rayfield Gen2
getgenv().RAYFIELD_SECURE = true
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

-- // Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer

local humanoids = workspace:WaitForChild("Humanoids")
local regions = humanoids:WaitForChild("Regions")

------------------------------------------------------------
-- // State
------------------------------------------------------------
local selectedArea = nil
local targetEnemyName = nil
local currentEnemy = nil
local followThread = nil
local killThread = nil
local activeTween = nil
local isHolding = false
local isHunting = false

-- // Setting
local BEHIND_DISTANCE = 4
local FOLLOW_INTERVAL = 0.12
local FOLLOW_MIN_DIST = 0.2

local function getCharacter()
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hum and hrp then return char, hum, hrp end
	return nil
end

------------------------------------------------------------
-- // ATTACK — HOLD left click
------------------------------------------------------------
local function attackHoldStart()
	if isHolding then return end
	isHolding = true
	VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
end

local function attackHoldStop()
	if not isHolding then return end
	isHolding = false
	VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
end

------------------------------------------------------------
-- // Helpers
------------------------------------------------------------
local function isEnemyAlive(enemy)
	if not enemy or not enemy.Parent then return false end
	local hum = enemy:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	return hum.Health > 0
end

local function getEnemyPart(enemy)
	if not enemy or not enemy.Parent then return nil end
	return enemy:FindFirstChild("HumanoidRootPart")
		or enemy:FindFirstChildWhichIsA("BasePart")
end

-- Posisi di BELAKANG musuh, Y ngikut musuh
local function getBehindCFrame(enemy)
	local tp = getEnemyPart(enemy)
	if not tp then return nil end

	local enemyCF = tp.CFrame
	local behindPos = enemyCF.Position - enemyCF.LookVector * BEHIND_DISTANCE

	local targetPos = Vector3.new(behindPos.X, enemyCF.Position.Y, behindPos.Z)
	local lookAtPos = Vector3.new(enemyCF.Position.X, enemyCF.Position.Y, enemyCF.Position.Z)

	return CFrame.new(targetPos, lookAtPos)
end

local function findAllEnemiesWithName()
	local result = {}
	if not selectedArea or not targetEnemyName then return result end
	local activeNpcs = selectedArea:FindFirstChild("ActiveNpcs")
	if not activeNpcs then return result end

	for _, npcFolder in ipairs(activeNpcs:GetChildren()) do
		if npcFolder:IsA("Folder") or npcFolder:IsA("Model") then
			for _, enemy in ipairs(npcFolder:GetChildren()) do
				if enemy:IsA("Model")
				and enemy.Name == targetEnemyName
				and isEnemyAlive(enemy) then
					table.insert(result, enemy)
				end
			end
		end
	end
	return result
end

------------------------------------------------------------
-- // FOLLOW LOOP
------------------------------------------------------------
local function startFollow()
	if followThread then
		pcall(function() task.cancel(followThread) end)
	end

	followThread = task.spawn(function()
		while isHunting and selectedArea do
			local char, hum, hrp = getCharacter()
			if not char then
				task.wait(0.3)
				continue
			end

			if currentEnemy and currentEnemy.Parent and isEnemyAlive(currentEnemy) then
				local targetCF = getBehindCFrame(currentEnemy)
				if targetCF then
					local dist = (hrp.Position - targetCF.Position).Magnitude
					if dist > FOLLOW_MIN_DIST then
						hrp.Anchored = true
						if activeTween then
							pcall(function() activeTween:Cancel() end)
						end
						local mt = TweenService:Create(
							hrp,
							TweenInfo.new(FOLLOW_INTERVAL, Enum.EasingStyle.Linear),
							{CFrame = targetCF}
						)
						activeTween = mt
						mt:Play()
					else
						hrp.CFrame = targetCF
					end
				end
			end

			task.wait(FOLLOW_INTERVAL)
		end
	end)
end

------------------------------------------------------------
-- // Approach awal
------------------------------------------------------------
local function approachEnemy(enemy)
	local char, hum, hrp = getCharacter()
	local targetCF = getBehindCFrame(enemy)
	if not char or not targetCF then return false end

	if activeTween then
		pcall(function() activeTween:Cancel() end)
		activeTween = nil
	end

	hum:MoveTo(hrp.Position)

	local dist = (hrp.Position - targetCF.Position).Magnitude
	local duration = math.max(dist / 70, 0.1)

	hrp.Anchored = true
	local tw = TweenService:Create(
		hrp,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CFrame = targetCF}
	)
	activeTween = tw
	tw:Play()
	tw.Completed:Wait()
	if activeTween == tw then activeTween = nil end
	return true
end

------------------------------------------------------------
-- // KILL LOOP
------------------------------------------------------------
local function startHunting()
	if killThread then
		pcall(function() task.cancel(killThread) end)
	end

	killThread = task.spawn(function()
		while isHunting and targetEnemyName and selectedArea do
			local list = findAllEnemiesWithName()

			if #list == 0 then
				currentEnemy = nil
				attackHoldStop()
				task.wait(1)
				continue
			end

			local char, hum, hrp = getCharacter()
			if not hrp then task.wait(0.5); continue end

			local closest, closestDist = nil, math.huge
			for _, enemy in ipairs(list) do
				local tp = getEnemyPart(enemy)
				if tp then
					local d = (hrp.Position - tp.Position).Magnitude
					if d < closestDist then
						closestDist = d
						closest = enemy
					end
				end
			end

			if not closest then task.wait(0.3); continue end
			currentEnemy = closest

			if closestDist > BEHIND_DISTANCE + 4 then
				approachEnemy(closest)
			end

			attackHoldStart()

			while isEnemyAlive(closest) and isHunting and targetEnemyName do
				task.wait(0.15)
			end

			attackHoldStop()
			task.wait(0.15)
		end
	end)
end

------------------------------------------------------------
-- // Stop
------------------------------------------------------------
local function stopAll()
	attackHoldStop()
	isHunting = false
	if followThread then
		pcall(function() task.cancel(followThread) end)
		followThread = nil
	end
	if killThread then
		pcall(function() task.cancel(killThread) end)
		killThread = nil
	end
	if activeTween then
		pcall(function() activeTween:Cancel() end)
		activeTween = nil
	end
	local char, hum, hrp = getCharacter()
	if hrp then hrp.Anchored = false end
	currentEnemy = nil
end

------------------------------------------------------------
-- // RAYFIELD UI
------------------------------------------------------------
local window = Rayfield:CreateWindow({
	name = "Enemy Selector",
	subtitle = "Rayfield Gen2",
	sidebarLayout = true,
	theme = "amethyst",
})

local tab = window:CreateTab({
	name = "Main",
	icon = 93364949241311,
})

------------------------------------------------------------
-- // Data helpers
------------------------------------------------------------
local function getAreaNames()
	local names = {}
	for _, r in ipairs(regions:GetChildren()) do
		if r:IsA("Folder") or r:IsA("Model") then
			table.insert(names, r.Name)
		end
	end
	table.sort(names)
	return names
end

local function getEnemyNames()
	local counts = {}
	if not selectedArea then return counts end
	local activeNpcs = selectedArea:FindFirstChild("ActiveNpcs")
	if not activeNpcs then return counts end
	for _, npcFolder in ipairs(activeNpcs:GetChildren()) do
		if npcFolder:IsA("Folder") or npcFolder:IsA("Model") then
			for _, enemy in ipairs(npcFolder:GetChildren()) do
				if enemy:IsA("Model") and enemy:FindFirstChildOfClass("Humanoid") then
					counts[enemy.Name] = (counts[enemy.Name] or 0) + 1
				end
			end
		end
	end
	return counts
end

local function buildEnemyList()
	local counts = getEnemyNames()
	local list = {}
	for name, count in pairs(counts) do
		table.insert(list, name .. "  (" .. count .. ")")
	end
	table.sort(list)
	return list
end

------------------------------------------------------------
-- // Dropdowns
------------------------------------------------------------
local EnemyDropdown

local AreaDropdown = tab:CreateDropdown({
	name = "Area",
	options = getAreaNames(),
	callback = function(opt)
		local val = type(opt) == "table" and opt[1] or opt
		if not val then return end

		local area = regions:FindFirstChild(val)
		if not area then
			window:Notify({ title = "Error", content = "Area gak ketemu: " .. val })
			return
		end

		selectedArea = area
		targetEnemyName = nil
		stopAll()

		local list = buildEnemyList()
		if EnemyDropdown then
			pcall(function() EnemyDropdown:Refresh(list) end)
		end

		window:Notify({
			title = "Area",
			content = val .. " • " .. #list .. " jenis enemy",
		})
	end,
})

EnemyDropdown = tab:CreateDropdown({
	name = "Nama Enemy",
	options = {},
	callback = function(opt)
		local val = type(opt) == "table" and opt[1] or opt
		if not val then return end

		local name = string.match(val, "^(.-)%s+%(%d+%)$") or val
		targetEnemyName = name

		if not selectedArea then
			window:Notify({ title = "Pilih area dulu", content = "Belum ada area." })
			return
		end

		stopAll()
		isHunting = true
		startFollow()
		startHunting()

		window:Notify({ title = "Hunting", content = "Target: " .. name })
	end,
})

------------------------------------------------------------
-- // Stop button
------------------------------------------------------------
tab:CreateButton({
	name = "Stop Hunting",
	callback = function()
		stopAll()
		window:Notify({ title = "Stopped", content = "Hunting dihentikan." })
	end,
})

------------------------------------------------------------
-- // Info
------------------------------------------------------------
tab:CreateParagraph({
	title = "Cara Pakai",
	content = "1. Pilih Area\n2. Pilih Nama Enemy → auto hunting\n3. Klik Stop buat berhenti\n\nTween: belakang musuh, Y ngikut musuh\nAttack: hold left click",
})

------------------------------------------------------------
-- // Auto-refresh list tiap 5s
------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(5)
		pcall(function() AreaDropdown:Refresh(getAreaNames()) end)

		if selectedArea and not isHunting then
			pcall(function() EnemyDropdown:Refresh(buildEnemyList()) end)
		end
	end
end)

window:Notify({
	title = "Enemy Selector",
	content = "Loaded • Theme: amethyst",
})