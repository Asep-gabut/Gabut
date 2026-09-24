-- // Rayfield Gen2
getgenv().RAYFIELD_SECURE = true
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local humanoids = workspace:WaitForChild("Humanoids")
local regions = humanoids:WaitForChild("Regions")

local SignalEvent = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("ServerAndClient")
	:WaitForChild("Signals")
	:WaitForChild("SignalEvent")
	:WaitForChild("Event")

------------------------------------------------------------
-- // ATTACK — Combo 1→2→3→4→5
------------------------------------------------------------
local COMBO = {
	{ slot = 1, press = true,  delay = 0.038000000000000006, arg6 = false },
	{ slot = 2, press = false, delay = 0,                    arg6 = false },
	{ slot = 3, press = false, delay = 0,                    arg6 = false },
	{ slot = 4, press = false, delay = 0,                    arg6 = false },
}

local function attackFire(entry)
	local args = {
		"Combat_Service",
		"Combat",
		entry.slot,
		entry.press,
		entry.delay,
		entry.arg6
	}
	local ok, err = pcall(function()
		SignalEvent:FireServer(unpack(args))
	end)
	if not ok then
		warn("[EnemySel] FireServer error:", err)
	end
end

local function attackCombo()
	for _, entry in ipairs(COMBO) do
		attackFire(entry)
	end
end

------------------------------------------------------------
-- // CONFIG
------------------------------------------------------------
local Config = {
	BehindDistance = 4,
	FollowInterval = 0.05,
	AttackInterval = 0.15,
}

------------------------------------------------------------
-- // State
------------------------------------------------------------
local selectedArea = nil
local targetEnemyName = nil
local currentEnemy = nil
local followThread = nil
local killThread = nil
local isHunting = false

local function getCharacter()
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hum and hrp then return char, hum, hrp end
	return nil
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

local function getBehindCFrame(enemy)
	local tp = getEnemyPart(enemy)
	if not tp then return nil end

	local enemyCF = tp.CFrame
	local behindPos = enemyCF.Position - enemyCF.LookVector * Config.BehindDistance

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
-- // FOLLOW LOOP — Set CFrame langsung (no tween, no anchor)
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
					hrp.CFrame = targetCF
				end
			end

			task.wait(Config.FollowInterval)
		end
	end)
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

			while isEnemyAlive(closest) and isHunting and targetEnemyName do
				attackCombo()
				task.wait(Config.AttackInterval)
			end

			task.wait(0.15)
		end
	end)
end

------------------------------------------------------------
-- // Stop
------------------------------------------------------------
local function stopAll()
	isHunting = false

	if followThread then
		pcall(function() task.cancel(followThread) end)
		followThread = nil
	end
	if killThread then
		pcall(function() task.cancel(killThread) end)
		killThread = nil
	end

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
-- // TARGET SECTION
------------------------------------------------------------
tab:CreateSection("Target")

local EnemyDropdown
local HuntToggle

tab:CreateDropdown({
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

		if isHunting then
			stopAll()
			if HuntToggle then pcall(function() HuntToggle:Set(false) end) end
		end

		selectedArea = area
		targetEnemyName = nil

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

		window:Notify({
			title = "Target",
			content = name .. " • nyalain Farm buat mulai",
		})
	end,
})

------------------------------------------------------------
-- // FARM SECTION
------------------------------------------------------------
tab:CreateSection("Farm")

HuntToggle = tab:CreateToggle({
	name = "Farm Enemy",
	flag = "FarmEnemy",
	value = false,
	callback = function(value)
		if value then
			if not selectedArea then
				window:Notify({ title = "Pilih area dulu", content = "Belum ada area." })
				HuntToggle:Set(false)
				return
			end
			if not targetEnemyName then
				window:Notify({ title = "Pilih enemy dulu", content = "Belum ada target." })
				HuntToggle:Set(false)
				return
			end

			stopAll()
			isHunting = true
			startFollow()
			startHunting()
			window:Notify({ title = "Farm Started", content = "Target: " .. targetEnemyName })
		else
			stopAll()
			window:Notify({ title = "Farm Stopped", content = "Hunting dihentikan." })
		end
	end,
})

------------------------------------------------------------
-- // SETTINGS SECTION
------------------------------------------------------------
tab:CreateSection("Settings")

tab:CreateSlider({
	name = "Behind Distance",
	range = { 1, 15 },
	increment = 0.5,
	value = Config.BehindDistance,
	suffix = " stud",
	callback = function(value)
		Config.BehindDistance = value
	end,
})

tab:CreateSlider({
	name = "Follow Interval",
	range = { 0.01, 0.2 },
	increment = 0.01,
	value = Config.FollowInterval,
	suffix = "s",
	callback = function(value)
		Config.FollowInterval = value
	end,
})

tab:CreateSlider({
	name = "Attack Interval",
	range = { 0.03, 1 },
	increment = 0.01,
	value = Config.AttackInterval,
	suffix = "s",
	callback = function(value)
		Config.AttackInterval = value
	end,
})

------------------------------------------------------------
-- // INFO
------------------------------------------------------------
tab:CreateSection("Info")

tab:CreateParagraph({
	title = "Cara Pakai",
	content = "1. Pilih Area\n2. Pilih Nama Enemy\n3. Nyalain 'Farm Enemy'\n\nFollow: set CFrame langsung (no tween, no anchor)\nAttack: combo 1→2→3→4→5",
})

------------------------------------------------------------
-- // Auto-refresh enemy list
------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(5)
		if not isHunting and selectedArea then
			pcall(function() EnemyDropdown:Refresh(buildEnemyList()) end)
		end
	end
end)

window:Notify({
	title = "Enemy Selector",
	content = "Loaded • Theme: amethyst",
})