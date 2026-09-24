-- // Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local humanoids = workspace:WaitForChild("Humanoids")
local regions = humanoids:WaitForChild("Regions")

-- // State
local selectedArea = nil
local targetEnemyName = nil
local currentEnemy = nil
local followThread = nil
local killThread = nil
local activeTween = nil
local isHolding = false

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
-- // GUI
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "EnemySelectorGUI"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(0, 60, 0, 60)
toggle.Position = UDim2.new(1, -80, 1, -80)
toggle.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
toggle.Text = "⚔"
toggle.TextSize = 28
toggle.TextColor3 = Color3.fromRGB(255, 220, 120)
toggle.Font = Enum.Font.GothamBold
toggle.BorderSizePixel = 0
toggle.Parent = gui
Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)
local togStroke = Instance.new("UIStroke", toggle)
togStroke.Color = Color3.fromRGB(255, 220, 120)
togStroke.Thickness = 2

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 300, 0, 450)
main.Position = UDim2.new(0.5, -150, 0.5, -225)
main.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
main.BorderSizePixel = 0
main.Visible = false
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Color3.fromRGB(255, 220, 120)
mainStroke.Thickness = 2

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
title.Text = "  ⚔  Enemy Selector"
title.TextColor3 = Color3.fromRGB(255, 220, 120)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.BorderSizePixel = 0
title.Parent = main
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 12)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -36, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.BorderSizePixel = 0
closeBtn.Parent = main
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1,0)
closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)

local dragging, dragStart, startPos
title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = main.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
	or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
		                          startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

local areaLabel = Instance.new("TextLabel")
areaLabel.Size = UDim2.new(1, -20, 0, 22)
areaLabel.Position = UDim2.new(0, 10, 0, 48)
areaLabel.BackgroundTransparency = 1
areaLabel.Text = "📍 Area:"
areaLabel.TextColor3 = Color3.fromRGB(200,200,200)
areaLabel.Font = Enum.Font.GothamBold
areaLabel.TextSize = 13
areaLabel.TextXAlignment = Enum.TextXAlignment.Left
areaLabel.Parent = main

local areaScroll = Instance.new("ScrollingFrame")
areaScroll.Size = UDim2.new(1, -20, 0, 110)
areaScroll.Position = UDim2.new(0, 10, 0, 72)
areaScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
areaScroll.BorderSizePixel = 0
areaScroll.ScrollBarThickness = 4
areaScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
areaScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
areaScroll.Parent = main
Instance.new("UICorner", areaScroll).CornerRadius = UDim.new(0, 8)
local areaLayout = Instance.new("UIListLayout", areaScroll)
areaLayout.Padding = UDim.new(0, 4)
local areaPad = Instance.new("UIPadding", areaScroll)
areaPad.PaddingTop = UDim.new(0,4)
areaPad.PaddingBottom = UDim.new(0,4)
areaPad.PaddingLeft = UDim.new(0,4)
areaPad.PaddingRight = UDim.new(0,4)

local enemyLabel = Instance.new("TextLabel")
enemyLabel.Size = UDim2.new(1, -20, 0, 22)
enemyLabel.Position = UDim2.new(0, 10, 0, 188)
enemyLabel.BackgroundTransparency = 1
enemyLabel.Text = "👹 Nama Enemy:"
enemyLabel.TextColor3 = Color3.fromRGB(200,200,200)
enemyLabel.Font = Enum.Font.GothamBold
enemyLabel.TextSize = 13
enemyLabel.TextXAlignment = Enum.TextXAlignment.Left
enemyLabel.Parent = main

local enemyScroll = Instance.new("ScrollingFrame")
enemyScroll.Size = UDim2.new(1, -20, 0, 110)
enemyScroll.Position = UDim2.new(0, 10, 0, 212)
enemyScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
enemyScroll.BorderSizePixel = 0
enemyScroll.ScrollBarThickness = 4
enemyScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
enemyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
enemyScroll.Parent = main
Instance.new("UICorner", enemyScroll).CornerRadius = UDim.new(0, 8)
local enemyLayout = Instance.new("UIListLayout", enemyScroll)
enemyLayout.Padding = UDim.new(0, 4)
local enemyPad = Instance.new("UIPadding", enemyScroll)
enemyPad.PaddingTop = UDim.new(0,4)
enemyPad.PaddingBottom = UDim.new(0,4)
enemyPad.PaddingLeft = UDim.new(0,4)
enemyPad.PaddingRight = UDim.new(0,4)

local attackBtn = Instance.new("TextButton")
attackBtn.Size = UDim2.new(1, -20, 0, 46)
attackBtn.Position = UDim2.new(0, 10, 0, 330)
attackBtn.BackgroundColor3 = Color3.fromRGB(60, 150, 80)
attackBtn.Text = "HUNTING..."
attackBtn.TextColor3 = Color3.fromRGB(255,255,255)
attackBtn.Font = Enum.Font.GothamBold
attackBtn.TextSize = 15
attackBtn.BorderSizePixel = 0
attackBtn.Parent = main
Instance.new("UICorner", attackBtn).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 60)
status.Position = UDim2.new(0, 10, 0, 382)
status.BackgroundTransparency = 1
status.Text = "Pilih area & nama enemy..."
status.TextColor3 = Color3.fromRGB(180,180,180)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = main

------------------------------------------------------------
-- // Helpers
------------------------------------------------------------
local function clearScroll(scroll)
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
end

