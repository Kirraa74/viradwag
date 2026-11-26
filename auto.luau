if not game:IsLoaded() then
	game.Loaded:Wait()
end

local RS = game:GetService("ReplicatedStorage")
local TS = game:GetService("TeleportService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Http = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

local LP = Players.LocalPlayer
while not LP do
	Players.PlayerAdded:Wait()
	LP = Players.LocalPlayer
end
if not LP.Character then
	LP.CharacterAdded:Wait()
end

local RemoteFolder = RS:WaitForChild("Remote")
local MarketRemote = RemoteFolder:WaitForChild("PlayerMarketService")
local SearchIndex = MarketRemote:WaitForChild("SearchIndex")
local PurchaseRemote = MarketRemote:WaitForChild("Purchase")

local TradeRemote = RemoteFolder:WaitForChild("Trade")
local RequestNotice = TradeRemote:WaitForChild("RequestNotice")
local RequestAccept = TradeRemote:WaitForChild("RequestAccept")
local StartEvent = TradeRemote:WaitForChild("Start")
local CloseEvent = TradeRemote:WaitForChild("Close")
local CancelNotice = TradeRemote:WaitForChild("CancelNotice")
local SelectRemote = TradeRemote:WaitForChild("Select")
local SetConfirm = TradeRemote:WaitForChild("SetConfirm")
local ReadyRemote = TradeRemote:WaitForChild("Ready")

local CONFIG_JSON_FILE = "kirraa74_market_config.json"
local UNIFIED_CONFIG_FILE = "kirraa74_config.txt"
local TRADE_SWITCH_FILE = "kirraa74_autotrade_switch.txt"
local FORCE_TRADE_ON_FILE = "kirraa74_force_trade_on.txt"

local UI_NAME = "Kirraa74MarketUI"
local MAX_SEEN = 100
local FAILED_COOLDOWN = 120
local MAX_LOT_WAIT = 95
local PENDING_RETRY = 0.5
local TRADE_SAFETY_TIMEOUT = 45

local DEFAULT_TARGETS = {
	["Exotic.Rainbow.AWP"] = 2000,
	["Exotic.Rainbow.AX-50"] = 2000,
	["Exotic.Rainbow.Crossbow"] = 2000,
	["Exotic.Rainbow.DSR1"] = 2000,
	["Exotic.Rainbow.GM6"] = 2000,
	["Exotic.Rainbow.Kar98k"] = 2000,
	["Exotic.Rainbow.Lucas"] = 2000,
	["Exotic.Rainbow.M200"] = 2000,
	["Exotic.Rainbow.M82A1"] = 2000,
	["Exotic.Rainbow.Marlin"] = 2000,
	["Exotic.Rainbow.NTW20"] = 2000,
	["Exotic.Rainbow.R11"] = 2000,
	["Exotic.Rainbow.Specter"] = 2000,
	["Exotic.Rainbow.SSG"] = 2000,
	["Exotic.Rainbow.WA2000"] = 2000,
	["Exotic.Prismatica_Solstice.M82A1"] = 6000,
	["Exotic.Eternium.Lucas"] = 2000,
	["Exotic.Flarion.Lucas"] = 2000,
	["Exotic.NeonCore_Cyan.NTW20"] = 2000,
	["Exotic.NeonCore_Purple.NTW20"] = 2000,
	["Exotic.NeonCore_Holo.NTW20"] = 2000,
	["Exotic.Hacker.AWP"] = 2000,
	["Exotic.Hacker_Red.AWP"] = 2000,
	["Exotic.Hacker_Purple.AWP"] = 2000,
	["Exotic.Hacker.M82A1"] = 2000,
	["Exotic.Hacker_Red.M82A1"] = 2000,
	["Exotic.Hacker_Purple.M82A1"] = 2000,
	["Exotic.Hacker.Specter"] = 2000,
	["Exotic.Hacker_Red.Specter"] = 2000,
	["Exotic.Hacker_Purple.Specter"] = 2000,
	["Exotic.Hacker.Marlin"] = 2000,
	["Exotic.Hacker_Red.Marlin"] = 2000,
	["Exotic.Hacker_Purple.Marlin"] = 2000,
	["Exotic.Hacker.Wakizashi"] = 2000,
	["Exotic.Hacker_Red.Wakizashi"] = 2000,
	["Exotic.Hacker_Purple.Wakizashi"] = 2000,
	["Exotic.Hacker.Karambit"] = 2000,
	["Exotic.Hacker_Red.Karambit"] = 2000,
	["Exotic.Hacker_Purple.Karambit"] = 2000,
	["Exotic.Hacker.Glove"] = 2000,
	["Exotic.Hacker_Red.Glove"] = 2000,
	["Exotic.Hacker_Purple.Glove"] = 2000,
	["Exotic.Hacker.Punisher"] = 2000,
	["Exotic.Hacker_Purple.Punisher"] = 2000,
	["Exotic.Hacker_Red.Punisher"] = 2000,
	["Exotic.Starborne.Punisher"] = 2000,
	["Exotic.Starry.Punisher"] = 2000,
	["Exotic.Starlight.Punisher"] = 2000,
	["Exotic.Starfade.Punisher"] = 2000,
	["Exotic.Starember.Punisher"] = 2000,
	["Exotic.NeonCore_Cyan.Punisher"] = 2000,
	["Exotic.NeonCore_Holo.Punisher"] = 2000,
	["Exotic.NeonCore_Purple.Punisher"] = 2000,
	["Exotic.AbyssPrism.M82A1"] = 2000,
	["Exotic.Starember.GM6"] = 2000,
	["Exotic.Starry.WA2000"] = 2000,
	["Exotic.US_2026_Black.R11"] = 2000,
	["Exotic.US_2026_Black.M82A1"] = 2000,
	["Exotic.Starfade.ButterflyKnife"] = 2000,
	["Exotic.Starfade.AWP"] = 2000,
	["Exotic.NeonCore_Holo.Fan"] = 2000,
}

local function hasIO()
	return typeof(writefile) == "function"
		and typeof(readfile) == "function"
		and typeof(isfile) == "function"
end

local function readRawFile(path)
	if not hasIO() then
		return nil
	end
	local okEx, exists = pcall(isfile, path)
	if not okEx or not exists then
		return nil
	end
	local okRd, raw = pcall(readfile, path)
	if okRd and type(raw) == "string" then
		return string.gsub(raw, "^\239\187\191", "")
	end
	return nil
end

local function parseUnifiedConfig()
	local alts = {}
	local targets = {}
	local targetCount = 0
	local skinLines = {}

	local raw = readRawFile(UNIFIED_CONFIG_FILE)
	if not raw then
		return alts, nil, 0, ""
	end

	local section = nil
	for line in string.gmatch(raw, "[^\r\n]+") do
		local clean = string.match(line, "^%s*(.-)%s*$")
		if clean ~= "" and string.sub(clean, 1, 1) ~= "#" and string.sub(clean, 1, 2) ~= "//" and string.sub(clean, 1, 1) ~= ";" then
			local sec = string.match(clean, "^%[(.+)%]$")
			if sec then
				section = string.upper(string.match(sec, "^%s*(.-)%s*$"))
			elseif section == "ACCOUNTS" then
				local nick = string.match(clean, "^([^:%s]+)")
				if nick and nick ~= "" and string.lower(nick) ~= string.lower(LP.Name) then
					alts[string.lower(nick)] = true
				end
			elseif section == "SKINS" then
				local name, priceStr = string.match(clean, "^(.-)%s*[=:]%s*(%d+)%s*$")
				if not name then
					name, priceStr = string.match(clean, "^(%S+)%s+(%d+)%s*$")
				end
				if not name then
					name = string.match(clean, "^(%S+)%s*$")
					priceStr = "2000"
				end
				local price = tonumber(priceStr)
				if name and name ~= "" and price and price > 0 then
					targets[name] = price
					targetCount += 1
					table.insert(skinLines, name .. "=" .. tostring(price))
				end
			end
		end
	end

	table.sort(skinLines)
	return alts, (targetCount > 0 and targets or nil), targetCount, table.concat(skinLines, ";")
end

local function cloneTargets(src)
	local copy = {}
	for k, v in pairs(src) do
		copy[k] = v
	end
	return copy
end

local staleTradeUuids = {}

local function normalizeName(str)
	if type(str) ~= "string" then
		return ""
	end
	str = string.gsub(str, "^[^%.]+%.", "")
	str = string.lower(str)
	str = string.gsub(str, "[%s_%-%.]", "")
	return str
end

local function safeGetName(tbl)
	local ok, val = pcall(function()
		return rawget(tbl, "Name")
	end)
	if ok and type(val) == "string" and val ~= "" then
		return val
	end
	return nil
end

local function isUuidKey(k)
	return type(k) == "string" and #k >= 20 and string.sub(k, -2) == "=="
end

local function findAllTargetSkins(targets)
	local normTargets = {}
	for key, val in pairs(targets) do
		local rawName = (type(key) == "string") and key or val
		if type(rawName) == "string" and val ~= false then
			normTargets[normalizeName(rawName)] = true
		end
	end

	local results = {}
	local seen = {}

	if typeof(getgc) ~= "function" then
		return results
	end

	for _, parentTbl in ipairs(getgc(true)) do
		if type(parentTbl) == "table" then
			pcall(function()
				for k, v in pairs(parentTbl) do
					if type(v) == "table" then
						local uuid = isUuidKey(k) and k or (rawget(v, "Key") or rawget(v, "UUID"))
						if type(uuid) == "string" and isUuidKey(uuid) and not seen[uuid] and not staleTradeUuids[uuid] then
							local skinName = safeGetName(v)
							if skinName and (targets[skinName] or normTargets[normalizeName(skinName)]) then
								seen[uuid] = true
								table.insert(results, { uuid = uuid, name = skinName })
							end
						end
					end
				end
			end)
		end
	end

	return results
end

local RUN_TOKEN = Http:GenerateGUID(false)
getgenv().KIRRAA74_MARKET_TOKEN = RUN_TOKEN

local function isActive()
	return getgenv().KIRRAA74_MARKET_TOKEN == RUN_TOKEN
end

local _, parsedTargets, _, initialSkinsSig = parseUnifiedConfig()

local State = {
	lastConfigSkinsSig = initialSkinsSig,
	lastForceToken = "",
	running = false,
	autoBuy = true,
	autoTeleport = true,
	autoTrade = true,
	soundAlert = true,
	inTrade = false,
	tradeStartedAt = 0,
	skinDelay = 2.5,
	loopDelay = 3.0,
	tpWait = 5.0,
	tpCooldown = 90,
	buyRetries = 1,
	minPrice = 1,
	prioritySkin = nil,
	priorityPasses = 0,
	foundCount = 0,
	boughtCount = 0,
	hotkey = "RightShift",
	seenEntries = {},
	seenOrder = {},
	badJobIds = {},
	failedEntryIds = {},
	pendingLots = {},
	targets = parsedTargets or cloneTargets(DEFAULT_TARGETS),
}

local logLabel, logScroll, pageLogs, statusLabel, statusDot, foundLabel, boughtLabel, toggleRunBtn, tradeToggleBtn, refreshTargetsUI
local settingsRefreshers = {}

local alertSound = Instance.new("Sound")
alertSound.Name = "Kirraa74BuyAlert"
alertSound.SoundId = "rbxassetid://4590662766"
alertSound.Volume = 0.6
alertSound.Parent = SoundService

local function jitter(base)
	return base + (0.05 + math.random() * 0.20)
end

local function syncTradeSwitchFile()
	if typeof(writefile) == "function" then
		pcall(writefile, TRADE_SWITCH_FILE, State.autoTrade and "1" or "0")
	end
end

local function readNum(val, minV, maxV, isInt)
	local n = tonumber(val)
	if not n then
		return nil
	end
	if isInt then
		n = math.floor(n)
	end
	if minV then
		n = math.max(minV, n)
	end
	if maxV then
		n = math.min(maxV, n)
	end
	return n
end

local function updateCounters()
	if foundLabel then
		foundLabel.Text = "Найдено: " .. State.foundCount
	end
	if boughtLabel then
		boughtLabel.Text = "Куплено: " .. State.boughtCount
	end
end

local function scrollLogs()
	if logScroll and pageLogs and pageLogs.Visible then
		task.defer(function()
			if logScroll and isActive() then
				logScroll.CanvasPosition = Vector2.new(0, math.max(0, logScroll.AbsoluteCanvasSize.Y))
			end
		end)
	end
end

local function pushLog(text)
	if not isActive() then
		return
	end
	local line = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(text))
	print(line)
	if logLabel then
		logLabel.Text = logLabel.Text == "" and line or (logLabel.Text .. "\n" .. line)
		local lines = string.split(logLabel.Text, "\n")
		if #lines > 140 then
			table.remove(lines, 1)
			logLabel.Text = table.concat(lines, "\n")
		end
		scrollLogs()
	end
