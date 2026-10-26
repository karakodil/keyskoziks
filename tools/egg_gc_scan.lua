--[[
	EGG GC SCAN — ищет в памяти клиента таблицу слотов яиц.
	Запуск одной строкой, результат — ссылка на paste.rs.

	Идея: UID слотов лежат в workspace.AreaEggSlotsClient (имена вроде
	"9df1b2fcd6ff499189982714eb2294b0"). Если клиент держит их данные
	в Lua-таблице, мы найдём её по совпадению ключей и вытащим пета.
]]

local OUT = {}
local function add(line)
	OUT[#OUT + 1] = tostring(line)
end

add("EGG GC SCAN")
add("Job: " .. tostring(game.JobId))
add("")

local slots = game:GetService("Workspace"):FindFirstChild("AreaEggSlotsClient")
if not slots then
	add("нет AreaEggSlotsClient")
else
	local uids, slotList = {}, {}
	for _, slot in ipairs(slots:GetChildren()) do
		uids[slot.Name] = true
		slotList[#slotList + 1] = slot.Name
	end

	add("слотов: " .. #slotList)

	if not getgc then
		add("getgc недоступен в этом исполнителе")
	else
		local ok, gc = pcall(getgc, true)
		if not ok or type(gc) ~= "table" then
			add("getgc(true) вернул не таблицу")
		else
			add("gc-объектов: " .. #gc)

			local best, bestScore = nil, 0

			for _, obj in ipairs(gc) do
				if type(obj) == "table" then
					local score = 0
					local okPairs = pcall(function()
						for key in pairs(obj) do
							if type(key) == "string" and uids[key] then
								score = score + 1
								if score >= 5 then
									break
								end
							end
						end
					end)

					if okPairs and score > bestScore then
						best, bestScore = obj, score
					end
				end
			end

			add("лучшая таблица: совпадений " .. bestScore)

			if best then
				local printed = 0
				for key, value in pairs(best) do
					if printed >= 25 then
						break
					end
					printed = printed + 1

					local summary
					if type(value) == "table" then
						local parts = {}
						local count = 0
						for k, v in pairs(value) do
							count = count + 1
							if count <= 12 then
								if type(v) == "table" then
									local sub = {}
									local subCount = 0
									for k2, v2 in pairs(v) do
										subCount = subCount + 1
										if subCount <= 8 then
											sub[#sub + 1] = tostring(k2) .. "=" .. tostring(v2)
										end
									end
									parts[#parts + 1] = tostring(k) .. "={"
										.. table.concat(sub, ", ") .. "}"
								else
									parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
								end
							end
						end
						summary = "{" .. table.concat(parts, ", ") .. "}"
					else
						summary = tostring(value)
					end

					add(tostring(key) .. " => " .. summary:sub(1, 700))
				end
			end
		end
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
		if type(body) == "string" then
			link = body:match("https://paste%.rs/%S+")
		end
	end
end

if link then
	print("[EGG GC] " .. link)
	if setclipboard then
		pcall(setclipboard, link)
	end
else
	warn("[EGG GC] не удалось залить. Длина: " .. #text)
end

return text
