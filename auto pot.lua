local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local ITEM_NAMES = {
   "All Season Potion",
   "Glitched Potion", 
   "Luck Potion",
   "Lure Speed Potion",
}

local MAX_CLAIM_ITERATIONS = 3
local MAX_POTION_CYCLES = 20

local claimEvent = ReplicatedStorage.packages.Net["RE/PersonalAquarium/ClaimRewards"]

task.spawn(function()
   local count = 0
   while count < MAX_CLAIM_ITERATIONS do
       pcall(function()
           claimEvent:FireServer()
       end)
       count = count + 1
       task.wait(1)
   end
end)

local function getTool(name)
   local backpack = plr:FindFirstChild("Backpack")
   if backpack then
       for _, t in ipairs(backpack:GetChildren()) do
           if t.Name == name and t:IsA("Tool") then
               return t
           end
       end
   end
   return nil
end

task.spawn(function()
   local cycleCount = 0
   while cycleCount < MAX_POTION_CYCLES do
       for _, itemName in ipairs(ITEM_NAMES) do
           local tool = getTool(itemName)
           if tool then
               local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
               if hum then
                   hum:EquipTool(tool)
                   task.wait(0.2)
                   pcall(function()
                       tool:Activate()
                   end)
               end
           end
           task.wait()
       end
       cycleCount = cycleCount + 1
       task.wait(0.5)
   end
end)