end

local function setStatus(text, color)
	if not isActive() then
		return
	end
	if statusLabel then
		statusLabel.Text = text
		if color then
			statusLabel.TextColor3 = color
		end
	end
	if statusDot and color then
		statusDot.BackgroundColor3 = color
	end
end

local function refreshAllSettingsUI()
	for _, fn in ipairs(settingsRefreshers) do
		fn()
	end
end

local function markSeen(key)
	if State.seenEntries[key] then
		return false
	end
	State.seenEntries[key] = true
	table.insert(State.seenOrder, key)
	if #State.seenOrder > MAX_SEEN then
		local old = table.remove(State.seenOrder, 1)
		if old then
			State.seenEntries[old] = nil
		end
	end
	return true
end

local function isCooldown(tbl, key)
	local t = tbl[key]
	if not t then
		return false
	end
	if os.clock() >= t then
		tbl[key] = nil
		return false
	end
	return true
end

local function saveConfig(overrideRun)
	syncTradeSwitchFile()
	if not hasIO() then
		return
	end
	local ok, enc = pcall(Http.JSONEncode, Http, {
		running = (overrideRun ~= nil) and overrideRun or State.running,
		foundCount = State.foundCount,
		boughtCount = State.boughtCount,
		prioritySkin = State.prioritySkin,
		hotkey = State.hotkey,
		seenOrder = State.seenOrder,
		autoBuy = State.autoBuy,
		autoTeleport = State.autoTeleport,
		autoTrade = State.autoTrade,
		soundAlert = State.soundAlert,
		skinDelay = State.skinDelay,
		loopDelay = State.loopDelay,
		tpWait = State.tpWait,
		tpCooldown = State.tpCooldown,
		buyRetries = State.buyRetries,
		minPrice = State.minPrice,
		targets = State.targets,
		lastConfigSkinsSig = State.lastConfigSkinsSig,
		lastForceToken = State.lastForceToken,
	})
	if ok and type(enc) == "string" then
		pcall(writefile, CONFIG_JSON_FILE, enc)
	end
