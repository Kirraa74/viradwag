if not game:IsLoaded() then
	game.Loaded:Wait()
end

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local MAIN_USERNAME = "Blazpex82" -- Ник основы
local SIGNAL_FILE = "trade_done.txt"

if LP.Name == MAIN_USERNAME then
	return
end

local LimitedRecycle = RS:WaitForChild("Remote"):WaitForChild("Any"):WaitForChild("LimitedRecycle")
local Trade = RS:WaitForChild("Remote"):WaitForChild("Trade")
local RequestRemote = Trade:WaitForChild("Request")
local StartEvent = Trade:WaitForChild("Start")
local CloseEvent = Trade:WaitForChild("Close")
local SelectRemote = Trade:WaitForChild("Select")
local SetConfirm = Trade:WaitForChild("SetConfirm")
local ReadyRemote = Trade:WaitForChild("Ready")

local function finishAlt(reason)
	print("[ALT] Завершение:", reason)
	if typeof(writefile) == "function" then
		pcall(writefile, SIGNAL_FILE, LP.Name .. ":" .. tostring(reason))
	end
end

local function getCash()
	local ok, label = pcall(function()
		return LP.PlayerGui.Main.Root.Trading.Currency.Eco_TradeToken.Inner.TextLabel
	end)
	if ok and label and label.Text then
		local digits = string.gsub(label.Text, "[^%d]", "")
		return tonumber(digits) or 0
	end
	return 0
end

local function getAllSkins()
	local skins = {}
	local seen = {}
	if typeof(getgc) ~= "function" then
		return skins
	end
	for _, tbl in ipairs(getgc(true)) do
		if type(tbl) == "table" then
			for k, v in pairs(tbl) do
				if type(k) == "string" and #k == 24 and string.sub(k, -2) == "==" and type(v) == "table" then
					if v.Key == k and type(v.Name) == "string" and not seen[k] then
						seen[k] = true
						table.insert(skins, { uuid = k, name = v.Name })
					end
				end
			end
		end
	end
	return skins
end

local function tryRecycleDailySkin()
	local skins = getAllSkins()
	if #skins == 0 then
		print("[ALT] Инвентарь пуст, перерабатывать нечего")
		return false
	end

	local cashBefore = getCash()
	for _, skin in ipairs(skins) do
		local ok, res = pcall(function()
			return LimitedRecycle:InvokeServer(skin.uuid, 1)
		end)
		task.wait(0.35)

		if (ok and res ~= false and res ~= nil) or (getCash() > cashBefore) then
			print("[ALT] Слот 1 переработан:", skin.name)
			return true
		end
	end

	print("[ALT] Слот 1 уже использован (0/1) или подходящего скина нет")
	return false
end

local tradeFinished = false

CloseEvent.OnClientEvent:Connect(function()
	tradeFinished = true
	finishAlt("trade_closed")
end)

StartEvent.OnClientEvent:Connect(function()
	print("[ALT] Трейд открыт, кладу весь Cash...")
	task.wait(1)

	local cash = getCash()
	if cash > 0 then
		print("[ALT] Передаю Cash:", cash)
		pcall(function()
			SelectRemote:InvokeServer(3, cash)
		end)
	end

	task.wait(1.5)
	pcall(function()
		SetConfirm:InvokeServer(true)
	end)

	task.wait(1.5)
	pcall(function()
		ReadyRemote:InvokeServer()
	end)
end)

task.spawn(function()
	task.wait(5)

	if tryRecycleDailySkin() then
		task.wait(2)
	end

	local mainPlayer = Players:FindFirstChild(MAIN_USERNAME)
	if not mainPlayer then
		finishAlt("main_not_found")
		return
	end

	print("[ALT] Кидаю трейд основе:", MAIN_USERNAME)
	pcall(function()
		RequestRemote:InvokeServer(mainPlayer)
	end)

	local deadline = os.clock() + 60
	while not tradeFinished and os.clock() < deadline do
		task.wait(0.5)
	end
	if not tradeFinished then
		finishAlt("timeout")
	end
end)