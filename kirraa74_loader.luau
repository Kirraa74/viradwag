if not game:IsLoaded() then
	game.Loaded:Wait()
end

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG_TXT_FILE = "kirraa74_config.txt"
local MAIN_FILES = { "auto.luau", "auto.lua" }
local SIGNAL_FILE = "trade_done.txt"
local INJECT_SIGNAL_FILE = "alt_injected.txt"
local TRADE_SWITCH_FILE = "kirraa74_autotrade_switch.txt"
local TRADE_TIMEOUT = 65

local GUARD_KEY = "KIRRAA74_UNIVERSAL_LOADER_V5_" .. tostring(game.PlaceId)
if getgenv then
	if getgenv()[GUARD_KEY] then
		return
	end
	getgenv()[GUARD_KEY] = true
end

local function readRawFile(path)
	if typeof(isfile) ~= "function" or typeof(readfile) ~= "function" then
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
	local cfg = {
		mainAccount = "",
		skins = {},
	}
	local raw = readRawFile(CONFIG_TXT_FILE)
	if not raw then
		return cfg
	end

	local section = nil
	local seenSkins = {}
	for line in string.gmatch(raw, "[^\r\n]+") do
		local clean = string.match(line, "^%s*(.-)%s*$")
		if clean ~= "" and string.sub(clean, 1, 1) ~= "#" and string.sub(clean, 1, 2) ~= "//" and string.sub(clean, 1, 1) ~= ";" then
			local sec = string.match(clean, "^%[(.+)%]$")
			if sec then
				section = string.upper(string.match(sec, "^%s*(.-)%s*$"))
			elseif section == "SETTINGS" then
				local k, v = string.match(clean, "^(.-)%s*=%s*(.+)$")
				if k and v then
					k = string.upper(string.match(k, "^%s*(.-)%s*$"))
					v = string.match(v, "^%s*(.-)%s*$")
					if k == "MAIN_ACCOUNT" and v ~= "ВПИШИ_НИК_ОСНОВЫ" and v ~= "MAIN_USERNAME_HERE" then
						cfg.mainAccount = string.match(v, "^(%S+)") or v
					end
				end
			elseif section == "SKINS" then
				local skinName = string.match(clean, "^(.-)%s*[=:]%s*%d+%s*$")
					or string.match(clean, "^(%S+)%s+%d+%s*$")
					or string.match(clean, "^(%S+)%s*$")
				skinName = skinName and string.match(skinName, "^%s*(.-)%s*$") or nil
				if skinName and skinName ~= "" and not seenSkins[skinName] then
					seenSkins[skinName] = true
					table.insert(cfg.skins, skinName)
				end
			end
		end
	end
	return cfg
end

local function isAutoTradeEnabled()
	local raw = readRawFile(TRADE_SWITCH_FILE)
	if not raw then
		return true
	end
	local clean = string.match(raw, "^%s*(.-)%s*$")
	if clean == "" then
		return true
	end
	return clean ~= "0"
end

-- ============================================================================
-- ПРОВЕРКА РОЛИ: ОСНОВА -> ЗАПУСКАЕМ auto.luau
-- ============================================================================
local initialCfg = parseUnifiedConfig()
if initialCfg.mainAccount ~= "" and string.lower(LP.Name) == string.lower(initialCfg.mainAccount) then
	if typeof(isfile) == "function" and typeof(loadfile) == "function" then
		for _, fileName in ipairs(MAIN_FILES) do
			local okEx, exists = pcall(isfile, fileName)
			if okEx and exists then
				local fn, err = loadfile(fileName)
				if fn then
					print(string.format("[%s] [ROUTER] Запущен %s для основы %s", os.date("%H:%M:%S"), fileName, LP.Name))
					fn()
					return
				else
					warn("[ROUTER] Ошибка синтаксиса " .. fileName .. ": " .. tostring(err))
				end
			end
		end
	end
	warn("[ROUTER] Файл auto.luau не найден в workspace!")
	return
end