end

local function setRunning(val, save)
	State.running = val
	if toggleRunBtn and isActive() then
		toggleRunBtn.Text = val and "СТОП" or "СТАРТ"
		toggleRunBtn.BackgroundColor3 = val and Color3.fromRGB(214, 69, 80) or Color3.fromRGB(34, 197, 94)
		if not State.inTrade then
			setStatus(
				val and "ПОИСК" or "ПАУЗА",
				val and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(148, 163, 184)
			)
		end
	end
	if save then
		saveConfig()
	end
end

local function loadConfig()
	if not hasIO() then
		syncTradeSwitchFile()
		return false
	end

	local currentForceToken = readRawFile(FORCE_TRADE_ON_FILE) or ""
	currentForceToken = string.match(currentForceToken, "^%s*(.-)%s*$") or ""

	local eOk, exists = pcall(isfile, CONFIG_JSON_FILE)
	if not eOk or not exists then
		State.lastForceToken = currentForceToken
		syncTradeSwitchFile()
		return false
	end
	local rOk, raw = pcall(readfile, CONFIG_JSON_FILE)
	if not rOk or type(raw) ~= "string" then
		State.lastForceToken = currentForceToken
		syncTradeSwitchFile()
		return false
	end
	local dOk, d = pcall(Http.JSONDecode, Http, raw)
	if not dOk or type(d) ~= "table" then
		State.lastForceToken = currentForceToken
		syncTradeSwitchFile()
		return false
	end

	if type(d.autoBuy) == "boolean" then State.autoBuy = d.autoBuy end
	if type(d.autoTeleport) == "boolean" then State.autoTeleport = d.autoTeleport end
	if type(d.autoTrade) == "boolean" then State.autoTrade = d.autoTrade end
	if type(d.soundAlert) == "boolean" then State.soundAlert = d.soundAlert end
	if type(d.lastForceToken) == "string" then State.lastForceToken = d.lastForceToken end

	-- Включаем ТРЕЙД автоматически только если пришёл новый сигнал запуска start.bat
	local forceApplied = false
	if currentForceToken ~= "" and currentForceToken ~= State.lastForceToken then
		State.lastForceToken = currentForceToken
		State.autoTrade = true
		forceApplied = true
	end

	State.skinDelay = readNum(d.skinDelay, 0.05) or State.skinDelay
	State.loopDelay = readNum(d.loopDelay, 0.05) or State.loopDelay
	State.tpWait = readNum(d.tpWait, 1) or State.tpWait
	State.tpCooldown = readNum(d.tpCooldown, 5) or State.tpCooldown
	State.buyRetries = readNum(d.buyRetries, 0, 5, true) or State.buyRetries
	State.minPrice = readNum(d.minPrice, 0) or State.minPrice
	State.foundCount = readNum(d.foundCount, 0) or State.foundCount
	State.boughtCount = readNum(d.boughtCount, 0) or State.boughtCount

	if type(d.prioritySkin) == "string" and d.prioritySkin ~= "" then
		State.prioritySkin = d.prioritySkin
		State.priorityPasses = 0
	end
	if type(d.hotkey) == "string" and Enum.KeyCode[d.hotkey] then
		State.hotkey = d.hotkey
	end
	if type(d.seenOrder) == "table" then
		State.seenEntries = {}
		State.seenOrder = {}
		for _, k in ipairs(d.seenOrder) do
			if type(k) == "string" then
				markSeen(k)
			end
		end
	end

	-- Сохраняем пользовательские цены из меню при телепортах;
	-- перезагружаем из config.txt только если [SKINS] в файле реально изменился
	local savedTargets = nil
	if type(d.targets) == "table" then
		local clean = {}
		for k, v in pairs(d.targets) do
			local n = tonumber(v)
			if type(k) == "string" and k ~= "" and n and n > 0 then
				clean[k] = n
			end
		end
		if next(clean) then
			savedTargets = clean
		end
	end

	local _, txtTargets, _, txtSig = parseUnifiedConfig()
	local savedSig = type(d.lastConfigSkinsSig) == "string" and d.lastConfigSkinsSig or ""

	if savedTargets and (txtSig == "" or txtSig == savedSig) then
		State.targets = savedTargets
		State.lastConfigSkinsSig = savedSig ~= "" and savedSig or txtSig
	elseif txtTargets then
		State.targets = txtTargets
		State.lastConfigSkinsSig = txtSig
	elseif savedTargets then
		State.targets = savedTargets
	end

	syncTradeSwitchFile()
	if forceApplied then
		saveConfig()
	end

	if refreshTargetsUI then
		refreshTargetsUI()
	end
	refreshAllSettingsUI()
	updateCounters()
	pushLog(string.format("Конфиг загружен | ТРЕЙД: %s | Найдено: %d | Куплено: %d", State.autoTrade and "ВКЛ" or "ВЫКЛ", State.foundCount, State.boughtCount))
	return d.running == true
end

local function findSeller(item)
	if typeof(item.Seller) == "Instance" and item.Seller:IsA("Player") then
		return item.Seller
	end
	for _, f in ipairs({ "SellerUserId", "OwnerId", "UserId", "PlayerId" }) do
		local uid = tonumber(item[f])
		if uid then
			return Players:GetPlayerByUserId(uid)
		end
	end
	for _, f in ipairs({ "SellerName", "OwnerName", "PlayerName", "Seller" }) do
		if type(item[f]) == "string" then
			local p = Players:FindFirstChild(item[f])
			if p then
				return p
			end
		end
	end
	return nil
end

local function getSellerName(item)
	local p = findSeller(item)
	if p then
		return p.Name
	end
	for _, f in ipairs({ "SellerName", "SellerDisplayName", "OwnerName", "PlayerName", "Username", "Seller" }) do
		if type(item[f]) == "string" and item[f] ~= "" then
			return item[f]
		end
	end
	local uid = tonumber(item.SellerUserId or item.OwnerId or item.UserId)
	return uid and ("ID:" .. uid) or "Неизвестно"
end

local function finishTradeState(reason)
	if not State.inTrade then
		return
	end
	State.inTrade = false
	State.tradeStartedAt = 0
	pushLog("[ТРЕЙД] " .. reason)
	setStatus(
		State.running and "ПОИСК" or "ПАУЗА",
		State.running and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(148, 163, 184)
	)
end

local function callReadyRemote()
	if ReadyRemote:IsA("RemoteFunction") then
		return pcall(ReadyRemote.InvokeServer, ReadyRemote)
	elseif ReadyRemote:IsA("RemoteEvent") then
		return pcall(ReadyRemote.FireServer, ReadyRemote)
	end
	return false, "unsupported remote type"
end

