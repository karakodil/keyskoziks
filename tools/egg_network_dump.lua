--[[
	EGG NETWORK DUMP v2
	- без сканирования Workspace
	- список RemoteEvent (Egg/Spawn/Update/Area)
	- перехват OnClientEvent + hook __namecall
	- исходники ModuleScript (Egg/DropTable), если доступны
	- панель на экране: статус и ссылка (консоль не нужна)
]]

local waitFn = (task and task.wait) or wait

local OUT = {}
local MAX_CHARS = 45000
local totalChars = 0
local function add(...)
	if totalChars >= MAX_CHARS then return end
	local parts = {}
	for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
	local line = table.concat(parts, " ")
	totalChars = totalChars + #line + 1
	OUT[#OUT + 1] = line
end

--==== панель ====
local statusLabel
local function setStatus(text)
	if statusLabel then
		pcall(function() statusLabel.Text = tostring(text) end)
	end
end

local okGui = pcall(function()
	local player = game:GetService("Players").LocalPlayer
	local parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "EggNetDump"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(320, 120)
	frame.Position = UDim2.fromOffset(10, 10)
	frame.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 20)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(120, 230, 150)
	title.Text = "EGG NETWORK DUMP"
	title.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -12, 1, -26)
	label.Position = UDim2.fromOffset(6, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans
	label.TextSize = 12
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.Text = "Запуск..."
	label.Parent = frame

	gui.Parent = parent
	statusLabel = label
end)

setStatus("Сбор данных...")

local RS = game:GetService("ReplicatedStorage")

