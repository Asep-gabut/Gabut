--[[
Auto Fish with Rayfield UI
Features: Auto Fishing, Lag Fix, Teleports to Roslit Bay & Atlantis
]]
getgenv().RAYFIELD_SECURE = true
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
local Rep = game:GetService("ReplicatedStorage")
local Net = Rep:WaitForChild("packages"):WaitForChild("Net")
local Player = game:GetService("Players").LocalPlayer

repeat task.wait() until Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")

local Window = Rayfield:CreateWindow({
    Name = "Auto Fish",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "Asep",
    Configuration = {
        Saved = false,
        FolderName = "AutoFish",
        FileName = "Config",
    }
})

local Tab = Window:CreateTab({ Name = "Main", Icon = 4483362458 })

getgenv().AutoFish = false

Tab:CreateToggle({
    Name = "Auto Fishing",
    CurrentValue = false,
    Callback = function(Value)
        getgenv().AutoFish = Value
    end,
})

Tab:CreateToggle({
    Name = "Lag Fix",
    CurrentValue = false,
    Callback = function(Value)
        game.Lighting.GlobalShadows = not Value
        if Value then
            for _, v in pairs(game:GetDescendants()) do
                if v:IsA("Texture") or v:IsA("Decal") then
                    v.Transparency = 1
                end
            end
        end
    end,
})

Tab:CreateSection("Teleports")

Tab:CreateButton({
    Name = "Roslit Bay",
    Callback = function()
        if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            Player.Character.HumanoidRootPart.CFrame = CFrame.new(-1450, 135, 750)
        end
    end,
})

Tab:CreateButton({
    Name = "Atlantis",
    Callback = function()
        if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            Player.Character.HumanoidRootPart.CFrame = CFrame.new(-4275, -603, 1818)
        end
    end,
})

task.spawn(function()
    while true do
        if getgenv().AutoFish then
            pcall(function()
                -- 1. Cast (hanya lempar jika GUI reel tidak sedang aktif)
                local reel = Player.PlayerGui:FindFirstChild("reel")
                if not (reel and (not reel:IsA("ScreenGui") or reel.Enabled)) then
                    Net:WaitForChild("RF/FishingRod/Cast"):InvokeServer(0.1, false)
                    task.wait(0.5)
                end
                
                -- 2. ONLY INNER LOOP: Shake until reel GUI appears (aktif)
                local startTime = tick()
                while task.wait(0.1) do
                    if not getgenv().AutoFish then break end
                    if tick() - startTime > 15 then break end
                    Net:WaitForChild("RE/LureShake/Shake"):FireServer()
                    local currentReel = Player.PlayerGui:FindFirstChild("reel")
                    if currentReel and (not currentReel:IsA("ScreenGui") or currentReel.Enabled) then
                        break
                    end
                end

                local activeReel = Player.PlayerGui:FindFirstChild("reel")
                if getgenv().AutoFish and activeReel and (not activeReel:IsA("ScreenGui") or activeReel.Enabled) then
                    task.wait(0.5)
                    Net:WaitForChild("RE/Reel/Finish"):FireServer({{ e = 100.25426827967165, p = false, l = {}, d = { SlashCount = 0 } }})
                    
                    -- Tunggu GUI reel hilang/nonaktif sebelum mengulang loop
                    local closeTime = tick()
                    while task.wait(0.1) do
                        local r = Player.PlayerGui:FindFirstChild("reel")
                        if not (r and (not r:IsA("ScreenGui") or r.Enabled)) or (tick() - closeTime > 5) then
                            break
                        end
                    end
                    task.wait(0.3)
                end
            end)
        end
        task.wait()
    end
end)
