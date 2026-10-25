--[[
================================================================================
    EGG SCANNER — загрузчик (для телефона: вставлять ТОЛЬКО это, ~30 строк)
    Кладёт в исполнитель полный скрипт с GitHub.

    Если ничего не происходит:
      - полностью закрой Roblox (сбросить старые флаги запуска) и попробуй снова;
      - ошибка загрузки теперь показывается прямо на экране.
================================================================================
]]

local STAMP = tostring(os.time())

local URLS = {
	-- raw обновляется мгновенно, ?v= сбрасывает кэш CDN GitHub
	"https://raw.githubusercontent.com/karakodil/keyskoziks/egg-scanner/StealAnEggScanner.lua?v=" .. STAMP,
	-- запасное зеркало, если raw блокируется
	"https://cdn.jsdelivr.net/gh/karakodil/keyskoziks@egg-scanner/StealAnEggScanner.lua",
	"https://raw.githubusercontent.com/karakodil/keyskoziks/cline/r1zh20je/StealAnEggScanner.lua?v=" .. STAMP,
}

local function fetch(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" and #body > 1000 then
		return body
	end

	local requestFn = (syn and syn.request) or (http and http.request) or http_request or request
	if requestFn then
		local okReq, response = pcall(requestFn, { Url = url, Method = "GET" })
		if okReq and type(response) == "table" then
			local body2 = response.Body or response.body
			if type(body2) == "string" and #body2 > 1000 then
				return body2
			end
		end
	end

	return nil
end

local function showError(message)
	warn("[EggScanner] " .. message)
	pcall(function()
		local parent = (gethui and gethui()) or game:GetService("CoreGui")
		local gui = Instance.new("ScreenGui")
		gui.Name = "EggScannerLoadError"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 2000

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(300, 120)
		frame.Position = UDim2.fromOffset(10, 10)
		frame.BackgroundColor3 = Color3.fromRGB(60, 12, 12)
		frame.BorderSizePixel = 0
		frame.Parent = gui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -12, 1, -12)
		label.Position = UDim2.fromOffset(6, 6)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.SourceSans
		label.TextSize = 12
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.TextColor3 = Color3.fromRGB(255, 190, 190)
		label.Text = "EggScanner не загрузился:\n" .. tostring(message)
		label.Parent = frame

		gui.Parent = parent
	end)
end

local errors = {}

for _, url in ipairs(URLS) do
	local source = fetch(url)

	if source then
		local chunk, compileError = loadstring(source)

		if chunk then
			local ran, runError = pcall(chunk)
			if ran then
				return
			end
			table.insert(errors, url:sub(1, 30) .. ": " .. tostring(runError))
		else
			table.insert(errors, url:sub(1, 30) .. ": " .. tostring(compileError))
		end
	else
		table.insert(errors, url:sub(1, 30) .. ": нет ответа (блокировка/CDN?)")
	end
end

showError(table.concat(errors, "\n"))
