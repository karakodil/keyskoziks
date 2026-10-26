--[[
	EGG REMOTE SPY - ловит пакеты, которые сервер присылает клиенту
	(спавн яиц, данные слотов). Работает 90 секунд, потом заливает лог.
]]

local OUT = {}
local seen = 0
local MAX = 40

local function add(line)
	if #OUT < 2000 then
		OUT[#OUT + 1] = tostring(line)
	end
end

local function describe(value, depth)
	depth = depth or 0
	if type(value) ~= "table" then
		return tostring(value)
	end
	if depth > 1 then
		return "{...}"
	end

	local parts, count = {}, 0
	for key, inner in pairs(value) do
		count = count + 1
		if count > 12 then
			parts[#parts + 1] = "..."
			break
		end
		parts[#parts + 1] = tostring(key) .. "=" .. describe(inner, depth + 1)
	end

	return "{" .. table.concat(parts, ", ") .. "}"
end

add("EGG REMOTE SPY")
add("Job: " .. tostring(game.JobId))
add("")

for _, remote in ipairs(game:GetDescendants()) do
	if remote:IsA("RemoteEvent") then
		local ok = pcall(function()
			remote.OnClientEvent:Connect(function(...)
				if seen >= MAX then
					return
				end
				seen = seen + 1

				local count = select("#", ...)
				local parts = {}
				for index = 1, math.min(count, 4) do
					parts[#parts + 1] = describe((select(index, ...)), 0)
				end

				add(string.format("[%d] %s | args=%d | %s",
					seen, remote:GetFullName():sub(-70), count,
					table.concat(parts, " || "):sub(1, 900)))
			end)
		end)
	end
end

add("подключились к RemoteEvent, ждём пакеты 90 секунд...")

task.wait(90)

add("")
add("всего пакетов: " .. seen)

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
	print("[EGG SPY] " .. link)
	if setclipboard then pcall(setclipboard, link) end
else
	warn("[EGG SPY] не удалось залить. Длина: " .. #text)
end

return text
