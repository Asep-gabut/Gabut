local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local targetPosition = Vector3.new(502, 71, -375)

-- ============ GUI ROOT ============
local gui = Instance.new("ScreenGui")
gui.Name = "TweenGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- ============ FLOATING BUTTON ============
local fab = Instance.new("TextButton")
fab.AnchorPoint = Vector2.new(1, 0.5)
fab.Position = UDim2.new(1, -20, 0.5, 0)
fab.Size = UDim2.fromOffset(56, 56)
fab.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
fab.BorderSizePixel = 0
fab.Text = "≡"
fab.Font = Enum.Font.GothamBold
fab.TextColor3 = Color3.fromRGB(255, 255, 255)
fab.TextSize = 26
fab.AutoButtonColor = false
fab.Active = true
fab.Parent = gui

Instance.new("UICorner", fab).CornerRadius = UDim.new(1, 0)

local fabGrad = Instance.new("UIGradient")
fabGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(88, 101, 242)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 100, 255)),
})
fabGrad.Rotation = 90
fabGrad.Parent = fab

local fabStroke = Instance.new("UIStroke")
fabStroke.Color = Color3.fromRGB(180, 160, 255)
fabStroke.Thickness = 1.5
fabStroke.Transparency = 0.4
fabStroke.Parent = fab

-- ============ MAIN PANEL ============
local container = Instance.new("Frame")
container.Name = "Panel"
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.fromScale(0.5, 0.5)
container.Size = UDim2.fromOffset(340, 340)
container.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
container.BorderSizePixel = 0
container.Active = true
container.Visible = false
container.Parent = gui

Instance.new("UICorner", container).CornerRadius = UDim.new(0, 18)

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(255, 255, 255)
containerStroke.Thickness = 1
containerStroke.Transparency = 0.9
containerStroke.Parent = container

local shadow = Instance.new("ImageLabel")
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.fromScale(0.5, 0.5)
shadow.Size = UDim2.new(1, 50, 1, 50)
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://6014261993"
shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
shadow.ImageTransparency = 0.6
shadow.ScaleType = Enum.ScaleType.Slice
shadow.SliceCenter = Rect.new(49, 49, 450, 450)
shadow.ZIndex = 0
shadow.Parent = container

-- Header
local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 80)
header.Active = true
header.ZIndex = 1
header.Parent = container

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(24, 22)
title.Size = UDim2.new(1, -80, 0, 28)
title.Font = Enum.Font.GothamBold
title.Text = "Karakter Mover"
title.TextColor3 = Color3.fromRGB(245, 245, 255)
title.TextSize = 21
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 2
title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(24, 50)
subtitle.Size = UDim2.new(1, -80, 0, 18)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "Physics ke 502, 71, -375"
subtitle.TextColor3 = Color3.fromRGB(120, 120, 145)
subtitle.TextSize = 13
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 2
subtitle.Parent = header

-- Close
local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -14, 0, 14)
closeButton.Size = UDim2.fromOffset(38, 38)
closeButton.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
closeButton.BorderSizePixel = 0
closeButton.Text = "✕"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextColor3 = Color3.fromRGB(200, 200, 215)
closeButton.TextSize = 18
closeButton.AutoButtonColor = false
closeButton.ZIndex = 10
closeButton.Parent = container

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(1, 0)

-- Drag
local dragging, dragInput, dragStart, startPos = false, nil, nil, nil

local function updateDrag(input)
	local delta = input.Position - dragStart
	container.Position = UDim2.new(
		startPos.X.Scale, startPos.X.Offset + delta.X,
		startPos.Y.Scale, startPos.Y.Offset + delta.Y
	)
end

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = container.Position
		dragInput = input
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

header.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input == dragInput then
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			updateDrag(input)
		end
	end
end)

-- Panel toggle
local function openPanel()
	container.Visible = true
	container.Size = UDim2.fromOffset(300, 300)
	container.BackgroundTransparency = 1
	TweenService:Create(container, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(340, 340)
	}):Play()
	TweenService:Create(container, TweenInfo.new(0.2), {
		BackgroundTransparency = 0
	}):Play()
end

local function closePanel()
	local t = TweenService:Create(container, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(300, 300)
	})
	t:Play()
	t.Completed:Wait()
	container.Visible = false
end

fab.Activated:Connect(openPanel)
closeButton.Activated:Connect(closePanel)

-- ============ Speed Card ============
local speedCard = Instance.new("Frame")
speedCard.Position = UDim2.fromOffset(22, 96)
speedCard.Size = UDim2.new(1, -44, 0, 100)
speedCard.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
speedCard.BorderSizePixel = 0
speedCard.ZIndex = 2
speedCard.Parent = container

Instance.new("UICorner", speedCard).CornerRadius = UDim.new(0, 14)

local speedLabel = Instance.new("TextLabel")
speedLabel.BackgroundTransparency = 1
speedLabel.Position = UDim2.fromOffset(18, 14)
speedLabel.Size = UDim2.new(1, -70, 0, 20)
speedLabel.Font = Enum.Font.GothamMedium
speedLabel.Text = "Speed"
speedLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
speedLabel.TextSize = 14
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.ZIndex = 3
speedLabel.Parent = speedCard

local speedValue = Instance.new("TextLabel")
speedValue.BackgroundTransparency = 1
speedValue.Position = UDim2.new(1, -70, 0, 14)
speedValue.Size = UDim2.fromOffset(52, 20)
speedValue.Font = Enum.Font.GothamBold
speedValue.Text = "5"
speedValue.TextColor3 = Color3.fromRGB(140, 130, 255)
speedValue.TextSize = 16
speedValue.TextXAlignment = Enum.TextXAlignment.Right
speedValue.ZIndex = 3
speedValue.Parent = speedCard

