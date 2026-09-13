-- ============================================================
--  MONOCHROME ESP + UTILITIES (standalone)
--  Game: MONOCHROME (PlaceId 134208374070897)
--
--  Standalone project. No Uranium, no libraries required.
--  Run:
--    loadstring(game:HttpGet("https://raw.githubusercontent.com/Korsac2026/monochrome/main/monochrome-esp.lua"))()
--
--  Features:
--    1) Monster ESP : highlights the monster (outline + name + distance)
--    2) Key ESP     : marks key locations on the map
--    3) Code ESP    : marks WHERE the code IS (world texts/notes/screens
--                     showing digits), NOT the keypad where you type it
--    4) Noclip / Fly / Speed
--    5) Auto Win    : flies to the 4 keys, grabs them (E), opens the
--                     deadbolts, flies to the elevator panel with the code
--  All monochrome (black & white). RightShift shows/hides the GUI.
-- ============================================================

if getgenv and getgenv().MonochromeESP then
	pcall(function() getgenv().MonochromeESP.Unload() end)
	getgenv().MonochromeESP = nil
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local TARGET_PLACE = 134208374070897
local KEYS_NEEDED = 4

-- Monochrome palette
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PANEL = Color3.fromRGB(12, 12, 12)
local ROW_OFF = Color3.fromRGB(28, 28, 28)
local ROW_ON = Color3.fromRGB(225, 225, 225)
local TXT_ON = Color3.fromRGB(235, 235, 235)
local TXT_DIM = Color3.fromRGB(150, 150, 150)

-- Names that give away the monster (lowercase, partial match)
local MONSTER_NAMES = {
	"monster", "monstruo", "entity", "beast", "bestia",
	"killer", "asesino", "creature", "criatura", "demon", "demonio",
	"ghost", "fantasma", "stalker", "acosador", "hunter", "cazador",
	"slender", "chaser", "perseguidor", "predator", "depredador",
	"wraith", "specter", "spectre", "phantom", "shade",
	"crawler", "lurker", "nightmare", "pesadilla", "horror",
	"terror", "jumpscare", "susto", "morph", "boss", "jefe",
	"enemy", "enemigo", "eye", "ojo",
}
-- Folders whose humanoid contents count as the monster
local MONSTER_FOLDERS = {
	"monster", "monsters", "monstruo", "entity", "entities",
	"npcs", "enemies", "killers", "bosses", "ai", "enemy",
}
-- Key names (world pickups AND inventory tools)
local KEY_NAMES = { "key", "llave", "keycard" }
-- Entry/exit objects used by Auto Win navigation (NOT marked by Code ESP)
local ENTRY_NAMES = { "keypad", "teclado", "panel", "elevator", "elevador" }
local DEADBOLT_NAMES = { "deadbolt", "cerrojo", "exit", "salida", "door", "puerta" }

local DIST_STEPS = { 150, 300, 500, 1000, 999999 }
local DIST_LABELS = { "150m", "300m", "500m", "1000m", "INF" }
local SPEED_STEPS = { 16, 24, 32, 50, 75, 100, 150 }

local State = {
	running = true,
	monster = true,
	keys = true,
	codes = true,
	npcScan = false, -- mark ANY non-player humanoid as monster
	noclip = false,
	fly = false,
	speedIdx = 1, -- index into SPEED_STEPS (16)
	distStep = 3, -- index into DIST_STEPS (500m)
	autowin = false,
}

local Tracked = {} -- [instance] = {kind, target, part, hl, bb, txt, digits, label, root}
local Connections = {}
local Painters = {} -- GUI repaint functions set by buildGui
local StatusText = "starting..."

