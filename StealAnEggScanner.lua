--[[
================================================================================
    Steal An Egg — сканер яиц + сервер-хоппер
    PlaceId: 107778070777162
    Исполнители: Synapse X / Solara / Delta / Wave / Fluxus и т.п.
================================================================================

    ЧТО ДЕЛАЕТ:
      1. Ждёт загрузку карты и сканирует сервер: ищет объекты с тегом "Egg",
         с "Egg" в имени, либо с атрибутами Value / Income.
      2. Определяет самое дорогое яйцо (по Income, Value или максимуму из них).
      3. Если порог (по умолчанию 5B) пройден — отправляет данные в Discord
         вебхук: JobId, имя яйца, доход/цену, число игроков и прямую ссылку.
      4. Телепортируется (хоп) на другой публичный сервер, где есть свободные
         места, и повторяет всё заново.

    ЗАПУСК С ТЕЛЕФОНА (проще всего):
      Вставь в исполнитель содержимое loader.lua (~30 строк) — он скачает
      полный скрипт с GitHub (два зеркала) и покажет ошибку прямо на экране,
      если что-то не загрузилось.

    ЧТО БУДЕТ НА ЭКРАНЕ:
      Слева сверху появляется панель «EGG SCANNER v3-mobile» с логом и кнопками:
        Скан — разовый скан текущего сервера;
        Хоп  — разовый хоп на другой сервер;
        Дамп — показать, что реально есть у яиц (атрибуты/значения);
        Стоп — остановить скрипт.
      Панель перетаскивается за заголовок. RightShift тоже останавливает.

    ЕСЛИ ПОСЛЕ ИНЖЕКТА «НИЧЕГО»:
      - Полностью закрой Roblox и запусти снова: старые версии оставляли в
        памяти флаг __EGG_SCANNER_RUNNING, из-за которого скрипт молча
        завершался (в этой версии блокировка убрана).
      - Панель создаётся ДО основного цикла, поэтому если её нет вообще —
        скрипт не выполнился (неверный/обрезанный код, блокировка raw-ссылки).

    ЕСЛИ ЯЙЦА НЕ НАХОДЯТСЯ:
      - В этой игре цены могут лежать в других атрибутах — допиши их имена
        в INCOME_ATTRS / VALUE_ATTRS (блок "СКАНИРОВАНИЕ").
      - Что вообще есть на карте, можно глянуть в консоли исполнителя:
          for _, o in ipairs(workspace:GetDescendants()) do
              local i, v = o:GetAttribute("Income"), o:GetAttribute("Value")
              if i or v then print(o:GetFullName(), i, v) end
          end
      - Яйца вне workspace (в ReplicatedStorage) — включи SCAN_REPLICATED = true.
      - Если карта грузится долго — увеличь SCAN_INTERVAL (сейчас 3 сек).

    ВАЖНО:
      - Скрипт клиентский. TeleportService на клиенте иногда блокируется
        игрой/исполнителем, поэтому телепорт обёрнут в pcall и имеет
        резервный вариант Teleport(placeId).
      - Автоматизация, сервер-хопинг и сторонние исполнители нарушают
        правила Roblox. Используй на свой риск.
================================================================================
]]

--============================== НАСТРОЙКИ ==================================--

local CONFIG = {
	PLACE_ID          = 107778070777162,

	-- Ссылка на вебхук Discord: Server Settings -> Integrations -> Webhooks
	WEBHOOK_URL       = "https://discord.com/api/webhooks/1564046515595649105/IRllOp8HwD5O-nNjDV51kII-XkQKkoQhRp97l5v2g40ZRtsSk7cDzGfkqV7r2jav7PTa",

	THRESHOLD         = 1e6,         -- порог дохода, /сек: 1e6 = 1M
	                                 -- яйца в треке дают ~0.3M-3M;
	                                 -- строже: 1e9 (1B) или 5e9 (5B)
	THRESHOLD_MODE    = "max",       -- "max" | "income" | "value"
	                                 --   max = максимум из Income и Value

	SCAN_INTERVAL     = 3,           -- пауза перед сканом (карта успевает прогрузиться)
	IDLE_WAIT_MIN     = 5,           -- пауза, если топ-яйца нет
	IDLE_WAIT_MAX     = 10,
	WEBHOOK_MIN_GAP   = 2,           -- wait(2) после вебхука перед хопом
	WEBHOOK_COOLDOWN  = 300,         -- не спамить одним и тем же яйцом с того же JobId, сек

	SERVERS_PER_PAGE  = 100,         -- лимит API
	MAX_SERVER_PAGES  = 3,           -- сколько страниц серверов листать
	MIN_FREE_SLOTS    = 1,           -- минимум свободных мест на целевом сервере
	TELEPORT_COOLDOWN = 10,          -- антифлуд телепортов, сек
	FALLBACK_TELEPORT = false,       -- Teleport() по PlaceId может вернуть на тот же сервер

	MAX_SCAN_OBJECTS  = 200000,      -- предохранитель от зависания на огромных картах
	SCAN_REPLICATED   = false,       -- сканировать ещё и ReplicatedStorage
	IGNORE_EVENT_WORLDS = true,      -- пропускать *Dimension (Halloween и т.п.)
	STREAM_AREAS      = true,        -- просить клиент догрузить все зоны трека
	SHOW_GUI          = true,        -- небольшое окно со статусом
	AUTO_RELOAD       = true,        -- queue_on_teleport: перезапуск после телепорта
	SCRIPT_URL        = "https://raw.githubusercontent.com/karakodil/keyskoziks/egg-scanner/StealAnEggScanner.lua",
	                                 -- можно заменить на свою raw-ссылку

	VERBOSE           = true,
}

--=========================== СЛУЖБЫ И ХЕЛПЕРЫ ===============================--

local PREFIX  = "[EggScanner]"
local VERSION = "v26-slottext"

local Players           = game:GetService("Players")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	-- Не ждём вечно: если игрок ещё не прогрузился, продолжаем
	local deadline = os.clock() + 15
	repeat
		task.wait(0.1)
		LocalPlayer = Players.LocalPlayer
	until LocalPlayer or os.clock() > deadline
end

-- Флаг запуска. ВАЖНО: здесь больше НЕТ `return`.
-- Раньше при уже установленном флаге скрипт молча завершался — и после
-- одного «мёртвого» запуска (например, недокопированного кода) все
-- следующие инъекции ничего не делали.
if getgenv then
	getgenv().__EGG_SCANNER_RUNNING = true
end

-- Экранный лог (на телефоне консоль недоступна), назначается в блоке GUI
local pushLog = nil
local addLog      -- назначается в блоке GUI
local setStatus   -- назначается в блоке GUI
local requireModule -- определяется в блоке разведки

-- Перехватываем warn, чтобы предупреждения тоже были видны на экране
local rawWarn = warn
local function warn(...)
	if rawWarn then
		rawWarn(...)
	end
	if pushLog then
		local parts = {}
		for index = 1, select("#", ...) do
			parts[index] = tostring((select(index, ...)))
		end
		pushLog("! " .. table.concat(parts, " "))
	end
end

local function log(...)
	if CONFIG.VERBOSE then
		print(PREFIX, ...)
	end
	if pushLog then
		local parts = {}
		for index = 1, select("#", ...) do
			parts[index] = tostring((select(index, ...)))
		end
		pushLog(table.concat(parts, " "))
	end
end

--============================ HTTP (request) ================================--

-- В разных исполнителях функция называется по-разному
local function getRequestFunction()
	return (syn and syn.request) or (http and http.request) or http_request or request
end

-- Приводим ответ к единому виду: status, body, headers
local function normalizeResponse(response)
	if type(response) ~= "table" then
		return nil
	end
	local status  = response.StatusCode or response.status_code or response.status
	local body    = response.Body or response.body
	local headers = response.Headers or response.headers or {}
	if not status and response.Success == true then
		status = 200
	end
	return status, body, headers
end

local function decodeJson(body)
	if type(body) ~= "string" or #body == 0 then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

-- GET JSON: сначала request/syn.request, при 401/403 — game:HttpGet
local function fetchJson(url)
	local requestFn = getRequestFunction()
	if requestFn then
		local ok, response = pcall(requestFn, {
			Url = url,
			Method = "GET",
			Headers = { Accept = "application/json" },
		})
		if ok then
			local status, body, headers = normalizeResponse(response)
			if status == 200 then
				local data = decodeJson(body)
				if data then
					return data
				end
				return nil, "не удалось распарсить JSON"
			elseif status == 429 then
				local retryAfter = tonumber(headers["retry-after"] or headers["Retry-After"]) or 5
				return nil, "HTTP 429 (rate limit)", retryAfter
			elseif status and status ~= 401 and status ~= 403 then
				return nil, "HTTP " .. tostring(status)
			end
			-- 401/403 — пробуем game:HttpGet ниже (в Synapse он идёт с куки)
		end
	end

	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok then
		local data = decodeJson(body)
		if data then
			return data
		end
	end

	return nil, "не удалось получить ответ API"
end

--=========================== СПИСОК СЕРВЕРОВ ================================--

