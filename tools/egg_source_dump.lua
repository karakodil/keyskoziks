--[[
	EGG SOURCE DUMP — выгружает исходники скриптов, связанных с яйцами/слотами.
	Запуск одной строкой (см. ниже), результат — ссылка на paste.rs.

	Нужен, чтобы понять, откуда клиент берёт питомца для каждого слота
	AreaEggSlotsClient (у большинства слотов нет PreparedSourceName).
]]

local OUT = {}
local function add(line)
	OUT[#OUT + 1] = tostring(line)
end

add("EGG SOURCE DUMP")
add("Job: " .. tostring(game.JobId))
add("")

-- 1) собираем подозрительные скрипты
local targets = {}
local seen = {}

local function addTarget(obj, reason)
	if obj and not seen[obj] and obj:IsA("LuaSourceContainer") then
		seen[obj] = true
		targets[#targets + 1] = { script = obj, reason = reason }
	end
end

for _, obj in ipairs(game:GetDescendants()) do
	if obj:IsA("LuaSourceContainer") then
		local path = string.lower(obj:GetFullName())
		if string.find(path, "egg", 1, true)
			or string.find(path, "slot", 1, true)
			or string.find(path, "hatch", 1, true)
			or string.find(path, "incubat", 1, true) then
			addTarget(obj, "name")
		end
	end
end

-- LocalScript'ы игрока (там обычно и живёт клиентская логика)
local player = game:GetService("Players").LocalPlayer
local playerScripts = player and player:FindFirstChild("PlayerScripts")
if playerScripts then
	local count = 0
	for _, obj in ipairs(playerScripts:GetDescendants()) do
		if obj:IsA("LocalScript") then
			count = count + 1
			if count <= 40 then
				addTarget(obj, "player")
			end
		end
	end
end

add("найдено скриптов: " .. #targets)
add("")

-- 2) выгружаем исходники
local function getSource(object)
	if decompile then
		local ok, result = pcall(decompile, object)
		if ok and type(result) == "string" and #result > 0 then
			return result, "decompile"
		end
	end

	local ok, result = pcall(function()
		return object.Source
	end)
	if ok and type(result) == "string" and #result > 0 then
		return result, "source"
	end

	if getscriptbytecode then
		local okByte, bytecode = pcall(getscriptbytecode, object)
		if okByte and type(bytecode) == "string" then
			return "<только байткод, " .. #bytecode .. " байт>", "bytecode"
		end
	end

	return nil, "нет доступа"
end

for _, entry in ipairs(targets) do
	local source, how = getSource(entry.script)

	add("==================================================")
	add("SCRIPT: " .. entry.script:GetFullName())
	add("CLASS: " .. entry.script.ClassName .. " | " .. how)

	if source then
		add(source:sub(1, 60000))
	else
		add("<исходник недоступен>")
	end
	add("")
end

local text = table.concat(OUT, "\n")
if #text > 180000 then
	text = text:sub(1, 180000) .. "\n... (обрезано)"
end

-- 3) заливаем на paste.rs
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
		if type(body) == "string" then
			link = body:match("https://paste%.rs/%S+")
		end
	end
end

if link then
	print("[EGG DUMP] " .. link)
	if setclipboard then
		pcall(setclipboard, link)
	end
else
	warn("[EGG DUMP] не удалось залить, длина текста: " .. #text)
end

return text