RequestNotice.OnClientEvent:Connect(function(sender)
	if not isActive() or not State.autoTrade then
		return
	end
	local senderName = typeof(sender) == "Instance" and sender.Name or tostring(sender)
	local allowedAlts = parseUnifiedConfig()
	if sender and sender ~= LP and allowedAlts[string.lower(senderName)] then
		State.inTrade = true
		State.tradeStartedAt = os.clock()
		setStatus("ТРЕЙД", Color3.fromRGB(244, 114, 182))
		pushLog("[ТРЕЙД] Принимаю запрос от твинка: " .. senderName)
		task.wait(0.35)
		if not isActive() or not State.autoTrade then
			finishTradeState("Отменено: авто-трейд выключен")
			return
		end
		local ok, err = pcall(function()
			RequestAccept:InvokeServer(sender)
		end)
		if not ok then
			pushLog("[ТРЕЙД] Ошибка принятия: " .. tostring(err))
			finishTradeState("Сброшен после ошибки принятия")
		end
	end
end)

StartEvent.OnClientEvent:Connect(function()
	if not isActive() or not State.autoTrade then
		return
	end
	State.inTrade = true
	State.tradeStartedAt = os.clock()
	local openedAt = os.clock()
	setStatus("ТРЕЙД", Color3.fromRGB(244, 114, 182))
	pushLog("[ТРЕЙД] Окно открыто -> кладу 1 скин из целей...")

	task.spawn(function()
		task.wait(0.5)
		if not isActive() or not State.inTrade or not State.autoTrade then
			return
		end

		local placed = false
		local lastErr = "нет подходящих скинов"

		for attempt = 1, 3 do
			if not isActive() or not State.inTrade or not State.autoTrade then
				return
			end

			local candidates = findAllTargetSkins(State.targets)
			if #candidates == 0 and next(staleTradeUuids) ~= nil then
				staleTradeUuids = {}
				candidates = findAllTargetSkins(State.targets)
			end

			for _, skin in ipairs(candidates) do
				if not isActive() or not State.inTrade or not State.autoTrade then
					return
				end
				local okSel, resSel = pcall(function()
					return SelectRemote:InvokeServer(1, skin.uuid, true)
				end)
				if okSel and resSel ~= false and resSel ~= nil then
					pushLog(string.format("[ТРЕЙД] Положен скин: %s (попытка %d)", tostring(skin.name), attempt))
					placed = true
					break
				else
					lastErr = string.format("%s -> ok=%s, res=%s", tostring(skin.name), tostring(okSel), tostring(resSel))
					if attempt >= 2 then
						staleTradeUuids[skin.uuid] = true
					end
					task.wait(0.1)
				end
			end

			if placed then
				break
			end
			task.wait(0.25)
		end

		if not placed then
			pushLog("[ТРЕЙД] Скин не положен (" .. lastErr .. ")")
		end

		local waitToConfirm = math.max(0.2, 1.5 - (os.clock() - openedAt))
		task.wait(waitToConfirm)
		if not isActive() or not State.inTrade or not State.autoTrade then
			return
		end

		pcall(function()
			SetConfirm:InvokeServer(true)
		end)
		task.wait(0.45)
		if not isActive() or not State.inTrade or not State.autoTrade then
			return
		end
		pcall(function()
			SetConfirm:InvokeServer(true)
		end)
		task.wait(0.4)

		local deadline = os.clock() + 20
		while isActive() and State.inTrade and State.autoTrade and os.clock() < deadline do
			local okR, resR = callReadyRemote()
			if okR and resR == false then
				pcall(function()
					SetConfirm:InvokeServer(true)
				end)
			end
			task.wait(0.8)
		end
	end)
end)

CloseEvent.OnClientEvent:Connect(function()
	if isActive() then
		finishTradeState("Трейд закрыт")
	end
end)

CancelNotice.OnClientEvent:Connect(function()
	if isActive() then
		finishTradeState("Трейд отменён")
	end
end)

-- ============================================================================
-- UI ОСНОВЫ
-- ============================================================================
local function getUiParent()
	local ok, cg = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and cg then
		local testOk = pcall(function()
			local f = Instance.new("Folder")
			f.Parent = cg
			f:Destroy()
		end)
		if testOk then
			return cg
		end
	end
	return LP:WaitForChild("PlayerGui")
end

for _, parent in ipairs({ getUiParent(), LP:FindFirstChild("PlayerGui") }) do
	if parent then
		for _, o in ipairs(parent:GetChildren()) do
			if o.Name == UI_NAME then
				pcall(o.Destroy, o)
			end
		end
	end
end

local function mk(cls, props, parent, corner, strokeColor, strokeTr)
	local o = Instance.new(cls)
	for k, v in pairs(props) do
		o[k] = v
	end
	if corner then
		Instance.new("UICorner", o).CornerRadius = UDim.new(0, corner)
	end
	if strokeColor then
		local s = Instance.new("UIStroke", o)
		s.Color = strokeColor
		s.Transparency = strokeTr or 0.35
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	o.Parent = parent
	return o
end

local gui = mk("ScreenGui", {
	Name = UI_NAME,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, getUiParent())

local main = mk("Frame", {
	Size = UDim2.new(0, 680, 0, 410),
	Position = UDim2.new(0.5, -340, 0.5, -205),
	BackgroundColor3 = Color3.fromRGB(16, 19, 26),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Active = true,
}, gui, 10, Color3.fromRGB(72, 84, 114), 0.25)

local header = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundColor3 = Color3.fromRGB(22, 26, 36),
	BackgroundTransparency = 0.16,
	BorderSizePixel = 0,
}, main, 10)

mk("Frame", {
	Size = UDim2.new(0, 3, 0, 20),
	Position = UDim2.new(0, 12, 0.5, -10),
	BackgroundColor3 = Color3.fromRGB(99, 102, 241),
	BorderSizePixel = 0,
}, header, 99)

