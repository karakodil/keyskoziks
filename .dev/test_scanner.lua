-- Компактные мок-тесты StealAnEggScanner.lua (без Roblox)
local SCRIPT = "/workspace/StealAnEggScanner.lua"

local failures, checks = 0, 0
local function check(cond, msg)
	checks = checks + 1
	if cond then
		print("  ok   " .. msg)
	else
		failures = failures + 1
		print("  FAIL " .. msg)
	end
end

--============================ моки =========================================--
local function newInstance(className, name)
	local inst = {
		ClassName = className,
		Name = name or className,
		Parent = nil,
		_children = {},
		_attributes = {},
	}
	function inst:IsA(q)
		if q == self.ClassName then return true end
		if q == "ValueBase" then
			return self.ClassName == "NumberValue" or self.ClassName == "StringValue" or self.ClassName == "IntValue"
		end
		if q == "BasePart" then return self.ClassName == "Part" end
		return false
	end
	function inst:GetChildren() return self._children end
	function inst:GetDescendants()
		local out = {}
		for _, c in ipairs(self._children) do
			out[#out + 1] = c
			for _, s in ipairs(c:GetDescendants()) do out[#out + 1] = s end
		end
		return out
	end
	function inst:FindFirstChild(name)
		for _, c in ipairs(self._children) do
			if c.Name == name then return c end
		end
		return nil
	end
	function inst:GetAttribute(k) return self._attributes[k] end
	function inst:SetAttribute(k, v) self._attributes[k] = v end
	function inst:GetAttributes() return self._attributes end
	function inst:GetPivot() return { Position = nil } end
	return inst
end

local function addChild(parent, child)
	child.Parent = parent
	parent._children[#parent._children + 1] = child
	return child
end

local ws = newInstance("Workspace", "Workspace")

-- реальные яйца
local eggsFolder = addChild(ws, newInstance("Folder", "Eggs"))
local basicEgg = addChild(eggsFolder, newInstance("Model", "Basic Egg"))
basicEgg:SetAttribute("Value", 1000)

local world = addChild(ws, newInstance("Folder", "World"))
local areas = addChild(world, newInstance("Folder", "Areas"))
local guardAreas = addChild(areas, newInstance("Folder", "GuardAreas"))
local cherry = addChild(guardAreas, newInstance("Folder", "Cherry Blossom"))
local nests = addChild(cherry, newInstance("Folder", "Nests"))
local nestModel = addChild(nests, newInstance("Model", "NestModel"))
local holyPeacock = addChild(nestModel, newInstance("Model", "HolyPeacock"))

local slotsClient = addChild(ws, newInstance("Folder", "AreaEggSlotsClient"))
local slotEgg = addChild(slotsClient, newInstance("Model", "slot1"))
slotEgg:SetAttribute("PreparedSourceName", "Workspace.NewEnchantedEggs.SpiritPanda")

local slotEgg2 = addChild(slotsClient, newInstance("Model", "slot2"))
local slotEgg2Child = addChild(slotEgg2, newInstance("Part", "Decal"))
slotEgg2Child:SetAttribute("EggSource", "Holy Peacock Egg")

local slot4 = addChild(slotsClient, newInstance("Model", "slot4"))
addChild(slot4, newInstance("Part", "Plane"))

local slot3 = addChild(slotsClient, newInstance("Model", "slot3"))
addChild(slot3, newInstance("MeshPart", "HolyPeacockMesh"))

local placed = addChild(ws, newInstance("Folder", "PlacedEggRenders"))
local placedEgg = addChild(placed, newInstance("Model", "8301557848_deadbeef"))
placedEgg:SetAttribute("PreparedSourceName", "Dread Wolf")

-- декор, который НЕ должен считаться яйцом
local waterfalls = addChild(ws, newInstance("Folder", "Waterfalls"))
local waterfallPart = addChild(waterfalls, newInstance("Part", "Part"))
addChild(waterfallPart, newInstance("ParticleEmitter", "Koi"))

local creatures = addChild(ws, newInstance("Folder", "Creatures"))
local krakenArm = addChild(creatures, newInstance("Model", "Kraken Arm 07"))
local krakenRoot = addChild(krakenArm, newInstance("Model", "Root"))
local modelsForEgg = addChild(krakenRoot, newInstance("Model", "Models for egg.053"))
addChild(modelsForEgg, newInstance("MeshPart", "Kraken"))

local convert = addChild(ws, newInstance("Model", "Convert"))
local aetheron = addChild(convert, newInstance("Model", "Aetheron"))
aetheron:SetAttribute("PreparedSourceName", "Archangel")

local plots = addChild(ws, newInstance("Folder", "Plots"))
local basePet = addChild(plots, newInstance("Model", "8687390958_10b4"))
basePet:SetAttribute("UID", "10b4")
basePet:SetAttribute("SourceName", "Cosmos Fox")

--============================ сервисы =====================================--
local JSON_TABLES = {}
local LAST_REQUEST, LAST_PAYLOAD = nil, nil
local GENV = { __EGG_SCANNER_TEST = true }

local ASSETS = {
	Directory = {
		Crowshade = { BaseConfig = { EarningRate = 4500000 } },
		SpiritPanda = { BaseConfig = { EarningRate = 90000000 } },
		["Holy Peacock"] = { BaseConfig = { EarningRate = 273000000 } },
		["Dread Wolf"] = { BaseConfig = { EarningRate = 4900000000 } },
		Koi = { BaseConfig = { EarningRate = 12000000 } },
	},
}

local AREAS = {
	Directory = {
		["Cherry Blossom"] = { DropTable = { { "Holy Peacock", 5 } } },
		Cosmic = { DropTable = {} },
	},
}

local services = {}

services.Players = {
	LocalPlayer = { Name = "Tester" },
	MaxPlayers = 7,
	GetPlayers = function() return { {}, {}, {} } end,
}

services.TeleportService = {
	TeleportToPlaceInstance = function() end,
	Teleport = function() end,
}

services.HttpService = {
	JSONDecode = function(_, body) return JSON_TABLES[body] end,
	JSONEncode = function(_, value) LAST_PAYLOAD = value; return "{}" end,
	UrlEncode = function(_, text) return text end,
}

services.CollectionService = { GetTagged = function() return {} end }
services.UserInputService = { InputBegan = { Connect = function() return {} end } }

local rs = newInstance("ReplicatedStorage", "ReplicatedStorage")
local rsData = addChild(rs, newInstance("Folder", "Data"))
addChild(rsData, newInstance("ModuleScript", "Assets"))
addChild(rsData, newInstance("ModuleScript", "Areas"))
services.ReplicatedStorage = rs

local game = {
	JobId = "job-test",
	GetService = function(_, name) return assert(services[name], "no service " .. name) end,
	IsLoaded = function() return true end,
	HttpGet = function() error("HttpGet not allowed in tests") end,
}

local function requestMock(options)
	LAST_REQUEST = options
	if options.Url:find("servers/Public", 1, true) then
		return { StatusCode = 200, Body = "page1", Headers = {} }
	end
	if options.Url:find("paste.rs", 1, true) then
		return { StatusCode = 201, Body = "https://paste.rs/TEST1\n", Headers = {} }
	end
	if options.Url:find("discord", 1, true) then
		return { StatusCode = 204, Body = "", Headers = {} }
	end
	return { StatusCode = 404, Body = "", Headers = {} }
end

JSON_TABLES.page1 = {
	data = { { id = "srv-a", maxPlayers = 7, playing = 3, ping = 20 } },
	nextPageCursor = nil,
}

local env = setmetatable({
	game = game,
	workspace = ws,
	task = { wait = function() end },
	warn = function(...) print("[warn]", ...) end,
	request = requestMock,
	getgenv = function() return GENV end,
	setclipboard = function() end,
	require = function(module)
		if module and module.Name == "Assets" then return ASSETS end
		if module and module.Name == "Areas" then return AREAS end
		return nil
	end,
	Enum = { KeyCode = { RightShift = 1 } },
	UDim2 = {},
	Color3 = { fromRGB = function() return {} end },
	Instance = { new = function() error("GUI не должен создаваться") end },
}, { __index = _G })

assert(loadfile(SCRIPT, "t", env))()
local API = GENV.__EGG_SCANNER_API
assert(API, "API not exported")

--============================ тесты =======================================--
print("== версия ==")
check(API.VERSION == "v49-zones", "версия v49-zones (получено " .. tostring(API.VERSION) .. ")")

print("== формат чисел ==")
check(API.formatNumber(25600000) == "25.6M", "25.6M -> " .. API.formatNumber(25600000))
check(API.formatNumber(273000000) == "273M", "273M -> " .. API.formatNumber(273000000))
check(API.formatNumber(5e9) == "5B", "5B -> " .. API.formatNumber(5e9))
check(API.formatNumber(999) == "999", "999 -> " .. API.formatNumber(999))

print("== яйца ==")
local eggs = API.collectEggs()
local names, byName = {}, {}
for _, egg in ipairs(eggs) do
	names[egg.name] = true
	byName[egg.name] = egg
end

check(names["Basic Egg"] == true, "яйцо по имени найдено")
check(names["HolyPeacock"] == true, "яйцо в Nests найдено")
check(names["slot1"] == true, "яйцо в AreaEggSlotsClient найдено")
check(names["8301557848_deadbeef"] == nil, "яйцо на базе (PlacedEggRenders) НЕ сканируется")
check(names["Koi"] == nil, "эмиттер Koi в водопаде НЕ считается яйцом")
check(names["Aetheron"] == nil, "станция Convert НЕ считается яйцом")
check(names["8687390958_10b4"] == nil, "питомец на базе НЕ считается яйцом")
check(names["Models for egg.053"] == nil, "лапа кракена (Models for egg) НЕ считается яйцом")
check(names["slot4"] == true, "слот без пета тоже показывается")

check(byName["slot1"] and byName["slot1"].pet == "SpiritPanda", "питомец из PreparedSourceName")
check(byName["slot1"] and byName["slot1"].income == 90000000, "доход SpiritPanda 90M")
check(byName["HolyPeacock"] and byName["HolyPeacock"].income == 273000000, "доход HolyPeacock 273M")
check(byName["HolyPeacock"] and byName["HolyPeacock"].biome == "Cherry Blossom", "биом Cherry Blossom по пути")
check(byName["slot2"] and byName["slot2"].pet == "Holy Peacock", "EggSource на ребёнке слота: " .. tostring(byName["slot2"] and byName["slot2"].pet))
check(byName["slot2"] and byName["slot2"].income == 273000000, "доход из EggSource: " .. tostring(byName["slot2"] and byName["slot2"].income))
check(byName["slot3"] and byName["slot3"].pet == "Holy Peacock", "пет из имени ребёнка (blob): " .. tostring(byName["slot3"] and byName["slot3"].pet))
check(byName["slot3"] and byName["slot3"].income == 273000000, "доход из blob-пета: " .. tostring(byName["slot3"] and byName["slot3"].income))
check(byName["slot1"] and byName["slot1"].placed == false, "яйцо в мире не помечено placed")

print("== инспектор ==")
local text = API.collectEggInspect()
check(type(text) == "string" and #text > 200, "отчёт собран (" .. tostring(#text) .. " симв.)")
check(text:find("[CONFIG]", 1, true) ~= nil, "есть CONFIG")
check(text:find("[ЯЙЦА]", 1, true) ~= nil, "есть список яиц")
check(text:find("[РЯДОМ]", 1, true) ~= nil, "есть секция РЯДОМ")
check(text:find("[PLACED EGGS]", 1, true) ~= nil, "есть PLACED EGGS")

print(string.format("\n%d проверок, %d провалов", checks, failures))
if failures > 0 then os.exit(1) end
print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ")