-- ============================================================================
-- ИНАЧЕ ЭТО ТВИНК: ПЕРЕРАБОТКА 1 СКИНА + ПЕРЕДАЧА CASH ОСНОВЕ
-- ============================================================================
-- Сразу сообщаем лаунчеру, что скрипт успешно заинжектился на твинке
if typeof(writefile) == "function" then
	pcall(writefile, INJECT_SIGNAL_FILE, LP.Name .. ":" .. tostring(os.time()))
end

local RemoteFolder = RS:WaitForChild("Remote")
local TradeRemote = RemoteFolder:WaitForChild("Trade")
local LimitedRecycle = RemoteFolder:WaitForChild("Any"):WaitForChild("LimitedRecycle")
local RequestRemote = TradeRemote:FindFirstChild("RequestSend") or TradeRemote:WaitForChild("Request")
local RequestNotice = TradeRemote:FindFirstChild("RequestNotice")
local RequestAccept = TradeRemote:FindFirstChild("RequestAccept")
local StartEvent = TradeRemote:WaitForChild("Start")
local CloseEvent = TradeRemote:WaitForChild("Close")
local CancelNotice = TradeRemote:FindFirstChild("CancelNotice")
local SelectRemote = TradeRemote:WaitForChild("Select")
local SetConfirm = TradeRemote:WaitForChild("SetConfirm")
local ReadyRemote = TradeRemote:WaitForChild("Ready")

local function logAlt(msg)
	print(string.format("[%s] [ALT:%s] %s", os.date("%H:%M:%S"), LP.Name, tostring(msg)))
end

local doneSent = false
local tradeOpened = false
local tradeFinished = false

local function finishAlt(reason)
	if doneSent then
		return
	end
	doneSent = true
	logAlt("Завершение: " .. tostring(reason))
	if typeof(writefile) == "function" then
		pcall(writefile, SIGNAL_FILE, LP.Name .. ":" .. tostring(reason))
	end
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

local function normalizeName(str)
	if type(str) ~= "string" then
		return ""
	end
	str = string.gsub(str, "^[^%.]+%.", "")
	str = string.lower(str)
	str = string.gsub(str, "[%s_%-%.]", "")
	return str
end

local function isInAllowedList(skinName, allowedList)
	if type(skinName) ~= "string" or skinName == "" then
		return false
	end
	if not allowedList or #allowedList == 0 then
		return true
	end
	local norm = normalizeName(skinName)
	for _, target in ipairs(allowedList) do
		if skinName == target or string.lower(skinName) == string.lower(target) then
			return true
		end
		if norm ~= "" and norm == normalizeName(target) then
			return true
		end
	end
	return false
end

