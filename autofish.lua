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

-- Fungsi pembantu untuk mengecek apakah GUI reel benar-benar muncul di layar
local function isReelVisible()
    local reelGui = Player.PlayerGui:FindFirstChild("reel")
    if reelGui then
        -- Pastikan objeknya ada DAN statusnya sedang aktif (Enabled)
        if reelGui:IsA("ScreenGui") then
            return reelGui.Enabled
        end
        return true
    end
    return false
end

task.spawn(function()
    while true do
        if getgenv().AutoFish then
            pcall(function()
                -- Pastikan GUI reel dari tangkapan sebelumnya sudah tidak ada sebelum Cast
                if not isReelVisible() then
                    -- 1. Cast
                    Net:WaitForChild("RF/FishingRod/Cast"):InvokeServer(0.1, false)
                    task.wait(0.5) -- Jeda singkat agar animasi/proses cast terbaca server
                end
                
                -- 2. Shake sampai GUI reel muncul (dengan batas waktu/timeout 15 detik)
                local startTime = tick()
                while task.wait(0.1) do
                    if not getgenv().AutoFish then break end
                    if isReelVisible() then break end
                    if tick() - startTime > 15 then break end -- Mencegah stuck jika gagal cast
                    
                    Net:WaitForChild("RE/LureShake/Shake"):FireServer()
                end

                -- 3. Tarik ikan jika GUI reel benar-benar aktif
                if getgenv().AutoFish and isReelVisible() then
                    task.wait(0.5)
                    Net:WaitForChild("RE/Reel/Finish"):FireServer({{ e = 100.25426827967165, p = false, l = {}, d = { SlashCount = 0 } }})
                    
                    -- 4. TUNGGU sampai GUI reel hilang/tertutup sebelum lanjut ke siklus berikutnya
                    local waitClose = tick()
                    while isReelVisible() and (tick() - waitClose < 5) do
                        task.wait(0.1)
                    end
                    task.wait(0.5) -- Jeda aman sebelum melempar kail lagi
                end
            end)
        end
        task.wait()
    end
end)