local function trackConnection(conn)
	Connections[#Connections + 1] = conn
	return conn
end

local function setStatus(s)
	StatusText = s
end

local function lowerName(inst)
	local ok, name = pcall(function() return inst.Name end)
	if not ok or type(name) ~= "string" then return "" end
	return string.lower(name)
end

local function matchesAny(nameLower, list)
	for i = 1, #list do
		if string.find(nameLower, list[i], 1, true) then
			return true
		end
	end
	return false
end

local function isPlayerCharacter(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return false end
	local ok, plr = pcall(function() return Players:GetPlayerFromCharacter(model) end)
	return ok and plr ~= nil
end

local function isUnderPlayer(obj)
	local node = obj
	while node do
		if node:IsA("Model") and isPlayerCharacter(node) then return true end
		if node == Players or node == LocalPlayer then return true end
		if node:IsA("Backpack") or node:IsA("PlayerGui") then return true end
		node = node.Parent
	end
	return false
end

local function inWorkspace(obj)
	local ok, res = pcall(function() return obj:IsDescendantOf(workspace) end)
	return ok and res
end

local function hasMonsterFolderAncestor(model)
	local node = model.Parent
	local depth = 0
	while node and node ~= workspace and node ~= game and depth < 6 do
		local n = lowerName(node)
		for i = 1, #MONSTER_FOLDERS do
			if n == MONSTER_FOLDERS[i] then return true end
		end
		node = node.Parent
		depth = depth + 1
	end
	return false
end

local function hasHumanoid(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return false end
	return model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function myCharacter()
	return LocalPlayer and LocalPlayer.Character or nil
end

local function myHRP()
	local char = myCharacter()
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function myHumanoid()
	local char = myCharacter()
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

-- Classify a workspace instance. Returns kind ("monster"/"key") + label, or nil.
-- NOTE: codes are handled by the text scanner (scanCodeTexts), NOT by name,
-- so Code ESP marks where the code IS, never the keypad where you type it.
local function classify(inst)
	if typeof(inst) ~= "Instance" then return nil end
	if not inst:IsA("Model") and not inst:IsA("Tool") and not inst:IsA("BasePart") then
		return nil
	end
	if isUnderPlayer(inst) then return nil end
	-- Loose parts inside a model are evaluated through the model
	if inst:IsA("BasePart") and inst.Parent and (inst.Parent:IsA("Model") or inst.Parent:IsA("Tool")) then
		return nil
	end

	local name = lowerName(inst)

	-- Monster: by name
	if (inst:IsA("Model") or inst:IsA("BasePart")) and matchesAny(name, MONSTER_NAMES) then
		return "monster", "MONSTER"
	end
	-- Monster: humanoid inside a suspicious folder
	if inst:IsA("Model") and not isPlayerCharacter(inst) and hasHumanoid(inst) and hasMonsterFolderAncestor(inst) then
		return "monster", "MONSTER"
	end
	-- Monster: full NPC scan (optional)
	if State.npcScan and inst:IsA("Model") and not isPlayerCharacter(inst) and hasHumanoid(inst) then
		return "monster", "MONSTER"
	end
	-- Keys
	if matchesAny(name, KEY_NAMES) then
		return "key", "KEY"
	end
	return nil
end

-- Resolve what to adorn: returns target (Model/BasePart for Highlight)
-- plus one BasePart for the billboard and distance measuring.
local function resolveTarget(inst)
	if inst:IsA("BasePart") then
		return inst, inst
	end
	if inst:IsA("Model") then
		local part = inst:FindFirstChild("HumanoidRootPart")
			or inst:FindFirstChild("Head")
			or inst.PrimaryPart
			or inst:FindFirstChildWhichIsA("BasePart", true)
		if part and part:IsA("BasePart") then
			return inst, part
		end
		return inst, nil
	end
	if inst:IsA("Tool") then
		local part = inst:FindFirstChild("Handle")
			or inst:FindFirstChildWhichIsA("BasePart", true)
		if part and part:IsA("BasePart") then
			return part, part
		end
		return nil, nil
	end
	return nil, nil
end

local EspFolder = nil

local function makeEspObjects(target, part)
	local hl = Instance.new("Highlight")
	hl.Name = "MonoESP_HL"
	hl.Adornee = target
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0
	hl.OutlineColor = WHITE
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = EspFolder

	local bb = Instance.new("BillboardGui")
	bb.Name = "MonoESP_BB"
	bb.Adornee = part
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 220, 0, 44)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.Parent = EspFolder

	local txt = Instance.new("TextLabel")
	txt.Name = "Label"
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.Font = Enum.Font.GothamBold
	txt.TextSize = 14
	txt.TextColor3 = WHITE
	txt.TextStrokeTransparency = 0
	txt.TextStrokeColor3 = BLACK
	txt.Text = ""
	txt.Parent = bb

	return hl, bb, txt
end

-- Given a TextLabel/TextButton, find the world part it is displayed on.
-- Returns nil for player UI (ScreenGui) so we never mark menus.
local function adorneePartForText(txtInst)
	local node = txtInst
	while node and not node:IsA("SurfaceGui") and not node:IsA("BillboardGui") and not node:IsA("ScreenGui") do
		node = node.Parent
	end
	if not node then return nil end
	if not inWorkspace(node) then return nil end
	if node:IsA("BillboardGui") then
		local ad = node.Adornee
		if ad and ad:IsA("BasePart") and inWorkspace(ad) then return ad end
		return nil
	elseif node:IsA("SurfaceGui") then
		local ad = node.Adornee
		if ad and ad:IsA("BasePart") and inWorkspace(ad) then return ad end
		local par = node.Parent
		if par and par:IsA("BasePart") and inWorkspace(par) then return par end
		return nil
	end
	return nil
end

local function digitsInString(s)
	if type(s) ~= "string" then return nil end
	local m4 = string.match(s, "%d%d%d%d")
	if m4 then return string.sub(m4, 1, 8) end
	local m3 = string.match(s, "%d%d%d+")
	if m3 then return string.sub(m3, 1, 8) end
	return nil
end

-- Scan every world text for digits. This is what Code ESP marks:
-- the NOTE / SCREEN / PAPER where the code IS.
local function scanCodeTexts()
	if not State.codes then return end
	local descs = workspace:GetDescendants()
	for i = 1, #descs do
		local d = descs[i]
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and not Tracked[d] then
			local digits = nil
			pcall(function() digits = digitsInString(d.Text) end)
			if digits then
				local part = adorneePartForText(d)
				if part then
					local hl, bb, txt = makeEspObjects(part, part)
					Tracked[d] = { kind = "code", target = part, part = part, hl = hl, bb = bb, txt = txt, digits = digits, label = "CODE", root = d }
				end
			end
		elseif (d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue")) and not Tracked[d] then
			local n = lowerName(d)
			if string.find(n, "code", 1, true) or string.find(n, "pass", 1, true) or string.find(n, "pin", 1, true) then
				local val = tostring(d.Value)
				if digitsInString(val) then
					local host = d.Parent
					local part = nil
					if host and host:IsA("BasePart") then
						part = host
					elseif host and host:IsA("Model") then
						local _, p = resolveTarget(host)
						part = p
					end
					if part then
						local hl, bb, txt = makeEspObjects(part, part)
						Tracked[d] = { kind = "code", target = part, part = part, hl = hl, bb = bb, txt = txt, digits = string.sub(val, 1, 8), label = "CODE", root = d }
					end
				end
			end
		end
	end
end

-- First 4-digit code found (preferred), else any digit string.
local function getFoundCode()
	local fallback = nil
	for _, e in pairs(Tracked) do
		if e.kind == "code" and e.digits then
			if #e.digits == 4 then return e.digits end
			if not fallback then fallback = e.digits end
		end
	end
	return fallback
end

local function removeEntry(inst)
	local e = Tracked[inst]
	if e then
		pcall(function() e.hl:Destroy() end)
		pcall(function() e.bb:Destroy() end)
		Tracked[inst] = nil
	end
end

local function clearKind(kind)
	for inst, e in pairs(Tracked) do
		if e.kind == kind then
			removeEntry(inst)
		end
	end
end

local function isKindEnabled(kind)
	if kind == "monster" then return State.monster end
	if kind == "key" then return State.keys end
	if kind == "code" then return State.codes end
	return false
end

local function addEntry(inst)
	if Tracked[inst] then return end
	if not inWorkspace(inst) then return end
	local kind, label = classify(inst)
	if not kind then return end
	if not isKindEnabled(kind) then return end
	local target, part = resolveTarget(inst)
	if not target or not part then
		-- No parts yet (streaming): keep pending, resolved in the loop
		Tracked[inst] = { kind = kind, target = nil, part = nil, hl = nil, bb = nil, txt = nil, digits = nil, label = label, root = inst }
		return
	end
	local hl, bb, txt = makeEspObjects(target, part)
	Tracked[inst] = { kind = kind, target = target, part = part, hl = hl, bb = bb, txt = txt, digits = nil, label = label, root = inst }
end

local function fullScan()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("Tool") then
			pcall(addEntry, inst)
		elseif inst:IsA("BasePart") and inst.Parent and not (inst.Parent:IsA("Model") or inst.Parent:IsA("Tool")) then
			pcall(addEntry, inst)
		end
	end
	scanCodeTexts()
end

local function rootPosition()
	local hrp = myHRP()
	if hrp then return hrp.Position end
	if Camera then return Camera.CFrame.Position end
	return Vector3.new(0, 0, 0)
end

local Gui = nil
local StatusLabel = nil

local function countTargets()
	local m, k, c = 0, 0, 0
	for _, e in pairs(Tracked) do
		if e.hl then
			if e.kind == "monster" then m = m + 1
			elseif e.kind == "key" then k = k + 1
			elseif e.kind == "code" then c = c + 1 end
		end
	end
	return m, k, c
end

local function refreshCodeDigits(e)
	-- Re-read live text (a code can appear later on the same label)
	if e.kind ~= "code" then return true end
	local root = e.root
	if root:IsA("TextLabel") or root:IsA("TextButton") then
		local digits = nil
		pcall(function() digits = digitsInString(root.Text) end)
		if digits then
			e.digits = digits
			return true
		end
		return false -- code text is gone, drop the entry
	elseif root:IsA("StringValue") or root:IsA("IntValue") or root:IsA("NumberValue") then
		local val = tostring(root.Value)
		if digitsInString(val) then
			e.digits = string.sub(val, 1, 8)
			return true
		end
		return false
	end
	return true
end

local function updateEntry(e, origin, maxDist, refreshDigits)
	local root = e.root
	if not root or not inWorkspace(root) then
		return false -- flag for removal
	end
	-- Resolve pending parts (streaming)
	if not e.target or not e.part then
		local target, part = resolveTarget(root)
		if target and part and EspFolder then
			local hl, bb, txt = makeEspObjects(target, part)
			e.target, e.part, e.hl, e.bb, e.txt = target, part, hl, bb, txt
		else
			return true -- still pending
		end
	end
	if e.kind == "code" and refreshDigits then
		if not refreshCodeDigits(e) then
			return false
		end
	end
	local pos = e.part.Position
	local dist = (pos - origin).Magnitude
	if dist > maxDist then
		e.hl.Enabled = false
		e.bb.Enabled = false
		return true
	end
	e.hl.Enabled = true
	e.bb.Enabled = true
	local title = e.label
	if e.kind == "code" and e.digits then
		title = "CODE " .. e.digits
	end
	e.txt.Text = title .. "\n" .. tostring(math.floor(dist)) .. "m"
	return true
end

-- ===================== MOVEMENT (noclip / fly / speed) =====================

local FlyBV, FlyBG = nil, nil
local FlyKeys = { W = false, A = false, S = false, D = false, Up = false, Down = false }

local function applySpeed()
	local hum = myHumanoid()
	if hum then
		pcall(function() hum.WalkSpeed = SPEED_STEPS[State.speedIdx] end)
	end
end

local function setNoclipParts(collide)
	local char = myCharacter()
	if not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			if p.Name == "HumanoidRootPart" then
				pcall(function() p.CanCollide = false end)
			else
				pcall(function() p.CanCollide = collide end)
			end
		end
	end
end

local function enableFly()
	if FlyBV then return end
	local hrp = myHRP()
	if not hrp then return end
	FlyBV = Instance.new("BodyVelocity")
	FlyBV.Name = "MonoFlyBV"
	FlyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	FlyBV.Velocity = Vector3.new(0, 0, 0)
	FlyBV.Parent = hrp
	FlyBG = Instance.new("BodyGyro")
	FlyBG.Name = "MonoFlyBG"
	FlyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	FlyBG.CFrame = hrp.CFrame
	FlyBG.Parent = hrp
end

local function disableFly()
	if FlyBV then pcall(function() FlyBV:Destroy() end) end
	if FlyBG then pcall(function() FlyBG:Destroy() end) end
	FlyBV, FlyBG = nil, nil
	local hrp = myHRP()
	if hrp then
		pcall(function() hrp.Velocity = Vector3.new(0, 0, 0) end)
	end
end

local function flyStep()
	if not State.fly or not FlyBV or not FlyBG then return end
	local hrp = myHRP()
	if not hrp or not Camera then return end
	local speed = SPEED_STEPS[State.speedIdx] + 44 -- fly a bit faster than walk
	local cf = Camera.CFrame
	local move = Vector3.new(0, 0, 0)
	if FlyKeys.W then move = move + cf.LookVector end
	if FlyKeys.S then move = move - cf.LookVector end
	if FlyKeys.D then move = move + cf.RightVector end
	if FlyKeys.A then move = move - cf.RightVector end
	if FlyKeys.Up then move = move + Vector3.new(0, 1, 0) end
	if FlyKeys.Down then move = move - Vector3.new(0, 1, 0) end
	if move.Magnitude > 0 then
		move = move.Unit * speed
	end
	pcall(function()
		FlyBV.Velocity = move
		FlyBG.CFrame = cf
	end)
end

-- ===================== INTERACTION (grab / prompts) =====================

local function firePrompt(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return end
	if typeof(fireproximityprompt) == "function" then
		pcall(fireproximityprompt, prompt)
	end
	task.wait((prompt.HoldDuration or 0) + 0.25)
end

local function firePromptsIn(model)
	if typeof(model) ~= "Instance" then return end
	local ok, descs = pcall(function() return model:GetDescendants() end)
	if not ok then return end
	for i = 1, #descs do
		if descs[i]:IsA("ProximityPrompt") then
			firePrompt(descs[i])
		end
	end
end

local function countKeysHeld()
	local n = 0
	local function scan(container)
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and matchesAny(lowerName(t), KEY_NAMES) then
				n = n + 1
			end
		end
	end
	pcall(scan, LocalPlayer.Backpack)
	local char = myCharacter()
	if char then pcall(scan, char) end
	return n
end

-- Smooth flight toward a position. Returns true on arrival.
local function flyTo(pos, timeout)
	local t0 = os.clock()
	timeout = timeout or 14
	while State.autowin and State.running do
		local hrp = myHRP()
		if not hrp then return false end
		local d = pos - hrp.Position
		if d.Magnitude < 5 then return true end
		if os.clock() - t0 > timeout then return false end
		hrp.CFrame = CFrame.new(hrp.Position + d.Unit * math.min(3.5, d.Magnitude))
		task.wait(0.05)
	end
	return false
end

local function keyTargets()
	local list = {}
	for inst, e in pairs(Tracked) do
		if e.kind == "key" and e.part and inWorkspace(inst) then
			list[#list + 1] = { inst = inst, pos = e.part.Position }
		end
	end
	return list
end

local function nearestKey(origin)
	local best, bestDist = nil, math.huge
	for _, k in ipairs(keyTargets()) do
		local d = (k.pos - origin).Magnitude
		if d < bestDist then
			best, bestDist = k, d
		end
	end
	return best
end

-- Objects with prompts where keys get used (deadbolts / exit / doors)
local function deadboltTargets()
	local list = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			local host = inst.Parent
			local scope = host and host.Parent or nil
			local hay = lowerName(host) .. " " .. lowerName(scope)
			local hit = false
			for i = 1, #DEADBOLT_NAMES do
				if string.find(hay, DEADBOLT_NAMES[i], 1, true) then hit = true break end
			end
			if hit then
				local part = host:IsA("BasePart") and host or (host and host:FindFirstChildWhichIsA("BasePart", true))
				if part then
					list[#list + 1] = { prompt = inst, pos = part.Position }
				end
			end
		end
	end
	return list
end

-- Elevator / code entry panel position (internal navigation only)
local function findEntryPanel()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			if matchesAny(lowerName(inst), ENTRY_NAMES) then
				local hasIO = false
				pcall(function()
					hasIO = inst:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
						or inst:FindFirstChildWhichIsA("ClickDetector", true) ~= nil
				end)
				if hasIO then
					local _, part = resolveTarget(inst)
					if part then return inst, part.Position end
				end
			end
		end
	end
	return nil, nil
end

local function pressPanelDigits(panelModel, code)
	for i = 1, #code do
		if not State.autowin then return end
		local digit = string.sub(code, i, i)
		local found = nil
		for _, d in ipairs(panelModel:GetDescendants()) do
			if d:IsA("ClickDetector") and lowerName(d.Parent) == digit then
				found = d
				break
			end
		end
		if found and typeof(fireclickdetector) == "function" then
			pcall(fireclickdetector, found)
		end
		task.wait(0.45)
	end
end

local function autoWinLoop()
	while State.autowin and State.running do
		-- Phase 1: collect the 4 keys
		setStatus("AUTO WIN: collecting keys (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. ")")
		local guard = 0
		while State.autowin and State.running and countKeysHeld() < KEYS_NEEDED and guard < 24 do
			guard = guard + 1
			local target = nearestKey(rootPosition())
			if not target then
				fullScan()
				scanCodeTexts()
				target = nearestKey(rootPosition())
				if not target then break end
			end
			if flyTo(target.pos + Vector3.new(0, 4, 0)) then
				local inst = target.inst
				local before = countKeysHeld()
				for attempt = 1, 3 do
					if not State.autowin then break end
					firePromptsIn(inst)
					local hrp = myHRP()
					if hrp and inWorkspace(inst) then
						local _, part = resolveTarget(inst)
						if part then
							hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
						end
					end
					task.wait(0.6)
					if not inWorkspace(inst) or countKeysHeld() > before then break end
				end
			end
			task.wait(0.2)
		end
		if not State.autowin or not State.running then break end

		-- Phase 2: use keys on deadbolts / exit
		setStatus("AUTO WIN: opening deadbolts (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. " keys)")
		for _, db in ipairs(deadboltTargets()) do
			if not State.autowin then break end
			if flyTo(db.pos + Vector3.new(0, 3, 0), 10) then
				firePrompt(db.prompt)
				firePrompt(db.prompt)
				task.wait(0.4)
			end
		end
		if not State.autowin or not State.running then break end

		-- Phase 3: elevator panel + code
		local code = getFoundCode()
		if not code then
			scanCodeTexts()
			code = getFoundCode()
		end
		local panel, panelPos = findEntryPanel()
		if panel and panelPos then
			flyTo(panelPos + Vector3.new(0, 4, 0))
			if code and #code == 4 then
				setStatus("AUTO WIN: entering code " .. code)
				pressPanelDigits(panel, code)
				task.wait(1)
			end
		end
		if code then
			setStatus("AUTO WIN done. Code: " .. code)
		else
			setStatus("AUTO WIN done. Code not found, enter it manually.")
		end
		State.autowin = false
		if Painters.autowin then Painters.autowin(false) end
		break
	end
end

-- ===================== GUI =====================

local function uiParent()
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and hui then return hui end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then return cg end
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function makeRow(parent, order, text, initial, callback)
	local btn = Instance.new("TextButton")
	btn.Name = "Row" .. text
	btn.Size = UDim2.new(1, -16, 0, 32)
	btn.Position = UDim2.new(0, 8, 0, 44 + (order - 1) * 36)
	btn.BackgroundColor3 = initial and ROW_ON or ROW_OFF
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.Text = "  " .. text
	btn.TextColor3 = initial and BLACK or TXT_ON
	btn.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	local state = Instance.new("TextLabel")
	state.BackgroundTransparency = 1
	state.Size = UDim2.new(0, 52, 1, 0)
	state.Position = UDim2.new(1, -56, 0, 0)
	state.Font = Enum.Font.GothamBold
	state.TextSize = 12
	state.TextXAlignment = Enum.TextXAlignment.Right
	state.Text = ""
	state.TextColor3 = initial and BLACK or TXT_DIM
	state.Parent = btn
	local on = initial
	local function paint(v)
		if v ~= nil then on = v end
		btn.BackgroundColor3 = on and ROW_ON or ROW_OFF
		btn.TextColor3 = on and BLACK or TXT_ON
		state.TextColor3 = on and BLACK or TXT_DIM
		state.Text = on and "ON" or "OFF"
	end
	paint()
	btn.MouseButton1Click:Connect(function()
		paint(not on)
		callback(on)
	end)
	return btn, paint
end

local function makeCycle(parent, order, prefix, labels, initialIdx, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -16, 0, 32)
	btn.Position = UDim2.new(0, 8, 0, 44 + (order - 1) * 36)
	btn.BackgroundColor3 = ROW_OFF
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.TextColor3 = TXT_ON
	btn.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	local idx = initialIdx
	local function paint()
		btn.Text = "  " .. prefix .. labels[idx]
	end
	paint()
	btn.MouseButton1Click:Connect(function()
		idx = idx + 1
		if idx > #labels then idx = 1 end
		paint()
		callback(idx)
	end)
	return btn
end

local ROWS = 9

local function buildGui()
	local parent = uiParent()
	local screen = Instance.new("ScreenGui")
	screen.Name = "MonochromeESP"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 9999
	screen.Parent = parent

	local height = 44 + ROWS * 36 + 62
	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 250, 0, height)
	main.Position = UDim2.new(0, 24, 0.5, -height / 2)
	main.BackgroundColor3 = PANEL
	main.BorderSizePixel = 0
	main.Active = true
	main.Parent = screen

	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 1
	stroke.Transparency = 0.25
	stroke.Parent = main
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = main

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 36)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = TXT_ON
	title.Text = "MONOCHROME ESP"
	title.Active = true
	title.Parent = main

	local close = Instance.new("TextButton")
	close.Size = UDim2.new(0, 28, 0, 28)
	close.Position = UDim2.new(1, -34, 0, 4)
	close.BackgroundTransparency = 1
	close.Font = Enum.Font.GothamBold
	close.TextSize = 15
	close.TextColor3 = TXT_DIM
	close.Text = "X"
	close.Parent = main

	-- Drag from the title bar
	local dragging, dragStart, startPos = false, nil, nil
	title.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	local function onDragChanged(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end
	local function onDragEnded(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end

	-- Rows
	local _, pMonster = makeRow(main, 1, "MONSTER ESP", State.monster, function(v)
		State.monster = v
		if v then fullScan() else clearKind("monster") end
	end)
	local _, pKeys = makeRow(main, 2, "KEY ESP", State.keys, function(v)
		State.keys = v
		if v then fullScan() else clearKind("key") end
	end)
	local _, pCodes = makeRow(main, 3, "CODE ESP", State.codes, function(v)
		State.codes = v
		if v then scanCodeTexts() else clearKind("code") end
	end)
	local _, pNpc = makeRow(main, 4, "NPC SCAN (any humanoid)", State.npcScan, function(v)
		State.npcScan = v
		clearKind("monster")
		if State.monster then fullScan() end
	end)
	local _, pNoclip = makeRow(main, 5, "NOCLIP", State.noclip, function(v)
		State.noclip = v
		if not v then setNoclipParts(true) end
	end)
	local _, pFly = makeRow(main, 6, "FLY", State.fly, function(v)
		State.fly = v
		if v then enableFly() else disableFly() end
	end)
	makeCycle(main, 7, "SPEED: ", { "16", "24", "32", "50", "75", "100", "150" }, State.speedIdx, function(idx)
		State.speedIdx = idx
		applySpeed()
	end)
	makeCycle(main, 8, "MAX DIST: ", DIST_LABELS, State.distStep, function(idx)
		State.distStep = idx
	end)
	local _, pAuto = makeRow(main, 9, "AUTO WIN", State.autowin, function(v)
		State.autowin = v
		if v then
			State.noclip = true
			if Painters.noclip then Painters.noclip(true) end
			State.fly = true
			if Painters.fly then Painters.fly(true) end
			enableFly()
			task.spawn(autoWinLoop)
		end
	end)

	Painters.noclip = pNoclip
	Painters.fly = pFly
	Painters.autowin = pAuto
	Painters.monster = pMonster
	Painters.keys = pKeys
	Painters.codes = pCodes
	Painters.npc = pNpc

	StatusLabel = Instance.new("TextLabel")
	StatusLabel.Size = UDim2.new(1, -16, 0, 30)
	StatusLabel.Position = UDim2.new(0, 8, 1, -58)
	StatusLabel.BackgroundTransparency = 1
	StatusLabel.Font = Enum.Font.Code
	StatusLabel.TextSize = 12
	StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	StatusLabel.TextColor3 = TXT_DIM
	StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	StatusLabel.Text = "starting..."
	StatusLabel.Parent = main

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -16, 0, 18)
	hint.Position = UDim2.new(0, 8, 1, -26)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Code
	hint.TextSize = 11
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = TXT_DIM
	hint.Text = "RightShift: show / hide - WASD+Space fly"
	hint.Parent = main

	return screen, main, close, onDragChanged, onDragEnded
end

-- ===================== STARTUP =====================

EspFolder = Instance.new("Folder")
EspFolder.Name = "MonoESP"
EspFolder.Parent = uiParent()

local DragChanged, DragEnded
Gui, _, CloseBtn, DragChanged, DragEnded = buildGui()
local MainFrame = Gui:FindFirstChild("Main")

trackConnection(UserInputService.InputChanged:Connect(DragChanged))
trackConnection(UserInputService.InputEnded:Connect(DragEnded))

trackConnection(CloseBtn.MouseButton1Click:Connect(function()
	if getgenv and getgenv().MonochromeESP then
		pcall(function() getgenv().MonochromeESP.Unload() end)
		getgenv().MonochromeESP = nil
	end
end))

trackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.W then FlyKeys.W = true end
	if input.KeyCode == Enum.KeyCode.A then FlyKeys.A = true end
	if input.KeyCode == Enum.KeyCode.S then FlyKeys.S = true end
	if input.KeyCode == Enum.KeyCode.D then FlyKeys.D = true end
	if input.KeyCode == Enum.KeyCode.Space then FlyKeys.Up = true end
	if input.KeyCode == Enum.KeyCode.LeftShift then FlyKeys.Down = true end
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.RightShift and MainFrame then
		MainFrame.Visible = not MainFrame.Visible
	end
end))

trackConnection(UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.W then FlyKeys.W = false end
	if input.KeyCode == Enum.KeyCode.A then FlyKeys.A = false end
	if input.KeyCode == Enum.KeyCode.S then FlyKeys.S = false end
	if input.KeyCode == Enum.KeyCode.D then FlyKeys.D = false end
	if input.KeyCode == Enum.KeyCode.Space then FlyKeys.Up = false end
	if input.KeyCode == Enum.KeyCode.LeftShift then FlyKeys.Down = false end
end))

trackConnection(workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") or inst:IsA("Tool") then
		pcall(addEntry, inst)
	elseif inst:IsA("BasePart") and inst.Parent and not (inst.Parent:IsA("Model") or inst.Parent:IsA("Tool")) then
		pcall(addEntry, inst)
	elseif (inst:IsA("TextLabel") or inst:IsA("TextButton")) and State.codes then
		task.delay(0.5, function()
			if not State.codes or Tracked[inst] or not inWorkspace(inst) then return end
			local digits = nil
			pcall(function() digits = digitsInString(inst.Text) end)
			if digits then
				local part = adorneePartForText(inst)
				if part then
					local hl, bb, txt = makeEspObjects(part, part)
					Tracked[inst] = { kind = "code", target = part, part = part, hl = hl, bb = bb, txt = txt, digits = digits, label = "CODE", root = inst }
				end
			end
		end)
	end
end))

trackConnection(workspace.DescendantRemoving:Connect(function(inst)
	if Tracked[inst] then
		removeEntry(inst)
	end
end))

trackConnection(LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)
	applySpeed()
	if State.fly then enableFly() end
end))