mk("TextLabel", {
	Size = UDim2.new(0, 145, 1, 0),
	Position = UDim2.new(0, 22, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(241, 245, 249),
	Text = "KIRRAA74 // МАРКЕТ",
}, header)

local counterPill = mk("Frame", {
	Size = UDim2.new(0, 200, 0, 28),
	Position = UDim2.new(1, -506, 0.5, -14),
	BackgroundColor3 = Color3.fromRGB(28, 33, 46),
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
}, header, 6, Color3.fromRGB(68, 80, 108))

foundLabel = mk("TextLabel", {
	Size = UDim2.new(0, 76, 1, 0),
	Position = UDim2.new(0, 8, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(125, 211, 252),
	Text = "Найдено: 0",
}, counterPill)

boughtLabel = mk("TextLabel", {
	Size = UDim2.new(0, 74, 1, 0),
	Position = UDim2.new(0, 84, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(74, 222, 128),
	Text = "Куплено: 0",
}, counterPill)

mk("TextButton", {
	Size = UDim2.new(0, 38, 0, 20),
	Position = UDim2.new(1, -42, 0.5, -10),
	BackgroundColor3 = Color3.fromRGB(45, 55, 74),
	BackgroundTransparency = 0.12,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = Color3.fromRGB(248, 250, 252),
	Text = "Сброс",
}, counterPill, 5).MouseButton1Click:Connect(function()
	State.foundCount = 0
	State.boughtCount = 0
	State.seenEntries = {}
	State.seenOrder = {}
	State.badJobIds = {}
	State.failedEntryIds = {}
	State.pendingLots = {}
	staleTradeUuids = {}
	updateCounters()
	saveConfig()
	pushLog("Счётчики и кэш сброшены")
end)

local statusPill = mk("Frame", {
	Size = UDim2.new(0, 96, 0, 28),
	Position = UDim2.new(1, -300, 0.5, -14),
	BackgroundColor3 = Color3.fromRGB(28, 33, 46),
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
}, header, 6, Color3.fromRGB(68, 80, 108))

statusDot = mk("Frame", {
	Size = UDim2.new(0, 7, 0, 7),
	Position = UDim2.new(0, 9, 0.5, -3.5),
	BackgroundColor3 = Color3.fromRGB(148, 163, 184),
	BorderSizePixel = 0,
}, statusPill, 99)

statusLabel = mk("TextLabel", {
	Size = UDim2.new(1, -22, 1, 0),
	Position = UDim2.new(0, 20, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextColor3 = Color3.fromRGB(148, 163, 184),
	Text = "ПАУЗА",
}, statusPill)

tradeToggleBtn = mk("TextButton", {
	Size = UDim2.new(0, 88, 0, 28),
	Position = UDim2.new(1, -198, 0.5, -14),
	BackgroundColor3 = Color3.fromRGB(124, 58, 237),
	BackgroundTransparency = 0.1,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "ТРЕЙД: ВКЛ",
}, header, 6)

local function paintTradeToggleBtn()
	if not tradeToggleBtn then
		return
	end
	tradeToggleBtn.Text = State.autoTrade and "ТРЕЙД: ВКЛ" or "ТРЕЙД: ВЫКЛ"
	tradeToggleBtn.BackgroundColor3 = State.autoTrade and Color3.fromRGB(124, 58, 237) or Color3.fromRGB(71, 85, 105)
end
paintTradeToggleBtn()
table.insert(settingsRefreshers, paintTradeToggleBtn)

tradeToggleBtn.MouseButton1Click:Connect(function()
	State.autoTrade = not State.autoTrade
	syncTradeSwitchFile()
	if not State.autoTrade and State.inTrade then
		finishTradeState("Авто-трейд выключен вручную")
	end
	refreshAllSettingsUI()
	saveConfig()
	pushLog(State.autoTrade and "Авто-трейд ВКЛЮЧЕН" or "Авто-трейд ВЫКЛЮЧЕН")
end)

toggleRunBtn = mk("TextButton", {
	Size = UDim2.new(0, 68, 0, 28),
	Position = UDim2.new(1, -104, 0.5, -14),
	BackgroundColor3 = Color3.fromRGB(34, 197, 94),
	BackgroundTransparency = 0.08,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "СТАРТ",
}, header, 6)

local minBtn = mk("TextButton", {
	Size = UDim2.new(0, 26, 0, 28),
	Position = UDim2.new(1, -30, 0.5, -14),
	BackgroundColor3 = Color3.fromRGB(32, 38, 52),
	BackgroundTransparency = 0.18,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(226, 232, 240),
	Text = "—",
}, header, 6, Color3.fromRGB(68, 80, 108))

do
	local drag, startPos, dragStart
	header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			drag = true
			dragStart = i.Position
			startPos = main.Position
		end
	end)
	header.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			drag = false
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
			local d = i.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

local body = mk("Frame", {
	Size = UDim2.new(1, 0, 1, -46),
	Position = UDim2.new(0, 0, 0, 46),
	BackgroundTransparency = 1,
}, main)

local tabBar = mk("Frame", {
	Size = UDim2.new(1, -24, 0, 32),
	Position = UDim2.new(0, 12, 0, 10),
	BackgroundColor3 = Color3.fromRGB(22, 26, 36),
	BackgroundTransparency = 0.2,
}, body, 7, Color3.fromRGB(62, 74, 102))

local pages = mk("Frame", {
	Size = UDim2.new(1, -24, 1, -54),
	Position = UDim2.new(0, 12, 0, 48),
	BackgroundTransparency = 1,
}, body)

local pageTargets = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, pages)
local pageSettings = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = Color3.fromRGB(99, 102, 241),
	CanvasSize = UDim2.new(0, 0, 0, 500),
	Visible = false,
}, pages)
pageLogs = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, pages)

local tabBtns = {}
local tabPages = { pageTargets, pageSettings, pageLogs }
for i, name in ipairs({ "Цели", "Настройки", "Логи" }) do
	local b = mk("TextButton", {
		Size = UDim2.new(1 / 3, -4, 1, -4),
		Position = UDim2.new((i - 1) / 3, 2, 0, 2),
		BackgroundColor3 = i == 1 and Color3.fromRGB(79, 70, 229) or Color3.fromRGB(28, 33, 46),
		BackgroundTransparency = i == 1 and 0.1 or 0.25,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = i == 1 and Color3.new(1, 1, 1) or Color3.fromRGB(148, 163, 184),
		Text = name,
	}, tabBar, 5)
	tabBtns[i] = b
	b.MouseButton1Click:Connect(function()
		for j = 1, 3 do
			local on = (j == i)
			tabPages[j].Visible = on
			tabBtns[j].BackgroundColor3 = on and Color3.fromRGB(79, 70, 229) or Color3.fromRGB(28, 33, 46)
			tabBtns[j].BackgroundTransparency = on and 0.1 or 0.25
			tabBtns[j].TextColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(148, 163, 184)
		end
		if i == 3 then
			scrollLogs()
		end
	end)
end

local addRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, pageTargets)

local skinInput = mk("TextBox", {
	Size = UDim2.new(0.55, -5, 1, 0),
	BackgroundColor3 = Color3.fromRGB(22, 26, 36),
	BackgroundTransparency = 0.2,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(241, 245, 249),
	PlaceholderColor3 = Color3.fromRGB(148, 163, 184),
	PlaceholderText = "ID предмета (напр. Exotic.Rainbow.AWP)",
	Text = "",
	ClearTextOnFocus = false,
}, addRow, 6, Color3.fromRGB(65, 76, 104))

local priceInput = mk("TextBox", {
	Size = UDim2.new(0.21, -5, 1, 0),
	Position = UDim2.new(0.55, 2, 0, 0),
	BackgroundColor3 = Color3.fromRGB(22, 26, 36),
	BackgroundTransparency = 0.2,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(125, 211, 252),
	Text = "2000",
	ClearTextOnFocus = false,
}, addRow, 6, Color3.fromRGB(65, 76, 104))

local addBtn = mk("TextButton", {
	Size = UDim2.new(0.24, 0, 1, 0),
	Position = UDim2.new(0.76, 0, 0, 0),
	BackgroundColor3 = Color3.fromRGB(79, 70, 229),
	BackgroundTransparency = 0.1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "+ Добавить",
}, addRow, 6)

local bulkRow = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 28),
	Position = UDim2.new(0, 0, 0, 36),
	BackgroundColor3 = Color3.fromRGB(20, 24, 34),
	BackgroundTransparency = 0.22,
}, pageTargets, 6, Color3.fromRGB(58, 68, 94))

