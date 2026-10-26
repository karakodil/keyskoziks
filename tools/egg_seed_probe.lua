--[[
	EGG SEED PROBE - проверяет, можно ли вычислить пета из AssetColorSeed.
	Запуск одной строкой, результат - ссылка на paste.rs.
]]

local OUT = {}
local function add(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end OUT[#OUT + 1] = table.concat(t, " ") end

add("EGG SEED PROBE")
add("Job: " .. tostring(game.JobId))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local function req(name)
	local ok, result = pcall(function()
		local data = ReplicatedStorage:FindFirstChild("Data")
		local module = data and data:FindFirstChild(name)
		return module and require(module) or nil
	end)
	if ok then return result end
	return nil
end

local areas = req("Areas")
add("Areas: " .. tostring(areas ~= nil))

-- ищем в GC таблицу uid -> запись
local slots = Workspace:FindFirstChild("AreaEggSlotsClient")
local uids = {}
if slots then
	for _, slot in ipairs(slots:GetChildren()) do uids[slot.Name] = true end
end

local registry
if getgc then
	local ok, gc = pcall(getgc, true)
	if ok and type(gc) == "table" then
		for _, obj in ipairs(gc) do
			if type(obj) == "table" then
				local hits = 0
				pcall(function()
					for k, v in pairs(obj) do
						if type(k) == "string" and uids[k] and type(v) == "table" and v.AssetColorSeed then
							hits = hits + 1
						end
					end
				end)
				if hits >= 5 then registry = obj break end
			end
		end
	end
end

add("реестр слотов: " .. tostring(registry ~= nil))

local function zoneOf(x)
	local zones = {
		{ "Forest", 553.42, 646.49 }, { "Lake", 653.01, 793.51 },
		{ "Desert", 796.48, 1005.04 }, { "Jungle", 1008.56, 1240.12 },
		{ "Snow", 1244.13, 1564.18 }, { "Volcano", 1568.33, 1949.58 },
		{ "Abyss Ocean", 1953.30, 2378.73 }, { "Prehistoric", 2382.87, 2884.09 },
		{ "Cosmic", 2888.03, 3523.51 }, { "Cherry Blossom", 3527.67, 4263.53 },
		{ "Titan Temple", 4268.09, 5123.06 }, { "Enchanted Forest", 5127.00, 7600.00 },
	}
	for _, z in ipairs(zones) do
		if x >= z[2] and x <= z[3] then return z[1] end
	end
	return nil
end

if registry and areas and type(areas.Directory) == "table" then
	local printed = 0
	for uid, record in pairs(registry) do
		if printed >= 6 then break end
		printed = printed + 1

		local frame = record.BoundsCFrame
		local x = type(frame) == "userdata" and frame.Position.X or tonumber(tostring(frame):match("^(%-?[%d%.]+)"))
		local zone = x and zoneOf(x) or nil
		local area = zone and areas.Directory[zone] or nil

		add("")
		add("uid=" .. tostring(uid):sub(1, 12) .. " | x=" .. tostring(x) .. " | zone=" .. tostring(zone))
		add("seed=" .. tostring(record.AssetColorSeed) .. " | scale=" .. tostring(record.AssetScale) .. " | mut=" .. tostring(record.BaseMutation))

		if type(area) == "table" then
			local keys = {}
			for k in pairs(area) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			add("area keys: " .. table.concat(keys, ", "):sub(1, 300))

			for _, fn in ipairs({ "Roll", "GetAsset", "GetPet", "RollPet", "GetEgg", "Pick" }) do
				if type(area[fn]) == "function" then
					local okCall, result = pcall(area[fn], record.AssetColorSeed)
					add(string.format("  %s(seed) -> %s (%s)", fn, tostring(result):sub(1, 80), tostring(okCall)))
				end
			end
		else
			add("area config не найден")
		end
	end
end

local text = table.concat(OUT, "\n")
local requestFn = (syn and syn.request) or (http and http.request) or http_request or request
local link
if requestFn then
	local ok, response = pcall(requestFn, { Url = "https://paste.rs", Method = "POST", Headers = { ["Content-Type"] = "text/plain" }, Body = text })
	if ok and type(response) == "table" then
		local body = response.Body or response.body
		if type(body) == "string" then link = body:match("https://paste%.rs/%S+") end
	end
end
if link then
	print("[EGG SEED] " .. link)
	if setclipboard then pcall(setclipboard, link) end
else
	warn("[EGG SEED] не удалось залить. Длина: " .. #text)
end
return text
