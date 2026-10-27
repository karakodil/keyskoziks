--[[
	EGG NETWORK DUMP - без сканирования Workspace.
	1) список RemoteEvent/RemoteFunction в ReplicatedStorage (Egg/Spawn/Update/Area)
	2) перехват OnClientEvent (что сервер шлёт клиенту при спавне яиц)
	3) hook __namecall (FireServer/InvokeServer) — что клиент шлёт серверу
	4) исходники ModuleScript с Egg/DropTable в имени
	Работает 75 секунд, затем заливает отчёт на paste.rs.
]]

local OUT = {}
local function add(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = tostring((select(index, ...)))
	end
	OUT[#OUT + 1] = table.concat(parts, " ")
end

local RS = game:GetService("ReplicatedStorage")

local function deep(value, depth, seen)
	depth = depth or 0
	seen = seen or {}

	local kind = type(value)
	if kind ~= "table" then
		local text = tostring(value)
		if #text > 140 then text = text:sub(1, 140) .. "..." end
		return text
	end

	if seen[value] then return "<cycle>" end
	if depth >= 3 then return "{...}" end
	seen[value] = true

	local parts, count = {}, 0
	for key, inner in pairs(value) do
		count = count + 1
		if count > 18 then
			parts[#parts + 1] = "..."
			break
		end
		parts[#parts + 1] = tostring(key) .. "=" .. deep(inner, depth + 1, seen)
	end

	return "{" .. table.concat(parts, ", ") .. "}"
end

add("EGG NETWORK DUMP")
add("Job: " .. tostring(game.JobId))
add("")

local function interesting(name)
	local lower = string.lower(tostring(name or ""))
	return lower:find("egg", 1, true) or lower:find("spawn", 1, true)
		or lower:find("update", 1, true) or lower:find("area", 1, true)
end

-- 1) список ремоутов
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
		add(string.format("%s (%s) | connections=%d", remote:GetFullName():sub(-80), remote.ClassName, conns))
	end
end
add("")

-- 2) перехват входящих пакетов
add("[PACKETS]")
local packetCount = 0
local MAX_PACKETS = 60
local hookedRemotes = 0

for _, remote in ipairs(remotes) do
	if remote:IsA("RemoteEvent") and hookedRemotes < 120 then
		hookedRemotes = hookedRemotes + 1
		pcall(function()
			remote.OnClientEvent:Connect(function(...)
				if packetCount >= MAX_PACKETS then return end
				packetCount = packetCount + 1

				local count = select("#", ...)
				local args = {}
				for index = 1, math.min(count, 5) do
					args[#args + 1] = deep((select(index, ...)))
				end

				add(string.format("[%d] %s | %d args\n    %s", packetCount,
					remote:GetFullName():sub(-70), count,
					table.concat(args, "\n    "):sub(1, 1500)))
			end)
		end)
	end
end
add("подписались на " .. hookedRemotes .. " RemoteEvent")
add("")

-- 3) hook namecall (что клиент шлёт серверу)
add("[NAMECALL]")
local calls = 0
if hookmetamethod and newcclosure and getnamecallmethod then
	local okHook = pcall(function()
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if (method == "FireServer" or method == "InvokeServer") and calls < 40 then
				local okClass, isRemote = pcall(function()
					return self:IsA("RemoteEvent") or self:IsA("RemoteFunction")
				end)
				if okClass and isRemote then
					calls = calls + 1
					local count = select("#", ...)
					local args = {}
					for index = 1, math.min(count, 4) do
						args[#args + 1] = deep((select(index, ...)))
					end
					add(string.format("[%d] %s:%s | %s", calls, tostring(self.Name),
						method, table.concat(args, " || "):sub(1, 600)))
				end
			end
			return oldNamecall(self, ...)
		end))
	end)
	add(okHook and "hook __namecall установлен" or "hook __namecall не удался")
else
	add("hookmetamethod недоступен")
end
add("")

-- 4) модули с Egg/DropTable
add("[MODULES]")
local modules = {}
for _, obj in ipairs(RS:GetDescendants()) do
	if obj:IsA("ModuleScript") then
		modules[#modules + 1] = obj
	end
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
			return "<bytecode " .. #bytecode .. " bytes>", "bytecode"
		end
	end
	return nil, "no access"
end

local shown = 0
for _, module in ipairs(modules) do
	local lower = string.lower(module:GetFullName())
	if (lower:find("egg", 1, true) or lower:find("droptable", 1, true) or lower:find("spawn", 1, true))
		and shown < 5 then
		shown = shown + 1
		local source, how = sourceOf(module)
		add("==================================================")
		add("MODULE: " .. module:GetFullName() .. " | " .. how)
		if source then
			add(source:sub(1, 12000))
		else
			add("<исходник недоступен>")
		end
	end
end
add("")
add("итого пакетов: " .. packetCount .. " | клиентских вызовов: " .. calls)

add("ждём 75 секунд...")
task.wait(75)

add("")
add("ПОСЛЕ ОЖИДАНИЯ: пакетов " .. packetCount .. ", вызовов " .. calls)

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
	print("[EGG NET] " .. link)
	if setclipboard then pcall(setclipboard, link) end
else
	warn("[EGG NET] не удалось залить. Длина: " .. #text)
end

return text