applySpeed()
fullScan()

local accDist, accCode, accText = 0, 0, 0
trackConnection(RunService.Heartbeat:Connect(function(dt)
	if not State.running then return end
	-- Movement systems
	if State.noclip then
		local char = myCharacter()
		if char then
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") and p.CanCollide then
					pcall(function() p.CanCollide = false end)
				end
			end
		end
	end
	flyStep()
	-- ESP refresh timers
	accDist = accDist + dt
	accCode = accCode + dt
	accText = accText + dt
	local doDist = accDist >= 0.3
	local doCode = accCode >= 1.5
	local doText = accText >= 8
	if doDist then accDist = 0 end
	if doCode then accCode = 0 end
	if doText then
		accText = 0
		if State.codes then scanCodeTexts() end
	end
	if not doDist and not doCode then return end
	local origin = rootPosition()
	local maxDist = DIST_STEPS[State.distStep]
	local dead = {}
	for inst, e in pairs(Tracked) do
		if not isKindEnabled(e.kind) then
			dead[#dead + 1] = inst
		else
			local ok, alive = pcall(updateEntry, e, origin, maxDist, doCode and e.kind == "code")
			if not ok or not alive then
				dead[#dead + 1] = inst
			end
		end
	end
	for i = 1, #dead do
		removeEntry(dead[i])
	end
	if doDist and StatusLabel then
		if not State.autowin then
			local m, k, c = countTargets()
			local code = getFoundCode()
			local note = ""
			if game.PlaceId ~= TARGET_PLACE then
				note = " (outside MONOCHROME)"
			end
			local codeTxt = code and ("  code:" .. code) or ""
			StatusLabel.Text = "monster:" .. m .. "  key:" .. k .. "  code:" .. c .. codeTxt .. "  keys:" .. countKeysHeld() .. "/4" .. note
		else
			StatusLabel.Text = StatusText
		end
	end
	-- Keep walkspeed applied (the game may reset it)
	local hum = myHumanoid()
	if hum and hum.WalkSpeed ~= SPEED_STEPS[State.speedIdx] then
		applySpeed()
	end
end))

local Api = {}
function Api.Unload()
	State.running = false
	State.autowin = false
	State.fly = false
	State.noclip = false
	disableFly()
	for _, conn in ipairs(Connections) do
		pcall(function() conn:Disconnect() end)
	end
	for inst in pairs(Tracked) do
		removeEntry(inst)
	end
	pcall(function() EspFolder:Destroy() end)
	pcall(function() Gui:Destroy() end)
end

if getgenv then
	getgenv().MonochromeESP = Api
end

return Api