mk("TextLabel", {
	Size = UDim2.new(0.42, -8, 1, 0),
	Position = UDim2.new(0, 10, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(165, 180, 204),
	Text = "Цена для всех целей:",
}, bulkRow)

local bulkInput = mk("TextBox", {
	Size = UDim2.new(0.16, -4, 0, 22),
	Position = UDim2.new(0.42, 0, 0.5, -11),
	BackgroundColor3 = Color3.fromRGB(15, 18, 26),
	BackgroundTransparency = 0.22,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(125, 211, 252),
	Text = "2000",
	ClearTextOnFocus = false,
}, bulkRow, 5, Color3.fromRGB(65, 76, 104))

mk("TextButton", {
	Size = UDim2.new(0.20, -4, 0, 22),
	Position = UDim2.new(0.58, 2, 0.5, -11),
	BackgroundColor3 = Color3.fromRGB(30, 58, 95),
	BackgroundTransparency = 0.14,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(186, 230, 253),
	Text = "Всем макс.",
}, bulkRow, 5, Color3.fromRGB(76, 118, 172)).MouseButton1Click:Connect(function()
	local n = tonumber(bulkInput.Text)
	if not n or n <= 0 then
		pushLog("Укажи цену > 0")
		return
	end
	local c = 0
	for k in pairs(State.targets) do
		State.targets[k] = n
		c += 1
	end
	refreshTargetsUI()
	saveConfig()
	pushLog(string.format("Цена %d применена к %d целям", n, c))
end)

mk("TextButton", {
	Size = UDim2.new(0.22, -6, 0, 22),
	Position = UDim2.new(0.78, 2, 0.5, -11),
	BackgroundColor3 = Color3.fromRGB(67, 56, 202),
	BackgroundTransparency = 0.14,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(224, 231, 255),
	Text = "Из config.txt",
}, bulkRow, 5, Color3.fromRGB(129, 140, 248)).MouseButton1Click:Connect(function()
	local _, loaded, count, loadedSig = parseUnifiedConfig()
	if loaded then
		State.targets = loaded
		State.lastConfigSkinsSig = loadedSig
		refreshTargetsUI()
		saveConfig()
		pushLog("Загружено из config.txt (" .. count .. " шт.)")
	else
		State.targets = cloneTargets(DEFAULT_TARGETS)
		refreshTargetsUI()
		saveConfig()
		pushLog("В config.txt нет скинов — загружен стандартный список")
	end
end)

local targetList = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -70),
	Position = UDim2.new(0, 0, 0, 70),
	BackgroundColor3 = Color3.fromRGB(19, 23, 33),
	BackgroundTransparency = 0.24,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = Color3.fromRGB(99, 102, 241),
	CanvasSize = UDim2.new(),
}, pageTargets, 7, Color3.fromRGB(58, 68, 94))

local targetLayout = mk("UIListLayout", { Padding = UDim.new(0, 4) }, targetList)
mk("UIPadding", {
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
}, targetList)

