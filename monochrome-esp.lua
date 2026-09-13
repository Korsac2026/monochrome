-- ============================================================
--  URANIUM for MONOCHROME (standalone)
--  Game: MONOCHROME (PlaceId 134208374070897)
--  UI: Zolar Ui (https://github.com/Da7mu/Ui-Collection)
--
--  Standalone project. No other libraries required
--  (besides Zolar Ui, loaded remotely below).
--  Run:
--    loadstring(game:HttpGet("https://raw.githubusercontent.com/Korsac2026/monochrome/main/monochrome-esp.lua"))()
--
--  Tabs:
--    ESP      : Monster ESP, Key ESP, Code ESP (marks the NOTE/PAPER
--               where the code IS — handwritten digits live in the paper
--               texture, plus world texts/values showing digits).
--               It never marks the keypad where you type the code.
--    Movement : Noclip, Fly, Walk Speed, Fly Speed
--    Auto     : Auto Win (instant teleport: clears entrance, opens
--               drawers, grabs 4 keys, opens deadbolts, reads notes,
--               flies to the elevator panel and ENTERS the code)
--    Settings : theme, text size, collect distance, rescan, unload
--  Menu key: RightShift. All monochrome (black & white).
-- ============================================================

-- ---------- cleanup previous run ----------
pcall(function()
	local old = getgenv and (getgenv().UraniumMono or getgenv().MonochromeESP) or nil
	if old then
		if old.Window then pcall(function() old.Window:SetOpen(false) end) end
		if old.Unload then pcall(old.Unload) end
	end
	if getgenv then
		getgenv().UraniumMono = nil
		getgenv().MonochromeESP = nil
	end
end)

-- ---------- load Zolar Ui ----------
local Zolar = nil
do
	local urls = {
		"https://raw.githubusercontent.com/Da7mu/Ui-Collection/refs/heads/main/Zolar%20Ui/Library.lua",
		"https://raw.githubusercontent.com/Da7mu/Ui-Collection/main/Zolar%20Ui/Library.lua",
	}
	local err
	for i = 1, #urls do
		local ok, lib = pcall(function()
			return loadstring(game:HttpGet(urls[i]))()
		end)
		if ok and lib then Zolar = lib break end
		err = lib
	end
	if not Zolar then
		error("[Uranium] Zolar Ui failed to load: " .. tostring(err), 0)
	end
end
-- Keep RightShift menu convention (Zolar default is G, used by goggles).
pcall(function() Zolar.MenuKeybind = Enum.KeyCode.RightShift end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local TARGET_PLACE = 134208374070897
local KEYS_NEEDED = 4

-- Monochrome palette (ESP visuals)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Our own ESP object names (never scan/mark these or we loop on ourselves)
local OWN_NAMES = {
	["UraniumESP"] = true,
	["Uranium_HL"] = true,
	["Uranium_BB"] = true,
	["MonoESP"] = true,
	["MonoESP_HL"] = true,
	["MonoESP_BB"] = true,
}

local function isOurEsp(inst)
	local node = inst
	while node do
		local ok, nm = pcall(function() return node.Name end)
		if ok and OWN_NAMES[nm] then return true end
		node = node.Parent
	end
	return false
end

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
-- Paper/note-like objects: this is WHERE the code IS. Handwritten digits
-- live in the paper texture (not a TextLabel), so detect the object itself.
local NOTE_NAMES = {
	"note", "nota", "paper", "papel", "page", "pagina",
	"sheet", "hoja", "sticky", "postit", "post-it", "memo", "letter", "carta",
	"diary", "diario", "notebook", "libreta", "cuaderno", "clue",
	"pista", "hint", "document", "documento", "password", "contrasena",
	"passcode", "cipher", "cifra", "cifrado", "code", "codigo", "pin",
	"combination", "combinacion", "secret", "secreto", "receipt", "ticket",
}
-- Prompt action/object words meaning "read this" (the note gives the code)
local READ_WORDS = {
	"read", "leer", "view", "ver", "inspect", "inspeccionar",
	"look", "mirar", "check", "revisar", "examine", "examinar",
}
-- Entry objects: where you TYPE the code. NEVER marked by Code ESP,
-- only used internally by Auto Win navigation.
local ENTRY_SKIP = {
	"keypad", "teclado", "elevator", "elevador", "lock", "cerradura",
	"locker", "casillero", "safe", "cajafuerte", "vault", "boveda",
	"computer", "computadora", "ordenador", "terminal", "digit", "digito",
	"button", "boton", "door", "puerta", "deadbolt", "cerrojo", "exit", "salida",
	"panel",
}
-- Containers Auto Win opens first (keys hide inside drawers)
local DRAWER_NAMES = {
	"drawer", "cajon", "dresser", "tocador", "cabinet", "gabinete",
	"cupboard", "alacena", "crate", "chest", "cofre",
	"container", "contenedor", "furniture", "mueble",
}
-- Blockers cleared at run start (boarded doorway)
local PLANK_NAMES = { "plank", "tabla", "tablon", "pry", "palanca", "board", "madera", "nail", "clavo", "barricade", "barricada" }
-- Exit / deadbolt objects
local DEADBOLT_NAMES = { "deadbolt", "cerrojo", "exit", "salida", "door", "puerta" }
-- Words that must never be treated as exit targets (hiding spots)
local NEVER_EXIT = { "closet", "armario", "hide", "esconder" }

local State = {
	running = true,
	monster = true,
	keys = true,
	codes = true,
	npcScan = false, -- mark ANY non-player humanoid as monster
	noclip = false,
	fly = false,
	speed = 16, -- WalkSpeed
	flySpeed = 70,
	maxDist = 500,
	collectDist = 4, -- stand-off distance when Auto Win grabs (studs)
	textSize = 14,
	autowin = false,
}

local Tracked = {} -- [instance] = {kind, target, part, hl, bb, txt, digits, label, root}
local Connections = {}
local UiRefs = {} -- Zolar control refs for programmatic sync

local function trackConnection(conn)
	Connections[#Connections + 1] = conn
	return conn
end

local function notify(title, desc, icon)
	if Zolar then
		pcall(function()
			Zolar:Notification({ Name = title, Description = desc or "", Icon = icon or "bell", Duration = 5 })
		end)
	end
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

local function isEntryObject(inst)
	-- Keypads/panels/locks/safes are where you TYPE the code: never Code ESP.
	return matchesAny(lowerName(inst), ENTRY_SKIP)
end

-- Classify a workspace instance. Returns kind ("monster"/"key"/"code") + label, or nil.
local function classify(inst)
	if typeof(inst) ~= "Instance" then return nil end
	if isOurEsp(inst) then return nil end
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
	-- Code location: paper/note-like objects (handwritten code lives here).
	-- Entry objects (keypads/panels/locks) are explicitly excluded.
	if matchesAny(name, NOTE_NAMES) and not isEntryObject(inst) then
		return "code", "NOTE"
	end
	return nil
end

-- A "read this" prompt means its host shows the code: mark it as NOTE.
local function readPromptHost(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return nil end
	local s = lowerName(prompt) .. " " .. tostring(prompt.ObjectText or ""):lower() .. " " .. tostring(prompt.ActionText or ""):lower()
	local hit = false
	for i = 1, #READ_WORDS do
		if string.find(s, READ_WORDS[i], 1, true) then hit = true break end
	end
	if not hit then
		for i = 1, #NOTE_NAMES do
			if string.find(s, NOTE_NAMES[i], 1, true) then hit = true break end
		end
	end
	if not hit then return nil end
	local host = prompt.Parent
	if not host or isOurEsp(host) or isEntryObject(host) then return nil end
	if host:IsA("BasePart") then return host end
	if host:IsA("Model") or host:IsA("Tool") then return host end
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
	hl.Name = "Uranium_HL"
	hl.Adornee = target
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0
	hl.OutlineColor = WHITE
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = EspFolder

	local bb = Instance.new("BillboardGui")
	bb.Name = "Uranium_BB"
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
	txt.TextSize = State.textSize
	txt.TextColor3 = WHITE
	txt.TextStrokeTransparency = 0
	txt.TextStrokeColor3 = BLACK
	txt.Text = ""
	txt.Parent = bb

	return hl, bb, txt
end

-- Given a TextLabel/TextButton, find the world part it is displayed on.
-- Returns nil for player UI (ScreenGui) so we never mark menus,
-- and nil for our own ESP labels so we never loop on ourselves.
local function adorneePartForText(txtInst)
	if isOurEsp(txtInst) then return nil end
	local node = txtInst
	while node and not node:IsA("SurfaceGui") and not node:IsA("BillboardGui") and not node:IsA("ScreenGui") do
		node = node.Parent
	end
	if not node then return nil end
	if not inWorkspace(node) then return nil end
	if node:IsA("BillboardGui") then
		local ad = node.Adornee
		if ad and ad:IsA("BasePart") and inWorkspace(ad) and not isOurEsp(ad) then return ad end
		return nil
	elseif node:IsA("SurfaceGui") then
		local ad = node.Adornee
		if ad and ad:IsA("BasePart") and inWorkspace(ad) and not isOurEsp(ad) then return ad end
		local par = node.Parent
		if par and par:IsA("BasePart") and inWorkspace(par) and not isOurEsp(par) then return par end
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

-- Read digits inside an object subtree (screens, prompts, code values).
local function extractDigits(root)
	local found = nil
	local ok, descendants = pcall(function() return root:GetDescendants() end)
	if not ok or type(descendants) ~= "table" then return nil end
	for i = 1, #descendants do
		local d = descendants[i]
		if isOurEsp(d) then
			-- skip our own labels
		elseif d:IsA("TextLabel") or d:IsA("TextButton") then
			local s = d.Text or ""
			local m = digitsInString(s)
			if m then
				found = m
				break
			end
		elseif d:IsA("ProximityPrompt") then
			local s = tostring(d.ObjectText or "") .. " " .. tostring(d.ActionText or "")
			local m = digitsInString(s)
			if m then
				found = m
				break
			end
		elseif d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue") then
			local n = lowerName(d)
			if string.find(n, "code", 1, true) or string.find(n, "pass", 1, true) or string.find(n, "pin", 1, true) then
				found = tostring(d.Value)
				break
			end
		end
	end
	return found
end

-- Scan every world text for digits. Marks the NOTE/SCREEN/PAPER where the
-- code IS (plus readable values). Keypads are never marked here.
local function scanCodeTexts()
	if not State.codes then return end
	local descs = workspace:GetDescendants()
	for i = 1, #descs do
		local d = descs[i]
		if isOurEsp(d) then
			-- skip our own ESP objects entirely
		elseif (d:IsA("TextLabel") or d:IsA("TextButton")) and not Tracked[d] then
			local digits = nil
			pcall(function() digits = digitsInString(d.Text) end)
			if digits then
				local part = adorneePartForText(d)
				if part and not isEntryObject(part) and not isEntryObject(part.Parent) then
					local hl, bb, txt = makeEspObjects(part, part)
					Tracked[d] = { kind = "code", target = part, part = part, hl = hl, bb = bb, txt = txt, digits = digits, label = "CODE", root = d }
				end
			end
		elseif d:IsA("ProximityPrompt") and not Tracked[d] then
			-- A "read this" prompt marks its host as a code location.
			local host = readPromptHost(d)
			if host and not Tracked[host] then
				local target, part = resolveTarget(host)
				if target and part then
					local hl, bb, txt = makeEspObjects(target, part)
					Tracked[host] = { kind = "code", target = target, part = part, hl = hl, bb = bb, txt = txt, digits = extractDigits(host), label = "NOTE", root = host }
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
					if part and not isEntryObject(part) then
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

-- PlayerGui scan: reading the note pops the code into player UI.
-- Skips our own UI (Zolar lives in gethui, not PlayerGui, but stay safe).
local function scanPlayerGuiForCode()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or nil
	if not pg then return nil end
	local best, fallback = nil, nil
	for _, d in ipairs(pg:GetDescendants()) do
		if isOurEsp(d) then
			-- skip
		elseif (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
			local t = d.Text or ""
			-- skip our own status-like texts
			if not string.find(t, "monster:", 1, true) then
				local m = digitsInString(t)
				if m then
					if #m == 4 then best = m break end
					if not fallback then fallback = m end
				end
			end
		end
	end
	return best or fallback
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
	local digits = nil
	if kind == "code" then
		digits = extractDigits(inst)
	end
	Tracked[inst] = { kind = kind, target = target, part = part, hl = hl, bb = bb, txt = txt, digits = digits, label = label, root = inst }
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

local StatusLabel = nil

local function setStatus(s)
	if StatusLabel then
		pcall(function() StatusLabel:Set(s) end)
	end
end

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
	-- Re-read live state (a code can appear later, or a note can be taken).
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
	elseif root:IsA("Model") or root:IsA("BasePart") or root:IsA("Tool") then
		-- Note/paper object: re-read its subtree, keep marking even without digits.
		e.digits = extractDigits(root)
		return true
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
	if e.kind == "code" then
		title = e.digits and ("CODE " .. e.digits) or "NOTE"
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
		pcall(function() hum.WalkSpeed = State.speed end)
	end
end

-- Aggressive enforcement: the game resets WalkSpeed constantly (sprint/
-- stamina system), so re-apply instantly on change plus every frame.
local function watchSpeed(hum)
	if not hum then return end
	trackConnection(hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if State.running and hum.Parent and hum.WalkSpeed ~= State.speed then
			pcall(function() hum.WalkSpeed = State.speed end)
		end
	end))
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
	FlyBV.Name = "UraniumFlyBV"
	FlyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	FlyBV.Velocity = Vector3.new(0, 0, 0)
	FlyBV.Parent = hrp
	FlyBG = Instance.new("BodyGyro")
	FlyBG.Name = "UraniumFlyBG"
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
	local speed = State.flySpeed
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

-- Simulate holding E (fallback when fireproximityprompt is missing).
local function pressE(holdTime)
	if not VIM then return false end
	holdTime = holdTime or 0.3
	local ok = false
	pcall(function()
		VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
		ok = true
	end)
	if not ok then return false end
	task.wait(holdTime)
	pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
	return true
end

-- Click at screen coordinates (for keypad digit buttons).
local function vimClick(x, y)
	if not VIM then return false end
	local ok = false
	pcall(function()
		VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
		ok = true
	end)
	if not ok then return false end
	task.wait(0.12)
	pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
	return true
end

-- Fire one prompt: executor fast-path, else real E-hold in range.
local function firePrompt(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return end
	if not prompt.Enabled then return end
	if typeof(fireproximityprompt) == "function" then
		pcall(fireproximityprompt, prompt)
		task.wait((prompt.HoldDuration or 0) + 0.3)
		return
	end
	pressE((prompt.HoldDuration or 0) + 0.4)
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

local function promptRootPart(prompt)
	local host = prompt.Parent
	if host and host:IsA("BasePart") then return host end
	local node = host
	while node and node ~= workspace do
		if node:IsA("BasePart") then return node end
		local found = node:FindFirstChildWhichIsA("BasePart", false)
		if found then return found end
		node = node.Parent
	end
	if host then
		local _, part = resolveTarget(host)
		return part
	end
	return nil
end

-- Instant teleport (no tween). This game has no movement anticheat, so a
-- single CFrame set + noclip is undetectable here and the fastest method.
local function instantTP(pos)
	local hrp = myHRP()
	if not hrp then return false end
	pcall(function() hrp.CFrame = CFrame.new(pos) end)
	task.wait(0.12)
	return myHRP() ~= nil
end

-- Stand on a prompt (inside its activation range) and use it.
local function usePrompt(prompt)
	if not State.autowin then return false end
	local part = promptRootPart(prompt)
	if part then
		local range = math.max(2, math.min((prompt.MaxActivationDistance or 10) - 2, 12))
		local to = part.Position + Vector3.new(0, math.min(range, State.collectDist + 1), 0)
		instantTP(to)
		if not State.autowin then return false end
	end
	firePrompt(prompt)
	return true
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

local function waitRespawn()
	while State.autowin and State.running and not myHRP() do
		task.wait(0.5)
	end
	task.wait(0.4)
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

-- Prompts whose host matches a name list (broad scan for autowin phases).
local function scanPrompts(nameList, excludeList, limit)
	local out = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			local host = inst.Parent
			local scope = host and host.Parent or nil
			local hay = lowerName(host) .. " " .. lowerName(scope)
			local hit = false
			for i = 1, #nameList do
				if string.find(hay, nameList[i], 1, true) then hit = true break end
			end
			if hit and excludeList then
				for i = 1, #excludeList do
					if string.find(hay, excludeList[i], 1, true) then hit = false break end
				end
			end
			if hit then
				local part = promptRootPart(inst)
				if part then
					out[#out + 1] = { prompt = inst, pos = part.Position }
					if limit and #out >= limit then break end
				end
			end
		end
	end
	return out
end

-- Elevator / code entry panel (internal navigation only).
local function findEntryPanel()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			local n = lowerName(inst)
			local hit = string.find(n, "keypad", 1, true) or string.find(n, "panel", 1, true)
				or string.find(n, "elevator", 1, true)
			if hit then
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

-- Collect digit controls on the panel: ClickDetectors (fast path) and
-- clickable TextButtons (VIM screen clicks).
local function panelDigitControls(panelModel)
	local clicks, buttons = {}, {}
	for _, d in ipairs(panelModel:GetDescendants()) do
		if d:IsA("ClickDetector") then
			local nm = lowerName(d.Parent)
			if #nm == 1 and string.match(nm, "%d") then clicks[nm] = d end
		elseif d:IsA("TextButton") then
			local t = d.Text or ""
			if #t == 1 and string.match(t, "%d") and d.Visible then
				buttons[t] = d
			end
		end
	end
	return clicks, buttons
end

local function faceTowards(pos)
	local hrp = myHRP()
	if hrp and Camera then
		pcall(function()
			Camera.CFrame = CFrame.new(Camera.CFrame.Position, pos)
		end)
	end
	task.wait(0.15)
end

local function clickButtonAt(btn)
	local ax, ay = btn.AbsolutePosition.X, btn.AbsolutePosition.Y
	local sx, sy = btn.AbsoluteSize.X, btn.AbsoluteSize.Y
	if sx < 2 or sy < 2 then return false end
	local vs = Camera and Camera.ViewportSize or Vector2.new(800, 600)
	local cx, cy = ax + sx / 2, ay + sy / 2
	if cx < 0 or cy < 0 or cx > vs.X or cy > vs.Y then return false end
	return vimClick(cx, cy)
end

local function pressPanelDigits(panelModel, code)
	local clicks, buttons = panelDigitControls(panelModel)
	for i = 1, #code do
		if not State.autowin then return end
		local digit = string.sub(code, i, i)
		local det = clicks[digit]
		if det and typeof(fireclickdetector) == "function" then
			pcall(fireclickdetector, det)
		else
			local btn = buttons[digit]
			if btn then
				faceTowards((promptRootPart(btn) or myHRP() or {}).Position or rootPosition())
				clickButtonAt(btn)
			end
		end
		task.wait(0.45)
	end
end

local function grabKey(inst)
	local before = countKeysHeld()
	for attempt = 1, 4 do
		if not State.autowin or not State.running then return false end
		if not inWorkspace(inst) then return true end
		waitRespawn()
		if not State.autowin then return false end
		local _, part = resolveTarget(inst)
		local pos = part and part.Position or nil
		if pos then
			instantTP(pos + Vector3.new(0, State.collectDist, 0))
		end
		if not State.autowin then return false end
		firePromptsIn(inst)
		pressE(0.6)
		local hrp = myHRP()
		if hrp and part and inWorkspace(part) then
			pcall(function() hrp.CFrame = part.CFrame + Vector3.new(0, 2, 0) end)
		end
		task.wait(0.35)
		if not inWorkspace(inst) or countKeysHeld() > before then return true end
	end
	return (not inWorkspace(inst)) or countKeysHeld() > before
end

local function autoWinLoop()
	while State.autowin and State.running do
		waitRespawn()
		if not State.autowin then break end

		-- Phase 0: pry planks / boards blocking the way in
		setStatus("AUTO WIN 1/5: clearing entrance")
		notify("Auto Win", "Phase 1/5: clearing entrance", "door-open")
		for _, t in ipairs(scanPrompts(PLANK_NAMES, nil, 12)) do
			if not State.autowin then break end
			waitRespawn()
			usePrompt(t.prompt)
			task.wait(0.25)
		end
		if not State.autowin then break end

		-- Phase 1: open drawers/containers (keys hide inside)
		setStatus("AUTO WIN 2/5: opening drawers")
		notify("Auto Win", "Phase 2/5: opening drawers", "archive")
		do
			local seen = {}
			for _, t in ipairs(scanPrompts(DRAWER_NAMES, nil, 60)) do
				if not State.autowin then break end
				waitRespawn()
				local key = tostring(t.prompt:GetDebugId())
				if not seen[key] then
					seen[key] = true
					usePrompt(t.prompt)
					task.wait(0.2)
				end
			end
		end
		if not State.autowin then break end
		fullScan()
		scanCodeTexts()

		-- Phase 1b: read every note (fires Read prompts, code pops into UI)
		setStatus("AUTO WIN: reading notes")
		for _, e in pairs(Tracked) do
			if not State.autowin then break end
			if e.kind == "code" and e.root and inWorkspace(e.root) then
				firePromptsIn(e.root)
			end
		end
		task.wait(0.5)

		-- Phase 2: collect the 4 keys
		setStatus("AUTO WIN 3/5: collecting keys (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. ")")
		notify("Auto Win", "Phase 3/5: collecting keys", "key")
		do
			local guard = 0
			while State.autowin and State.running and countKeysHeld() < KEYS_NEEDED and guard < 30 do
				guard = guard + 1
				waitRespawn()
				if not State.autowin then break end
				local target = nearestKey(rootPosition())
				if not target then
					fullScan()
					target = nearestKey(rootPosition())
					if not target then break end
				end
				grabKey(target.inst)
				setStatus("AUTO WIN 3/5: collecting keys (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. ")")
				task.wait(0.15)
			end
		end
		if not State.autowin then break end

		-- Phase 3: deadbolts / exit
		setStatus("AUTO WIN 4/5: opening deadbolts (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. " keys)")
		notify("Auto Win", "Phase 4/5: opening exit", "lock-open")
		for _, t in ipairs(scanPrompts(DEADBOLT_NAMES, NEVER_EXIT, 20)) do
			if not State.autowin then break end
			waitRespawn()
			usePrompt(t.prompt)
			task.wait(0.25)
			if not State.autowin then break end
			usePrompt(t.prompt)
			task.wait(0.25)
		end
		if not State.autowin then break end

		-- Phase 4: elevator panel + code
		local code = getFoundCode()
		if not code then
			code = scanPlayerGuiForCode()
		end
		if not code then
			scanCodeTexts()
			code = getFoundCode()
		end
		local panel, panelPos = findEntryPanel()
		if panel and panelPos then
			waitRespawn()
			instantTP(panelPos + Vector3.new(0, 4, 0))
			if code and #code == 4 then
				setStatus("AUTO WIN 5/5: entering code " .. code)
				notify("Auto Win", "Entering code " .. code, "hash")
				pressPanelDigits(panel, code)
				task.wait(0.8)
				firePromptsIn(panel)
				task.wait(0.8)
			end
		end
		if code then
			setStatus("AUTO WIN done. Code: " .. code)
			notify("Auto Win finished", "Code: " .. code .. " — check the elevator", "check")
		else
			setStatus("AUTO WIN done. Code not found, enter it manually.")
			notify("Auto Win finished", "Code not found — read the NOTE marks", "info")
		end
		State.autowin = false
		if UiRefs.autoTgl then pcall(function() UiRefs.autoTgl:Set(false) end) end
		break
	end
end

-- ===================== ZOLAR UI =====================

local Window, StatusLabel = nil, nil

local function setToggle(ref, v)
	if ref then pcall(function() ref:Set(v) end) end
end

local function buildGui()
	local window = Zolar:Window({
		Name = "URANIUM",
		Icon = "eye",
		Accent = Color3.fromRGB(235, 235, 235),
	})

	-- ESP tab
	local espTab = window:Tab({ Name = "ESP", Icon = "eye" })
	local espMonster = espTab:SubTab({ Name = "Monster", Icon = "ghost" })
	local espItems = espTab:SubTab({ Name = "Items", Icon = "scan-eye" })

	local mSec = espMonster:Section({ Name = "Monster", Side = 1 })
	UiRefs.monsterTgl = mSec:Toggle({
		Name = "Monster ESP", Default = State.monster, Flag = "ura_monster",
		Callback = function(v)
			State.monster = v
			if v then fullScan() else clearKind("monster") end
		end,
	})
	mSec:Toggle({
		Name = "NPC scan (any humanoid)", Default = State.npcScan, Flag = "ura_npcscan",
		Callback = function(v)
			State.npcScan = v
			clearKind("monster")
			if State.monster then fullScan() end
		end,
	})
	mSec:Paragraph({
		Title = "How it works",
		Content = "Monster ESP outlines the monster with name + distance. If the monster uses an odd name, enable NPC scan.",
	})

	local iSec = espItems:Section({ Name = "Keys & Code", Side = 1 })
	iSec:Toggle({
		Name = "Key ESP", Default = State.keys, Flag = "ura_keys",
		Callback = function(v)
			State.keys = v
			if v then fullScan() else clearKind("key") end
		end,
	})
	iSec:Toggle({
		Name = "Code ESP (notes)", Default = State.codes, Flag = "ura_codes",
		Callback = function(v)
			State.codes = v
			if v then scanCodeTexts() else clearKind("code") end
		end,
	})
	iSec:Paragraph({
		Title = "Code ESP",
		Content = "Marks the NOTE / PAPER where the code IS (handwritten). It never marks the keypad where you type it.",
	})

	local vSec = espItems:Section({ Name = "View", Side = 2 })
	vSec:Slider({
		Name = "Max distance", Min = 100, Max = 2000, Default = State.maxDist, Suffix = "m", Flag = "ura_maxdist",
		Callback = function(v) State.maxDist = v end,
	})
	vSec:Slider({
		Name = "Text size", Min = 10, Max = 24, Default = State.textSize, Flag = "ura_textsize",
		Callback = function(v)
			State.textSize = v
			for _, e in pairs(Tracked) do
				if e.txt then pcall(function() e.txt.TextSize = v end) end
			end
		end,
	})

	-- Movement tab
	local movTab = window:Tab({ Name = "Movement", Icon = "wind" })
	local movMain = movTab:SubTab({ Name = "Main", Icon = "move" })
	local movSec = movMain:Section({ Name = "Movement", Side = 1 })
	UiRefs.noclipTgl = movSec:Toggle({
		Name = "Noclip", Default = State.noclip, Flag = "ura_noclip",
		Callback = function(v)
			State.noclip = v
			if not v then setNoclipParts(true) end
		end,
	})
	UiRefs.flyTgl = movSec:Toggle({
		Name = "Fly (WASD + Space/Shift)", Default = State.fly, Flag = "ura_fly",
		Callback = function(v)
			State.fly = v
			if v then enableFly() else disableFly() end
		end,
	})
	local spdSec = movMain:Section({ Name = "Speed", Side = 2 })
	spdSec:Slider({
		Name = "Walk speed", Min = 16, Max = 150, Default = State.speed, Flag = "ura_speed",
		Callback = function(v)
			State.speed = v
			applySpeed()
		end,
	})
	spdSec:Slider({
		Name = "Fly speed", Min = 20, Max = 150, Default = State.flySpeed, Flag = "ura_flyspeed",
		Callback = function(v) State.flySpeed = v end,
	})
	spdSec:Paragraph({
		Title = "Speed",
		Content = "Walk speed is re-applied constantly because the game keeps resetting it.",
	})

	-- Auto tab
	local autoTab = window:Tab({ Name = "Auto", Icon = "zap" })
	local autoMain = autoTab:SubTab({ Name = "Win", Icon = "trophy" })
	local autoSec = autoMain:Section({ Name = "Auto Win", Side = 1 })
	UiRefs.autoTgl = autoSec:Toggle({
		Name = "Auto Win", Default = false, Flag = "ura_autowin",
		Callback = function(v)
			State.autowin = v
			if v then
				State.noclip = true
				setToggle(UiRefs.noclipTgl, true)
				State.fly = true
				setToggle(UiRefs.flyTgl, true)
				enableFly()
				task.spawn(autoWinLoop)
			end
		end,
	})
	autoSec:Paragraph({
		Title = "What it does",
		Content = "Instant teleport: 1 clears entrance, 2 opens drawers, 3 grabs 4 keys, 4 opens deadbolts, 5 reads notes + enters the code at the elevator.",
	})
	local grabSec = autoMain:Section({ Name = "Grab", Side = 2 })
	grabSec:Slider({
		Name = "Collect distance", Min = 2, Max = 20, Default = State.collectDist, Suffix = "studs", Flag = "ura_collect",
		Callback = function(v) State.collectDist = v end,
	})
	grabSec:Paragraph({
		Title = "Teleport",
		Content = "Auto Win teleports instantly (CFrame). This game has no movement anticheat, so instant TP is undetected here.",
	})
	local statSec = autoMain:Section({ Name = "Status", Side = 2 })
	StatusLabel = statSec:Label({ Name = "starting..." })

	-- Settings tab
	local setTab = window:Tab({ Name = "Settings", Icon = "settings" })
	local cfgSub = setTab:SubTab({ Name = "Config", Icon = "save" })
	cfgSub:ThemeConfig({ })
	local miscSub = setTab:SubTab({ Name = "Misc", Icon = "info" })
	local miscSec = miscSub:Section({ Name = "Script", Side = 1 })
	miscSec:Button({
		Name = "Rescan world",
		Callback = function()
			fullScan()
			scanCodeTexts()
			notify("URANIUM", "World rescanned", "refresh")
		end,
	})
	miscSec:Button({
		Name = "Unload script",
		Callback = function()
			if getgenv and getgenv().UraniumMono and getgenv().UraniumMono.Unload then
				pcall(getgenv().UraniumMono.Unload)
				getgenv().UraniumMono = nil
			end
		end,
	})
	miscSec:Paragraph({
		Title = "Help",
		Content = "RightShift toggles this menu. E interacts, F torch, Shift sprint. In first person press M to free the mouse.",
	})

	window:Watermark({ Name = "URANIUM" })
	return window
end

-- ===================== STARTUP =====================

EspFolder = Instance.new("Folder")
EspFolder.Name = "UraniumESP"
do
	local ok, parent = pcall(function()
		if gethui then return gethui() end
		return game:GetService("CoreGui")
	end)
	EspFolder.Parent = (ok and parent) or workspace
end

trackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.W then FlyKeys.W = true end
	if input.KeyCode == Enum.KeyCode.A then FlyKeys.A = true end
	if input.KeyCode == Enum.KeyCode.S then FlyKeys.S = true end
	if input.KeyCode == Enum.KeyCode.D then FlyKeys.D = true end
	if input.KeyCode == Enum.KeyCode.Space then FlyKeys.Up = true end
	if input.KeyCode == Enum.KeyCode.LeftShift then FlyKeys.Down = true end
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
	if isOurEsp(inst) then return end
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
				if part and not isEntryObject(part) then
					local hl, bb, txt = makeEspObjects(part, part)
					Tracked[inst] = { kind = "code", target = part, part = part, hl = hl, bb = bb, txt = txt, digits = digits, label = "CODE", root = inst }
				end
			end
		end)
	elseif inst:IsA("ProximityPrompt") and State.codes then
		task.delay(0.5, function()
			if not State.codes then return end
			local host = readPromptHost(inst)
			if host and not Tracked[host] and inWorkspace(host) then
				local target, part = resolveTarget(host)
				if target and part then
					local hl, bb, txt = makeEspObjects(target, part)
					Tracked[host] = { kind = "code", target = target, part = part, hl = hl, bb = bb, txt = txt, digits = extractDigits(host), label = "NOTE", root = host }
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

trackConnection(LocalPlayer.CharacterAdded:Connect(function(char)
	task.wait(1)
	applySpeed()
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then watchSpeed(hum) end
	if State.fly then enableFly() end
end))

do
	local hum = myHumanoid()
	if hum then watchSpeed(hum) end
end
applySpeed()
fullScan()

Window = buildGui()

local accDist, accCode, accText = 0, 0, 0
trackConnection(RunService.Heartbeat:Connect(function(dt)
	if not State.running then return end
	-- Movement systems run every frame (game resets speed constantly)
	local hum = myHumanoid()
	if hum and hum.WalkSpeed ~= State.speed then
		applySpeed()
	end
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
	local maxDist = State.maxDist
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
			pcall(function()
				StatusLabel:Set("monster:" .. m .. "  key:" .. k .. "  code:" .. c .. codeTxt .. "  keys:" .. countKeysHeld() .. "/4" .. note)
			end)
		end
	end
end))

if game.PlaceId ~= TARGET_PLACE then
	notify("URANIUM", "Outside MONOCHROME — ESP still active", "info")
else
	notify("URANIUM loaded", "Press RightShift for the menu", "check")
end

local Api = {}
Api.Window = Window
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
	if Window then pcall(function() Window:SetOpen(false) end) end
end

if getgenv then
	getgenv().UraniumMono = Api
end

return Api
