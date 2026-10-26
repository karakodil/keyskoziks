--[[
	EGG GC SCAN v2 - ищет в памяти клиента таблицу слотов яиц вместе с именами петов.
	Запуск одной строкой, результат - ссылка на paste.rs.
]]

local OUT = {}
local function add(line) OUT[#OUT + 1] = tostring(line) end

local function normalize(text)
	return (string.lower(tostring(text)):gsub("[^%w]", ""))
end

add("EGG GC SCAN v2")
add("Job: " .. tostring(game.JobId))
add("")

local slots = game:GetService("Workspace"):FindFirstChild("AreaEggSlotsClient")

local uids, slotCount = {}, 0
if slots then
	for _, slot in ipairs(slots:GetChildren()) do
		uids[slot.Name] = true
		slotCount = slotCount + 1
	end
end
add("слотов: " .. slotCount)

local petKeys = {}
local replicated = game:GetService("ReplicatedStorage")
local okAssets, assets = pcall(function()
	local data = replicated:FindFirstChild("Data")
	local module = data and data:FindFirstChild("Assets")
	return module and require(module) or nil
end)
if okAssets and type(assets) == "table" and type(assets.Directory) == "table" then
	for key in pairs(assets.Directory) do
		petKeys[normalize(key)] = tostring(key)
	end
end
local petCount = 0
for _ in pairs(petKeys) do petCount = petCount + 1 end
add("петов в Data.Assets: " .. petCount)

if not getgc then
	add("getgc недоступен")
else
	local okGc, gc = pcall(getgc, true)
	if not okGc or type(gc) ~= "table" then
		add("getgc(true) не вернул таблицу")
	else
		add("gc-объектов: " .. #gc)
		add("")

		local best, bestScore, bestUidHits = nil, 0, 0
		local bestPetOnly, bestPetScore = nil, 0

		for _, obj in ipairs(gc) do
			if type(obj) == "table" then
				local uidHits, petHits = 0, 0
				pcall(function()
					for key, value in pairs(obj) do
						if type(key) == "string" and uids[key] then
							uidHits = uidHits + 1
						end
						if type(value) == "string" then
							if petKeys[normalize(value)] then petHits = petHits + 1 end
						elseif type(value) == "table" then
							local inner = 0
							for _, innerValue in pairs(value) do
								inner = inner + 1
								if inner > 40 then break end
								if type(innerValue) == "string" and petKeys[normalize(innerValue)] then
									petHits = petHits + 1
								end
							end
						end
					end
				end)

				if uidHits > 0 and petHits > 0 and (uidHits * 2 + petHits) > bestScore then
					best, bestScore, bestUidHits = obj, uidHits * 2 + petHits, uidHits
				end
				if petHits > bestPetScore then
					bestPetOnly, bestPetScore = obj, petHits
				end
			end
		end

		add("таблица с UID+петом: uid=" .. bestUidHits .. " score=" .. bestScore)
		add("таблица только с петами: score=" .. bestPetScore)
		add("")

		local function summary(v, depth)
			if type(v) ~= "table" then return tostring(v) end
			local parts, count = {}, 0
			for k, v2 in pairs(v) do
				count = count + 1
				if count > 14 then break end
				if type(v2) == "table" and depth < 1 then
					parts[#parts + 1] = tostring(k) .. "=" .. summary(v2, depth + 1)
				else
					parts[#parts + 1] = tostring(k) .. "=" .. tostring(v2)
				end
			end
			return "{" .. table.concat(parts, ", ") .. "}"
		end

		local function dumpTable(tbl, title, limit)
			add("=== " .. title .. " ===")
			local printed = 0
			for key, value in pairs(tbl) do
				if printed >= limit then break end
				printed = printed + 1
				add(tostring(key) .. " => " .. summary(value, 0):sub(1, 800))
			end
			add("")
		end

		if best then dumpTable(best, "UID + пет", 25) end
		if bestPetOnly and bestPetOnly ~= best then dumpTable(bestPetOnly, "только петы", 25) end
	end
end

local text = table.concat(OUT, "\n")

local requestFn = (syn and syn.request) or (http and http.request) or http_request or request
local link

if requestFn then
	local ok, response = pcall(requestFn, {
		Url = "https://paste.rs",
		Method = "POST",
		Headers = { ["Content-Type"] = "text/plain" },
		Body = text,
	})
	if ok and type(response) == "table" then
		local body = response.Body or response.body
		if type(body) == "string" then link = body:match("https://paste%.rs/%S+") end
	end
end

if link then
	print("[EGG GC] " .. link)
	if setclipboard then pcall(setclipboard, link) end
else
	warn("[EGG GC] не удалось залить. Длина: " .. #text)
end

return text
