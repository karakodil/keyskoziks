--!strict
--[[
    Steal An Egg — Modern Luau Autofarm
    PlaceId: 107778070777162

    Features:
    • Classic Rayfield UI
    • TweenService movement (smooth + reliable)
    • EggCmds + Network fallbacks
    • Auto Collect / Place / Hatch / Equip Best
    • Automatic + manual biome selection
    • Noclip during farm cycles
    • Updated biome speed gates (Sep 2026)
]]

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- Services
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Character   = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid    = Character:WaitForChild("Humanoid") :: Humanoid
local RootPart    = Character:WaitForChild("HumanoidRootPart") :: BasePart

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    Humanoid  = char:WaitForChild("Humanoid") :: Humanoid
    RootPart  = char:WaitForChild("HumanoidRootPart") :: BasePart
end)

-- State
local State = {
    AutoFarm   = false,
    Collect    = false,
    Place      = false,
    Hatch      = false,
    EquipBest  = false,
    ChosenArea = "Automatic",
    TweenSpeed = 140, -- studs per second
}

-- Soft require helper
local function softRequire(inst: Instance?): any?
    if not inst then return nil end
    local ok, mod = pcall(require, inst)
    return if ok then mod else nil
end

-- Game modules
local Library = ReplicatedStorage:FindFirstChild("Library")
local Client  = Library and Library:FindFirstChild("Client")
local EggCmds = softRequire(Client and Client:FindFirstChild("EggCmds"))
local Network = softRequire(Client and Client:FindFirstChild("Network"))

-- Paths
local GuardAreas  = Workspace:WaitForChild("__OBJECTS"):WaitForChild("Areas"):WaitForChild("GuardAreas")
local SpawnedEggs = Workspace:FindFirstChild("AreaEggSlotsClient") or Workspace:FindFirstChild("AreaEggSlots")

local PlayerBase: Model?
local function refreshBase()
    for _, base in Workspace.Plots:GetChildren() do
        local sign = base:FindFirstChild("PlotSign")
        if sign then
            local frame = sign:FindFirstChild("PlayerPlotSign") and sign.PlayerPlotSign:FindFirstChild("Frame")
            local icon  = frame and frame:FindFirstChild("PlayerIcon")
            if icon and icon:IsA("ImageLabel") and string.find(icon.Image, tostring(LocalPlayer.UserId)) then
                PlayerBase = base :: Model
                return
            end
        end
    end
end
refreshBase()

-- Biome data (updated Sep 2026)
local Biomes: {[string]: number} = {
    ["Forest"]         = 0,
    ["Lake"]           = 900,
    ["Desert"]         = 10_000,
    ["Jungle"]         = 40_000,
    ["Snow"]           = 170_000,
    ["Volcano"]        = 700_000,
    ["Abyss Ocean"]    = 2_500_000,
    ["Prehistoric"]    = 17_000_000,
    ["Cosmic"]         = 700_000_000,
    ["Cherry Blossom"] = 2_500_000_000,
    ["Titan Temple"]   = 7_000_000_000,
}

local BiomeList = {"Automatic"}
do
    local sorted = {}
    for name in pairs(Biomes) do
        table.insert(sorted, name)
    end
    table.sort(sorted, function(a, b)
        return Biomes[a] < Biomes[b]
    end)
    for _, name in sorted do
        table.insert(BiomeList, name)
    end
end

local SAFE_AREA = Vector3.new(542, 71, -363)

-- ============================================================
-- Advanced Tween Movement
-- ============================================================
local currentTween: Tween?

local function cancelTween()
    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end
end

local function tweenTo(goal: Vector3, speed: number?): boolean
    if not RootPart or not RootPart.Parent then return false end

    cancelTween()

    local distance = (RootPart.Position - goal).Magnitude
    if distance < 3 then return true end

    local tweenSpeed = speed or State.TweenSpeed
    local duration = math.clamp(distance / tweenSpeed, 0.15, 8)

    local goalCF = CFrame.new(goal + Vector3.new(0, 3, 0))

    local info = TweenInfo.new(
        duration,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out
    )

    currentTween = TweenService:Create(RootPart, info, { CFrame = goalCF })
    currentTween:Play()

    local completed = false
    local conn
    conn = currentTween.Completed:Connect(function()
        completed = true
        if conn then conn:Disconnect() end
    end)

    local start = os.clock()
    while not completed and os.clock() - start < duration + 1.5 do
        if not State.AutoFarm then
            cancelTween()
            return false
        end
        task.wait()
    end

    return completed or (RootPart.Position - goal).Magnitude < 8