--[[
	GET https://games.roblox.com/v1/games/<placeId>/servers/Public?limit=100
	Ответ:
	{
	  previousPageCursor = nil,
	  nextPageCursor     = "eyJzdGFydEluZGV4...",
	  data = {
	    { id = "<JobId>", maxPlayers = 7, playing = 6, ping = 27, fps = 59.9 },
	    ...
	  }
	}
	Поле id — это и есть JobId инстанса.
]]
local function getServers(maxPages)
	maxPages = maxPages or CONFIG.MAX_SERVER_PAGES

	local servers, seen = {}, {}
	local cursor, pages = nil, 0

	repeat
		local url = string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?limit=%d&sortOrder=Asc",
			CONFIG.PLACE_ID,
			CONFIG.SERVERS_PER_PAGE
		)
		if cursor then
			url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
		end

		local data, err, retryAfter = fetchJson(url)
		if not data then
			log("getServers(): " .. tostring(err))
			if retryAfter then
				task.wait(retryAfter)
			end
			break
		end

		local batch = data.data
		if type(batch) ~= "table" or #batch == 0 then
			break
		end

		for _, server in ipairs(batch) do
			if type(server) == "table" and type(server.id) == "string" and not seen[server.id] then
				seen[server.id] = true
				servers[#servers + 1] = server
			end
		end

		cursor = data.nextPageCursor
		pages = pages + 1
	until not cursor or pages >= maxPages

	return servers
end

-- Список подходящих серверов в случайном порядке
local function buildCandidates(servers)
	local candidates = {}

	for _, server in ipairs(servers) do
		local maxPlayers = tonumber(server.maxPlayers) or 0
		local playing    = tonumber(server.playing) or 0
		local free       = maxPlayers - playing

		if server.id ~= game.JobId and free >= CONFIG.MIN_FREE_SLOTS then
			candidates[#candidates + 1] = {
				id   = server.id,
				free = free,
				ping = tonumber(server.ping) or 999,
			}
		end
	end

	-- перемешиваем
	for index = #candidates, 2, -1 do
		local swap = math.random(1, index)
		candidates[index], candidates[swap] = candidates[swap], candidates[index]
	end

	return candidates
end

-- Случайный сервер, где есть свободные места и это не наш текущий сервер
local function pickServer(servers)
	local candidates = buildCandidates(servers)
	if #candidates == 0 then
		return nil
	end
	return candidates[1]
end

-- Автоперезапуск скрипта после телепорта (нужен CONFIG.SCRIPT_URL)
local function queueReload()
	if not CONFIG.AUTO_RELOAD or CONFIG.SCRIPT_URL == "" then
		return
	end

	local queueFn = queue_on_teleport
		or (syn and syn.queue_on_teleport)
		or (fluxus and fluxus.queue_on_teleport)

	if type(queueFn) ~= "function" then
		log("queue_on_teleport недоступен — после хопа запусти скрипт вручную")
		return
	end

	local code = string.format('loadstring(game:HttpGet("%s"))()', CONFIG.SCRIPT_URL)
	local ok, err = pcall(queueFn, code)
	if not ok then
		warn(PREFIX, "queue_on_teleport: " .. tostring(err))
	end
end

--============================== СЕРВЕР-ХОП ==================================--

local lastTeleportAt = 0

local function hopServer(reason)
	-- антифлуд телепортов
	local elapsed = os.clock() - lastTeleportAt
	if elapsed < CONFIG.TELEPORT_COOLDOWN then
		task.wait(CONFIG.TELEPORT_COOLDOWN - elapsed)
	end
	lastTeleportAt = os.clock()

	local jobBefore = game.JobId

	log(string.format("Хоп (%s): текущий сервер %s",
		tostring(reason), tostring(jobBefore):sub(1, 8)))
	local servers = getServers()
	local candidates = buildCandidates(servers)

	log(string.format("Серверов в API: %d, подходящих: %d", #servers, #candidates))

	if #candidates == 0 then
		-- серверы со свободными местами закончились — берём любые, кроме своего
		log("Свободных нет — беру любые серверы, кроме своего")

		for _, server in ipairs(servers) do
			if server.id ~= game.JobId then
				candidates[#candidates + 1] = {
					id = server.id,
					free = (tonumber(server.maxPlayers) or 0) - (tonumber(server.playing) or 0),
					ping = tonumber(server.ping) or 999,
				}
			end
		end

		for index = #candidates, 2, -1 do
			local swap = math.random(1, index)
			candidates[index], candidates[swap] = candidates[swap], candidates[index]
		end
	end

	if #candidates == 0 then
		if not CONFIG.FALLBACK_TELEPORT then
			log("Серверов нет вообще — остаёмся (fallback выключен)")
			return false
		end
		log("Серверов нет вообще — Teleport()")
		local ok = pcall(function()
			TeleportService:Teleport(CONFIG.PLACE_ID, LocalPlayer)
		end)
		return ok
	end

	queueReload()

	-- Пробуем до 3 разных JobId: если один не сработал, не возвращаемся на свой
	for index = 1, math.min(3, #candidates) do
		local target = candidates[index]
		log(string.format("Попытка %d: %s (свободно %d)",
			index, tostring(target.id):sub(1, 8), target.free))

		local ok, err = pcall(function()
			TeleportService:TeleportToPlaceInstance(CONFIG.PLACE_ID, target.id, LocalPlayer)
		end)

		if not ok then
			-- часть исполнителей не принимает третий аргумент
			ok, err = pcall(function()
				TeleportService:TeleportToPlaceInstance(CONFIG.PLACE_ID, target.id)
			end)
		end

		if ok then
			-- если телепорт реально начался, клиент перезайдёт и код ниже не выполнится
			task.wait(4)
			if game.JobId ~= jobBefore then
				return true
			end
			log("телепорт не состоялся (JobId тот же)")
		else
			log("ошибка: " .. tostring(err):sub(1, 70))
		end

		task.wait(2)
	end

	if not CONFIG.FALLBACK_TELEPORT then
		log("Все JobId не сработали — остаёмся (fallback выключен)")
		return false
	end

	log("Все JobId не сработали — Teleport() (может вернуть на тот же сервер)")
	local ok = pcall(function()
		TeleportService:Teleport(CONFIG.PLACE_ID, LocalPlayer)
	end)
	return ok
end

--============================= СКАНИРОВАНИЕ =================================--

-- Какие атрибуты/значения считаем "доходом" и "ценой"
local INCOME_ATTRS = {
	"Income", "income", "IncomePerSecond", "IncomePerSec",
	"PerSecond", "EPS", "Earnings", "Earn",
}
local VALUE_ATTRS = {
	"Value", "value", "Worth", "Price", "Cost", "SellPrice",
}

local EGG_TAG = "Egg"

-- "1.5B", "$5,000,000", "12.3M/sec", 5e9 -> число
local function parseNumber(value)
	if type(value) == "number" then
		return value
	elseif type(value) ~= "string" then
		return nil
	end

	local text = value:lower():gsub(",", ""):gsub("%s", ""):gsub("%$", "")
	local digits, suffix = text:match("([%d%.]+)([kmbtq]?)")
	if not digits then
		return nil
	end

	local number = tonumber(digits)
	if not number then
		return nil
	end

	local multipliers = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15 }
	return number * (multipliers[suffix] or 1)
end

-- Иногда цена не в атрибутах, а в тексте над яйцом (BillboardGui -> TextLabel)
local function readStatFromLabels(object, depth, visited)
	depth = depth or 0
	visited = visited or { count = 0 }

	if not object or depth > 2 then
		return nil
	end

	local children = object:GetChildren()
	for _, child in ipairs(children) do
		visited.count = visited.count + 1
		if visited.count > 60 then
			return nil
		end
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			local number = parseNumber(child.Text)
			if number and number > 0 then
				return number
			end
		end
	end

	for _, child in ipairs(children) do
		local number = readStatFromLabels(child, depth + 1, visited)
		if number then
			return number
		end
	end

	return nil
end

-- Ищем число в атрибутах объекта, его ValueBase-детях и папках (Config/Stats и т.п.)
local function readStat(object, names, depth)
	depth = depth or 0
	if not object then
		return nil
	end

	for _, name in ipairs(names) do
		local ok, value = pcall(object.GetAttribute, object, name)
		if ok and value ~= nil then
			local number = parseNumber(value)
			if number then
				return number
			end
		end
	end

	local children = object:GetChildren()

	for _, child in ipairs(children) do
		if child:IsA("ValueBase") then
			local childName = child.Name:lower()
			for _, name in ipairs(names) do
				if childName == name:lower() then
					local number = parseNumber(child.Value)
					if number then
						return number
					end
				end
			end
		end
	end

	-- Иногда статы лежат на уровень глубже: Egg -> Config -> Value
	if depth < 2 then
		for _, child in ipairs(children) do
			if child:IsA("Folder") or child:IsA("Configuration") or child:IsA("Model") then
				local number = readStat(child, names, depth + 1)
				if number then
					return number
				end
			end
		end
	end

	-- И последний вариант: число нарисовано в тексте над яйцом
	if depth == 0 then
		local labelNumber = readStatFromLabels(object)
		if labelNumber then
			return labelNumber
		end
	end

	return nil
end

local function isEggName(name)
	return string.find(string.lower(name), "egg", 1, true) ~= nil
end

local getEggPetName -- определяется ниже

-- Слова, по которым объект — обвязка, а не само яйцо
local EGG_SKIP_WORDS = {
	"holder", "glow", "nest", "spawn", "point", "spot",
	"fitbounds", "area", "carry", "prompt", "bounds",
	"display", "storage", "pedestal", "sign", "shop",
}

-- Контейнеры, в которых реально лежат яйца (включая трек)
local EGG_CONTAINERS = {
	"worldeggs", "eggnests", "eggpoint", "eggspawn", "eggspot", "eggs",
}

local function isEggContainerName(name)
	local lower = string.lower(tostring(name))

	if lower == "eggs" or lower == "worldeggs" or lower == "eggnests" then
		return true
	end

	for _, container in ipairs({ "worldeggs", "eggnests", "eggpoint", "eggspawn", "eggspot" }) do
		if string.find(lower, container, 1, true) then
			return true
		end
	end

	-- AreaEggSlotsClient / NewEnchantedEggs, но не AreaEggSlot1
	if string.find(lower, "eggs", 1, true) then
		return string.sub(lower, -6) == "client" or string.sub(lower, -4) == "eggs"
	end

	return false
end

--[[
	Яйцо определяем строго:
	  1) атрибут вида ...CanPickUp = true (самый надёжный признак);
	  2) имя содержит "egg" и не является обвязкой (EggGlow, CarryAreaEgg...);
	  3) объект лежит прямо в WorldEggs / EggNests.
	Так отсекаются витрины/пьюты с питомцами, из-за которых раньше
	в топ попадали объекты вида 11654316434_8f699e...
]]
-- Миры/папки, которые не сканируем: эвенты, базы игроков, клиентские ассеты
local IGNORE_WORLDS = {
	"dimension", "halloween", "plots", "clientrenderedassets",
}

local function isEventWorld(instance)
	local lower = string.lower(tostring(instance.Name))
	for _, word in ipairs(IGNORE_WORLDS) do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

local function insideEventWorld(instance)
	local node = instance
	for _ = 1, 6 do
		if not node or node == workspace then
			break
		end
		if isEventWorld(node) then
			return true
		end
		node = node.Parent
	end
	return false
end

local function isEggLike(instance)
	if instance:IsA("Folder") then
		return false
	end

	if CONFIG.IGNORE_EVENT_WORLDS and insideEventWorld(instance) then
		return false
	end

	-- 1) лежит в контейнере яиц на глубине до 3 уровней
	local node = instance.Parent
	for _ = 1, 3 do
		if not node or node == workspace then
			break
		end
		if isEggContainerName(node.Name) then
			return true
		end
		node = node.Parent
	end

	-- питомец в атрибутах: яйцо даже если имя похоже на обвязку
	local petName = getEggPetName(instance)

	-- 2) атрибуты, по которым яйцо узнаётся в любой зоне
	local ok, attributes = pcall(function()
		return instance:GetAttributes()
	end)
	if ok and type(attributes) == "table" then
		for name, value in pairs(attributes) do
			local key = string.lower(tostring(name))

			-- PreparedSourceName есть и у станций конвертации, поэтому его тут нет
			if string.find(key, "canpickup", 1, true)
				or (string.find(key, "egg", 1, true) and string.find(key, "uid", 1, true)) then
				return true
			end
		end
	end

	-- 3) имя с "egg" (обвязки пропускаем, но не если внутри есть питомец)
	local lowerName = string.lower(tostring(instance.Name))
	if isEggName(lowerName) then
		if petName then
			return true
		end
		for _, word in ipairs(EGG_SKIP_WORDS) do
			if string.find(lowerName, word, 1, true) then
				return false
			end
		end
		return true
	end

	return false