refreshTargetsUI = function()
	for _, c in ipairs(targetList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local keys = {}
	for k in pairs(State.targets) do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, skin in ipairs(keys) do
		local row = mk("Frame", {
			Size = UDim2.new(1, -6, 0, 28),
			BackgroundColor3 = Color3.fromRGB(26, 31, 43),
			BackgroundTransparency = 0.22,
		}, targetList, 6, Color3.fromRGB(62, 74, 102), 0.4)

		mk("TextLabel", {
			Size = UDim2.new(1, -155, 1, 0),
			Position = UDim2.new(0, 10, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = Color3.fromRGB(226, 232, 240),
			Text = skin,
		}, row)

		mk("TextLabel", {
			Size = UDim2.new(0, 76, 0, 20),
			Position = UDim2.new(1, -142, 0.5, -10),
			BackgroundColor3 = Color3.fromRGB(20, 36, 52),
			BackgroundTransparency = 0.18,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = Color3.fromRGB(125, 211, 252),
			Text = "до " .. State.targets[skin],
		}, row, 5)

		mk("TextButton", {
			Size = UDim2.new(0, 56, 0, 20),
			Position = UDim2.new(1, -62, 0.5, -10),
			BackgroundColor3 = Color3.fromRGB(153, 27, 27),
			BackgroundTransparency = 0.14,
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextColor3 = Color3.fromRGB(254, 226, 226),
			Text = "Удалить",
		}, row, 5).MouseButton1Click:Connect(function()
			State.targets[skin] = nil
			refreshTargetsUI()
			saveConfig()
			pushLog("Удалена цель: " .. skin)
		end)
	end
	targetList.CanvasSize = UDim2.new(0, 0, 0, targetLayout.AbsoluteContentSize.Y + 12)
end

addBtn.MouseButton1Click:Connect(function()
	local name = string.match(skinInput.Text, "^%s*(.-)%s*$")
	local p = tonumber(priceInput.Text)
	if name and name ~= "" and p and p > 0 then
		State.targets[name] = p
		skinInput.Text = ""
		refreshTargetsUI()
		saveConfig()
		pushLog(string.format("Добавлена цель: %s (до %d)", name, p))
	else
		pushLog("Укажи ID предмета и цену > 0")
	end
end)
refreshTargetsUI()

mk("UIListLayout", { Padding = UDim.new(0, 5) }, pageSettings)

local function addToggle(txt, getV, setV)
	local row = mk("Frame", {
		Size = UDim2.new(1, -6, 0, 32),
		BackgroundColor3 = Color3.fromRGB(22, 26, 36),
		BackgroundTransparency = 0.2,
	}, pageSettings, 6, Color3.fromRGB(58, 68, 94))

	mk("TextLabel", {
		Size = UDim2.new(0.7, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(226, 232, 240),
		Text = txt,
	}, row)

	local b = mk("TextButton", {
		Size = UDim2.new(0, 76, 0, 22),
		Position = UDim2.new(1, -84, 0.5, -11),
		BackgroundTransparency = 0.1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1),
	}, row, 5)

	local function paint()
		local v = getV()
		b.Text = v and "ВКЛ" or "ВЫКЛ"
		b.BackgroundColor3 = v and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(71, 85, 105)
	end
	paint()
	table.insert(settingsRefreshers, paint)

	b.MouseButton1Click:Connect(function()
		setV(not getV())
		refreshAllSettingsUI()
		saveConfig()
	end)
end

local function addNumber(txt, getV, minV, maxV, setV, isInt)
	local row = mk("Frame", {
		Size = UDim2.new(1, -6, 0, 32),
		BackgroundColor3 = Color3.fromRGB(22, 26, 36),
		BackgroundTransparency = 0.2,
	}, pageSettings, 6, Color3.fromRGB(58, 68, 94))

	mk("TextLabel", {
		Size = UDim2.new(0.7, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(226, 232, 240),
		Text = txt,
	}, row)

	local box = mk("TextBox", {
		Size = UDim2.new(0, 86, 0, 22),
		Position = UDim2.new(1, -94, 0.5, -11),
		BackgroundColor3 = Color3.fromRGB(16, 20, 29),
		BackgroundTransparency = 0.2,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(125, 211, 252),
		ClearTextOnFocus = false,
	}, row, 5, Color3.fromRGB(68, 80, 108))

	local function paint()
		box.Text = tostring(getV())
	end
	paint()
	table.insert(settingsRefreshers, paint)

	box.FocusLost:Connect(function()
		local n = readNum(box.Text, minV, maxV, isInt)
		if n then
			setV(n)
			saveConfig()
		end
		paint()
	end)
end

do
	local listening = false
	local row = mk("Frame", {
		Size = UDim2.new(1, -6, 0, 32),
		BackgroundColor3 = Color3.fromRGB(22, 26, 36),
		BackgroundTransparency = 0.2,
	}, pageSettings, 6, Color3.fromRGB(58, 68, 94))

	mk("TextLabel", {
		Size = UDim2.new(0.65, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(226, 232, 240),
		Text = "Скрыть / показать меню",
	}, row)

	local kb = mk("TextButton", {
		Size = UDim2.new(0, 110, 0, 22),
		Position = UDim2.new(1, -118, 0.5, -11),
		BackgroundColor3 = Color3.fromRGB(49, 46, 129),
		BackgroundTransparency = 0.12,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(224, 231, 255),
	}, row, 5, Color3.fromRGB(115, 118, 255), 0.3)

	local function paint()
		kb.Text = listening and "Нажми клавишу..." or State.hotkey
	end
	paint()
	table.insert(settingsRefreshers, paint)

	kb.MouseButton1Click:Connect(function()
		listening = true
		paint()
	end)

	UIS.InputBegan:Connect(function(i, gp)
		if not isActive() or i.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if listening and i.KeyCode ~= Enum.KeyCode.Unknown then
			State.hotkey = i.KeyCode.Name
			listening = false
			paint()
			saveConfig()
			pushLog("Клавиша меню: " .. State.hotkey)
		elseif not gp and i.KeyCode.Name == State.hotkey then
			main.Visible = not main.Visible
		end
	end)
end

addToggle("Авто-трейд (выдача 1 скина из целей)", function() return State.autoTrade end, function(v)
	State.autoTrade = v
	syncTradeSwitchFile()
	if not v and State.inTrade then
		finishTradeState("Авто-трейд выключен вручную")
	end
end)
addToggle("Автопокупка (на текущем сервере)", function() return State.autoBuy end, function(v) State.autoBuy = v end)
addToggle("Автотелепорт (по JobId)", function() return State.autoTeleport end, function(v) State.autoTeleport = v end)
addToggle("Звук при покупке", function() return State.soundAlert end, function(v) State.soundAlert = v end)
addNumber("Повторы покупки (0-5)", function() return State.buyRetries end, 0, 5, function(v) State.buyRetries = v end, true)
addNumber("Кулдаун плохого TP (сек)", function() return State.tpCooldown end, 5, 3600, function(v) State.tpCooldown = v end)
addNumber("Задержка на скин (сек)", function() return State.skinDelay end, 0.05, 60, function(v) State.skinDelay = v end)
addNumber("Задержка цикла (сек)", function() return State.loopDelay end, 0.05, 60, function(v) State.loopDelay = v end)
addNumber("Ожидание телепорта (сек)", function() return State.tpWait end, 1, 60, function(v) State.tpWait = v end)
addNumber("Мин. цена (фильтр)", function() return State.minPrice end, 0, 1e8, function(v) State.minPrice = v end)

mk("TextButton", {
	Size = UDim2.new(0, 110, 0, 26),
	Position = UDim2.new(1, -110, 0, 0),
	BackgroundColor3 = Color3.fromRGB(28, 33, 46),
	BackgroundTransparency = 0.2,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(226, 232, 240),
	Text = "Очистить логи",
}, pageLogs, 6, Color3.fromRGB(68, 80, 108)).MouseButton1Click:Connect(function()
	logLabel.Text = ""
	logScroll.CanvasPosition = Vector2.new()
end)

logScroll = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -32),
	Position = UDim2.new(0, 0, 0, 32),
	BackgroundColor3 = Color3.fromRGB(14, 17, 24),
	BackgroundTransparency = 0.14,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = Color3.fromRGB(99, 102, 241),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, pageLogs, 7, Color3.fromRGB(58, 68, 94))

logLabel = mk("TextLabel", {
	Size = UDim2.new(1, -14, 0, 0),
	Position = UDim2.new(0, 8, 0, 6),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	TextColor3 = Color3.fromRGB(203, 213, 225),
	Text = "",
}, logScroll)

toggleRunBtn.MouseButton1Click:Connect(function()
	local n = not State.running
	setRunning(n, true)
	pushLog(n and "Цикл запущен" or "Цикл остановлен")
end)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	body.Visible = not minimized
	main.Size = minimized and UDim2.new(0, 680, 0, 46) or UDim2.new(0, 680, 0, 410)
	minBtn.Text = minimized and "+" or "—"
end)

-- ============================================================================
-- АВТО-ВКЛЮЧЕНИЕ КНОПКИ ТРЕЙД ПРИ ЗАПУСКЕ ЛАУНЧЕРА (start.bat)
-- ============================================================================
task.spawn(function()
	task.wait(1.5)
	while isActive() do
		local rawToken = readRawFile(FORCE_TRADE_ON_FILE) or ""
		local currentToken = string.match(rawToken, "^%s*(.-)%s*$") or ""
		if currentToken ~= "" and currentToken ~= State.lastForceToken then
			State.lastForceToken = currentToken
			if not State.autoTrade then
				State.autoTrade = true
				syncTradeSwitchFile()
				refreshAllSettingsUI()
				pushLog("[ЛАУНЧЕР] Запущена автосмена аккаунтов -> ТРЕЙД автоматически ВКЛЮЧЕН")
			end
			local _, freshTargets, _, freshSig = parseUnifiedConfig()
			if freshTargets and freshSig ~= "" and freshSig ~= State.lastConfigSkinsSig then
				State.targets = freshTargets
				State.lastConfigSkinsSig = freshSig
				refreshTargetsUI()
				pushLog("[ЛАУНЧЕР] Обновлён список скинов из config.txt")
			end
			saveConfig()
		end
		task.wait(1.0)
	end
end)

-- ============================================================================
-- ЛОГИКА МАРКЕТА
-- ============================================================================
local function buildQueue()
	local q, added = {}, {}
	local function add(skin)
		if skin and State.targets[skin] and not added[skin] then
			added[skin] = true
			table.insert(q, { skinId = skin, maxPrice = State.targets[skin] })
		end
	end
	for _, p in pairs(State.pendingLots) do add(p.skinId) end
	add(State.prioritySkin)
	for skin in pairs(State.targets) do add(skin) end
	return q
end

local function hasPending()
	local now = os.clock()
	for key, info in pairs(State.pendingLots) do
		if now - info.createdAt > MAX_LOT_WAIT then
			State.pendingLots[key] = nil
			State.failedEntryIds[key] = now + FAILED_COOLDOWN
			pushLog("Таймаут (95с): " .. tostring(info.skinId))
		else
			return true
		end
	end
	return false
end

local function tryBuyLot(skinId, price, item, key)
	if isCooldown(State.failedEntryIds, key) then return "failed" end
	local seller = findSeller(item)
	if not seller or item.EntryId == nil then
		State.failedEntryIds[key] = os.clock() + FAILED_COOLDOWN
		State.pendingLots[key] = nil
		return "failed"
	end

	local now = os.clock()
	local pend = State.pendingLots[key]
	if pend and now < pend.nextTryAt then
		setStatus("ЖДУ " .. math.max(1, math.ceil(MAX_LOT_WAIT - (now - pend.createdAt))) .. "с", Color3.fromRGB(251, 191, 36))
		return "wait"
	end

	setStatus("ПОКУПКА", Color3.fromRGB(167, 139, 250))
	local attempts = pend and 1 or (State.buyRetries + 1)
	local bought, lastRes = false, nil

	for i = 1, attempts do
		local ok, res = pcall(PurchaseRemote.InvokeServer, PurchaseRemote, seller, item.EntryId)
		lastRes = res
		if ok and res ~= false and res ~= nil then
			bought = true
			break
		end
		if i < attempts then task.wait(0.25) end
	end

	if bought then
		State.boughtCount += 1
		State.pendingLots[key] = nil
		State.failedEntryIds[key] = now + FAILED_COOLDOWN
		if State.prioritySkin == skinId then
			State.prioritySkin = nil
			State.priorityPasses = 0
		end
		updateCounters()
		saveConfig()
		if State.soundAlert then pcall(alertSound.Play, alertSound) end
		pushLog(string.format("КУПЛЕНО: %s | %d | %s", skinId, price, seller.Name))
		setStatus("ПОИСК", Color3.fromRGB(125, 211, 252))
		return "bought"
	end

	if not pend then
		State.pendingLots[key] = { skinId = skinId, createdAt = now, nextTryAt = now + PENDING_RETRY }
		pushLog(string.format("Жду таймер: %s за %d у %s", skinId, price, seller.Name))
		setStatus("ЖДУ ТАЙМЕР", Color3.fromRGB(251, 191, 36))
		return "wait"
	end

	if now - pend.createdAt < MAX_LOT_WAIT then
		pend.nextTryAt = now + PENDING_RETRY
		setStatus("ЖДУ " .. math.max(1, math.ceil(MAX_LOT_WAIT - (now - pend.createdAt))) .. "с", Color3.fromRGB(251, 191, 36))
		return "wait"
	end

	State.pendingLots[key] = nil
	State.failedEntryIds[key] = now + FAILED_COOLDOWN
	pushLog(string.format("Не куплено за %dс: %s (%s)", MAX_LOT_WAIT, skinId, tostring(lastRes)))
	setStatus("ПОИСК", Color3.fromRGB(125, 211, 252))
	return "failed"
end

local function smartTeleport(skinId, jobId)
	if State.inTrade then return end
	setStatus("ТЕЛЕПОРТ", Color3.fromRGB(250, 204, 21))
	State.prioritySkin = skinId
	State.priorityPasses = 0
	saveConfig(true)
	State.running = false

	local initJob = game.JobId
	local tpFailed, reason = false, ""

	local conn = TS.TeleportInitFailed:Connect(function(p, res, msg)
		if p == LP then
			tpFailed = true
			reason = tostring(res) .. (msg ~= "" and (": " .. msg) or "")
		end
	end)

	local ok, err = pcall(TS.TeleportToPlaceInstance, TS, game.PlaceId, jobId, LP)
	if not ok then
		conn:Disconnect()
		State.badJobIds[jobId] = os.clock() + State.tpCooldown
		setRunning(true, false)
		pushLog("Ошибка TP: " .. tostring(err))
		return
	end

	pushLog("Телепорт -> " .. skinId .. " (" .. jobId .. ")")
	local deadline = os.clock() + State.tpWait
	while os.clock() < deadline and isActive() and not tpFailed and game.JobId == initJob do
		task.wait(0.15)
	end
	conn:Disconnect()

	if isActive() and game.JobId == initJob then
		State.badJobIds[jobId] = os.clock() + State.tpCooldown
		setRunning(true, false)
		pushLog(tpFailed and ("TP отклонён: " .. reason) or "TP не сработал")
	end
end

task.spawn(function()
	while isActive() do
		if State.inTrade and State.tradeStartedAt > 0 and (os.clock() - State.tradeStartedAt > TRADE_SAFETY_TIMEOUT) then
			finishTradeState("Таймаут ожидания трейда (45с)")
		end

		if State.running and not State.inTrade then
			for _, entry in ipairs(buildQueue()) do
				if not isActive() or not State.running or State.inTrade then break end
				local skinId, maxPrice = entry.skinId, entry.maxPrice
				local boughtLocal, waitingLocal = false, false

				setStatus("ПОИСК", Color3.fromRGB(125, 211, 252))
				local ok, results = pcall(SearchIndex.InvokeServer, SearchIndex, skinId, {})
				if not isActive() or State.inTrade then break end

				if ok and type(results) == "table" then
					local localLots, remoteLots, activeKeys = {}, {}, {}
					local foundIncremented = false

					for _, item in pairs(results) do
						local price = type(item) == "table" and tonumber(item.Price) or nil
						if price and price >= State.minPrice and price <= maxPrice then
							local key = item.EntryId ~= nil and tostring(item.EntryId) or (skinId .. "_" .. price .. "_" .. tostring(item.JobId))
							if markSeen(key) then
								State.foundCount += 1
								foundIncremented = true
								updateCounters()
								pushLog(string.format("НАЙДЕНО: %s | %d | %s", skinId, price, getSellerName(item)))
							end
							local isLocal = type(item.JobId) ~= "string" or item.JobId == "" or item.JobId == game.JobId
							if isLocal then
								activeKeys[key] = true
								if not isCooldown(State.failedEntryIds, key) then
									table.insert(localLots, { item = item, price = price, key = key })
								end
							else
								table.insert(remoteLots, { item = item, price = price, key = key })
							end
						end
					end

					if foundIncremented then saveConfig() end

					for pKey, pInfo in pairs(State.pendingLots) do
						if pInfo.skinId == skinId and not activeKeys[pKey] then
							State.pendingLots[pKey] = nil
							pushLog("Отложенный лот пропал: " .. skinId)
						end
					end

					table.sort(localLots, function(a, b) return a.price < b.price end)
					table.sort(remoteLots, function(a, b) return a.price < b.price end)

					if State.autoBuy then
						for _, lot in ipairs(localLots) do
							if not isActive() or not State.running or State.inTrade then break end
							local res = tryBuyLot(skinId, lot.price, lot.item, lot.key)
							if res == "bought" then boughtLocal = true
							elseif res == "wait" then waitingLocal = true end
						end
					end

					if State.prioritySkin == skinId and not boughtLocal and not waitingLocal and #localLots == 0 then
						State.priorityPasses += 1
						if State.priorityPasses >= 2 then
							State.prioritySkin = nil
							State.priorityPasses = 0
							saveConfig()
						end
					end

					if isActive() and State.running and not State.inTrade and not boughtLocal and not waitingLocal and not hasPending() and State.autoTeleport then
						for _, lot in ipairs(remoteLots) do
							local jid = lot.item.JobId
							if type(jid) == "string" and jid ~= "" and jid ~= game.JobId and not isCooldown(State.badJobIds, jid) then
								smartTeleport(skinId, jid)
								break
							end
						end
					end
				end

				if not isActive() or not State.running or State.inTrade or hasPending() then break end
				task.wait(jitter(State.skinDelay))
			end

			if isActive() and State.running and not State.inTrade then
				setStatus(
					hasPending() and "ЖДУ ТАЙМЕР" or "ОЖИДАНИЕ",
					hasPending() and Color3.fromRGB(251, 191, 36) or Color3.fromRGB(148, 163, 184)
				)
			end
		end
		task.wait(hasPending() and PENDING_RETRY or jitter(State.loopDelay))
	end
end)

pushLog("UI инициализирован (Основа: " .. LP.Name .. ")")
if loadConfig() then
	task.delay(2, function()
		if isActive() then
			setRunning(true, false)
			pushLog("Автозапуск цикла после загрузки")
		end
	end)
end