end

-- ============================================================
-- Core Logic
-- ============================================================
local function getSpeed(): number
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local speed = ls and ls:FindFirstChild("Speed")
    return if speed and speed:IsA("NumberValue") or speed:IsA("IntValue") then speed.Value else 0
end

local function getBestBiome(): string?
    if State.ChosenArea ~= "Automatic" then
        return State.ChosenArea
    end

    local current = getSpeed()
    local bestName: string? = nil
    local bestReq = -1

    for name, req in pairs(Biomes) do
        if req <= current and req > bestReq then
            bestName = name
            bestReq = req
        end
    end
    return bestName
end

local function getClosestEgg(): Model?
    if not SpawnedEggs or not RootPart then return nil end

    local closest: Model? = nil
    local closestDist = math.huge

    for _, egg in SpawnedEggs:GetChildren() do
        if egg:IsA("Model") then
            local primary = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
            if primary then
                local dist = (primary.Position - RootPart.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = egg
                end
            end
        end
    end
    return closest
end

local function stealEgg(egg: Model): boolean
    local uid = egg.Name

    -- Preferred modern path
    if EggCmds and type(EggCmds.RequestCarryAreaEgg) == "function" then
        local ok, res = pcall(EggCmds.RequestCarryAreaEgg, uid)
        if ok and res == true then return true end
    end

    -- Network module fallback
    if Network and type(Network.Invoke) == "function" then
        local ok, res = pcall(Network.Invoke, "Eggs: RequestAreaEggCarry", { Uid = uid })
        if ok and res == true then return true end
    end

    -- Raw remote fallback
    local netFolder = ReplicatedStorage:FindFirstChild("Network")
    local remote = netFolder and netFolder:FindFirstChild("Eggs: RequestAreaEggCarry")
    if remote and remote:IsA("RemoteFunction") then
        local ok, res = pcall(function()
            return remote:InvokeServer({ Uid = uid })
        end)
        if ok and res == true then return true end
    end

    return false
end

local function placeEggs()
    if not EggCmds or type(EggCmds.RequestPlaceEgg) ~= "function" then return end
    if type(EggCmds.GetOwnerRuntimeRecords) ~= "function" then return end

    local records = EggCmds.GetOwnerRuntimeRecords(LocalPlayer.UserId)
    if not records then return end

    refreshBase()
    if not PlayerBase then return end

    local center = PlayerBase:FindFirstChild("CenterPoint")
    if center and center:IsA("BasePart") then
        tweenTo(center.Position)
    end

    for uid in pairs(records) do
        local offset = CFrame.new(
            math.random(-22, 22),
            -0.5,
            math.random(-28, 28)
        )
        pcall(EggCmds.RequestPlaceEgg, uid, offset)
        task.wait(0.12)
    end
end

local function hatchEggs()
    if not EggCmds then return end
    if type(EggCmds.GetOwnerRuntimeRecords) ~= "function" then return end

    local records = EggCmds.GetOwnerRuntimeRecords(LocalPlayer.UserId)
    if not records then return end

    for uid in pairs(records) do
        local ready = true
        if type(EggCmds.IsLocalEggReady) == "function" then
            ready = EggCmds.IsLocalEggReady(uid)
        end

        if ready then
            pcall(function()
                if type(EggCmds.RequestHatchEgg) == "function" then
                    local res = EggCmds.RequestHatchEgg(uid)
                    if res and type(EggCmds.RequestCompleteHatchEgg) == "function" then
                        EggCmds.RequestCompleteHatchEgg(uid)
                    end
                end
            end)
            task.wait(0.18)
        end
    end
end

local function equipBest()
    if EggCmds and type(EggCmds.RequestEquipBest) == "function" then
        pcall(EggCmds.RequestEquipBest)
        return
    end

    local netFolder = ReplicatedStorage:FindFirstChild("Network")
    local remote = netFolder and netFolder:FindFirstChild("Backpack: EquipBest")
    if remote and remote:IsA("RemoteFunction") then
        pcall(function() remote:InvokeServer() end)
    end
end

-- Noclip helper
local noclipConn: RBXScriptConnection?
local function enableNoclip()
    if noclipConn then return end
    noclipConn = RunService.Stepped:Connect(function()
        if not Character then return end
        for _, part in Character:GetDescendants() do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end
    if Character then
        for _, part in Character:GetDescendants() do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

-- Main farm loop
local function runFarmCycle()
    if not State.AutoFarm then return end
    if not RootPart or not Humanoid then return end

    enableNoclip()

    if State.Collect then
        local biomeName = getBestBiome()
        local area = biomeName and GuardAreas:FindFirstChild(biomeName)

        if area then
            local bounds = area:FindFirstChild("Bounds")
            if bounds and bounds:IsA("BasePart") then
                tweenTo(SAFE_AREA)
                task.wait(0.1)
                tweenTo(bounds.Position)
                task.wait(0.2)

                local egg = getClosestEgg()
                if egg then
                    local primary = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
                    if primary then
                        tweenTo(primary.Position)
                        task.wait(0.35)
                        stealEgg(egg)
                        task.wait(0.45)
                        tweenTo(SAFE_AREA)
                    end
                end
            end
        end
    end

    if State.Place then
        placeEggs()
    end

    if State.Hatch then
        hatchEggs()
    end

    if State.EquipBest then
        equipBest()
    end

    disableNoclip()
end

-- ============================================================
-- UI (Classic Rayfield)
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name = "Steal An Egg • Modern",
    LoadingTitle = "Steal An Egg",
    LoadingSubtitle = "Luau + TweenService",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "StealAnEgg",
        FileName = "ModernAutofarm"
    },
    Discord = { Enabled = false },
    KeySystem = false,
})