end

-- Позиция зоны: EggPoint или любая часть внутри
local function areaPosition(area)
	local guard = area:FindFirstChild("Guard")
	local eggPoint = guard and guard:FindFirstChild("EggPoint")
	if eggPoint and eggPoint:IsA("BasePart") then
		return eggPoint.Position
	end

	for _, descendant in ipairs(area:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.Position
		end
	end

	return nil
end

local areaPositionsCache = nil

local function getAreaPositions()
	if areaPositionsCache then
		return areaPositionsCache
	end

	local list = {}
	local world = workspace:FindFirstChild("World")
	local areasFolder = world and world:FindFirstChild("Areas")
	local guardAreas = areasFolder and areasFolder:FindFirstChild("GuardAreas")

	if guardAreas then
		for _, area in ipairs(guardAreas:GetChildren()) do
			local position = areaPosition(area)
			if position then
				list[#list + 1] = { name = tostring(area.Name), position = position }
			end
		end
	end

	areaPositionsCache = list
	return list
end

local function nearestAreaName(instance)
	local ok, position = pcall(function()
		return instance.Position
	end)
	if not ok or position == nil then
		return nil
	end

	local bestName, bestDistance = nil, math.huge
	for _, entry in ipairs(getAreaPositions()) do
		local okDistance, distance = pcall(function()
			return (entry.position - position).Magnitude
		end)
		if okDistance and type(distance) == "number" and distance < bestDistance then
			bestName, bestDistance = entry.name, distance
		end
	end

	return bestName
end

local areaNameCache = nil

local function getAreaNames()
	if areaNameCache then
		return areaNameCache
	end

	local names = {}
	local areas = requireModule and requireModule("Areas")
	if type(areas) == "table" and type(areas.Directory) == "table" then
		for key in pairs(areas.Directory) do
			names[#names + 1] = tostring(key)
		end
	end

	areaNameCache = names
	return names
end

local function matchAreaName(text)
	local lower = string.lower(tostring(text))
	local best = nil

	for _, areaName in ipairs(getAreaNames()) do
		local areaLower = string.lower(areaName)
		local firstWord = areaLower:match("^(%S+)") or areaLower
		if #firstWord >= 4 and string.find(lower, firstWord, 1, true) then
			if not best or #areaName > #best then
				best = areaName
			end
		end
	end

	return best
end

-- Биом: <X>Dimension, GuardAreas.<Area> или имя контейнера (NewEnchantedEggs)
local function getBiomeName(instance)
	local node = instance.Parent
	local eggContainerName = nil

	for _ = 1, 6 do
		if not node or node == workspace then
			break
		end

		local lower = string.lower(tostring(node.Name))

		if string.find(lower, "dimension", 1, true) then
			return node.Name
		end

		local parent = node.Parent
		if parent then
			local parentName = string.lower(tostring(parent.Name))
			if parentName == "guardareas" or parentName == "areas" then
				return node.Name
			end
		end

		local areaName = matchAreaName(node.Name)
		if areaName then
			return areaName
		end

		if not eggContainerName and isEggName(node.Name) then
			eggContainerName = node.Name
		end

		node = node.Parent
	end

	-- резерв: атрибуты самого яйца
	local ok, attributes = pcall(function()
		return instance:GetAttributes()
	end)
	if ok and type(attributes) == "table" then
		for _, field in ipairs({ "Area", "AreaName", "Biome", "BiomeName", "ZoneName" }) do
			local value = attributes[field]
			if type(value) == "string" then
				local matched = matchAreaName(value)
				return matched or value
			end
		end
	end

	local nearest = nearestAreaName(instance)
	if nearest then
		return nearest
	end

	if eggContainerName then
		return eggContainerName
	end

	return "?"
end

-- UID яйца: HalloweenEggUid, EggUid, ...
local function getEggUid(instance)
	local ok, attributes = pcall(function()
		return instance:GetAttributes()
	end)

	if not ok or type(attributes) ~= "table" then
		return nil, nil
	end

	for name, value in pairs(attributes) do
		if string.find(string.lower(tostring(name)), "uid", 1, true) then
			return tostring(value), tostring(name)
		end
	end

	return nil, nil
end

-- Питомец, который вылупится: PreparedSourceName / SourceName / ...
local PET_ATTRS = {
	"PreparedSourceName", "SourceName", "PetName", "AssetId", "PetId", "Source",
}

-- "Workspace.NewEnchantedEggs.Enchanted Bluejay" -> "Enchanted Bluejay"
local function normalizePetName(value)
	local text = tostring(value)
	local lastSegment = text:match("([^%.]+)$")
	if lastSegment and lastSegment ~= "" then
		text = lastSegment
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return text
end

function getEggPetName(instance)
	local ok, attributes = pcall(function()
		return instance:GetAttributes()
	end)

	if not ok or type(attributes) ~= "table" then
		return nil
	end

	for _, name in ipairs(PET_ATTRS) do
		if attributes[name] ~= nil then
			return normalizePetName(attributes[name])
		end
	end

	for name, value in pairs(attributes) do
		local lower = string.lower(tostring(name))
		if string.find(lower, "source", 1, true) or string.find(lower, "pet", 1, true) then
			return normalizePetName(value)
		end
	end

	-- иногда данные лежат на ребёнке слота (Hitbox и т.п.), но не у контейнеров
	if isEggContainerName(instance.Name) then
		return nil
	end

	for _, child in ipairs(instance:GetChildren()) do
		local okChild, childAttributes = pcall(function()
			return child:GetAttributes()
		end)
		if okChild and type(childAttributes) == "table" then
			for _, name in ipairs(PET_ATTRS) do
				if childAttributes[name] ~= nil then
					return normalizePetName(childAttributes[name])
				end
			end
		end
	end

	return nil
end

-- Поля, в которых может лежать доход в секунду
local INCOME_FIELDS = {
	"EarningRate", "Income", "MoneyPerSecond", "Earnings", "PerSecond", "Value",
}

local function findIncomeField(config)
	if type(config) ~= "table" then
		return nil
	end

	for _, field in ipairs(INCOME_FIELDS) do
		local value = config[field]
		if type(value) == "number" and value > 0 then
			return value, field
		end
	end

	if type(config.Egg) == "table" then
		for _, field in ipairs(INCOME_FIELDS) do
			local value = config.Egg[field]
			if type(value) == "number" and value > 0 then
				return value, "Egg." .. field
			end
		end
	end

	return nil
end

-- Индекс питомцев без пробелов/знаков: "PetalBeetle" == "Petal Beetle"
local petIndexCache = nil

local function normalizeKey(text)
	return (string.lower(tostring(text)):gsub("[^%w]", ""))
end

local function getPetIndex()
	if petIndexCache then
		return petIndexCache
	end

	local index = {}
	local assets = requireModule and requireModule("Assets")
	if type(assets) == "table" and type(assets.Directory) == "table" then
		for key, value in pairs(assets.Directory) do
			index[normalizeKey(key)] = value
			if type(value) == "table" and type(value.DisplayName) == "string" then
				index[normalizeKey(value.DisplayName)] = value
			end
		end
	end

	petIndexCache = index
	return index
end

-- Доход яйца по конфигу питомца (Assets.Directory[pet].BaseConfig)
local function getPetIncome(petName)
	if not petName or not requireModule then
		return nil
	end

	local assets = requireModule("Assets")
	if type(assets) ~= "table" or type(assets.Directory) ~= "table" then
		return nil
	end

	local entry = assets.Directory[petName]

	if type(entry) ~= "table" then
		entry = getPetIndex()[normalizeKey(petName)]
	end

	if type(entry) ~= "table" then
		local wanted = string.lower(tostring(petName))
		for key, value in pairs(assets.Directory) do
			if string.lower(tostring(key)) == wanted then
				entry = value
				break
			end
			if type(value) == "table" and type(value.DisplayName) == "string"
				and string.lower(value.DisplayName) == wanted then
				entry = value
				break
			end
		end
	end

	if type(entry) ~= "table" then
		return nil
	end

	local value, field = findIncomeField(entry.BaseConfig)
	if not value then
		value, field = findIncomeField(entry)
	end

	return value, field
end

-- Питомец -> локация по Areas.Directory[*].DropTable
local petAreaCache = nil

local function getPetAreaIndex()
	if petAreaCache then
		return petAreaCache
	end

	local index = {}
	local areas = requireModule and requireModule("Areas")
	if type(areas) == "table" and type(areas.Directory) == "table" then
		for areaName, config in pairs(areas.Directory) do
			if type(config) == "table" and type(config.DropTable) == "table" then
				for _, entry in pairs(config.DropTable) do
					local petName = entry
					if type(entry) == "table" then
						petName = entry[1]
					end
					if type(petName) == "string" then
						index[normalizeKey(petName)] = tostring(areaName)
					end
				end
			end
		end
	end

	petAreaCache = index
	return index
end

-- Собираем всё про яйцо: атрибуты, UID, биом, питомца и его доход
local function buildEggEntry(instance)
	-- контейнеры (EggPoint, EggSpawn...) не считаем яйцом, иначе не зайдём внутрь
	if isEggContainerName(instance.Name) then
		return nil
	end

	local income = readStat(instance, INCOME_ATTRS)
	local value  = readStat(instance, VALUE_ATTRS)
	local uid, uidName = getEggUid(instance)
	local pet = getEggPetName(instance)
	local petIncome, petField = getPetIncome(pet)

	local finalIncome = income
	if (not finalIncome or finalIncome <= 0) and petIncome then
		finalIncome = petIncome
	end

	if not finalIncome and not value and not uid and not pet then
		return nil
	end

	local displayName = instance.Name
	if #displayName >= 24 and displayName:match("^%x+$") and pet then
		displayName = pet
	end

	local biome = getBiomeName(instance)
	if pet then
		local petArea = getPetAreaIndex()[normalizeKey(pet)]
		if petArea then
			biome = petArea
		end
	end

	return {
		instance = instance,
		name     = displayName,
		income   = finalIncome or 0,
		pet      = pet,
		petField = petField,
		value    = value or 0,
		uid      = uid,
		uidName  = uidName,
		biome    = biome,
	}
end

--[[
	Обход workspace (DFS, без рекурсии — не переполнит стек).
	Яйцом считаем объект, если:
	  - на нём тег "Egg", или
	  - в имени есть "egg" (и это не Folder-контейнер),
	  и при этом у него реально есть Value/Income (иначе это просто папка).
	Внутрь найденного яйца не спускаемся, чтобы не ловить его части.
]]
local function collectEggs()
	local results   = {}
	local seen      = {}
	local scanned   = 0
	local truncated = false

	local tagged = {}
	for _, instance in ipairs(CollectionService:GetTagged(EGG_TAG)) do
		tagged[instance] = true

		-- Тег — самый надёжный признак, учитываем такое яйцо даже вне workspace
		if not seen[instance] and instance.Parent ~= nil
			and not (CONFIG.IGNORE_EVENT_WORLDS and insideEventWorld(instance)) then
			local entry = buildEggEntry(instance)
			if entry then
				seen[instance] = true
				results[#results + 1] = entry
			end
		end
	end

	local stack = { workspace }
	if CONFIG.SCAN_REPLICATED then
		stack[#stack + 1] = ReplicatedStorage
	end

	while #stack > 0 do
		local instance = table.remove(stack)

		scanned = scanned + 1
		if scanned > CONFIG.MAX_SCAN_OBJECTS then
			truncated = true
			break
		end

		local shouldDescend = true

		if CONFIG.IGNORE_EVENT_WORLDS and isEventWorld(instance) then
			shouldDescend = false
		elseif instance ~= workspace and instance.Parent ~= nil then
			local matched = tagged[instance] or isEggLike(instance)

			if matched and not seen[instance] then
				local entry = buildEggEntry(instance)
				if entry then
					seen[instance] = true
					results[#results + 1] = entry
					shouldDescend = false
				end
			end
		end

		if shouldDescend then
			for _, child in ipairs(instance:GetChildren()) do
				stack[#stack + 1] = child
			end
		end

		-- отдаём поток раз в 2000 объектов, чтобы не фризить клиент
		if scanned % 2000 == 0 then
			task.wait()
		end
	end

	return results, truncated, scanned
end

-- Короткий «отпечаток» набора яиц: по нему видно, одинаковые ли яйца на серверах
local function eggFingerprint(eggs)
	local parts = {}
	for _, egg in ipairs(eggs) do
		parts[#parts + 1] = tostring(egg.pet or "?") .. ":" .. tostring(egg.uid or "?")
	end
	table.sort(parts)

	local text = table.concat(parts, ";")
	local hash = 0
	for index = 1, #text do
		hash = (hash * 31 + string.byte(text, index)) % 4294967296
	end

	return string.format("%08x", hash)
end

-- Собираем лучшее яйцо по каждому имени, затем выбираем максимум
-- Позиция зоны (EggPoint или любая часть)
local function findAreaPosition(area)
	local guard = area:FindFirstChild("Guard")
	local eggPoint = guard and guard:FindFirstChild("EggPoint")
	if eggPoint and eggPoint:IsA("BasePart") then
		return eggPoint.Position
	end

	for _, descendant in ipairs(area:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.Position
		end
	end

	return nil
end

-- Просим клиент догрузить все зоны трека (если включён стриминг)
local function streamAllAreas()
	if not CONFIG.STREAM_AREAS then
		return 0
	end

	local okEnabled, enabled = pcall(function()
		return workspace.StreamingEnabled
	end)
	if not okEnabled or not enabled then
		return 0
	end

	local world = workspace:FindFirstChild("World")
	local areasFolder = world and world:FindFirstChild("Areas")
	local guardAreas = areasFolder and areasFolder:FindFirstChild("GuardAreas")
	if not guardAreas then
		return 0
	end

	local count = 0
	for _, area in ipairs(guardAreas:GetChildren()) do
		local position = findAreaPosition(area)
		if position then
			local okRequest = pcall(function()
				workspace:RequestStreamAroundAsync(position, 3)
			end)
			if okRequest then
				count = count + 1
			end
			task.wait(0.35)
		end
	end

	return count
end

local function scanServer()
	local streamed = streamAllAreas()
	if streamed > 0 then
		log("Стриминг: запрошено зон " .. streamed)
		task.wait(1)
	end

	local eggs, truncated, scanned = collectEggs()

	local byName = {}
	for _, egg in ipairs(eggs) do
		local score = math.max(egg.income, egg.value)
		-- группируем по питомцу: у одинаковых яиц разные питомцы и разный доход
		local key = string.lower(tostring(egg.pet or "?")) .. "|" .. string.lower(egg.name)
		local previous = byName[key]

		if not previous or score > previous.score then
			byName[key] = {
				name     = egg.name,
				income   = egg.income,
				value    = egg.value,
				score    = score,
				instance = egg.instance,
				biome    = egg.biome or "?",
				uid      = egg.uid,
				uidName  = egg.uidName,
				pet      = egg.pet,
				petField = egg.petField,
			}
		end
	end

	local ranked = {}
	for _, entry in pairs(byName) do
		ranked[#ranked + 1] = entry
	end

	table.sort(ranked, function(a, b)
		return a.score > b.score
	end)

	return ranked[1], #ranked, truncated, scanned, eggs, #eggs, ranked
end

-- Прошло ли яйцо порог (с учётом THRESHOLD_MODE)
local function isValuable(egg)
	if not egg then
		return false, 0
	end

	local metric
	if CONFIG.THRESHOLD_MODE == "income" then
		metric = egg.income
	elseif CONFIG.THRESHOLD_MODE == "value" then
		metric = egg.value
	else
		metric = math.max(egg.income, egg.value)
	end

	return metric >= CONFIG.THRESHOLD, metric
end

-- 1500000000 -> "1.50B"
local function formatNumber(number)
	if type(number) ~= "number" then
		return "?"
	end

	local units = {
		{ 1e15, "Q" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" },
	}

	for _, unit in ipairs(units) do
		if number >= unit[1] then
			return string.format("%.2f%s", number / unit[1], unit[2])
		end
	end

	return string.format("%d", math.floor(number))
end

--============================= DISCORD WEBHOOK ==============================--

-- Не отправляем одно и то же яйцо с того же сервера чаще WEBHOOK_COOLDOWN
local reported = {}

local function eggKey(egg)
	return string.format("%s|%s", game.JobId or "?", string.lower(egg.name))
end

local function alreadyReported(egg)
	local last = reported[eggKey(egg)]
	return last ~= nil and (os.time() - last) < CONFIG.WEBHOOK_COOLDOWN
end

local function markReported(egg)
	reported[eggKey(egg)] = os.time()
end

local function sendWebhook(egg, metric)
	if CONFIG.WEBHOOK_URL == "" then
		log(string.format(
			"WEBHOOK_URL пуст — только лог. Яйцо: %s | Income=%s | Value=%s",
			egg.name, formatNumber(egg.income), formatNumber(egg.value)
		))
		return false
	end

	local requestFn = getRequestFunction()
	if not requestFn then
		warn(PREFIX, "Нет request/syn.request — вебхук отправить нечем")
		return false
	end

	local jobId      = game.JobId
	local players    = #Players:GetPlayers()
	local maxPlayers = Players.MaxPlayers
	local deepLink   = string.format(
		"https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s",
		CONFIG.PLACE_ID, jobId
	)

	local payload = {
		username = "Egg Scanner",
		content  = string.format("🥚 **%s** — %s", egg.name, formatNumber(metric)),
		embeds = {
			{
				title       = "Найдено дорогое яйцо",
				color       = 0x2ECC71,
				description = string.format("Сервер `%s`", jobId),
				fields = {
					{ name = "Яйцо",           value = egg.name,                     inline = true },
					{ name = "Доход (Income)", value = formatNumber(egg.income),     inline = true },
					{ name = "Цена (Value)",   value = formatNumber(egg.value),      inline = true },
					{ name = "Порог",          value = formatNumber(CONFIG.THRESHOLD), inline = true },
					{ name = "Игроки",         value = string.format("%d/%d", players, maxPlayers), inline = true },
					{ name = "Биом",          value = tostring(egg.biome or "?"), inline = true },
					{ name = "UID",           value = tostring(egg.uid or "-"), inline = true },
					{ name = "Питомец",        value = tostring(egg.pet or "-"), inline = true },
					{ name = "JobId",          value = "`" .. tostring(jobId) .. "`", inline = false },
					{ name = "Зайти на сервер", value = "[прямая ссылка](" .. deepLink .. ")", inline = false },
				},
				footer    = { text = "Steal An Egg • egg scanner" },
				timestamp = DateTime.now():ToIsoDate(),
			},
		},
	}

	local body = HttpService:JSONEncode(payload)

	for attempt = 1, 3 do
		local ok, response = pcall(requestFn, {
			Url     = CONFIG.WEBHOOK_URL,
			Method  = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body    = body,
		})

		if not ok then
			warn(PREFIX, "Вебхук не отправлен: " .. tostring(response))
			break
		end

		local status, responseBody = normalizeResponse(response)

		if status == 204 or status == 200 then
			log(string.format("Вебхук отправлен: %s (%s)", egg.name, formatNumber(metric)))
			return true
		end

		if status == 429 then
			local waitTime = 2
			local decoded = decodeJson(responseBody or "")
			if type(decoded) == "table" and tonumber(decoded.retry_after) then
				waitTime = tonumber(decoded.retry_after)
			end
			warn(PREFIX, string.format("Discord rate limit, жду %.1f сек", waitTime))
			task.wait(waitTime)
		else
			warn(PREFIX, string.format(
				"Вебхук вернул статус %s: %s",
				tostring(status), tostring(responseBody)
			))
			break
		end
	end

	return false
end

--============================== ПАНЕЛЬ (GUI) ================================--

local running = true

local UI = {
	gui      = nil,
	frame    = nil,
	status   = nil,
	logLabel = nil,
	actions  = {}, -- заполняется в главном цикле
}

local logLines = {}
local LOG_LINES_MAX = 10

local function refreshLog()
	if not UI.logLabel then
		return
	end
	pcall(function()
		UI.logLabel.Text = table.concat(logLines, "\n")
	end)
end

function addLog(text)
	text = tostring(text)
	logLines[#logLines + 1] = text
	while #logLines > LOG_LINES_MAX do
		table.remove(logLines, 1)
	end
	refreshLog()
	if rconsoleprint then
		pcall(rconsoleprint, "[EggScanner] " .. text .. "\n")
	end
end

pushLog = addLog

function setStatus(text)
	if not UI.status then
		return
	end
	pcall(function()
		UI.status.Text = tostring(text)
	end)
end

local function makeButton(parent, caption, x, width, callback)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(width or 68, 32)
	button.Position = UDim2.fromOffset(x, 0)
	button.BackgroundColor3 = Color3.fromRGB(45, 48, 60)
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.SourceSansSemibold
	button.TextSize = 12
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.Text = caption
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	button.Activated:Connect(function()
		local ok, err = pcall(callback)
		if not ok then
			addLog("Ошибка кнопки: " .. tostring(err))
		end
	end)

	return button
end

--============================= РАЗВЕДКА КАРТЫ ===============================--

local function shortPath(instance, limit)
	limit = limit or 60
	local ok, path = pcall(function()
		return instance:GetFullName()
	end)
	if not ok or type(path) ~= "string" then
		path = tostring(instance)
	end
	if #path > limit then
		path = "..." .. path:sub(-(limit - 3))
	end
	return path
end

-- Держим в списке только N самых больших значений
local function pushTop(list, item, limit, isBetter)
	local size = #list + 1
	list[size] = item

	while size > 1 and isBetter(list[size], list[size - 1]) do
		list[size], list[size - 1] = list[size - 1], list[size]
		size = size - 1
	end

	while #list > limit do
		table.remove(list)
	end
end

-- Discord режет сообщения по 2000 символов
local function splitMessage(text, limit)
	limit = limit or 1800
	local parts, buffer = {}, ""

	for line in (text .. "\n"):gmatch("(.-)\n") do
		if #buffer + #line + 1 > limit then
			parts[#parts + 1] = buffer
			buffer = ""
		end
		buffer = buffer .. line .. "\n"
	end

	if buffer ~= "" then
		parts[#parts + 1] = buffer
	end

	return parts
end

local function sendDiscordMessage(content)
	if CONFIG.WEBHOOK_URL == "" then
		return false
	end

	local requestFn = getRequestFunction()
	if not requestFn then
		return false
	end

	local body = HttpService:JSONEncode({
		username = "Egg Scanner",
		content = content,
	})

	for attempt = 1, 2 do
		local ok, response = pcall(requestFn, {
			Url = CONFIG.WEBHOOK_URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})

		if not ok then
			return false
		end

		local status = normalizeResponse(response)
		if status == 204 or status == 200 then
			return true
		end

		if status ~= 429 then
			return false
		end

		task.wait(2)
	end

	return false
end

-- Заливаем текст на пастбин, чтобы не копировать простыню с телефона
local function uploadText(text)
	local requestFn = getRequestFunction()
	if not requestFn then
		return nil, "нет request"
	end

	-- 1) paste.rs: тело запроса = сам текст, ответ = ссылка
	local ok, response = pcall(requestFn, {
		Url = "https://paste.rs",
		Method = "POST",
		Headers = { ["Content-Type"] = "text/plain" },
		Body = text,
	})

	if ok then
		local status, body = normalizeResponse(response)
		if status == 200 or status == 201 then
			local link = tostring(body or ""):match("https://paste%.rs/%S+")
			if link then
				return link
			end
		end
	end

	-- 2) tmpfiles.org (multipart), ответ — JSON с url
	local boundary = "----EggScanner" .. tostring(math.random(100000, 999999))
	local body = table.concat({
		"--" .. boundary,
		'Content-Disposition: form-data; name="file"; filename="recon.txt"',
		"Content-Type: text/plain",
		"",
		text,
		"--" .. boundary .. "--",
		"",
	}, "\r\n")

	local ok2, response2 = pcall(requestFn, {
		Url = "https://tmpfiles.org/api/v1/upload",
		Method = "POST",
		Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
		Body = body,
	})

	if ok2 then
		local status2, body2 = normalizeResponse(response2)
		if status2 == 200 and type(body2) == "string" then
			local url = body2:match('"url"%s*:%s*"([^"]+)"')
			if url then
				return (url:gsub("tmpfiles%.org/", "tmpfiles.org/dl/"))
			end
		end
	end

	return nil, "пастбины недоступны"
end

-- Отчёт: сначала пробуем ссылку, иначе режем на сообщения Discord
local function deliverReport(text, title)
	local link = uploadText(text)

	if link then
		addLog(title .. ": " .. link)
		setStatus(title .. " готов")
		if setclipboard then
			pcall(setclipboard, link)
		end
		sendDiscordMessage(string.format("**%s** (%d симв.)\n%s", title, #text, link))
		return link
	end

	local parts = splitMessage(text)
	local sent = 0

	for index = 1, math.min(#parts, 6) do
		if sendDiscordMessage(parts[index]) then
			sent = sent + 1
		end
		task.wait(1)
	end

	if sent > 0 then
		addLog(string.format("%s: отправлено в Discord %d сообщ.", title, sent))
		setStatus(title .. " в Discord")
		return nil
	end

	for line in text:gmatch("[^\n]+") do
		addLog(line:sub(1, 60))
	end
	setStatus("Нет связи — лог на экране")
	return nil
end

--[[
	Разведка карты: где вообще лежат данные о яйцах.
	  - имена объектов с "egg" (сколько, есть ли статы, пример пути);
	  - числовые атрибуты (имя, максимум, пример пути);
	  - топ ValueBase (NumberValue/IntValue/StringValue) по значению;
	  - топ TextLabel с крупными числами (цены в UI);
	  - объекты с income/value/price/worth/cost в имени;
	  - содержимое ReplicatedStorage;
	  - RemoteEvent / RemoteFunction.
]]
local function collectRecon()
	local scanned, truncated = 0, false
	local eggNames, attrStats = {}, {}
	local topValues, topLabels, nameHits = {}, {}, {}
	local remotes, labelCount = {}, 0

	local stack = { workspace }
	if ReplicatedStorage then
		stack[#stack + 1] = ReplicatedStorage
	end

	local function markEgg(instance, attributes)
		local key = instance.Name:lower()
		local entry = eggNames[key]

		if not entry then
			entry = { count = 0, stats = false, sample = instance, name = instance.Name }
			eggNames[key] = entry
		end

		entry.count = entry.count + 1
		if entry.stats then
			return
		end

		-- есть ли у яйца хоть какие-то числовые данные
		if attributes then
			for _, value in pairs(attributes) do
				local number = parseNumber(value)
				if number and number > 0 then
					entry.stats = true
					return
				end
			end
		end

		for _, child in ipairs(instance:GetChildren()) do
			if child:IsA("ValueBase") then
				local number = parseNumber(child.Value)
				if number and number > 0 then
					entry.stats = true
					return
				end
			end
		end
	end

	while #stack > 0 do
		local instance = table.remove(stack)
		scanned = scanned + 1

		if scanned > CONFIG.MAX_SCAN_OBJECTS then
			truncated = true
			break
		end

		local attributes = nil
		local okAttrs, result = pcall(function()
			return instance:GetAttributes()
		end)
		if okAttrs and type(result) == "table" then
			attributes = result
		end

		if attributes then
			for name, value in pairs(attributes) do
				local number = parseNumber(value)
				if number and number > 0 then
					local entry = attrStats[name]
					if not entry then
						entry = { count = 0, max = number, sample = instance }
						attrStats[name] = entry
					end
					entry.count = entry.count + 1
					if number > entry.max then
						entry.max = number
						entry.sample = instance
					end
				end
			end
		end

		local className = instance.ClassName

		if isEggName(instance.Name) and not instance:IsA("Folder") then
			markEgg(instance, attributes)
		end

		if className == "NumberValue" or className == "IntValue" or className == "StringValue" then
			local number = parseNumber(instance.Value)
			if number and number > 0 then
				pushTop(topValues, {
					instance = instance,
					value = number,
					className = className,
				}, 10, function(a, b)
					return a.value > b.value
				end)
			end
		elseif className == "TextLabel" or className == "TextButton" then
			if labelCount < 3000 then
				labelCount = labelCount + 1
				local number = parseNumber(instance.Text)
				if number and number >= 1e6 then
					pushTop(topLabels, {
						instance = instance,
						text = tostring(instance.Text),
						number = number,
					}, 8, function(a, b)
						return a.number > b.number
					end)
				end
			end
		elseif className == "RemoteEvent" or className == "RemoteFunction" then
			if #remotes < 20 then
				remotes[#remotes + 1] = instance.Name .. " (" .. className .. ")"
			end
		end

		local lowerName = instance.Name:lower()
		if #nameHits < 15 and (lowerName:find("income", 1, true)
			or lowerName:find("value", 1, true)
			or lowerName:find("price", 1, true)
			or lowerName:find("worth", 1, true)
			or lowerName:find("cost", 1, true)) then
			nameHits[#nameHits + 1] = { instance = instance, className = className }
		end

		for _, child in ipairs(instance:GetChildren()) do
			stack[#stack + 1] = child
		end

		if scanned % 2000 == 0 then
			task.wait()
		end
	end

	-- сортируем по «весу»
	local eggList = {}
	for name, info in pairs(eggNames) do
		eggList[#eggList + 1] = {
			name = info.name or name,
			count = info.count,
			stats = info.stats,
			sample = info.sample,
		}
	end
	table.sort(eggList, function(a, b)
		return a.count > b.count
	end)

	local attrList = {}
	for name, info in pairs(attrStats) do
		attrList[#attrList + 1] = {
			name = name,
			count = info.count,
			max = info.max,
			sample = info.sample,
		}
	end
	table.sort(attrList, function(a, b)
		if a.max ~= b.max then
			return a.max > b.max
		end
		return a.count > b.count
	end)

	local lines = {}
	local function add(...)
		lines[#lines + 1] = string.format(...)
	end

	add("RECON %s | Job %s | объектов %d%s",
		VERSION, tostring(game.JobId):sub(1, 8), scanned, truncated and " (лимит)" or "")
	add("")

	add("[EGG-имена] уникальных: %d", #eggList)
	for index = 1, math.min(8, #eggList) do
		local entry = eggList[index]
		add("%s x%d | статы: %s | %s",
			entry.name, entry.count, entry.stats and "да" or "нет",
			shortPath(entry.sample, 55))
	end
	if #eggList == 0 then
		add("нет имён с egg")
	end
	add("")

	add("[ЧИСЛОВЫЕ АТРИБУТЫ] уникальных: %d", #attrList)
	for index = 1, math.min(8, #attrList) do
		local entry = attrList[index]
		add("%s x%d = %s | %s",
			entry.name, entry.count, formatNumber(entry.max),
			shortPath(entry.sample, 50))
	end
	if #attrList == 0 then
		add("нет")
	end
	add("")

	add("[ValueBase топ-%d]", #topValues)
	for _, item in ipairs(topValues) do
		add("%s (%s) = %s", shortPath(item.instance, 50), item.className, formatNumber(item.value))
	end
	if #topValues == 0 then
		add("нет")
	end
	add("")

	add("[Текст с числами топ-%d]", #topLabels)
	for _, item in ipairs(topLabels) do
		add("%s = %s", shortPath(item.instance, 45), tostring(item.text):sub(1, 24))
	end
	if #topLabels == 0 then
		add("нет")
	end
	add("")

	add("[Имена со value/price/worth/cost]")
	for _, item in ipairs(nameHits) do
		add("%s (%s)", shortPath(item.instance, 55), item.className)
	end
	if #nameHits == 0 then
		add("нет")
	end
	add("")

	-- биомы трека: Workspace.World.Areas.GuardAreas.<Area>
	local areaNames = {}
	local world = workspace:FindFirstChild("World")
	local areasFolder = world and world:FindFirstChild("Areas")
	local guardAreas = areasFolder and areasFolder:FindFirstChild("GuardAreas")

	if guardAreas then
		for _, area in ipairs(guardAreas:GetChildren()) do
			areaNames[#areaNames + 1] = string.format("%s (%d детей)",
				tostring(area.Name):sub(1, 30), #(area:GetChildren()))
		end
	end

	for _, child in ipairs(workspace:GetChildren()) do
		local lower = string.lower(tostring(child.Name))
		if string.find(lower, "dimension", 1, true) or string.find(lower, "biome", 1, true) then
			areaNames[#areaNames + 1] = tostring(child.Name) .. " (эвент)"
		end
	end

	add("[Биомы] найдено: %d", #areaNames)
	if #areaNames == 0 then
		add("нет GuardAreas и Dimension")
	else
		for index = 1, math.min(#areaNames, 15) do
			add("  " .. areaNames[index])
		end
	end
	add("")

	if ReplicatedStorage then
		add("[ReplicatedStorage]")
		local children = ReplicatedStorage:GetChildren()
		for index = 1, math.min(25, #children) do
			local child = children[index]
			add("%s (%s)", tostring(child.Name):sub(1, 40), child.ClassName)
			if child:IsA("Folder") then
				local inner = child:GetChildren()
				for innerIndex = 1, math.min(5, #inner) do
					add("  %s (%s)", tostring(inner[innerIndex].Name):sub(1, 34), inner[innerIndex].ClassName)
				end
			end
		end
		if #children == 0 then
			add("пусто")
		end
		add("")
	end

	add("[Remote-объекты]")
	for _, item in ipairs(remotes) do
		add(item)
	end
	if #remotes == 0 then
		add("нет")
	end

	local text = table.concat(lines, "\n")
	if #text > 12000 then
		text = text:sub(1, 12000) .. "\n... (обрезано)"
	end

	return text, scanned, #eggList
end

--============================= ИНСПЕКТОР ЯЙЦА ================================--

local function describeValue(value, depth, budget, seen)
	if budget.left <= 0 then
		return "..."
	end

	local valueType = type(value)

	if valueType == "table" then
		if seen[value] then
			return "<cycle>"
		end
		seen[value] = true

		if depth <= 0 then
			return "{...}"
		end

		local keys = {}
		for key in pairs(value) do
			keys[#keys + 1] = key
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)

		local parts = {}
		for _, key in ipairs(keys) do
			if budget.left <= 0 then
				parts[#parts + 1] = "..."
				break
			end
			budget.left = budget.left - 1
			parts[#parts + 1] = tostring(key) .. "=" .. describeValue(value[key], depth - 1, budget, seen)
		end

		return "{" .. table.concat(parts, ", ") .. "}"
	end

	if valueType == "string" then
		local text = tostring(value):gsub("\n", " ")
		if #text > 46 then
			text = text:sub(1, 46) .. "..."
		end
		return '"' .. text .. '"'
	end

	if valueType == "number" then
		if value >= 1e6 then
			return formatNumber(value)
		end
		return tostring(value)
	end

	return tostring(value)
end

local function describeInstance(instance, depth, lines, budget, maxDepth)
	if budget.left <= 0 then
		return
	end
	budget.left = budget.left - 1

	local indent = string.rep("  ", depth)
	local label = string.format("%s%s (%s)",
		indent, tostring(instance.Name):sub(1, 40), instance.ClassName)

	local extra = {}

	local okAttrs, attributes = pcall(function()
		return instance:GetAttributes()
	end)
	if okAttrs and type(attributes) == "table" then
		local count = 0
		for name, value in pairs(attributes) do
			count = count + 1
			if count <= 5 then
				extra[#extra + 1] = tostring(name) .. "=" .. tostring(value):sub(1, 26)
			end
		end
	end

	if instance:IsA("ValueBase") then
		extra[#extra + 1] = "value=" .. tostring(instance.Value):sub(1, 30)
	elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
		local text = tostring(instance.Text):gsub("\n", " ")
		extra[#extra + 1] = "text=" .. text:sub(1, 44)
	end

	if #extra > 0 then
		label = label .. "  " .. table.concat(extra, " | ")
	end

	lines[#lines + 1] = label

	if depth >= (maxDepth or 4) then
		return
	end

	for _, child in ipairs(instance:GetChildren()) do
		describeInstance(child, depth + 1, lines, budget)
	end
end

-- Ищем настоящие яйца: под WorldEggs/EggNests, без слов-обвязок
local function findEggSamples(limit)
	local candidates = {}
	local stack = { workspace }
	local scanned = 0

	while #stack > 0 and scanned < 80000 do
		local instance = table.remove(stack)
		scanned = scanned + 1

		local inEventWorld = CONFIG.IGNORE_EVENT_WORLDS and isEventWorld(instance)

		local matched = not inEventWorld
			and instance ~= workspace
			and instance.Parent ~= nil
			and isEggName(instance.Name)
			and not instance:IsA("Folder")

		if matched then
			local lower = string.lower(instance.Name)
			local skipped = false
			for _, word in ipairs(EGG_SKIP_WORDS) do
				if string.find(lower, word, 1, true) then
					skipped = true
					break
				end
			end

			if skipped then
				-- это контейнер (EggPoint, EggSpawn...), заходим внутрь
				for _, child in ipairs(instance:GetChildren()) do
					stack[#stack + 1] = child
				end
			else
				local score = 0
				if instance.Parent and isEggName(instance.Parent.Name) then
					score = score + 3
				end
				if instance:IsA("Model") then
					score = score + 1
				end

				local okAttrs, attributes = pcall(function()
					return instance:GetAttributes()
				end)
				local attributeCount = 0
				if okAttrs and type(attributes) == "table" then
					for _ in pairs(attributes) do
						attributeCount = attributeCount + 1
					end
				end
				if attributeCount > 0 then
					score = score + 1
				end

				candidates[#candidates + 1] = {
					instance = instance,
					score = score,
					attributes = attributeCount,
				}
			end
		elseif not inEventWorld then
			for _, child in ipairs(instance:GetChildren()) do
				stack[#stack + 1] = child
			end
		end

		if scanned % 2000 == 0 then
			task.wait()
		end
	end

	table.sort(candidates, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.attributes > b.attributes
	end)

	local samples = {}
	for index = 1, math.min(limit, #candidates) do
		samples[#samples + 1] = candidates[index].instance
	end

	return samples, scanned, candidates
end

-- Достаём модуль из ReplicatedStorage.Data (require в pcall)
function requireModule(name)
	if not ReplicatedStorage then
		return nil
	end

	local data = ReplicatedStorage:FindFirstChild("Data")
	local module = data and data:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end

	local ok, result = pcall(function()
		return require(module)
	end)

	if ok then
		return result
	end
	return nil
end

local function sortedKeys(tbl)
	local keys = {}
	for key in pairs(tbl) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	return keys
end

-- Конфиги игры: ищем, где лежат цены/доходы яиц
local function dumpConfig(lines)
	local assets   = requireModule("Assets")
	local areas    = requireModule("Areas")
	local limited  = requireModule("LimitedEgg")
	local rarity   = requireModule("Rarity")
	local currency = requireModule("Currency")
	local products = requireModule("Products")

	-- 1) LimitedEgg — самый вероятный конфиг яиц
	lines[#lines + 1] = "[LimitedEgg]"
	if limited then
		lines[#lines + 1] = "  " .. describeValue(limited, 4, { left = 200 }, {}):sub(1, 2600)
	else
		lines[#lines + 1] = "  require failed"
	end
	lines[#lines + 1] = ""

	-- 2) Areas — биомы трека
	lines[#lines + 1] = "[Areas]"
	if type(areas) == "table" and type(areas.Directory) == "table" then
		local keys = sortedKeys(areas.Directory)
		lines[#lines + 1] = string.format("  биомы (%d): %s",
			#keys, table.concat(keys, ", "):sub(1, 700))
		if keys[1] then
			lines[#lines + 1] = "  " .. keys[1] .. ": "
				.. describeValue(areas.Directory[keys[1]], 3, { left = 60 }, {}):sub(1, 800)
		end
	else
		lines[#lines + 1] = "  нет Directory"
	end
	lines[#lines + 1] = ""

	-- 3) Assets: ключи с "egg" + пример
	lines[#lines + 1] = "[Assets.Directory]"
	if type(assets) == "table" and type(assets.Directory) == "table" then
		local eggKeys, total = {}, 0
		for key in pairs(assets.Directory) do
			total = total + 1
			if string.find(string.lower(tostring(key)), "egg", 1, true) then
				eggKeys[#eggKeys + 1] = tostring(key)
			end
		end
		table.sort(eggKeys)

		lines[#lines + 1] = string.format("  всего %d, с 'egg' в имени: %d", total, #eggKeys)
		if #eggKeys > 0 then
			lines[#lines + 1] = "  ключи: " .. table.concat(eggKeys, ", "):sub(1, 600)
			lines[#lines + 1] = "  " .. eggKeys[1] .. ": "
				.. describeValue(assets.Directory[eggKeys[1]], 3, { left = 120 }, {}):sub(1, 1400)
		end
	else
		lines[#lines + 1] = "  нет Directory"
	end
	lines[#lines + 1] = ""

	-- 4) Rarity
	lines[#lines + 1] = "[Rarity]"
	if type(rarity) == "table" and type(rarity.Rarities) == "table" then
		local keys = sortedKeys(rarity.Rarities)
		lines[#lines + 1] = "  " .. table.concat(keys, ", "):sub(1, 500)
		if keys[1] then
			lines[#lines + 1] = "  " .. keys[1] .. ": "
				.. describeValue(rarity.Rarities[keys[1]], 3, { left = 40 }, {}):sub(1, 600)
		end
	else
		lines[#lines + 1] = "  нет Rarities"
	end
	lines[#lines + 1] = ""

	-- 5) Currency
	lines[#lines + 1] = "[Currency]"
	if type(currency) == "table" and type(currency.Directory) == "table" then
		local keys = sortedKeys(currency.Directory)
		lines[#lines + 1] = "  " .. table.concat(keys, ", "):sub(1, 300)
		if keys[1] then
			lines[#lines + 1] = "  " .. keys[1] .. ": "
				.. describeValue(currency.Directory[keys[1]], 3, { left = 40 }, {}):sub(1, 600)
		end
	else
		lines[#lines + 1] = "  нет Directory"
	end
	lines[#lines + 1] = ""

	-- 6) Products, в которых есть Egg
	lines[#lines + 1] = "[Products с Egg]"
	if type(products) == "table" and type(products.Directory) == "table" then
		local eggKeys = {}
		for key in pairs(products.Directory) do
			if string.find(string.lower(tostring(key)), "egg", 1, true) then
				eggKeys[#eggKeys + 1] = tostring(key)
			end
		end
		table.sort(eggKeys)
		lines[#lines + 1] = "  " .. table.concat(eggKeys, ", "):sub(1, 700)
		if eggKeys[1] then
			lines[#lines + 1] = "  " .. eggKeys[1] .. ": "
				.. describeValue(products.Directory[eggKeys[1]], 2, { left = 40 }, {}):sub(1, 700)
		end
	else
		lines[#lines + 1] = "  нет Directory"
	end
end

local function collectNumericFields(value, prefix, depth, out, budget, seen)
	if budget.left <= 0 then
		return
	end

	if type(value) ~= "table" then
		if type(value) == "number" then
			budget.left = budget.left - 1
			out[#out + 1] = string.format("%s = %s", prefix, tostring(value))
		end
		return
	end

	if depth <= 0 or seen[value] then
		return
	end
	seen[value] = true

	for key, child in pairs(value) do
		if budget.left <= 0 then
			return
		end
		collectNumericFields(child, prefix .. "." .. tostring(key), depth - 1, out, budget, seen)
	end
end

-- Разбор трека: Workspace.World.Areas.GuardAreas.<Area>.Guard.EggPoint
local function dumpTrack(lines)
	local world = workspace:FindFirstChild("World")
	local areas = world and world:FindFirstChild("Areas")
	local guardAreas = areas and areas:FindFirstChild("GuardAreas")

	if not guardAreas then
		lines[#lines + 1] = "нет Workspace.World.Areas.GuardAreas"
		return
	end

	local printed = 0
	for _, area in ipairs(guardAreas:GetChildren()) do
		if printed >= 20 then
			break
		end
		printed = printed + 1

		lines[#lines + 1] = string.format("%s (%s) | детей: %d",
			area.Name, area.ClassName, #(area:GetChildren()))

		local guard = area:FindFirstChild("Guard")
		if guard then
			lines[#lines + 1] = string.format("  Guard | детей: %d", #(guard:GetChildren()))

			for _, child in ipairs(guard:GetChildren()) do
				if string.find(string.lower(child.Name), "egg", 1, true) then
					local parts = {}
					local okAttrs, attributes = pcall(function()
						return child:GetAttributes()
					end)
					if okAttrs and type(attributes) == "table" then
						for name, value in pairs(attributes) do
							parts[#parts + 1] = tostring(name) .. "=" .. tostring(value):sub(1, 28)
						end
					end

					lines[#lines + 1] = string.format("    %s (%s) | детей %d | %s",
						child.Name, child.ClassName, #(child:GetChildren()),
						table.concat(parts, ", "):sub(1, 160))

					for _, sub in ipairs(child:GetChildren()) do
						lines[#lines + 1] = string.format("      %s (%s)", sub.Name, sub.ClassName)
					end
				end
			end
		end
	end
end

-- Поиск объектов по части имени (глубина ограничена)
local function findByName(root, pattern, maxDepth)
	local found = {}

	local function walk(instance, depth)
		if depth > maxDepth or #found >= 10 then
			return
		end
		for _, child in ipairs(instance:GetChildren()) do
			if string.find(string.lower(tostring(child.Name)), pattern, 1, true) then
				found[#found + 1] = child
			else
				walk(child, depth + 1)
			end
		end
	end

	walk(root, 0)
	return found
end

-- Разбор AreaEggSlots*: возможно, там слоты всех локаций
local function dumpAreaSlots(lines)
	local candidates = {}

	for _, root in ipairs({ workspace, ReplicatedStorage }) do
		if root then
			for _, instance in ipairs(findByName(root, "areaeggslots", 4)) do
				candidates[#candidates + 1] = instance
			end
		end
	end

	lines[#lines + 1] = "найдено AreaEggSlots: " .. #candidates

	for _, instance in ipairs(candidates) do
		lines[#lines + 1] = string.format("%s (%s) | детей %d",
			shortPath(instance, 80), instance.ClassName, #(instance:GetChildren()))

		local children = instance:GetChildren()
		for index = 1, math.min(#children, 10) do
			local child = children[index]
			lines[#lines + 1] = string.format("  %s (%s) | детей %d",
				tostring(child.Name):sub(1, 34), child.ClassName, #(child:GetChildren()))
		end

		if instance:IsA("ModuleScript") then
			local ok, result = pcall(function()
				return require(instance)
			end)
			if ok then
				lines[#lines + 1] = "  require: "
					.. describeValue(result, 3, { left = 80 }, {}):sub(1, 2200)
			else
				lines[#lines + 1] = "  require error: " .. tostring(result):sub(1, 90)
			end
		end
	end
end

-- Полный дамп слотов AreaEggSlotsClient: атрибуты каждого слота
local function dumpSlots(lines)
	local slots = workspace:FindFirstChild("AreaEggSlotsClient")
	if not slots then
		lines[#lines + 1] = "нет Workspace.AreaEggSlotsClient"
		return
	end

	local children = slots:GetChildren()

	local withAttrs, withPet = 0, 0
	for _, slot in ipairs(children) do
		local ok, attributes = pcall(function()
			return slot:GetAttributes()
		end)
		if ok and type(attributes) == "table" then
			local count = 0
			for name in pairs(attributes) do
				count = count + 1
				if string.find(string.lower(tostring(name)), "source", 1, true) then
					withPet = withPet + 1
					break
				end
			end
			if count > 0 then
				withAttrs = withAttrs + 1
			end
		end
	end

	lines[#lines + 1] = string.format("слотов: %d | с атрибутами: %d | с питомцем: %d",
		#children, withAttrs, withPet)

	for index = 1, math.min(#children, 70) do
		local slot = children[index]
		local parts = {}

		local ok, attributes = pcall(function()
			return slot:GetAttributes()
		end)
		if ok and type(attributes) == "table" then
			for name, value in pairs(attributes) do
				parts[#parts + 1] = tostring(name) .. "=" .. tostring(value):sub(1, 26)
			end
		end

		if #parts == 0 then
			for _, child in ipairs(slot:GetChildren()) do
				local okChild, childAttributes = pcall(function()
					return child:GetAttributes()
				end)
				if okChild and type(childAttributes) == "table" then
					for name, value in pairs(childAttributes) do
						parts[#parts + 1] = tostring(child.Name):sub(1, 12) .. "."
							.. tostring(name) .. "=" .. tostring(value):sub(1, 18)
					end
				end
			end
		end

		local okPosition, position = pcall(function()
			return slot.Position
		end)
		if okPosition and position then
			local okXYZ = pcall(function()
				parts[#parts + 1] = string.format("pos=%.0f,%.0f,%.0f", position.X, position.Y, position.Z)
			end)
			if not okXYZ then
				-- не Vector3, пропускаем
			end
		end

		lines[#lines + 1] = string.format("%d) %s | детей %d | %s",
			index, tostring(slot.Name):sub(1, 20), #(slot:GetChildren()),
			table.concat(parts, ", "):sub(1, 170))

		-- тексты внутри слота (BillboardGui/TextLabel) — часто там имя/цена яйца
		local texts = {}
		local budget = 4
		local okDescendants, descendants = pcall(function()
			return slot:GetDescendants()
		end)
		for _, descendant in ipairs(okDescendants and descendants or {}) do
			if budget <= 0 then
				break
			end
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				local text = tostring(descendant.Text):gsub("\n", " ")
				if text ~= "" then
					budget = budget - 1
					texts[#texts + 1] = text:sub(1, 36)
				end
			end
		end
		if #texts > 0 then
			lines[#lines + 1] = "   текст: " .. table.concat(texts, " | ")
		end
	end
end

local function collectEggInspect()
	local lines = {}
	local function add(...)
		lines[#lines + 1] = string.format(...)
	end

	add("EGG INSPECT %s | Job %s", VERSION, tostring(game.JobId):sub(1, 8))
	add("")

	local eggs = collectEggs()
	add("яиц найдено: %d", #eggs)

	-- по одному лучшему яйцу на питомца
	local byPet = {}
	for _, egg in ipairs(eggs) do
		local key = tostring(egg.pet or egg.name)
		local entry = byPet[key]
		if not entry or (egg.income or 0) > (entry.income or 0) then
			byPet[key] = egg
		end
	end

	local list = {}
	for _, egg in pairs(byPet) do
		list[#list + 1] = egg
	end
	table.sort(list, function(a, b)
		return (a.income or 0) > (b.income or 0)
	end)

	add("")
	add("[ЯЙЦА]")
	for index = 1, math.min(12, #list) do
		local egg = list[index]
		add("%d) %s", index, shortPath(egg.instance, 70))
		add("   питомец %s | доход %s | биом %s | UID %s",
			tostring(egg.pet or "-"), formatNumber(egg.income or 0),
			tostring(egg.biome), tostring(egg.uid or "-"))
	end
	add("")

	local first = list[1]
	if first then
		add("=== Атрибуты яйца: %s ===", shortPath(first.instance, 80))

		local okAttrs, attributes = pcall(function()
			return first.instance:GetAttributes()
		end)
		if okAttrs and type(attributes) == "table" then
			local parts = {}
			for name, value in pairs(attributes) do
				parts[#parts + 1] = tostring(name) .. "=" .. tostring(value):sub(1, 34)
			end
			add("%s", table.concat(parts, ", "):sub(1, 900))
		end

		add("дерево (глубина 2):")
		describeInstance(first.instance, 1, lines, { left = 30 }, 2)
		add("")
	end

	add("[СЛОТЫ]")
	dumpSlots(lines)
	add("")

	add("[AREA SLOTS]")
	dumpAreaSlots(lines)
	add("")

	add("[КОНТЕЙНЕРЫ ЯИЦ]")
	for _, child in ipairs(workspace:GetChildren()) do
		if isEggName(child.Name) then
			add("%s (%s) | детей %d", tostring(child.Name), child.ClassName, #(child:GetChildren()))
			local shown = 0
			for _, sub in ipairs(child:GetChildren()) do
				if shown >= 8 then
					break
				end
				shown = shown + 1
				add("  %s (%s) | детей %d", tostring(sub.Name), sub.ClassName, #(sub:GetChildren()))
			end
		end
	end
	add("")

	add("[CONFIG]")
	dumpConfig(lines)
	add("")

	add("[ТРЕК]")
	dumpTrack(lines)

	local text = table.concat(lines, "\n")
	if #text > 20000 then
		text = text:sub(1, 20000) .. "\n... (обрезано)"
	end

	return text, #eggs
end

local function createStatusGui()
	if not CONFIG.SHOW_GUI then
		return
	end

	local ok, err = pcall(function()
		local parent = nil
		if gethui then
			local okHui, hui = pcall(gethui)
			if okHui and hui then
				parent = hui
			end
		end
		if not parent and LocalPlayer then
			parent = LocalPlayer:FindFirstChild("PlayerGui")
				or LocalPlayer:WaitForChild("PlayerGui", 5)
		end
		if not parent then
			parent = game:GetService("CoreGui")
		end

		local gui = Instance.new("ScreenGui")
		gui.Name = "EggScannerPanel"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 1000

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(300, 250)
		frame.Position = UDim2.fromOffset(10, 10)
		frame.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
		frame.BackgroundTransparency = 0.1
		frame.BorderSizePixel = 0
		frame.Active = true
		frame.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(60, 200, 120)
		stroke.Thickness = 1
		stroke.Transparency = 0.5
		stroke.Parent = frame

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.SourceSansBold
		title.TextSize = 13
		title.TextColor3 = Color3.fromRGB(120, 230, 150)
		title.Text = "EGG SCANNER " .. VERSION .. "  •  Steal An Egg"
		title.Parent = frame

		local status = Instance.new("TextLabel")
		status.Size = UDim2.new(1, -12, 0, 30)
		status.Position = UDim2.fromOffset(6, 24)
		status.BackgroundTransparency = 1
		status.Font = Enum.Font.SourceSansSemibold
		status.TextSize = 13
		status.TextWrapped = true
		status.TextXAlignment = Enum.TextXAlignment.Left
		status.TextYAlignment = Enum.TextYAlignment.Top
		status.TextColor3 = Color3.fromRGB(255, 220, 120)
		status.Text = "Запуск..."
		status.Parent = frame

		local logLabel = Instance.new("TextLabel")
		logLabel.Size = UDim2.new(1, -12, 0, 138)
		logLabel.Position = UDim2.fromOffset(6, 56)
		logLabel.BackgroundTransparency = 1
		logLabel.Font = Enum.Font.SourceSans
		logLabel.TextSize = 12
		logLabel.TextWrapped = true
		logLabel.TextXAlignment = Enum.TextXAlignment.Left
		logLabel.TextYAlignment = Enum.TextYAlignment.Top
		logLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
		logLabel.Text = ""
		logLabel.Parent = frame

		local buttons = Instance.new("Frame")
		buttons.Size = UDim2.new(1, 0, 0, 34)
		buttons.Position = UDim2.fromOffset(0, 206)
		buttons.BackgroundTransparency = 1
		buttons.Parent = frame

		makeButton(buttons, "Скан", 4, 54, function()
			if UI.actions.scan then
				UI.actions.scan()
			end
		end)

		makeButton(buttons, "Хоп", 63, 54, function()
			if UI.actions.hop then
				UI.actions.hop()
			end
		end)

		makeButton(buttons, "Яйцо", 122, 54, function()
			if UI.actions.egg then
				UI.actions.egg()
			end
		end)

		makeButton(buttons, "Дамп", 181, 54, function()
			if UI.actions.dump then
				UI.actions.dump()
			end
		end)

		makeButton(buttons, "Стоп", 240, 54, function()
			if UI.actions.stop then
				UI.actions.stop()
			end
		end)

		-- перетаскивание за заголовок (работает и на тач-экране)
		local dragging, dragStart, startPosition = false, nil, nil

		title.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPosition = frame.Position

				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				frame.Position = UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + delta.X,
					startPosition.Y.Scale,
					startPosition.Y.Offset + delta.Y
				)
			end
		end)

		gui.Parent = parent
		UI.gui = gui
		UI.frame = frame
		UI.status = status
		UI.logLabel = logLabel
		refreshLog()
	end)

	if not ok then
		warn(PREFIX, "GUI не создан: " .. tostring(err))
	end
end

-- Остановка по RightShift (на телефоне есть кнопка «Стоп»)
pcall(function()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.RightShift then
			running = false
			setStatus("Остановлено")
			if getgenv then
				getgenv().__EGG_SCANNER_RUNNING = nil
			end
			addLog("Остановлено с клавиатуры")
		end
	end)
end)

--============================= ГЛАВНЫЙ ЦИКЛ =================================--

local function waitForGame(timeout)
	local deadline = os.clock() + (timeout or 30)
	while not game:IsLoaded() and os.clock() < deadline do
		task.wait(0.25)
	end
end

local function main()
	log(string.format(
		"%s запущен. PlaceId=%d, порог=%s (%s)",
		VERSION, CONFIG.PLACE_ID, formatNumber(CONFIG.THRESHOLD), CONFIG.THRESHOLD_MODE
	))
	if CONFIG.WEBHOOK_URL == "" then
		warn("WEBHOOK_URL не задан — уведомления будут только на экране")
	end

	setStatus("Ожидание загрузки карты...")
	waitForGame(30)

	-- даём игре прогрузить объекты
	task.wait(CONFIG.SCAN_INTERVAL)

	local failedHops = 0
	local scansOnThisServer = 0
	local lastJob = game.JobId

	while running do
		local ok, err = pcall(function()
			if game.JobId ~= lastJob then
				lastJob = game.JobId
				scansOnThisServer = 0
			end
			scansOnThisServer = scansOnThisServer + 1

			setStatus("Сканирование сервера...")

			local best, types, truncated, scanned, allEggs, eggCount, ranked = scanServer()

			local hash = eggFingerprint(allEggs or {})
			addLog(string.format(
				"Сервер %s | объектов %d | яиц %d | типов %d | хэш %s",
				tostring(game.JobId):sub(1, 8), scanned, eggCount or 0, types, hash
			))

			local biomesSeen, biomeList = {}, {}
			for _, egg in ipairs(allEggs or {}) do
				local biomeName = tostring(egg.biome or "?")
				if not biomesSeen[biomeName] then
					biomesSeen[biomeName] = true
					biomeList[#biomeList + 1] = biomeName
				end
			end
			if #biomeList > 0 then
				addLog("Биомы: " .. table.concat(biomeList, ", "):sub(1, 90))
			end

			if truncated then
				log("Скан остановлен лимитом MAX_SCAN_OBJECTS — возможно, карта слишком большая")
			end

			if best then
				log(string.format(
					"Топ: %s [%s] | Income=%s | питомец=%s | типов: %d",
					best.name, tostring(best.biome),
					formatNumber(best.income),
					tostring(best.pet or "-"),
					types
				))

				for index = 2, math.min(3, #(ranked or {})) do
					local item = ranked[index]
					log(string.format("  #%d %s [%s] %s | %s",
						index, item.name, tostring(item.biome),
						formatNumber(item.score), tostring(item.pet or "-")))
				end
				setStatus(string.format(
					"Топ: %s [%s]\n%s | UID %s\nJobId: %s",
					best.name, tostring(best.biome), formatNumber(best.score),
					tostring(best.uid or "-"), tostring(game.JobId)
				))
			else
				log("Яйца не найдены (типов: " .. tostring(types) .. ")")
				setStatus("Яйца не найдены\nJobId: " .. tostring(game.JobId))
			end

			local valuable, metric = isValuable(best)

			if valuable then
				if alreadyReported(best) then
					log("Это яйцо с этого сервера уже отправлялось — вебхук пропущен")
					task.wait(CONFIG.SCAN_INTERVAL)
				else
					if sendWebhook(best, metric) then
						markReported(best)
					end
					task.wait(CONFIG.WEBHOOK_MIN_GAP)
				end
			else
				-- пусто: небольшая случайная пауза перед хопом
				task.wait(math.random(CONFIG.IDLE_WAIT_MIN, CONFIG.IDLE_WAIT_MAX))
			end

			if not running then
				return
			end

			setStatus("Хоп на другой сервер...")
			local hopped = hopServer(valuable and "найдено топ-яйцо" or "пустой сервер")

			if not hopped then
				failedHops = failedHops + 1
				local backoff = math.min(60, 5 * failedHops)
				warn(PREFIX, string.format(
					"Хоп не удался (%d подряд). Пауза %d сек", failedHops, backoff
				))
				task.wait(backoff)
			else
				failedHops = 0
				-- если телепорт всё-таки не случился, не долбим сервер и API сразу
				if scansOnThisServer >= 3 then
					warn(PREFIX, "Телепорт не срабатывает (JobId не меняется) — пауза 30 сек")
					task.wait(30)
				else
					task.wait(5)
				end
			end
		end)

		if not ok then
			warn(PREFIX, "Ошибка в главном цикле: " .. tostring(err))
			setStatus("Ошибка: " .. tostring(err))
			task.wait(5)
		end
	end

	setStatus("Скрипт остановлен")
	log("Завершено")
end

--=========================== КНОПКИ ПАНЕЛИ ==================================--

UI.actions.scan = function()
	setStatus("Ручной скан...")
	local best, types, truncated, scanned = scanServer()
	addLog(string.format("Скан: объектов %d, типов %d", scanned, types))
	if best then
		addLog(string.format("Топ: %s = %s", best.name, formatNumber(best.score)))
		setStatus(string.format("Топ: %s\n%s", best.name, formatNumber(best.score)))
	else
		addLog("Яиц с Value/Income нет — нажми «Дамп»")
		setStatus("Яиц не найдено")
	end
end

UI.actions.hop = function()
	setStatus("Ручной хоп...")
	local hopped = hopServer("вручную")
	addLog(hopped and "Хоп запущен" or "Хоп не удался")
end

UI.actions.dump = function()
	setStatus("Разведка карты...")
	addLog("Собираю разведку (10-30 сек)...")

	local text, scanned, uniqueEggNames = collectRecon()

	addLog(string.format("Разведка: объектов %d, egg-имён %d", scanned, uniqueEggNames))

	if writefile then
		pcall(writefile, "egg_recon.txt", text)
	end

	deliverReport(text, "RECON")
end

UI.actions.egg = function()
	setStatus("Инспектор яйца...")
	addLog("Разбираю яйцо и модули Data...")

	local text, samples = collectEggInspect()

	addLog(string.format("Инспектор: образцов %d", samples))

	if writefile then
		pcall(writefile, "egg_inspect.txt", text)
	end

	deliverReport(text, "EGG INSPECT")
end

UI.actions.stop = function()
	running = false
	setStatus("Остановлено")
	if getgenv then
		getgenv().__EGG_SCANNER_RUNNING = nil
	end
	addLog("Остановлено кнопкой")
end

--=============================== АВТОЗАПУСК =================================--

local isTest = getgenv and getgenv().__EGG_SCANNER_TEST

if isTest then
	getgenv().__EGG_SCANNER_API = {
		CONFIG       = CONFIG,
		VERSION      = VERSION,
		parseNumber  = parseNumber,
		formatNumber = formatNumber,
		readStat     = readStat,
		collectEggs  = collectEggs,
		scanServer   = scanServer,
		isValuable   = isValuable,
		pickServer   = pickServer,
		getServers   = getServers,
		hopServer    = hopServer,
		sendWebhook  = sendWebhook,
		collectRecon = collectRecon,
		eggFingerprint = eggFingerprint,
		collectEggInspect = collectEggInspect,
		uploadText   = uploadText,
		deliverReport = deliverReport,
	}
	return
end

-- Панель создаём ДО цикла: даже если что-то упадёт, ошибка будет видна на экране
createStatusGui()
addLog(VERSION .. " загружен")
setStatus("Инициализация...")

pcall(function()
	game:GetService("StarterGui"):SetCore("SendNotification", {
		Title = "Egg Scanner " .. VERSION,
		Text = "Скрипт запущен, панель слева сверху",
		Duration = 5,
	})
end)

task.spawn(function()
	local ok, err = xpcall(main, function(exception)
		return tostring(exception) .. "\n" .. debug.traceback("", 2)
	end)

	if not ok then
		addLog("ОШИБКА: " .. tostring(err):sub(1, 220))
		setStatus("Ошибка — смотри лог")
		if rconsoleprint then
			pcall(rconsoleprint, tostring(err) .. "\n")
		end
	end
end)