local function makeListButton(parent, text, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(230,230,230)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 13
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.MouseButton1Click:Connect(callback)
	return btn
end

local function highlight(container, selectedBtn)
	for _, b in ipairs(container:GetChildren()) do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
			b.TextColor3 = Color3.fromRGB(230,230,230)
		end
	end
	if selectedBtn then
		selectedBtn.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
		selectedBtn.TextColor3 = Color3.fromRGB(20,20,20)
	end
end

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

-- ✅ FIX Y: pakai posisi Y MUSUH, bukan player
local function getBehindCFrame(enemy)
	local tp = getEnemyPart(enemy)
	if not tp then return nil end

	local enemyCF = tp.CFrame

	-- Posisi di belakang musuh
	local behindPos = enemyCF.Position - enemyCF.LookVector * BEHIND_DISTANCE

	-- ⚠️ Y = posisi Y MUSUH (biar sejajar)
	local targetPos = Vector3.new(behindPos.X, enemyCF.Position.Y, behindPos.Z)

	-- Hadap ke musuh (dari belakang ngadep depan)
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
		while targetEnemyName and selectedArea do
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
						-- Udah deket, cuma update rotasi & Y biar presisi
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
-- // KILL LOOP — hold click selama ada target
------------------------------------------------------------
local function startHunting()
	if killThread then
		pcall(function() task.cancel(killThread) end)
	end

	killThread = task.spawn(function()
		while targetEnemyName and selectedArea do
			local list = findAllEnemiesWithName()

			if #list == 0 then
				currentEnemy = nil
				attackHoldStop()   -- stop hold kalau gak ada target
				status.Text = "⏳ Nunggu " .. targetEnemyName .. " spawn..."
				task.wait(1)
				continue
			end

			status.Text = "🎯 " .. #list .. " " .. targetEnemyName .. " hidup"

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

			-- 🔥 HOLD left click selama musuh masih hidup
			attackHoldStart()

			-- Tunggu sampai musuh mati (cek tiap 0.15s)
			while isEnemyAlive(closest) and targetEnemyName and selectedArea do
				task.wait(0.15)
			end

			-- Musuh mati → stop hold sebentar sebelum pindah target
			attackHoldStop()
			task.wait(0.1)

			if closest and closest.Parent then
				status.Text = "✅ " .. closest.Name .. " mati, lanjut..."
			end
			task.wait(0.2)
		end
	end)
end

------------------------------------------------------------
-- // Stop
------------------------------------------------------------
local function stopAll()
	attackHoldStop()  -- ⚠️ WAJIB: lepas hold biar gak nyangkut
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
-- // List refresh
------------------------------------------------------------
local refreshEnemies
refreshEnemies = function()
	clearScroll(enemyScroll)
	if not selectedArea then return end

	local activeNpcs = selectedArea:FindFirstChild("ActiveNpcs")
	if not activeNpcs then
		status.Text = "ActiveNpcs kosong di area ini."
		return
	end

	local nameCount = {}
	for _, npcFolder in ipairs(activeNpcs:GetChildren()) do
		if npcFolder:IsA("Folder") or npcFolder:IsA("Model") then
			for _, enemy in ipairs(npcFolder:GetChildren()) do
				if enemy:IsA("Model") and enemy:FindFirstChildOfClass("Humanoid") then
					nameCount[enemy.Name] = (nameCount[enemy.Name] or 0) + 1
				end
			end
		end
	end

	local sortedNames = {}
	for name, _ in pairs(nameCount) do
		table.insert(sortedNames, name)
	end
	table.sort(sortedNames)

	if #sortedNames == 0 then
		status.Text = "Tidak ada enemy aktif di area ini."
		return
	end

	for _, name in ipairs(sortedNames) do
		local label = name .. "  (" .. nameCount[name] .. ")"
		local btn
		btn = makeListButton(enemyScroll, label, function()
			targetEnemyName = name
			highlight(enemyScroll, btn)
			status.Text = "🎯 Target: " .. name
			startFollow()
			startHunting()
			attackBtn.Text = "STOP (F)"
			attackBtn.BackgroundColor3 = Color3.fromRGB(200, 55, 55)
		end)
	end

	status.Text = #sortedNames .. " jenis enemy ditemukan."
end

local function refreshAreas()
	clearScroll(areaScroll)
	for _, region in ipairs(regions:GetChildren()) do
		if region:IsA("Folder") or region:IsA("Model") then
			local btn
			btn = makeListButton(areaScroll, region.Name, function()
				selectedArea = region
				targetEnemyName = nil
				stopAll()
				attackBtn.Text = "HUNTING..."
				attackBtn.BackgroundColor3 = Color3.fromRGB(60, 150, 80)
				highlight(areaScroll, btn)
				refreshEnemies()
			end)
		end
	end
end

------------------------------------------------------------
-- // Toggle stop
------------------------------------------------------------
local function toggleStop()
	if targetEnemyName then
		targetEnemyName = nil
		stopAll()
		status.Text = "⏹ Stopped."
		attackBtn.Text = "HUNTING..."
		attackBtn.BackgroundColor3 = Color3.fromRGB(60, 150, 80)
	else
		status.Text = "Pilih nama enemy dulu di list."
	end
end

------------------------------------------------------------
-- // Inputs
------------------------------------------------------------
toggle.MouseButton1Click:Connect(function()
	main.Visible = not main.Visible
	if main.Visible then refreshAreas() end
end)

attackBtn.MouseButton1Click:Connect(toggleStop)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then
		toggleStop()
	end
end)

task.spawn(function()
	while true do
		task.wait(5)
		if main.Visible and selectedArea and not targetEnemyName then
			refreshEnemies()
		end
	end
end)