local function deep(value, depth, seen)
	depth = depth or 0
	seen = seen or {}

	if type(value) ~= "table" then
		local text = tostring(value)
		if #text > 100 then text = text:sub(1, 100) .. "..." end
		return text
	end

	if seen[value] then return "<cycle>" end
	if depth >= 3 then return "{...}" end
	seen[value] = true

	local parts, count = {}, 0
	for key, inner in pairs(value) do
		count = count + 1
		if count > 12 then parts[#parts + 1] = "..." break end
		parts[#parts + 1] = tostring(key) .. "=" .. deep(inner, depth + 1, seen)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

add("EGG NETWORK DUMP v2")
add("Job: " .. tostring(game.JobId))
add("")

local function interesting(name)
	local lower = string.lower(tostring(name or ""))
	return lower:find("egg", 1, true) or lower:find("spawn", 1, true)
		or lower:find("update", 1, true) or lower:find("area", 1, true)
end

--==== 1. ремоуты ====
add("[REMOTES]")
local remotes = {}
for _, obj in ipairs(RS:GetDescendants()) do
	if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
		remotes[#remotes + 1] = obj
	end
end
add("всего ремоутов: " .. #remotes)

for _, remote in ipairs(remotes) do
	if interesting(remote.Name) or interesting(remote.Parent and remote.Parent.Name or "") then
		local conns = 0
		if getconnections and remote:IsA("RemoteEvent") then
			local ok, list = pcall(getconnections, remote.OnClientEvent)
			if ok and type(list) == "table" then conns = #list end
		end
		add(string.format("%s (%s) | connections=%d",
			remote:GetFullName():sub(-70), remote.ClassName, conns))
	end
end
add("")

--==== 2. пакеты ====
add("[PACKETS]")
local packetCount = 0
local MAX_PACKETS = 30
local hooked = 0

for _, remote in ipairs(remotes) do
	if remote:IsA("RemoteEvent") and hooked < 120 then
		hooked = hooked + 1
		pcall(function()
			remote.OnClientEvent:Connect(function(...)
				if packetCount >= MAX_PACKETS then return end
				packetCount = packetCount + 1

				local count = select("#", ...)
				local args = {}
				for index = 1, math.min(count, 4) do
					args[#args + 1] = deep((select(index, ...)))
				end

				add(string.format("[%d] %s | %d args | %s", packetCount,
					remote.Name, count, table.concat(args, " || "):sub(1, 700)))
				setStatus("Пакетов: " .. packetCount .. ", ждём...")
			end)
		end)
	end
end
add("подписок: " .. hooked)
add("")

--==== 3. namecall ====
add("[NAMECALL]")
local calls = 0
if hookmetamethod and newcclosure and getnamecallmethod then
	local okHook = pcall(function()
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if (method == "FireServer" or method == "InvokeServer") and calls < 25 then
				local okClass, isRemote = pcall(function()
					return self:IsA("RemoteEvent") or self:IsA("RemoteFunction")
				end)
				if okClass and isRemote then
					calls = calls + 1
					local count = select("#", ...)
					local args = {}
					for index = 1, math.min(count, 3) do
						args[#args + 1] = deep((select(index, ...)))
					end
					add(string.format("[%d] %s:%s | %s", calls, tostring(self.Name), method,
						table.concat(args, " || "):sub(1, 400)))
				end
			end
			return oldNamecall(self, ...)
		end))
	end)
	add(okHook and "hook установлен" or "hook не удался")
else
	add("hookmetamethod недоступен")
end
add("")

--==== 4. модули ====
add("[MODULES]")
local modules = {}
for _, obj in ipairs(RS:GetDescendants()) do
	if obj:IsA("ModuleScript") then modules[#modules + 1] = obj end
end
add("модулей: " .. #modules)

local function sourceOf(module)
	if decompile then
		local ok, result = pcall(decompile, module)
		if ok and type(result) == "string" and #result > 0 then return result, "decompile" end
	end
	local ok, result = pcall(function() return module.Source end)
	if ok and type(result) == "string" and #result > 0 then return result, "source" end
	if getscriptbytecode then
		local okByte, bytecode = pcall(getscriptbytecode, module)
		if okByte and type(bytecode) == "string" then
			return "<bytecode " .. #bytecode .. ">", "bytecode"
		end
	end
	return nil, "no access"
end

local shown = 0
for _, module in ipairs(modules) do
	local lower = string.lower(module:GetFullName())
	if shown < 2 and (lower:find("egg", 1, true) or lower:find("droptable", 1, true)) then
		shown = shown + 1
		local source, how = sourceOf(module)
		add("MODULE: " .. module:GetFullName() .. " | " .. how)
		if source then
			add(source:sub(1, 6000))
		else
			add("<исходник недоступен>")
		end
		add("")
	end
end

--==== ожидание ====
for step = 1, 5 do
	setStatus(string.format("Ждём пакеты: %d сек | пакетов: %d", step * 15, packetCount))
	waitFn(15)
end

add("")
add("ИТОГО: пакетов " .. packetCount .. ", вызовов " .. calls)

local text = table.concat(OUT, "\n")
if #text > MAX_CHARS then text = text:sub(1, MAX_CHARS) end

local requestFn = (syn and syn.request) or (http and http.request) or http_request or request
local link

-- paste.rs
if requestFn then
	local ok, response = pcall(requestFn, {
		Url = "https://paste.rs", Method = "POST",
		Headers = { ["Content-Type"] = "text/plain" }, Body = text,
	})
	if ok and type(response) == "table" then
		local body = response.Body or response.body
		if type(body) == "string" then link = body:match("https://paste%.rs/%S+") end
	end
end

-- tmpfiles fallback
if not link and requestFn then
	local boundary = "----EggNet" .. tostring(math.random(100000, 999999))
	local body = table.concat({
		"--" .. boundary,
		'Content-Disposition: form-data; name="file"; filename="eggnet.txt"',
		"Content-Type: text/plain", "", text, "--" .. boundary .. "--", "",
	}, "\r\n")

	local ok, response = pcall(requestFn, {
		Url = "https://tmpfiles.org/api/v1/upload", Method = "POST",
		Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
		Body = body,
	})
	if ok and type(response) == "table" then
		local bodyText = response.Body or response.body
		if type(bodyText) == "string" then
			local url = bodyText:match('"url"%s*:%s*"([^"]+)"')
			if url then link = (url:gsub("tmpfiles%.org/", "tmpfiles.org/dl/")) end
		end
	end
end

if link then
	setStatus("ГОТОВО (ссылка скопирована):\n" .. link)
	if setclipboard then pcall(setclipboard, link) end
	print("[EGG NET] " .. link)
else
	setStatus(string.format("Не удалось залить (%d симв.)\nСкопируй вручную из консоли", #text))
	warn("[EGG NET] upload failed, chars=" .. #text)
end

return text
