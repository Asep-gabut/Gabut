--[[
Auto Fish with Rayfield UI
Features: Auto Fishing, Lag Fix, Teleports to Roslit Bay & Atlantis
]]

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
                -- Cast
                Net:WaitForChild("RF/FishingRod/Cast"):InvokeServer(0.1, false)
                
                -- Loop shake until reel gui appear
                repeat 
                    if not getgenv().AutoFish then break end
                    Net:WaitForChild("RE/LureShake/Shake"):FireServer()
                    task.wait(0.1)
                until Player.PlayerGui:FindFirstChild("reel")

                -- Wait 0.4 seconds
                task.wait(0.4)

                -- Fire reel finish
                if getgenv().AutoFish then
                    Net:WaitForChild("RE/Reel/Finish"):FireServer({{ e = 100.25426827967165, p = false, l = {}, d = { SlashCount = 0 } }})
                    
                    -- Wait until reel GUI is gone after finish before next cast
                    repeat
                        task.wait(0.1)
                    until not Player.PlayerGui:FindFirstChild("reel")
                end
            end)
        end
        task.wait()
    end
end)