local function parseCashFromFrame(tokenFrame)
	if not tokenFrame then
		return 0
	end
	local best = 0
	for _, d in ipairs(tokenFrame:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextBox") then
			local txt = tostring(d.Text)
			if not string.find(txt, "%%") then
				local digits = string.gsub(txt, "[^%d]", "")
				local n = tonumber(digits)
				if n and n > best then
					best = n
				end
			end
		end
	end
	return best
end

local function getCash()
	local ls = LP:FindFirstChild("leaderstats")
	if ls then
		for _, v in ipairs(ls:GetChildren()) do
			local n = string.lower(v.Name)
			if (n:find("cash") or n:find("token") or n:find("money") or n:find("coin")) and tonumber(v.Value) then
				local val = tonumber(v.Value)
				if val > 0 then
					return val
				end
			end
		end
	end

	for attrName, attrVal in pairs(LP:GetAttributes()) do
		local n = string.lower(attrName)
		if (n:find("cash") or n:find("token") or n:find("money")) and tonumber(attrVal) and tonumber(attrVal) > 0 then
			return tonumber(attrVal)
		end
	end

	local pg = LP:FindFirstChild("PlayerGui")
	if pg then
		local direct = pg:FindFirstChild("Main")
		if direct then
			local root = direct:FindFirstChild("Root")
			local trading = root and root:FindFirstChild("Trading")
			local currency = trading and trading:FindFirstChild("Currency")
			local token = currency and currency:FindFirstChild("Eco_TradeToken")
			local val = parseCashFromFrame(token)
			if val > 0 then
				return val
			end
		end
		local tokenFrame = pg:FindFirstChild("Eco_TradeToken", true)
		if tokenFrame then
			local val = parseCashFromFrame(tokenFrame)
			if val > 0 then
				return val
			end
		end
	end
	return 0
end

local function isCashVisibleInTrade(targetCash)
	local pg = LP:FindFirstChild("PlayerGui")
	local main = pg and pg:FindFirstChild("Main")
	local root = main and main:FindFirstChild("Root")
	local trading = root and root:FindFirstChild("Trading")
	if not trading then
		return true
	end
	local currency = trading:FindFirstChild("Currency")
	for _, d in ipairs(trading:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextBox")) and (not currency or not d:IsDescendantOf(currency)) then
			local txt = tostring(d.Text)
			if not string.find(txt, "%%") then
				local digits = string.gsub(txt, "[^%d]", "")
				if digits ~= "" and tonumber(digits) == targetCash then
					return true
				end
			end
		end
	end
	return false
end

local function getRecyclableSkins(allowedList)
	local skins, seen = {}, {}
	if typeof(getgc) ~= "function" then
		return skins
	end
	for _, parentTbl in ipairs(getgc(true)) do
		if type(parentTbl) == "table" then
			pcall(function()
				for k, v in pairs(parentTbl) do
					if type(v) == "table" then
						local skinName = safeGetName(v)
						if isInAllowedList(skinName, allowedList) then
							local uuid = isUuidKey(k) and k or (rawget(v, "Key") or rawget(v, "UUID"))
							if isUuidKey(uuid) and not seen[uuid] then
								seen[uuid] = true
								table.insert(skins, { uuid = uuid, name = skinName })
							end
						end
					end
				end
			end)
		end
	end
	return skins
end

local function tryRecycleOneSkin()
	local cfg = parseUnifiedConfig()
	local skins = {}
	for _ = 1, 16 do
		skins = getRecyclableSkins(cfg.skins)
		if #skins > 0 then
			break
		end
		task.wait(0.5)
	end

	if #skins == 0 then
		logAlt("В инвентаре нет скинов из списка [SKINS] для переработки")
		return false
	end

	local cashBefore = getCash()
	for idx, skin in ipairs(skins) do
		local ok, res = pcall(function()
			return LimitedRecycle:InvokeServer(skin.uuid, 1)
		end)
		task.wait(0.35)
		local cashAfter = getCash()
		logAlt(string.format(
			"Recycle #%d [%s]: ok=%s | res=%s | cash %d -> %d",
			idx, tostring(skin.name), tostring(ok), tostring(res), cashBefore, cashAfter
		))
		if cashAfter > cashBefore or (ok and res ~= false and res ~= nil) then
			logAlt("Переработан 1 скин: " .. tostring(skin.name))
			return true
		end
	end

	logAlt("Слот 1 переработки уже использован или скин не принят")
	return false
end

local function findMainPlayer()
	local cfg = parseUnifiedConfig()
	if cfg.mainAccount == "" then
		return nil
	end
	local lower = string.lower(cfg.mainAccount)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and (string.lower(plr.Name) == lower or string.lower(plr.DisplayName) == lower) then
			return plr
		end
	end
	return nil
end

local function fireRemote(rem, ...)
	if not rem then
		return false, "nil"
	end
	if rem:IsA("RemoteFunction") then
		return pcall(rem.InvokeServer, rem, ...)
	elseif rem:IsA("RemoteEvent") then
		return pcall(rem.FireServer, rem, ...)
	end
	return false, "unsupported"
end

if RequestNotice and RequestAccept then
	RequestNotice.OnClientEvent:Connect(function(sender)
		if tradeOpened or not isAutoTradeEnabled() then
			return
		end
		local cfg = parseUnifiedConfig()
		local sName = typeof(sender) == "Instance" and sender.Name or tostring(sender)
		if sender and sender ~= LP and cfg.mainAccount ~= "" and string.lower(sName) == string.lower(cfg.mainAccount) then
			task.wait(0.25)
			if not isAutoTradeEnabled() then
				return
			end
			pcall(function()
				RequestAccept:InvokeServer(sender)
			end)
		end
	end)
end

StartEvent.OnClientEvent:Connect(function()
	if not isAutoTradeEnabled() then
		logAlt("Трейд открыт, но авто-трейд выключен")
		return
	end
	tradeOpened = true
	tradeFinished = false
	logAlt("Трейд открыт -> кладу весь Cash и подтверждаю...")

	task.spawn(function()
		task.wait(0.85)
		if tradeFinished or not isAutoTradeEnabled() then
			return
		end

		local cash = getCash()
		if cash == 0 then
			task.wait(0.35)
			cash = getCash()
		end

		if cash > 0 and isAutoTradeEnabled() then
			local okC, resC = fireRemote(SelectRemote, 3, cash, true)
			logAlt(string.format("Передан Cash %d: ok=%s | res=%s", cash, tostring(okC), tostring(resC)))
			task.wait(0.45)
			if tradeFinished or not isAutoTradeEnabled() then
				return
			end
			if not isCashVisibleInTrade(cash) then
				logAlt("Cash сбросился в окне, повторяю отправку: " .. tostring(cash))
				fireRemote(SelectRemote, 3, cash, true)
				task.wait(0.4)
			end
		else
			logAlt("Баланс Cash = 0")
			task.wait(0.5)
		end

		if tradeFinished or not isAutoTradeEnabled() then
			return
		end

		fireRemote(SetConfirm, true)
		task.wait(0.45)
		if tradeFinished or not isAutoTradeEnabled() then
			return
		end
		fireRemote(SetConfirm, true)
		task.wait(0.4)

		local deadline = os.clock() + 20
		while not tradeFinished and isAutoTradeEnabled() and os.clock() < deadline do
			local okR, resR = fireRemote(ReadyRemote)
			if okR and resR == false then
				fireRemote(SetConfirm, true)
			end
			task.wait(0.8)
		end
	end)
end)

CloseEvent.OnClientEvent:Connect(function()
	local wasOpened = tradeOpened
	tradeFinished = true
	tradeOpened = false
	task.wait(0.35)
	logAlt("Трейд закрыт | Остаток Cash: " .. tostring(getCash()))
	if wasOpened then
		finishAlt("trade_closed")
	end
end)

if CancelNotice then
	CancelNotice.OnClientEvent:Connect(function()
		tradeFinished = true
		tradeOpened = false
		logAlt("Трейд отменён, готов к новой попытке")
	end)
end

task.spawn(function()
	task.wait(3)
	if doneSent then
		return
	end

	tryRecycleOneSkin()
	task.wait(1.2)

	local startClock = os.clock()
	local lastReq = 0

	while not doneSent do
		if not isAutoTradeEnabled() then
			startClock = os.clock()
			task.wait(1.0)
			continue
		end

		if os.clock() - startClock > TRADE_TIMEOUT then
			finishAlt(tradeFinished and "trade_closed" or "timeout")
			break
		end

		if not tradeOpened and (os.clock() - lastReq >= 3.0) then
			local mainPlr = findMainPlayer()
			if mainPlr then
				lastReq = os.clock()
				logAlt("Кидаю запрос на трейд основе: " .. mainPlr.Name)
				pcall(function()
					RequestRemote:InvokeServer(mainPlr)
				end)
			else
				logAlt("Ожидаю основу на сервере...")
			end
		end

		task.wait(0.4)
	end
end)

logAlt("Загружен скрипт твинка (основа: " .. (initialCfg.mainAccount ~= "" and initialCfg.mainAccount or "не задана") .. ")")