local trackHolder = Instance.new("Frame")
trackHolder.AnchorPoint = Vector2.new(0.5, 0.5)
trackHolder.Position = UDim2.new(0.5, 0, 0, 68)
trackHolder.Size = UDim2.new(1, -36, 0, 12)
trackHolder.BackgroundColor3 = Color3.fromRGB(48, 48, 60)
trackHolder.BorderSizePixel = 0
trackHolder.ZIndex = 3
trackHolder.Parent = speedCard

Instance.new("UICorner", trackHolder).CornerRadius = UDim.new(1, 0)

local trackFill = Instance.new("Frame")
trackFill.Size = UDim2.fromScale(0.4, 1)
trackFill.BackgroundColor3 = Color3.fromRGB(120, 100, 255)
trackFill.BorderSizePixel = 0
trackFill.ZIndex = 4
trackFill.Parent = trackHolder

Instance.new("UICorner", trackFill).CornerRadius = UDim.new(1, 0)

local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(88, 101, 242)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 100, 255)),
})
fillGrad.Parent = trackFill

local knob = Instance.new("Frame")
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.fromScale(0.4, 0.5)
knob.Size = UDim2.fromOffset(28, 28)
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.BorderSizePixel = 0
knob.ZIndex = 5
knob.Parent = trackHolder

Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

local knobStroke = Instance.new("UIStroke")
knobStroke.Color = Color3.fromRGB(120, 100, 255)
knobStroke.Thickness = 2
knobStroke.Parent = knob

local hitbox = Instance.new("TextButton")
hitbox.BackgroundTransparency = 1
hitbox.AnchorPoint = Vector2.new(0.5, 0.5)
hitbox.Position = UDim2.new(0.5, 0, 0, 68)
hitbox.Size = UDim2.new(1, -20, 0, 60)
hitbox.Text = ""
hitbox.AutoButtonColor = false
hitbox.ZIndex = 6
hitbox.Parent = speedCard

-- ============ Slider Logic ============
local MIN_SPEED, MAX_SPEED = 1, 20
local currentSpeed = 5
local sliderDragging = false

local function setFromX(mouseX)
	local relX = math.clamp((mouseX - trackHolder.AbsolutePosition.X) / trackHolder.AbsoluteSize.X, 0, 1)
	currentSpeed = math.floor(MIN_SPEED + relX * (MAX_SPEED - MIN_SPEED) + 0.5)
	local pct = (currentSpeed - MIN_SPEED) / (MAX_SPEED - MIN_SPEED)
	trackFill.Size = UDim2.fromScale(pct, 1)
	knob.Position = UDim2.fromScale(pct, 0.5)
	speedValue.Text = tostring(currentSpeed)
end

hitbox.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		sliderDragging = true
		setFromX(input.Position.X)
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				sliderDragging = false
			end
		end)
	end
end)

hitbox.InputChanged:Connect(function(input)
	if not sliderDragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		setFromX(input.Position.X)
	end
end)

-- ============ MOVE Button ============
local button = Instance.new("TextButton")
button.AnchorPoint = Vector2.new(0.5, 0)
button.Position = UDim2.new(0.5, 0, 0, 210)
button.Size = UDim2.fromOffset(280, 60)
button.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
button.BorderSizePixel = 0
button.Text = "MOVE"
button.Font = Enum.Font.GothamBold
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.TextSize = 17
button.AutoButtonColor = false
button.ZIndex = 2
button.Parent = container

Instance.new("UICorner", button).CornerRadius = UDim.new(0, 14)

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(88, 101, 242)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 100, 255)),
})
gradient.Rotation = 90
gradient.Parent = button

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = Color3.fromRGB(180, 160, 255)
buttonStroke.Thickness = 1
buttonStroke.Transparency = 0.6
buttonStroke.Parent = button

-- ============ LINEAR VELOCITY ACTION ============
local isMoving = false

local function doMove()
	if isMoving then return end

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	isMoving = true
	button.Text = "..."

	-- Simpan state
	local oldWalkSpeed = humanoid.WalkSpeed
	local oldJumpPower = humanoid.JumpPower
	local oldAutoRotate = humanoid.AutoRotate

	-- Biar humanoid ga ngelawan
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false

	-- Attachment + LinearVelocity
	local attachment = Instance.new("Attachment")
	attachment.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = Vector3.zero
	lv.Parent = hrp

	-- AlignOrientation biar karakter hadap arah gerak
	local ao = Instance.new("AlignOrientation")
	ao.Attachment0 = attachment
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.MaxTorque = math.huge
	ao.Responsiveness = 20
	ao.Parent = hrp

	-- Kecepatan (speed slider 1-20 → 15-300 studs/s)
	local studsPerSec = currentSpeed * 15

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not hrp.Parent then
			conn:Disconnect()
			return
		end

		local diff = targetPosition - hrp.Position
		local dist = diff.Magnitude

		-- Selesai
		if dist < 4 then
			conn:Disconnect()
			lv:Destroy()
			ao:Destroy()
			attachment:Destroy()

			hrp.CFrame = CFrame.new(targetPosition, targetPosition + hrp.CFrame.LookVector)

			humanoid.WalkSpeed = oldWalkSpeed
			humanoid.JumpPower = oldJumpPower
			humanoid.AutoRotate = oldAutoRotate

			button.Text = "MOVE"
			isMoving = false
			return
		end

		local dir = diff.Unit

		-- Kecepatan proporsional kalau udah deket (biar ga overshoot)
		local speedMul = math.clamp(dist / 20, 0.2, 1)
		lv.VectorVelocity = dir * studsPerSec * speedMul

		-- Hadap arah gerak
		ao.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(dir.X, 0, dir.Z))
	end)
end

button.Activated:Connect(doMove)