local FarmTab = Window:CreateTab("Autofarm", 4483362458)
local SettingsTab = Window:CreateTab("Settings", 4483362458)

FarmTab:CreateToggle({
    Name = "Auto Farm (Master)",
    CurrentValue = false,
    Flag = "AutoFarm",
    Callback = function(value: boolean)
        State.AutoFarm = value
        if not value then
            cancelTween()
            disableNoclip()
            return
        end

        task.spawn(function()
            while State.AutoFarm do
                local ok, err = pcall(runFarmCycle)
                if not ok then
                    warn("[StealAnEgg]", err)
                end
                task.wait(1.1)
            end
        end)
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Collect Eggs",
    CurrentValue = false,
    Flag = "Collect",
    Callback = function(value: boolean)
        State.Collect = value
    end,
})

FarmTab:CreateDropdown({
    Name = "Target Biome",
    Options = BiomeList,
    CurrentOption = {"Automatic"},
    MultipleOptions = false,
    Flag = "Biome",
    Callback = function(option)
        State.ChosenArea = if type(option) == "table" then option[1] else option
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Place",
    CurrentValue = false,
    Flag = "Place",
    Callback = function(value: boolean)
        State.Place = value
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Hatch",
    CurrentValue = false,
    Flag = "Hatch",
    Callback = function(value: boolean)
        State.Hatch = value
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Equip Best",
    CurrentValue = false,
    Flag = "EquipBest",
    Callback = function(value: boolean)
        State.EquipBest = value
    end,
})

SettingsTab:CreateSlider({
    Name = "Tween Speed (studs/s)",
    Range = {60, 280},
    Increment = 10,
    CurrentValue = 140,
    Flag = "TweenSpeed",
    Callback = function(value: number)
        State.TweenSpeed = value
    end,
})

SettingsTab:CreateParagraph({
    Title = "Info",
    Content = "Modern Luau rewrite with TweenService movement.\nBiomes updated to Titan Temple (7B).\nEnable Master + Collect to start farming.",
})

Rayfield:LoadConfiguration()

print("[Steal An Egg] Modern Luau autofarm loaded")
