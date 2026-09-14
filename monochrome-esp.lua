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
--               Never marks the keypad where you type the code.
--               Style: chams, labels, colors.
--    Movement : Noclip, Fly, Walk Speed, Fly Speed, Fullbright,
--               TP Spawn, Instant Interact.
--    Auto     : Auto Win (instant teleport run), Auto Use Keys,
--               Put Code Now, Collect distance, live status.
--    Settings : theme, text size, rescan, unload.
--  Menu key: RightShift. Default theme monochrome (black & white).
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
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local TARGET_PLACE = 134208374070897
local KEYS_NEEDED = 4
-- Discord server: shown + copied to clipboard every time the script loads.
local DISCORD_INVITE = "https://discord.gg/unWK5GXa9U"

-- Monochrome palette (ESP defaults)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Our own ESP object names (never scan/mark these or we loop on ourselves).
-- Also covers the other MONOCHROME script's ESP (ESP_Label / HiddenKeyESP /
-- VER_ESP / PlayerESP): running both at once would double every mark.
local OWN_NAMES = {
	["UraniumESP"] = true,
	["Uranium_HL"] = true,
	["Uranium_BB"] = true,
	["MonoESP"] = true,
	["MonoESP_HL"] = true,
	["MonoESP_BB"] = true,
	["ESP_Label"] = true,
	["HiddenKeyESP"] = true,
	["VER_ESP"] = true,
	["PlayerESP"] = true,
	["PlayerESP_Label"] = true,
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
-- Exact map structure (MONOCHROME): workspace.monochrome holds HiddenKey1-4
-- (Key > KeyPromptPoint > KeyPrompt), CodeNote (Printed > Digits, plain
-- TextLabel, NOT a SurfaceGui), Keypad (Digit1-4 each with Readout plus a
-- "Digit" child holding the ClickDetector), door locks (Cube.028/035/031/033
-- > LockPromptPoint > LockPrompt) and the elevator (Cylinder.002 >
-- ElevatorPromptPoint > ElevatorPrompt). The monster is workspace.VER.
local MAP_NAME = "monochrome"
local HIDDEN_KEY_PREFIX = "HiddenKey"
local HIDDEN_KEYS_TOTAL = 4
local LOCK_PARTS = { "Cube.028", "Cube.035", "Cube.031", "Cube.033" }
local ELEVATOR_PART = "Cylinder.002"
-- Closets / hiding spots
local CLOSET_NAMES = { "closet", "armario", "ropero", "wardrobe", "locker", "hideout", "hiding", "hide", "hidespot", "hidingspot" }
local HIDE_WORDS = { "hide", "esconder", "esconderse", "ocultar" }

local State = {
	running = true,
	monster = true,
	keys = true,
	codes = true,
	closets = true, -- hiding spots (closet/wardrobe/locker + Hide prompts)
	npcScan = false, -- mark ANY non-player humanoid as monster
	godmode = false, -- infinite lives attempt (client-side locks)
	chams = true, -- highlight outlines
	labels = true, -- name/distance billboards
	noclip = false,
	fly = false,
	antiKill = false, -- TP away when the monster gets close
	antiKillRadius = 15, -- trigger distance (studs)
	antiKillFlee = 100, -- distance to flee to (studs)
	instacollect = false, -- grab keys the moment you walk into range
	collectRadius = 12, -- pickup radius for Insta Collect (studs)
	playerEsp = false, -- see other players
	instantPrompt = false,
	fullbright = false,
	autowin = false,
	autokeys = false,
	autoPutCode = false, -- automatically enter the code when found
	speed = 16, -- WalkSpeed
	flySpeed = 70,
	maxDist = 500,
	collectDist = 4, -- stand-off distance when Auto Win grabs (studs)
	textSize = 14,
	colMonster = WHITE,
	colKey = WHITE,
	colCode = WHITE,
	colCloset = WHITE,
	colPlayer = WHITE,
}

local Tracked = {} -- [instance] = {kind, target, part, boxSize, hl, bb, txt, draw, digits, label, root}
local Connections = {}
local UiRefs = {} -- Zolar control refs for programmatic sync
local SavedHolds = {} -- original prompt HoldDurations for instant-prompt restore
local PromptHook = nil
local SavedLight = nil
local SavedHolder, SavedPopup = nil, nil
local DeadboltCache, DeadboltCacheAt = nil, 0

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

local function kindColor(kind)
	if kind == "monster" then return State.colMonster end
	if kind == "key" then return State.colKey end
	if kind == "closet" then return State.colCloset end
	if kind == "player" then return State.colPlayer end
	return State.colCode
end

local function kindTitle(kind)
	if kind == "monster" then return "MONSTER" end
	if kind == "key" then return "KEY" end
	if kind == "closet" then return "CLOSET" end
	if kind == "player" then return "PLAYER" end
	return "NOTE"
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
		-- Allow closet-named parts through even inside models
		local bpName = lowerName(inst)
		if not matchesAny(bpName, CLOSET_NAMES) and not matchesAny(bpName, KEY_NAMES) then
			return nil
		end
	end

	local name = lowerName(inst)

	-- Monster: exact game name (workspace.VER). Exact match first: a plain
	-- "ver" substring check would false-positive on "server"/"lever".
	if name == "ver" then
		return "monster", "MONSTER"
	end
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
	-- Closets / hiding spots (checked before keys/code so lockers count as hideouts)
	if matchesAny(name, CLOSET_NAMES) then
		return "closet", "CLOSET"
	end
	-- Keys (entry objects like the "keypad" excluded: "keypad" contains "key")
	if matchesAny(name, KEY_NAMES) and not isEntryObject(inst) then
		return "key", "KEY"
	end
	-- Code location: paper/note-like objects (handwritten code lives here).
	-- Entry objects (keypads/panels/locks) are explicitly excluded.
	if matchesAny(name, NOTE_NAMES) and not isEntryObject(inst) then
		return "code", "NOTE"
	end
	return nil
end

-- A "hide in here" prompt means its host is a closet/hiding spot.
local function hidePromptHost(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return nil end
	local s = lowerName(prompt) .. " " .. tostring(prompt.ObjectText or ""):lower() .. " " .. tostring(prompt.ActionText or ""):lower()
	local hit = false
	for i = 1, #HIDE_WORDS do
		if string.find(s, HIDE_WORDS[i], 1, true) then hit = true break end
	end
	if not hit then
		for i = 1, #CLOSET_NAMES do
			if string.find(s, CLOSET_NAMES[i], 1, true) then hit = true break end
		end
	end
	if not hit then return nil end
	local host = prompt.Parent
	if not host or isOurEsp(host) then return nil end
	if host:IsA("Attachment") and host.Parent and host.Parent:IsA("BasePart") then
		host = host.Parent
	end
	if host:IsA("BasePart") then return host end
	if host:IsA("Model") or host:IsA("Tool") then return host end
	if host.Parent and (host.Parent:IsA("Model") or host.Parent:IsA("BasePart")) and not isOurEsp(host.Parent) then
		return host.Parent
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
	if host:IsA("Attachment") and host.Parent and host.Parent:IsA("BasePart") then
		host = host.Parent
	end
	if host:IsA("BasePart") then return host end
	if host:IsA("Model") or host:IsA("Tool") then return host end
	if host.Parent and (host.Parent:IsA("Model") or host.Parent:IsA("BasePart")) and not isOurEsp(host.Parent) then
		return host.Parent
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

local function boxSizeOf(target, part)
	if target and target:IsA("Model") then
		local ok, size = pcall(function() return target:GetExtentsSize() end)
		if ok and size then return size end
	end
	if part then return part.Size end
	return Vector3.new(4, 6, 2)
end

local EspFolder = nil

local function getSafeUiParent()
	local ok, parent = pcall(function()
		if gethui then return gethui() end
		return game:GetService("CoreGui")
	end)
	if ok and parent then return parent end
	return (LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")) or workspace
end

local function initEspHolders()
	if not EspFolder or not EspFolder.Parent then
		EspFolder = Instance.new("Folder")
		EspFolder.Name = "UraniumESP"
		EspFolder.Parent = getSafeUiParent()
	end
end
initEspHolders()

local function makeEspObjects(target, part)
	initEspHolders()
	local col = WHITE

	-- 1. Highlight (Chams Outline + Fill)
	local hl = Instance.new("Highlight")
	hl.Name = "Uranium_HL"
	hl.Adornee = target
	hl.FillColor = col
	hl.FillTransparency = 1
	hl.OutlineColor = col
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = State.chams
	hl.Parent = EspFolder

	-- 2. Modern Sleek Billboard Badge
	local bb = Instance.new("BillboardGui")
	bb.Name = "Uranium_BB"
	bb.Adornee = part
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 140, 0, 28)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.Enabled = State.labels
	bb.Parent = EspFolder

	local bg = Instance.new("Frame")
	bg.Name = "Badge"
	bg.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
	bg.BackgroundTransparency = 0.25
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Border"
	stroke.Color = col
	stroke.Thickness = 1.2
	stroke.Transparency = 0.2
	stroke.Parent = bg

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.BackgroundColor3 = col
	dot.Position = UDim2.new(0, 7, 0.5, -4)
	dot.Size = UDim2.new(0, 8, 0, 8)
	dot.BorderSizePixel = 0
	dot.Parent = bg

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local txt = Instance.new("TextLabel")
	txt.Name = "Label"
	txt.BackgroundTransparency = 1
	txt.Position = UDim2.new(0, 20, 0, 0)
	txt.Size = UDim2.new(1, -24, 1, 0)
	txt.Font = Enum.Font.GothamBold
	txt.TextSize = State.textSize or 12
	txt.TextColor3 = Color3.fromRGB(245, 245, 245)
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.Text = ""
	txt.Parent = bg

	return hl, bb, txt, stroke, dot
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
	-- 1. Exact 4 consecutive digits
	local m4 = string.match(s, "%d%d%d%d")
	if m4 then return string.sub(m4, 1, 8) end
	-- 2. Strip all non-digit characters (handles "1 2 3 4", "1 - 2 - 3 - 4", "Code: 1 2 3 4")
	local clean = string.gsub(s, "%D", "")
	if #clean >= 4 and #clean <= 8 then
		return string.sub(clean, 1, 8)
	end
	if #clean == 3 then
		return clean
	end
	local m3 = string.match(s, "%d%d%d+")
	if m3 then return string.sub(m3, 1, 8) end
	return nil
end

local function checkAttributesForDigits(inst)
	if typeof(inst) ~= "Instance" then return nil end
	local ok, attrs = pcall(function() return inst:GetAttributes() end)
	if ok and type(attrs) == "table" then
		for name, val in pairs(attrs) do
			local n = string.lower(tostring(name))
			local s = tostring(val)
			if string.find(n, "code", 1, true) or string.find(n, "pass", 1, true)
				or string.find(n, "pin", 1, true) or string.find(n, "digit", 1, true)
				or string.find(n, "note", 1, true) or string.find(n, "answer", 1, true) then
				local d = digitsInString(s)
				if d then return d end
			end
			local d = digitsInString(s)
			if d and #d == 4 then return d end
		end
	end
	return nil
end

local function collectSingleDigits(container)
	if typeof(container) ~= "Instance" then return nil end
	local digits = {}
	local ok, descs = pcall(function() return container:GetDescendants() end)
	if not ok or type(descs) ~= "table" then return nil end
	for i = 1, #descs do
		local d = descs[i]
		if isOurEsp(d) then
			-- skip
		elseif d:IsA("TextLabel") or d:IsA("TextButton") then
			local t = string.match(d.Text or "", "%d")
			if t and #t == 1 then
				digits[#digits + 1] = t
			end
		elseif d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue") then
			local t = string.match(tostring(d.Value or ""), "%d")
			if t and #t == 1 then
				digits[#digits + 1] = t
			end
		end
	end
	if #digits == 4 then
		return table.concat(digits, "")
	end
	return nil
end

-- Read digits inside an object subtree (screens, prompts, code values, attributes).
local function extractDigits(root)
	if typeof(root) ~= "Instance" then return nil end
	-- Check root attributes directly
	local attrCode = checkAttributesForDigits(root)
	if attrCode then return attrCode end

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
			if string.find(n, "code", 1, true) or string.find(n, "pass", 1, true) or string.find(n, "pin", 1, true) or string.find(n, "answer", 1, true) then
				local m = digitsInString(tostring(d.Value))
				if m then
					found = m
					break
				end
			end
		end
		local da = checkAttributesForDigits(d)
		if da then
			found = da
			break
		end
	end
	if found then return found end
	return collectSingleDigits(root)
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
					local hl, bb, txt, box, stroke, dot = makeEspObjects(part, part)
					Tracked[d] = { kind = "code", target = part, part = part, boxSize = part.Size, hl = hl, bb = bb, txt = txt, box = box, stroke = stroke, dot = dot, digits = digits, label = "CODE", root = d }
				end
			end
		elseif d:IsA("ProximityPrompt") and not Tracked[d] then
			-- A "hide" prompt marks its host as a closet first.
			local hideHost = hidePromptHost(d)
			if hideHost and not Tracked[hideHost] and State.closets then
				local target, part = resolveTarget(hideHost)
				if target and part then
					local hl, bb, txt, box, stroke, dot = makeEspObjects(target, part)
					Tracked[hideHost] = { kind = "closet", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, box = box, stroke = stroke, dot = dot, digits = nil, label = "CLOSET", root = hideHost }
				end
			end
			-- A "read this" prompt marks its host as a code location.
			local host = readPromptHost(d)
			if host and not Tracked[host] then
				local target, part = resolveTarget(host)
				if target and part then
					local hl, bb, txt, box, stroke, dot = makeEspObjects(target, part)
					Tracked[host] = { kind = "code", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, box = box, stroke = stroke, dot = dot, digits = extractDigits(host), label = "NOTE", root = host }
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
						local hl, bb, txt, box, stroke, dot = makeEspObjects(part, part)
						Tracked[d] = { kind = "code", target = part, part = part, boxSize = part.Size, hl = hl, bb = bb, txt = txt, box = box, stroke = stroke, dot = dot, digits = string.sub(val, 1, 8), label = "CODE", root = d }
					end
				end
			end
		end
	end
end

-- First 4-digit code found: CodeNote entries first (the real paper),
-- then anything else. Falls back to any digit string.
local function rootIsCodeNote(e)
	local n = e.root
	for i = 1, 3 do
		if typeof(n) ~= "Instance" then break end
		local nm = lowerName(n)
		if nm == "codenote" or nm == "code note" then return true end
		n = n.Parent
	end
	return false
end

local function getFoundCode()
	local fallback, noteFallback = nil, nil
	for _, e in pairs(Tracked) do
		if e.kind == "code" and e.digits then
			if #e.digits == 4 then
				if rootIsCodeNote(e) then return e.digits end
				if not fallback then fallback = e.digits end
			elseif not noteFallback then
				noteFallback = e.digits
			end
		end
	end
	return fallback or noteFallback
end

-- PlayerGui scan: reading the note pops the code into player UI.
-- Skips our own UI texts so we never read ourselves.
local function scanPlayerGuiForCode()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or nil
	if not pg then return nil end
	local best, fallback = nil, nil
	for _, d in ipairs(pg:GetDescendants()) do
		if isOurEsp(d) then
			-- skip
		elseif d:IsA("TextLabel") or d:IsA("TextButton") then
			local t = d.Text or ""
			if not string.find(t, "monster:", 1, true) and not string.find(t, "URANIUM", 1, true) then
				local m = digitsInString(t)
				if m then
					if #m == 4 then best = m break end
					if not fallback then fallback = m end
				end
			end
		end
		local a = checkAttributesForDigits(d)
		if a and #a == 4 then best = a break end
	end
	return best or fallback
end

local function removeEntry(inst)
	local e = Tracked[inst]
	if e then
		if e.hl then pcall(function() e.hl:Destroy() end) end
		if e.bb then pcall(function() e.bb:Destroy() end) end
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
	if kind == "closet" then return State.closets end
	if kind == "player" then return State.playerEsp end
	return false
end

local function addEntry(inst)
	if Tracked[inst] then return end
	if not inWorkspace(inst) then return end
	local kind, label = classify(inst)
	if not kind then return end
	if not isKindEnabled(kind) then return end
	-- One monster only (this game has a single VER): extra humanoids/models
	-- with monster-ish names would duplicate the mark. NPC-scan mode keeps all.
	if kind == "monster" and not State.npcScan then
		for other, e in pairs(Tracked) do
			if other ~= inst and e.kind == "monster" and inWorkspace(other) then
				return
			end
		end
	end
	local target, part = resolveTarget(inst)
	if not target or not part then
		-- No parts yet (streaming): keep pending, resolved in the loop
		Tracked[inst] = { kind = kind, target = nil, part = nil, boxSize = nil, hl = nil, bb = nil, txt = nil, draw = nil, digits = nil, label = label, root = inst }
		return
	end
	local hl, bb, txt, stroke, dot = makeEspObjects(target, part)
	local digits = nil
	if kind == "code" then
		digits = extractDigits(inst)
	end
	Tracked[inst] = { kind = kind, target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, stroke = stroke, dot = dot, draw = nil, digits = digits, label = label, root = inst }
end

-- Force-mark a known object even when the generic scan skips it (e.g. a
-- BasePart nested inside a non-matching Model like the map folder).
local function forceEntry(inst, kind, label)
	if typeof(inst) ~= "Instance" then return end
	if Tracked[inst] or not inWorkspace(inst) or isOurEsp(inst) then return end
	if not isKindEnabled(kind) then return end
	if kind == "code" and isEntryObject(inst) then return end
	local target, part = resolveTarget(inst)
	if not target or not part then
		-- Non-adornable containers (e.g. CodeNote as a Folder): Highlight
		-- cannot adorn them, so anchor on the first inner part instead.
		local inner = inst:FindFirstChildWhichIsA("BasePart", true)
		if inner then
			part = inner
			if inst:IsA("Model") or inst:IsA("BasePart") then
				target = inst
			else
				target = inner
			end
		else
			Tracked[inst] = { kind = kind, target = nil, part = nil, boxSize = nil, hl = nil, bb = nil, txt = nil, box = nil, stroke = nil, dot = nil, draw = nil, digits = nil, label = label, root = inst }
			return
		end
	end
	local hl, bb, txt, stroke, dot = makeEspObjects(target, part)
	local digits = nil
	if kind == "code" then
		digits = extractDigits(inst)
	end
	Tracked[inst] = { kind = kind, target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, stroke = stroke, dot = dot, draw = nil, digits = digits, label = label, root = inst }
end

-- Structural closet pass: Hide prompts, Hide click detectors, and closet models/parts
local function scanClosetHosts()
	if not State.closets then return end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if isOurEsp(inst) then
			-- skip
		elseif inst:IsA("ProximityPrompt") then
			local host = hidePromptHost(inst)
			if host and not Tracked[host] and inWorkspace(host) then
				local target, part = resolveTarget(host)
				if target and part then
					local hl, bb, txt, box, stroke, dot = makeEspObjects(target, part)
					Tracked[host] = { kind = "closet", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, box = box, stroke = stroke, dot = dot, digits = nil, label = "CLOSET", root = host }
				end
			end
		elseif inst:IsA("ClickDetector") then
			local host = inst.Parent
			if typeof(host) == "Instance" and not Tracked[host] and inWorkspace(host)
				and (host:IsA("BasePart") or host:IsA("Model") or host:IsA("Tool")) then
				local hay = lowerName(inst) .. " " .. lowerName(host) .. " " .. (host.Parent and lowerName(host.Parent) or "")
				if matchesAny(hay, HIDE_WORDS) or matchesAny(hay, CLOSET_NAMES) then
					pcall(forceEntry, host, "closet", "CLOSET")
				end
			end
		elseif (inst:IsA("Model") or inst:IsA("BasePart")) and not Tracked[inst] and inWorkspace(inst) then
			local n = lowerName(inst)
			if matchesAny(n, CLOSET_NAMES) and not isUnderPlayer(inst) and not isEntryObject(inst) then
				pcall(forceEntry, inst, "closet", "CLOSET")
			end
		end
	end
end

-- Structural pass over the real map: CodeNote (Printed > Digits is a plain
-- TextLabel, not a SurfaceGui, so the text scan can never resolve its part)
-- and HiddenKey folders (classify ignores Folder instances).
local function scanStructural()
	local map = workspace:FindFirstChild(MAP_NAME)
	local scope = map or workspace
	if State.codes then
		for _, child in ipairs(scope:GetChildren()) do
			local n = lowerName(child)
			if (n == "codenote" or n == "code note") and not Tracked[child] then
				pcall(forceEntry, child, "code", "NOTE")
			end
		end
	end
	if State.keys then
		for i = 1, HIDDEN_KEYS_TOTAL do
			local hk = scope:FindFirstChild(HIDDEN_KEY_PREFIX .. i)
			if hk and not Tracked[hk] then
				local keyPart = hk:FindFirstChildWhichIsA("BasePart", true)
				if keyPart then
					pcall(forceEntry, keyPart, "key", "KEY")
				else
					pcall(forceEntry, hk, "key", "KEY")
				end
			end
		end
	end
end

local function fullScan()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("Tool") then
			pcall(addEntry, inst)
		elseif inst:IsA("BasePart") and inst.Parent and not (inst.Parent:IsA("Model") or inst.Parent:IsA("Tool")) then
			pcall(addEntry, inst)
		end
	end
	pcall(scanStructural)
	if State.closets then pcall(scanClosetHosts) end
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
	local m, k, c, h = 0, 0, 0, 0
	for _, e in pairs(Tracked) do
		if e.hl then
			if e.kind == "monster" then m = m + 1
			elseif e.kind == "key" then k = k + 1
			elseif e.kind == "code" then c = c + 1
			elseif e.kind == "closet" then h = h + 1 end
		end
	end
	return m, k, c, h
end

local function applyKindColors(kind)
	local col = kindColor(kind)
	for _, e in pairs(Tracked) do
		if e.kind == kind then
			if e.hl then pcall(function() e.hl.OutlineColor = col end) end
			if e.txt then pcall(function() e.txt.TextColor3 = col end) end
		end
	end
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
			e.boxSize = boxSizeOf(target, part)
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
		if e.hl then e.hl.Enabled = false end
		if e.bb then e.bb.Enabled = false end
		return true
	end
	local col = kindColor(e.kind)
	if e.hl then
		e.hl.Enabled = State.chams
		e.hl.OutlineColor = col
		e.hl.FillColor = col
		e.hl.FillTransparency = 1
	end
	if e.bb then e.bb.Enabled = State.labels end
	if e.stroke then pcall(function() e.stroke.Color = col end) end
	if e.dot then pcall(function() e.dot.BackgroundColor3 = col end) end
	local title = e.label
	if e.kind == "code" then
		title = e.digits and ("CODE " .. e.digits) or "NOTE"
	end
	if e.txt then
		e.txt.Text = title .. " [" .. tostring(math.floor(dist)) .. "m]"
	end
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

-- ===================== WORLD (fullbright / spawn) =====================

local function enforceFullbright()
	pcall(function()
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.FogEnd = 100000
		Lighting.GlobalShadows = false
		Lighting.Ambient = WHITE
		Lighting.OutdoorAmbient = WHITE
		Lighting.ExposureCompensation = 0
		for _, a in ipairs(Lighting:GetChildren()) do
			if a:IsA("Atmosphere") then
				a.Density = 0
				a.Offset = 0
				a.Haze = 0
				a.Glare = 0
			end
		end
	end)
end

local function applyFullbright(on)
	if on then
		if not SavedLight then
			SavedLight = { At = {} }
			pcall(function()
				SavedLight.B = Lighting.Brightness
				SavedLight.C = Lighting.ClockTime
				SavedLight.F = Lighting.FogEnd
				SavedLight.G = Lighting.GlobalShadows
				SavedLight.A = Lighting.Ambient
				SavedLight.O = Lighting.OutdoorAmbient
				SavedLight.E = Lighting.ExposureCompensation
				for _, a in ipairs(Lighting:GetChildren()) do
					if a:IsA("Atmosphere") then
						SavedLight.At[a] = { D = a.Density, O = a.Offset, H = a.Haze, C = a.Color, De = a.Decay, G = a.Glare }
					end
				end
			end)
		end
		enforceFullbright()
	else
		if SavedLight then
			pcall(function()
				Lighting.Brightness = SavedLight.B
				Lighting.ClockTime = SavedLight.C
				Lighting.FogEnd = SavedLight.F
				Lighting.GlobalShadows = SavedLight.G
				Lighting.Ambient = SavedLight.A
				Lighting.OutdoorAmbient = SavedLight.O
				Lighting.ExposureCompensation = SavedLight.E
				for a, s in pairs(SavedLight.At) do
					if a and a.Parent then
						a.Density = s.D
						a.Offset = s.O
						a.Haze = s.H
						a.Color = s.C
						a.Decay = s.De
						a.Glare = s.G
					end
				end
			end)
			SavedLight = nil
		end
	end
end

local SpawnPos = nil
do
	local hrp = myHRP()
	if hrp then SpawnPos = hrp.Position end
end

-- Destroy any leftover shader from previous sessions
pcall(function()
	local oldShader = Lighting:FindFirstChild("UraniumShader")
	if oldShader then oldShader:Destroy() end
end)

local function teleportSpawn()
	local hrp = myHRP()
	if not hrp then
		notify("URANIUM", "No character (dead?)", "info")
		return
	end
	local dest = nil
	pcall(function()
		local sp = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		if sp and sp:IsA("BasePart") then dest = sp.Position + Vector3.new(0, 4, 0) end
	end)
	if not dest then dest = SpawnPos end
	if dest then
		pcall(function() hrp.CFrame = CFrame.new(dest) end)
		notify("URANIUM", "Teleported to spawn", "check")
	else
		notify("URANIUM", "Spawn not found", "info")
	end
end

-- ===================== INTERACTION (grab / prompts) =====================

-- Instant Interact: prompts complete with zero hold time.
local function setPromptInstant(prompt, instant)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return end
	if instant then
		if SavedHolds[prompt] == nil then SavedHolds[prompt] = prompt.HoldDuration end
		pcall(function() prompt.HoldDuration = 0 end)
	else
		local old = SavedHolds[prompt]
		if old ~= nil then
			pcall(function() prompt.HoldDuration = old end)
			SavedHolds[prompt] = nil
		end
	end
end

local function applyInstantPrompt(on)
	if on then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") then setPromptInstant(d, true) end
		end
		if PromptHook then pcall(function() PromptHook:Disconnect() end) end
		PromptHook = workspace.DescendantAdded:Connect(function(inst)
			if inst:IsA("ProximityPrompt") then
				task.delay(0.2, function()
					if State.instantPrompt then setPromptInstant(inst, true) end
				end)
			end
		end)
		trackConnection(PromptHook)
	else
		if PromptHook then pcall(function() PromptHook:Disconnect() end) end
		PromptHook = nil
		local keys = {}
		for p in pairs(SavedHolds) do keys[#keys + 1] = p end
		for i = 1, #keys do setPromptInstant(keys[i], false) end
	end
end

-- Simulate holding E (fallback when fireproximityprompt is missing).
-- ===================== INFINITE LIVES =====================
-- No server exploit ("CVE") exists in the client-readable code: the other
-- script only touches prompts/click detectors, which the server validates.
-- So this locks everything client-side instead: Humanoid health pinned to
-- max (kills fizzle when damage is applied through the client) plus any
-- lives counter (life/lives/vida values in player/character/UI) pinned to
-- 999. Works fully when the game trusts the client; when the server is
-- authoritative the monster still can't finish you while noclip/fly is on.
local GOD_LIVES = 999
local LIFE_VALUE_WORDS = { "life", "lives", "live", "vidas", "vida" }
local GodConns = {}

local function livesValueCandidates()
	local out = {}
	local function consider(container)
		if typeof(container) ~= "Instance" then return end
		local ok, descs = pcall(function() return container:GetDescendants() end)
		if not ok then return end
		for i = 1, #descs do
			local d = descs[i]
			if (d:IsA("IntValue") or d:IsA("NumberValue")) and not isOurEsp(d) then
				local n = lowerName(d)
				for j = 1, #LIFE_VALUE_WORDS do
					if string.find(n, LIFE_VALUE_WORDS[j], 1, true) then
						out[#out + 1] = d
						break
					end
				end
			end
		end
	end
	consider(LocalPlayer)
	local char = myCharacter()
	if char then consider(char) end
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or nil
	if pg then consider(pg) end
	return out
end

local function lockLivesValue(v)
	pcall(function()
		if typeof(v.Value) == "number" and v.Value < GOD_LIVES then
			v.Value = GOD_LIVES
		end
	end)
	GodConns[#GodConns + 1] = v.Changed:Connect(function()
		if not State.godmode or not State.running then return end
		pcall(function()
			if typeof(v.Value) == "number" and v.Value < GOD_LIVES then
				v.Value = GOD_LIVES
			end
		end)
	end)
end

local function armGodHumanoid(hum)
	if typeof(hum) ~= "Instance" then return end
	pcall(function()
		hum.BreakJointsOnDeath = false
		if hum.Health < hum.MaxHealth then
			hum.Health = hum.MaxHealth
		end
	end)
	GodConns[#GodConns + 1] = hum.HealthChanged:Connect(function(hp)
		if not State.godmode or not State.running then return end
		if hum.Parent and hp < hum.MaxHealth then
			pcall(function() hum.Health = hum.MaxHealth end)
		end
	end)
end

local function applyGodmode(on)
	State.godmode = on
	for _, c in ipairs(GodConns) do
		pcall(function() c:Disconnect() end)
	end
	GodConns = {}
	if not on then return end
	armGodHumanoid(myHumanoid())
	for _, v in ipairs(livesValueCandidates()) do
		lockLivesValue(v)
	end
	-- Lock any "dead" / "isDead" BoolValues to false
	local function lockDeadValues(container)
		if typeof(container) ~= "Instance" then return end
		pcall(function()
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("BoolValue") then
					local n = d.Name:lower()
					if n == "dead" or n == "isdead" or n == "muerte" or n == "muerto" then
						pcall(function() d.Value = false end)
						GodConns[#GodConns + 1] = d.Changed:Connect(function()
							if State.godmode then pcall(function() d.Value = false end) end
						end)
					end
				end
			end
		end)
	end
	lockDeadValues(LocalPlayer)
	local char = myCharacter()
	if char then lockDeadValues(char) end
	-- Hook Humanoid.Died to force health back immediately
	local hum = myHumanoid()
	if hum then
		GodConns[#GodConns + 1] = hum.Died:Connect(function()
			if not State.godmode then return end
			pcall(function()
				hum.Health = hum.MaxHealth
			end)
		end)
	end
	GodConns[#GodConns + 1] = LocalPlayer.CharacterAdded:Connect(function(newChar)
		if not State.godmode then return end
		task.wait(0.5)
		if not State.godmode or not State.running then return end
		local newHum = newChar:FindFirstChildOfClass("Humanoid")
		if newHum then
			armGodHumanoid(newHum)
			GodConns[#GodConns + 1] = newHum.Died:Connect(function()
				if State.godmode then pcall(function() newHum.Health = newHum.MaxHealth end) end
			end)
		end
		for _, v in ipairs(livesValueCandidates()) do
			lockLivesValue(v)
		end
		lockDeadValues(newChar)
		lockDeadValues(LocalPlayer)
	end)
	notify("URANIUM", "Infinite Lives ON (health + lives + death locked)", "heart")
end

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

-- Loosen a prompt before firing (same trick as the reference script):
-- no line-of-sight needed, huge activation range.
local function prepPrompt(prompt)
	pcall(function()
		prompt.RequiresLineOfSight = false
		if (prompt.MaxActivationDistance or 0) < 500 then
			prompt.MaxActivationDistance = 5000
		end
	end)
end

-- Fire one prompt: executor fast-path, then the prompt's own hold
-- simulation (InputHoldBegin/End), else a real E-hold in range.
local function firePrompt(prompt, fast)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return end
	if not prompt.Enabled then return end
	if typeof(fireproximityprompt) == "function" then
		pcall(fireproximityprompt, prompt)
		if not fast then
			task.wait((prompt.HoldDuration or 0) + 0.1)
		end
		return
	end
	local began = false
	pcall(function()
		prompt:InputHoldBegin()
		began = true
	end)
	if began then
		task.wait((prompt.HoldDuration or 0) + (fast and 0.05 or 0.2))
		pcall(function() prompt:InputHoldEnd() end)
		if not fast then task.wait(0.1) end
		return
	end
	pressE((prompt.HoldDuration or 0) + (fast and 0.15 or 0.3))
end

local function firePromptsIn(model)
	if typeof(model) ~= "Instance" then return end
	local ok, descs = pcall(function() return model:GetDescendants() end)
	if not ok then return end
	for i = 1, #descs do
		if descs[i]:IsA("ProximityPrompt") then
			prepPrompt(descs[i])
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
	prepPrompt(prompt)
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
		if typeof(container) ~= "Instance" then return end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and matchesAny(lowerName(t), KEY_NAMES) then
				n = n + 1
			elseif (t:IsA("IntValue") or t:IsA("NumberValue")) and string.find(lowerName(t), "key", 1, true) then
				-- server-style counter (e.g. leaderstats "Keys")
				local v = tonumber(t.Value) or 0
				if v > 0 then n = n + v end
			end
		end
	end
	pcall(scan, LocalPlayer.Backpack)
	pcall(scan, LocalPlayer:FindFirstChild("leaderstats"))
	pcall(scan, LocalPlayer)
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

-- ===================== MAP STRUCTURE (MONOCHROME) =====================

local function mapRoot()
	local m = workspace:FindFirstChild(MAP_NAME)
	if m then return m end
	return workspace
end

local function hiddenKeyFolder(i)
	local map = mapRoot()
	local hk = map:FindFirstChild(HIDDEN_KEY_PREFIX .. i)
	if hk then return hk end
	if map ~= workspace then
		hk = workspace:FindFirstChild(HIDDEN_KEY_PREFIX .. i, true)
		if hk then return hk end
	end
	return nil
end

local function keyPromptIn(hk)
	if typeof(hk) ~= "Instance" then return nil end
	local p = hk:FindFirstChild("KeyPrompt", true)
	if p and p:IsA("ProximityPrompt") then return p end
	return nil
end

local function keyPartIn(hk)
	if typeof(hk) ~= "Instance" then return nil end
	if hk:IsA("BasePart") then return hk end
	return hk:FindFirstChildWhichIsA("BasePart", true)
end

local function lockPromptByName(partName)
	local map = mapRoot()
	local holder = map:FindFirstChild(partName) or workspace:FindFirstChild(partName, true)
	if not holder then return nil end
	local p = holder:FindFirstChild("LockPrompt", true)
	if p and p:IsA("ProximityPrompt") then return p end
	return nil
end

local function elevatorPrompt()
	local map = mapRoot()
	local holder = map:FindFirstChild(ELEVATOR_PART) or workspace:FindFirstChild(ELEVATOR_PART, true)
	if not holder then return nil end
	local p = holder:FindFirstChild("ElevatorPrompt", true)
	if p and p:IsA("ProximityPrompt") then return p end
	return nil
end

-- Keypad detection by READOUTS: the code panel is the only place with a
-- group of 3-4 single-digit TextLabels (the boxes showing each digit).
-- Groups them by their SurfaceGui-adorned part / common ancestor.
local function findKeypadByReadouts()
	local groups = {} -- [ancestor] = count
	local function ancestorOf(lbl)
		local node = lbl
		for _ = 1, 6 do
			if typeof(node) ~= "Instance" then return nil end
			if node:IsA("SurfaceGui") or node:IsA("BillboardGui") then
				local ad = node.Adornee
				if ad then
					local anc = ad
					for _ = 1, 3 do
						if anc and anc:IsA("Model") then return anc end
						anc = anc and anc.Parent
					end
					return ad
				end
				node = node.Parent
			elseif node:IsA("BasePart") then
				local anc = node
				for _ = 1, 3 do
					if anc and anc:IsA("Model") then return anc end
					anc = anc and anc.Parent
				end
				return node
			end
			node = node.Parent
		end
		return nil
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if not isOurEsp(inst) and (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
			local ok, t = pcall(function() return inst.Text end)
			if ok and type(t) == "string" and #t == 1 and string.match(t, "%d") then
				local anc = ancestorOf(inst)
				if anc then
					groups[anc] = (groups[anc] or 0) + 1
				end
			end
		end
	end
	local best, bestCount = nil, 2 -- need at least 3 digits grouped
	for anc, n in pairs(groups) do
		if n > bestCount then best, bestCount = anc, n end
	end
	return best
end

local function keypadModel()
	local map = mapRoot()
	local k = map:FindFirstChild("Keypad")
	if k then return k end
	-- Fuzzy: any model with "keypad" in the name...
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and string.find(lowerName(inst), "keypad", 1, true) then
			return inst
		end
	end
	-- ...or any model holding Digit1-4 anywhere in its hierarchy
	-- (digits may be nested: Keypad > Panel > Digit1).
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and not isOurEsp(inst) then
			local hits = 0
			for w = 1, 4 do
				if inst:FindFirstChild("Digit" .. w, true) then hits = hits + 1 end
			end
			if hits >= 3 then return inst end
		end
	end
	-- ...or the readout heuristic: group of 3-4 single-digit labels.
	local byReadouts = findKeypadByReadouts()
	if byReadouts then return byReadouts end
	return nil
end

local function findCodeNote()
	local note = mapRoot():FindFirstChild("CodeNote")
	if note then return note end
	return workspace:FindFirstChild("CodeNote", true)
end

local function findCodeInKeypadOrMap()
	local map = mapRoot()
	local c = checkAttributesForDigits(map)
	if c and #c == 4 then return c end

	local pad = keypadModel()
	if pad then
		c = checkAttributesForDigits(pad)
		if c and #c == 4 then return c end
		for _, d in ipairs(pad:GetDescendants()) do
			if d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue") then
				local n = lowerName(d)
				if string.find(n, "code", 1, true) or string.find(n, "pass", 1, true) or string.find(n, "pin", 1, true) or string.find(n, "answer", 1, true) then
					local m = digitsInString(tostring(d.Value))
					if m and #m == 4 then return m end
				end
			end
			local a = checkAttributesForDigits(d)
			if a and #a == 4 then return a end
		end
	end
	return nil
end

-- Direct read of the real paper: CodeNote > Printed > Digits (plain
-- TextLabel, no SurfaceGui). Returns the digit string or nil.
local function readCodeNoteDirect()
	local note = findCodeNote()
	if not note then return nil end
	local a = checkAttributesForDigits(note)
	if a and #a == 4 then return a end

	local printed = note:FindFirstChild("Printed")
	local digitsObj = (printed and printed:FindFirstChild("Digits"))
		or note:FindFirstChild("Digits", true)
	if digitsObj and (digitsObj:IsA("TextLabel") or digitsObj:IsA("TextButton")) then
		local m = digitsInString(digitsObj.Text)
		if m and #m == 4 then return m end
	end
	return extractDigits(note)
end

local function applyFoundCode(code)
	if not code or #code < 3 then return end
	for _, e in pairs(Tracked) do
		if e.kind == "code" then
			e.digits = code
		end
	end
end

-- Read the real paper first (CodeNote > Printed > Digits), then tracked
-- marks, then keypad/map attributes, then every NOTE (fires Read prompts) + UI + world scan.
local function acquireCode()
	local direct = readCodeNoteDirect()
	if direct and #direct == 4 then applyFoundCode(direct) return direct end

	local code = getFoundCode()
	if code and #code == 4 then applyFoundCode(code) return code end

	local padCode = findCodeInKeypadOrMap()
	if padCode and #padCode == 4 then applyFoundCode(padCode) return padCode end

	-- Fire prompts on CodeNote and all note objects
	local note = findCodeNote()
	if note then firePromptsIn(note) end
	for _, e in pairs(Tracked) do
		if e.kind == "code" and e.root and inWorkspace(e.root) then
			firePromptsIn(e.root)
		end
	end
	fireAllReadPrompts(20)
	task.wait(0.3)

	code = scanPlayerGuiForCode() or getFoundCode()
	if code and #code == 4 then applyFoundCode(code) return code end

	scanCodeTexts()
	code = getFoundCode() or readCodeNoteDirect() or scanPlayerGuiForCode() or findCodeInKeypadOrMap()
	if code then applyFoundCode(code) end
	return code
end
-- Hold a key Tool in hand: doors often validate the equipped key,
-- firing their prompt empty-handed does nothing.
local function equipKeyTool()
	local char = myCharacter()
	local hum = myHumanoid()
	if not char or not hum then return false end
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") and matchesAny(lowerName(t), KEY_NAMES) then
			return true
		end
	end
	local bp = LocalPlayer and LocalPlayer:FindFirstChild("Backpack") or nil
	if bp then
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") and matchesAny(lowerName(t), KEY_NAMES) then
				pcall(function() hum:EquipTool(t) end)
				task.wait(0.3)
				return true
			end
		end
	end
	return false
end

-- Any prompt with "lock" in its own/parent/grandparent name (e.g.
-- LockPromptPoint > LockPrompt). Closets ("locker") and the elevator are
-- excluded.
local function scanLockPrompts(limit)
	local out = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") and not isOurEsp(inst) then
			local host = inst.Parent
			local scope = host and host.Parent or nil
			local hay = lowerName(inst) .. " " .. lowerName(host) .. " " .. lowerName(scope)
			if string.find(hay, "lock", 1, true) then
				local skip = false
				if matchesAny(lowerName(host) .. " " .. lowerName(scope), CLOSET_NAMES) then
					skip = true
				end
				if not skip and string.find(hay, "elevator", 1, true) then
					skip = true
				end
				if not skip then
					local part = promptRootPart(inst)
					if part then
						out[#out + 1] = { prompt = inst, pos = part.Position }
						if limit and #out >= limit then break end
					end
				end
			end
		end
	end
	return out
end

-- Player ESP: marks other players (for trolling/visiting).
local function scanPlayers()
	if not State.playerEsp then return end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character and inWorkspace(plr.Character) then
			if not Tracked[plr.Character] then
				local target, part = resolveTarget(plr.Character)
				if target and part then
					local hl, bb, txt = makeEspObjects(target, part)
					Tracked[plr.Character] = { kind = "player", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, digits = nil, label = "PLAYER", root = plr.Character }
				end
			end
		end
	end
end

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
-- clickable TextButtons (VIM screen clicks). The ClickDetector usually
-- hangs off a child named "Digit" whose parent is "Digit1", so walk up
-- the ancestor chain looking for a digit slot name.
local function slotNameFrom(inst)
	local node = inst
	for _ = 1, 3 do
		if typeof(node) ~= "Instance" then break end
		local n = lowerName(node)
		local slot = string.match(n, "^digit(%d)$")
		if slot then return slot end
		if #n == 1 and string.match(n, "%d") then return n end
		node = node.Parent
	end
	return nil
end

local function panelDigitControls(panelModel)
	local clicks, buttons = {}, {}
	for _, d in ipairs(panelModel:GetDescendants()) do
		if d:IsA("ClickDetector") then
			local slot = slotNameFrom(d)
			if slot then clicks[slot] = d end
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
	if Camera then
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

-- Fire every "read this" prompt in the world (broad sweep for notes the
-- ESP may not have marked yet). Used by the code hunt.
local function fireAllReadPrompts(limit)
	local n = 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") and not isOurEsp(inst) then
			local host = readPromptHost(inst)
			if host and inWorkspace(host) then
				prepPrompt(inst)
				firePrompt(inst)
				n = n + 1
				if limit and n >= limit then break end
			end
		end
	end
	return n
end


local function enterCodeAtPanel(panel, code, force)
	pressPanelDigits(panel, code, force)
	task.wait(0.5)
	firePromptsIn(panel)
	task.wait(0.5)
end

-- Click a 3D part through the screen (fallback when the executor has no
-- fireclickdetector): face it, project to viewport, real mouse click.
local function screenClickPart(part)
	if not VIM or not Camera then return false end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return false end
	faceTowards(part.Position)
	local v, onScreen = Camera:WorldToViewportPoint(part.Position)
	if not onScreen then return false end
	return vimClick(v.X, v.Y)
end

-- Forward declarations, used by the panel-buttons module below and
-- enterCodeReference (which runs after everything is assigned).
local clickKeypadDigit = nil

-- Locate digit{w} model inside whatever the keypad turned out to be:
-- direct "Digit{w}" child first, then any descendant named digit{w}.
local function keypadDigitModel(pad, w)
	local direct = pad:FindFirstChild("Digit" .. w) or pad:FindFirstChild("digit" .. w)
	if direct then return direct end
	return pad:FindFirstChild("Digit" .. w, true) or pad:FindFirstChild("digit" .. w, true)
end

-- ===================== PANEL BUTTONS =====================
-- Overlay buttons projected onto the world (the trick the working scripts
-- use): a ScreenGui button is glued to each Keypad digit's screen position
-- every frame. Clicking it sends a REAL VIM mouse click at that exact
-- screen point, so the game's own input pipeline handles the press —
-- exactly like clicking the digit yourself.
local PanelButtons = { gui = nil, frame = nil, buttons = {}, conn = nil, active = false }

local function panelButtonsParent()
	local ok, parent = pcall(function()
		if gethui then return gethui() end
		return game:GetService("CoreGui")
	end)
	if ok and parent then return parent end
	return (LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")) or nil
end

local function ensurePanelButtons()
	if PanelButtons.gui and PanelButtons.gui.Parent then return end
	local parent = panelButtonsParent()
	if not parent then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UraniumPanelButtons"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 500
	gui.IgnoreGuiInset = true
	gui.Parent = parent
	PanelButtons.gui = gui
	local frame = Instance.new("Frame")
	frame.Name = "Holder"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Parent = gui
	PanelButtons.frame = frame
end

local function destroyPanelButtons()
	if PanelButtons.conn then
		pcall(function() PanelButtons.conn:Disconnect() end)
		PanelButtons.conn = nil
	end
	if PanelButtons.gui then
		pcall(function() PanelButtons.gui:Destroy() end)
	end
	PanelButtons.gui = nil
	PanelButtons.frame = nil
	PanelButtons.buttons = {}
	PanelButtons.active = false
end

-- Digit{w} part of the real Keypad (the clickable box), via any detector.
local function keypadDigitPart(w)
	local map = mapRoot()
	local pad = (map ~= workspace and map:FindFirstChild("Keypad"))
		or workspace:FindFirstChild("Keypad")
		or keypadModel()
	if not pad then return nil end
	local digitModel = keypadDigitModel(pad, w)
	if not digitModel then return nil end
	return digitModel:FindFirstChildWhichIsA("BasePart", true)
end

-- Show overlay buttons on every keypad digit. While visible they track
-- the digits on screen; a click = REAL VIM mouse click at that position.
local function showPanelButtons()
	ensurePanelButtons()
	if not PanelButtons.gui then return end
	for w = 1, 4 do
		local btn = PanelButtons.buttons[w]
		if not btn or not btn.Parent then
			btn = Instance.new("TextButton")
			btn.Name = "DigitBtn" .. w
			btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			btn.BackgroundTransparency = 0.75
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 13
			btn.Text = "+1"
			btn.Size = UDim2.new(0, 46, 0, 24)
			btn.Visible = false
			btn.Parent = PanelButtons.frame
			PanelButtons.buttons[w] = btn
			-- Clicking the overlay = real VIM click at this button's center,
			-- which sits exactly on the digit box. The game's own pipeline
			-- processes it like a genuine player click.
			btn.MouseButton1Click:Connect(function()
				local pos = btn.AbsolutePosition
				local size = btn.AbsoluteSize
				if pos and size then
					vimClick(pos.X + size.X / 2, pos.Y + size.Y / 2)
				end
			end)
		end
	end
	if PanelButtons.conn then
		pcall(function() PanelButtons.conn:Disconnect() end)
	end
	PanelButtons.active = true
	PanelButtons.conn = RunService.RenderStepped:Connect(function()
		if not PanelButtons.active then return end
		for w = 1, 4 do
			local btn = PanelButtons.buttons[w]
			local part = keypadDigitPart(w)
			if btn and part and inWorkspace(part) then
				local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
				if onScreen then
					btn.Position = UDim2.new(0, sp.X - 23, 0, sp.Y - 12)
					btn.Visible = true
				else
					btn.Visible = false
				end
			elseif btn then
				btn.Visible = false
			end
		end
	end)
end

-- One REAL click on digit{w} (via the overlay position = digit screen pos).
function clickKeypadDigitImpl(w)
	local part = keypadDigitPart(w)
	if not part then return false end
	if VIM then
		-- Face the digit then click its exact screen position: the game's
		-- own pipeline registers it (ClickDetector or whatever it uses).
		faceTowards(part.Position)
		local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
		if not onScreen then return false end
		return vimClick(sp.X, sp.Y)
	end
	-- No VIM: fall back to fireclickdetector on the direct child.
	local map = mapRoot()
	local pad = (map ~= workspace and map:FindFirstChild("Keypad"))
		or workspace:FindFirstChild("Keypad")
	if pad then
		local digitModel = pad:FindFirstChild("Digit" .. w)
		if digitModel then
			local det = digitModel:FindFirstChild("ClickDetector")
			if det and typeof(fireclickdetector) == "function" then
				pcall(fireclickdetector, det)
				return true
			end
		end
	end
	return false
end
clickKeypadDigit = clickKeypadDigitImpl

-- Read the digit currently shown on one Keypad slot. Reads the Readout
-- label first; if there is none, any single-digit TextLabel in the slot
-- subtree (the screenshot shows SurfaceGui digits on each box).
local function keypadSlotDigit(digitW)
	local readout = digitW:FindFirstChild("Readout", true)
	local shown = nil
	if readout then
		if readout:IsA("TextLabel") or readout:IsA("TextButton") then
			pcall(function() shown = readout.Text end)
		else
			local lbl = readout:FindFirstChildWhichIsA("TextLabel", true)
				or readout:FindFirstChildWhichIsA("TextButton", true)
			if lbl then pcall(function() shown = lbl.Text end) end
		end
	end
	if not shown then
		for _, d in ipairs(digitW:GetDescendants()) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				local t = d.Text or ""
				if #t == 1 and string.match(t, "%d") then
					shown = t
					break
				end
			end
		end
	end
	return shown and string.match(tostring(shown), "%d") or nil
end

-- Reference-style code entry: find the keypad (direct > fuzzy > readout
-- heuristic), then click each digit until its Readout shows the wanted
-- char. Clicks go through the REAL input pipeline (VIM mouse click at the
-- digit's screen position), fireclickdetector as fallback.
local function enterCodeReference(code, force)
	local map = mapRoot()
	local pad = (map ~= workspace and map:FindFirstChild("Keypad"))
		or workspace:FindFirstChild("Keypad")
		or keypadModel()
	if not pad then
		notify("Put Code", "Keypad Not Found (monochrome folder: "
			.. (map ~= workspace and "yes" or "NO") .. ", readout scan failed too)", "alert")
		return false
	end
	if not VIM and typeof(fireclickdetector) ~= "function" then
		notify("Put Code", "No click method (no VIM, no fireclickdetector)", "alert")
		return false
	end
	for w = 1, math.min(4, #code) do
		if not State.autowin and not force then return false end
		local want = string.sub(code, w, w)
		local digitModel = keypadDigitModel(pad, w)
		if not digitModel then
			notify("Put Code", "Digit" .. w .. " Not Found in " .. pad.Name, "alert")
			return false
		end
		local readout = digitModel:FindFirstChild("Readout")
			or digitModel:FindFirstChild("Readout", true)
		if not readout then
			notify("Put Code", "Readout missing on Digit" .. w .. " (" .. pad.Name .. ")", "alert")
			return false
		end
		if not (readout:IsA("TextLabel") or readout:IsA("TextButton")) then
			local lbl = readout:FindFirstChildWhichIsA("TextLabel", true)
				or readout:FindFirstChildWhichIsA("TextButton", true)
			if lbl then readout = lbl end
		end
		local tries = 0
		local txt = ""
		while true do
			if not State.autowin and not force then return false end
			pcall(function() txt = tostring(readout.Text) end)
			if txt == want then break end
			if tries >= 20 then
				notify("Put Code", "Digit" .. w .. " stuck: shows '" .. txt
					.. "' want '" .. want .. "' (" .. tries .. " clicks)", "alert")
				return false
			end
			tries = tries + 1
			if not clickKeypadDigit(w) then
				notify("Put Code", "Click failed on Digit" .. w .. " (no method)", "alert")
				return false
			end
			task.wait(0.12)
		end
	end
	notify("Put Code", "Code entered OK (" .. code .. ")", "check")
	return true
end

pressPanelDigits = function(panelModel, code, force)
	-- Primary: exact reference port.
	if enterCodeReference(code, force) then
		local pad = mapRoot() ~= workspace and mapRoot():FindFirstChild("Keypad") or nil
		if pad then
			firePromptsIn(pad)
		end
		return
	end
	-- Fallback: the old generic logic (recursive digit search, VIM clicks).
	local pad = keypadModel() or panelModel
	if not pad then return end
	local clicks, buttons = panelDigitControls(pad)
	for i = 1, #code do
		if not State.autowin and not force then return end
		local digit = string.sub(code, i, i)
		local det = clicks[digit]
		if det and typeof(fireclickdetector) == "function" then
			pcall(fireclickdetector, det)
		elseif VIM then
			local dw = pad:FindFirstChild("Digit" .. i, true) or nil
			local dp = dw and (dw:IsA("BasePart") and dw or dw:FindFirstChildWhichIsA("BasePart", true)) or nil
			if dp then
				screenClickPart(dp)
			else
				local btn = buttons[digit]
				if btn then
					local bp = promptRootPart(btn) or myHRP()
					if bp then faceTowards(bp.Position) end
					clickButtonAt(btn)
				end
			end
		end
		task.wait(0.3)
	end
	firePromptsIn(pad)
end

-- Structural key grab: HiddenKey{i} > KeyPrompt. Teleports onto the
-- prompt part, fires, verifies via inventory count or removal, then goes
-- back to the given home position (or stays where it started).
-- Find the drawer/furniture ancestor of an object by hierarchy (used by
-- the generic fallback grab).
local function drawerAncestorOf(inst)
	local node = typeof(inst) == "Instance" and inst.Parent or nil
	while node and node ~= workspace do
		if matchesAny(lowerName(node), DRAWER_NAMES) then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Find the SPECIFIC drawer/furniture physically holding a key. HiddenKey
-- folders are DIRECT children of the map folder (not nested in furniture),
-- so hierarchy never reveals the drawer — we locate it spatially: the
-- furniture model whose bounding box contains the key part, else the
-- nearest drawer-named model within 10 studs.
local function drawerOfKey(keyPart)
	if typeof(keyPart) ~= "Instance" or not keyPart:IsA("BasePart") then return nil end
	local kpos = keyPart.Position
	local scope = mapRoot()
	-- Pass 1: spatial containment (key inside the model's bounding box).
	local best, bestDist = nil, math.huge
	local okAll, all = pcall(function() return scope:GetDescendants() end)
	if okAll then
		for i = 1, #all do
			local m = all[i]
			if m:IsA("Model") and not isOurEsp(m) then
				local name = lowerName(m)
				if matchesAny(name, DRAWER_NAMES) then
					local ok, cf, sz = pcall(function() return m:GetBoundingBox() end)
					if ok and cf then
						local off = kpos - cf.Position
						local half = sz / 2 + Vector3.new(1, 1, 1)
						if math.abs(off.X) <= half.X and math.abs(off.Y) <= half.Y and math.abs(off.Z) <= half.Z then
							local d = off.Magnitude
							if d < bestDist then best, bestDist = m, d end
						end
					end
				end
			end
		end
	end
	if best then return best end
	-- Pass 2: nearest drawer-named model within 10 studs.
	best, bestDist = nil, 10
	if okAll then
		for i = 1, #all do
			local m = all[i]
			if m:IsA("Model") and not isOurEsp(m) and matchesAny(lowerName(m), DRAWER_NAMES) then
				local p = m:FindFirstChildWhichIsA("BasePart", true)
				if p then
					local d = (p.Position - kpos).Magnitude
					if d < bestDist then best, bestDist = m, d end
				end
			end
		end
	end
	return best
end

local function promptUsable(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return false end
	local ok, en = pcall(function() return prompt.Enabled end)
	return ok and en == true
end

-- Open the drawer holding a key: fire its prompt and click detectors.
local function openDrawer(drawer)
	if typeof(drawer) ~= "Instance" then return end
	local ok, descs = pcall(function() return drawer:GetDescendants() end)
	if not ok then return end
	for i = 1, #descs do
		local d = descs[i]
		if d:IsA("ProximityPrompt") and d.Enabled then
			prepPrompt(d)
			pcall(function() d.HoldDuration = 0 end)
			firePrompt(d, true)
		elseif d:IsA("ClickDetector") and typeof(fireclickdetector) == "function" then
			pcall(fireclickdetector, d)
		end
	end
end

-- ===================== ANTI-KILL (under-floor dive) =====================
-- During key collection the monster can't be allowed to interrupt: dive
-- under the floor where it can't reach — prepPrompt'ed prompts still fire
-- from there (LOS off, range 5000), so the grab continues from safety.
local UNDER_FLOOR_OFFSET = 25
local CurrentGrabPos = nil -- active grab anchor; heartbeat dives here
local lastDiveNotify = 0

local function monsterPosition()
	local ver = workspace:FindFirstChild("VER")
	if ver then
		local _, p = resolveTarget(ver)
		if p then return p.Position end
	end
	for inst, e in pairs(Tracked) do
		if e.kind == "monster" and e.part and inWorkspace(inst) then
			return e.part.Position
		end
	end
	return nil
end

local function monsterNear(pos, radius)
	if typeof(pos) ~= "Vector3" then return false end
	local m = monsterPosition()
	if not m then return false end
	return (m - pos).Magnitude <= (radius or State.antiKillRadius or 15)
end

local function diveUnder(pos, quiet)
	local hrp = myHRP()
	if not hrp or typeof(pos) ~= "Vector3" then return false end
	pcall(function() hrp.CFrame = CFrame.new(pos - Vector3.new(0, UNDER_FLOOR_OFFSET, 0)) end)
	if not quiet and os.clock() - lastDiveNotify > 4 then
		lastDiveNotify = os.clock()
		notify("Anti Kill", "Monster close — diving under floor", "shield")
	end
	return true
end

-- Reference-script grab, hardened: TP 3 studs ABOVE the key part, fire the
-- KeyPrompt directly (no blind E — that toggles drawers), verify by
-- inventory/removal, retry with the SPECIFIC drawer opened only when the
-- prompt is dead. Monster nearby -> do the whole thing from under the floor.
local function grabHiddenKey(hk, homeOverride)
	if typeof(hk) ~= "Instance" then return false end
	local before = countKeysHeld()
	local prompt = keyPromptIn(hk)
	if not prompt then return false end
	local hrp = myHRP()
	local home = homeOverride or ((hrp and hrp.CFrame) or nil)
	local drawer = nil -- located lazily (spatial search is not cheap)

	local function cleanup(goHome)
		CurrentGrabPos = nil
		hrp = myHRP()
		if goHome and hrp and home then
			pcall(function() hrp.CFrame = home end)
		end
	end

	for _ = 1, 4 do
		if not State.autowin or not State.running then cleanup(false) return false end
		if not inWorkspace(hk) then cleanup(true) return true end
		waitRespawn()
		if not State.autowin then cleanup(false) return false end
		-- Refresh the key part: it moves when the drawer slides open.
		local part = keyPartIn(hk)
		CurrentGrabPos = part and part.Position or nil

		-- Reference-style direct grab FIRST: prompt may already be alive.
		if not promptUsable(prompt) then
			-- Prompt dead -> the key sits in a CLOSED drawer. Locate and
			-- open the SPECIFIC drawer holding it, then wait for the
			-- prompt to wake up.
			if not drawer then drawer = drawerOfKey(part) end
			if drawer then
				openDrawer(drawer)
				for _ = 1, 8 do
					if promptUsable(prompt) then break end
					task.wait(0.15)
				end
			end
			prompt = keyPromptIn(hk) or prompt
			part = keyPartIn(hk) or part
			CurrentGrabPos = part and part.Position or CurrentGrabPos
		end

		prepPrompt(prompt)
		pcall(function() prompt.HoldDuration = 0 end)

		-- Monster nearby? Dive under the floor and grab from safety.
		local diving = CurrentGrabPos and monsterNear(CurrentGrabPos)
		if diving then
			diveUnder(CurrentGrabPos)
			task.wait(0.15)
		else
			hrp = myHRP()
			if hrp and part and inWorkspace(part) then
				-- Reference offset: 3 studs above the key part.
				pcall(function() hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0) end)
				task.wait(0.15)
			end
		end
		if not State.autowin then cleanup(false) return false end

		if promptUsable(prompt) and typeof(fireproximityprompt) == "function" then
			-- Works from under the floor: LOS off + range 5000.
			pcall(fireproximityprompt, prompt)
			task.wait(0.15)
			if inWorkspace(hk) and countKeysHeld() <= before then
				pcall(fireproximityprompt, prompt) -- second shot
			end
		elseif promptUsable(prompt) and not diving then
			firePrompt(prompt, true)
		elseif diving then
			-- No fireproximityprompt + monster near: wait it out below,
			-- then surface and grab normally.
			for _ = 1, 32 do
				if not State.autowin then cleanup(false) return false end
				if not monsterNear(CurrentGrabPos, 25) then break end
				task.wait(0.25)
			end
			hrp = myHRP()
			if hrp and part then
				pcall(function() hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0) end)
			end
			task.wait(0.15)
			firePrompt(prompt, true)
		end
		task.wait(0.25)
		if not inWorkspace(hk) or countKeysHeld() > before then
			cleanup(true)
			return true
		end
	end
	local ok = (not inWorkspace(hk)) or countKeysHeld() > before
	cleanup(ok)
	return ok
end

local function grabKey(inst)
	local before = countKeysHeld()
	local drawer = drawerAncestorOf(inst)
	for attempt = 1, 3 do
		if not State.autowin or not State.running then return false end
		if not inWorkspace(inst) then return true end
		waitRespawn()
		if not State.autowin then return false end
		local _, part = resolveTarget(inst)
		local pos = part and part.Position or nil
		if pos then
			instantTP(pos + Vector3.new(0, 1, 0))
		end
		if not State.autowin then return false end
		-- Open the drawer first if there is one; the key prompt is dead
		-- while closed and a blind E just toggles the drawer.
		if drawer then
			openDrawer(drawer)
			task.wait(0.35)
			if not State.autowin then return false end
		end
		firePromptsIn(inst)
		task.wait(0.2)
		if not inWorkspace(inst) or countKeysHeld() > before then return true end
		-- Real E as last resort only (it can hit the drawer prompt).
		pressE(0.2)
		task.wait(0.2)
		if not inWorkspace(inst) or countKeysHeld() > before then return true end
	end
	return (not inWorkspace(inst)) or countKeysHeld() > before
end

local function autoWinLoop()
	while State.autowin and State.running do
		waitRespawn()
		if not State.autowin then break end
		local hrp0 = myHRP()
		local home = (hrp0 and hrp0.CFrame) or nil

		-- 1/4: teleport to each key, grab it, come back home.
		setStatus("AUTO WIN 1/4: collecting keys (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. ")")
		notify("Auto Win", "Step 1/4: grabbing keys", "key")
		for i = 1, HIDDEN_KEYS_TOTAL do
			if not State.autowin then break end
			if countKeysHeld() >= KEYS_NEEDED then break end
			local hk = hiddenKeyFolder(i)
			if hk and inWorkspace(hk) then
				grabHiddenKey(hk, home)
				setStatus("AUTO WIN 1/4: collecting keys (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. ")")
			end
			task.wait(0.1)
		end
		-- Leftovers the structural pass missed.
		if State.autowin and State.running and countKeysHeld() < KEYS_NEEDED then
			local guard = 0
			while State.autowin and State.running and countKeysHeld() < KEYS_NEEDED and guard < 10 do
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
				local h = myHRP()
				if h and home then pcall(function() h.CFrame = home end) end
				setStatus("AUTO WIN 1/4: collecting keys (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. ")")
				task.wait(0.1)
			end
		end
		if not State.autowin then break end

		-- 2/4: put the keys in the doors (key equipped, back home after).
		setStatus("AUTO WIN 2/4: opening doors (" .. countKeysHeld() .. "/" .. KEYS_NEEDED .. " keys)")
		notify("Auto Win", "Step 2/4: unlocking doors", "lock-open")
		equipKeyTool()
		for _, lname in ipairs(LOCK_PARTS) do
			if not State.autowin then break end
			waitRespawn()
			if not State.autowin then break end
			equipKeyTool()
			local lp = lockPromptByName(lname)
			if lp then
				prepPrompt(lp)
				pcall(function() lp.HoldDuration = 0 end)
				local part = promptRootPart(lp)
				if part then instantTP(part.Position + Vector3.new(0, 1, 1)) end
				if not State.autowin then break end
				firePrompt(lp, true)
				pressE(0.15)
				task.wait(0.15)
			end
		end
		for _, t in ipairs(scanLockPrompts(20)) do
			if not State.autowin then break end
			waitRespawn()
			if not State.autowin then break end
			equipKeyTool()
			prepPrompt(t.prompt)
			pcall(function() t.prompt.HoldDuration = 0 end)
			instantTP(t.pos + Vector3.new(0, 1, 1))
			if not State.autowin then break end
			firePrompt(t.prompt, true)
			pressE(0.15)
			task.wait(0.15)
		end
		do
			local h = myHRP()
			if h and home then pcall(function() h.CFrame = home end) end
		end
		if not State.autowin then break end

		-- 3/4: read the code text.
		setStatus("AUTO WIN 3/4: reading code")
		notify("Auto Win", "Step 3/4: reading code", "eye")
		-- Teleport directly near CodeNote so it's loaded and readable
		do
			local note = findCodeNote()
			if note then
				local _, notePart = resolveTarget(note)
				if notePart then
					instantTP(notePart.Position + Vector3.new(0, 1, 1))
					task.wait(0.15)
				end
			end
		end
		local code = acquireCode()
		do
			local tries = 0
			while (not code) and State.autowin and State.running and tries < 4 do
				tries = tries + 1
				setStatus("AUTO WIN 3/4: reading code (" .. tries .. "/4)")
				for _, e in pairs(Tracked) do
					if not State.autowin then break end
					if e.kind == "code" and e.root and inWorkspace(e.root) then
						firePromptsIn(e.root)
					end
				end
				fireAllReadPrompts(20)
				task.wait(0.4)
				if not State.autowin then break end
				code = scanPlayerGuiForCode() or getFoundCode() or readCodeNoteDirect()
			end
		end
		if not State.autowin then break end
		if not (code and #code == 4) then
			setStatus("AUTO WIN: code not found — use View Code, then Put Code Now")
			notify("Auto Win stuck", "Code not found — use View Code, then Put Code Now", "info")
			State.autowin = false
			if UiRefs.autoTgl then pcall(function() UiRefs.autoTgl:Set(false) end) end
			break
		end

		-- 4/4: put the code in the panel, fire the elevator, done.
		local method = typeof(fireclickdetector) == "function" and "fireclickdetector"
			or (VIM and "VIM-screen" or "NONE")
		setStatus("AUTO WIN 4/4: entering " .. code .. " (" .. method .. ")")
		notify("Auto Win", "Step 4/4: entering " .. code, "hash")
		local panel, panelPos = nil, nil
		do
			local pad = keypadModel()
			if pad then
				local _, p = resolveTarget(pad)
				if p then panel, panelPos = pad, p.Position end
			end
			if not panel then
				panel, panelPos = findEntryPanel()
			end
		end
		if not panel then
			setStatus("AUTO WIN: keypad not found. Code: " .. code)
			notify("Auto Win stuck", "Keypad not found. Code: " .. code, "info")
			State.autowin = false
			if UiRefs.autoTgl then pcall(function() UiRefs.autoTgl:Set(false) end) end
			break
		end
		waitRespawn()
		instantTP(panelPos + Vector3.new(0, 1, 2))
		task.wait(0.15)
		enterCodeAtPanel(panel, code, true)
		task.wait(0.2)
		for i = 1, 3 do
			if not State.autowin then break end
			local ep = elevatorPrompt()
			if ep then
				prepPrompt(ep)
				pcall(function() ep.HoldDuration = 0 end)
				local epart = promptRootPart(ep)
				if epart then instantTP(epart.Position + Vector3.new(0, 1, 1)) end
				firePrompt(ep, true)
			else
				firePromptsIn(panel)
			end
			task.wait(0.3)
		end
		do
			local h = myHRP()
			if h and home then pcall(function() h.CFrame = home end) end
		end
		setStatus("AUTO WIN done. Code: " .. code)
		notify("Auto Win finished", "Code: " .. code .. " — game completed", "check")
		State.autowin = false
		if UiRefs.autoTgl then pcall(function() UiRefs.autoTgl:Set(false) end) end
		break
	end
end

-- Auto Use Keys: passive loop, uses held keys on nearby deadbolts (no TP).
local function autoKeysLoop()
	local lastUsed = 0
	while State.autokeys and State.running do
		if countKeysHeld() > 0 then
			equipKeyTool()
			local origin = rootPosition()
			for _, t in ipairs(scanPrompts(DEADBOLT_NAMES, NEVER_EXIT, 20)) do
				if not State.autokeys then break end
				if (t.pos - origin).Magnitude <= 30 then
					prepPrompt(t.prompt)
					firePrompt(t.prompt)
					lastUsed = os.clock()
					setStatus("AUTO KEYS: used key (" .. countKeysHeld() .. " held)")
					task.wait(0.5)
				end
			end
			if os.clock() - lastUsed < 3 and countKeysHeld() > 0 then
				setStatus("AUTO KEYS: watching exit (" .. countKeysHeld() .. " held)")
			end
		end
		for i = 1, 20 do
			if not State.autokeys or not State.running then break end
			task.wait(0.1)
		end
	end
end

-- One-shot: hunt the code remotely (Read prompts fire at any distance)
-- and show it — no need to walk to the note.
local function viewCodeNow()
	task.spawn(function()
		setStatus("VIEW CODE: reading notes...")
		notify("View Code", "Reading notes...", "eye")
		local code = acquireCode()
		if not code then
			scanCodeTexts()
			code = getFoundCode() or readCodeNoteDirect()
		end
		if code then
			pcall(function()
				if typeof(setclipboard) == "function" then setclipboard(code) end
			end)
			setStatus("CODE: " .. code .. " (copied)")
			notify("CODE: " .. code, "Copied to clipboard — type it at the Keypad", "check")
		else
			local m, _, c = countTargets()
			local noteTxt = findCodeNote() and "found" or "MISSING"
			setStatus("VIEW CODE: not found (note:" .. noteTxt .. " marks:" .. c .. ")")
			notify("View Code", "Not found — CodeNote:" .. noteTxt .. ", code marks:" .. c .. ". Walk near NOTE marks and retry", "info")
		end
	end)
end

-- Fire key-like prompts near a position (precise pickup when the prompt
-- does not sit on the tracked part itself).
local function fireKeyPromptsNear(pos, radius)
	local fired = false
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") and not isOurEsp(inst) then
			local part = promptRootPart(inst)
			if part and (part.Position - pos).Magnitude <= radius then
				local hay = lowerName(inst) .. " " .. lowerName(inst.Parent)
					.. " " .. tostring(inst.ObjectText or ""):lower()
					.. " " .. tostring(inst.ActionText or ""):lower()
				if matchesAny(hay, KEY_NAMES)
					or matchesAny(hay, { "pick", "take", "grab", "collect", "recoger", "agarrar" }) then
					prepPrompt(inst)
					firePrompt(inst)
					fired = true
				end
			end
		end
	end
	return fired
end

-- Insta Collect: grab nearby keys instantly through drawers and walls
local function instaCollectLoop()
	while State.instacollect and State.running do
		local hrp = myHRP()
		if hrp then
			local home = hrp.CFrame
			local radius = State.collectRadius or 14

			-- Direct check for HiddenKey1-4 folders
			for i = 1, HIDDEN_KEYS_TOTAL do
				if not State.instacollect then break end
				local hk = hiddenKeyFolder(i)
				if hk and inWorkspace(hk) then
					local part = keyPartIn(hk)
					if part then
						local dist = (part.Position - home.Position).Magnitude
						if dist <= radius then
							local kp = keyPromptIn(hk)
							if kp then
								pcall(function() hrp.CFrame = part.CFrame + Vector3.new(0, 0.5, 0) end)
								pcall(function()
									kp.MaxActivationDistance = 9999
									kp.Enabled = true
									kp.HoldDuration = 0
								end)
								prepPrompt(kp)
								firePrompt(kp, true)
								pressE(0.08)
								task.wait(0.05)
								pcall(function() hrp.CFrame = home end)
							end
						end
					end
				end
			end

			-- Check all tracked key objects
			for inst, e in pairs(Tracked) do
				if not State.instacollect then break end
				if e.kind == "key" and e.part and inWorkspace(inst) then
					local dist = (e.part.Position - home.Position).Magnitude
					if dist <= radius then
						pcall(function() hrp.CFrame = e.part.CFrame + Vector3.new(0, 0.5, 0) end)
						for _, d in ipairs(inst:GetDescendants()) do
							if d:IsA("ProximityPrompt") then
								pcall(function()
									d.MaxActivationDistance = 9999
									d.Enabled = true
									d.HoldDuration = 0
								end)
								prepPrompt(d)
								firePrompt(d, true)
							end
						end
						if e.root and e.root ~= inst then
							for _, d in ipairs(e.root:GetDescendants()) do
								if d:IsA("ProximityPrompt") then
									pcall(function()
										d.MaxActivationDistance = 9999
										d.Enabled = true
										d.HoldDuration = 0
									end)
									prepPrompt(d)
									firePrompt(d, true)
								end
							end
						end
						pressE(0.08)
						task.wait(0.05)
						pcall(function() hrp.CFrame = home end)
					end
				end
			end
		end
		task.wait(0.04)
	end
end

-- Forward declaration: pressPanelDigits is defined below enterCodeAtPanel
-- but called from within it. Without this, it's nil at call time.
local pressPanelDigits

-- One-shot: read code + teleport to panel + type it.
local function putCodeNow()
	task.spawn(function()
		setStatus("PUT CODE: finding code...")
		notify("Put Code", "Finding code...", "hash")
		local code = acquireCode()
		if not code then
			scanCodeTexts()
			code = getFoundCode()
		end
		if not code then
			setStatus("PUT CODE: code not found — read the NOTE marks")
			notify("Put Code", "Code not found — read the NOTE marks", "info")
			return
		end
		local panel, panelPos = nil, nil
		do
			local pad = keypadModel()
			if pad then
				local _, p = resolveTarget(pad)
				if p then panel, panelPos = pad, p.Position end
			end
			if not panel then
				panel, panelPos = findEntryPanel()
			end
		end
		if not panel or not panelPos then
			setStatus("PUT CODE: panel not found. Code: " .. code)
			notify("Put Code", "Panel not found. Code: " .. code, "info")
			return
		end
		do
			local method = typeof(fireclickdetector) == "function" and "fireclickdetector"
				or (VIM and "VIM-screen" or "NONE")
			notify("Put Code", "Keypad found, pressing via " .. method, "info")
			if method == "NONE" then
				setStatus("PUT CODE: no click method on this executor. Code: " .. code)
				notify("Put Code", "Executor can't click — type " .. code .. " manually", "alert")
				return
			end
		end
		local hrp = myHRP()
		if not hrp then
			setStatus("PUT CODE: no character. Code: " .. code)
			return
		end
		pcall(function() hrp.CFrame = CFrame.new(panelPos + Vector3.new(0, 1, 2)) end)
		task.wait(0.15)
		faceTowards(panelPos)
		setStatus("PUT CODE: entering " .. code)
		notify("Put Code", "Entering " .. code, "hash")
		pressPanelDigits(panel, code, true)
		task.wait(0.3)
		firePromptsIn(panel)
		setStatus("PUT CODE done: " .. code)
		notify("Put Code done", "Code: " .. code, "check")
	end)
end

-- Enter the code MANUALLY using the on-screen keypad buttons: walks each
-- digit with real VIM clicks, exactly like clicking them yourself.
local function putCodeWithButtons()
	task.spawn(function()
		setStatus("PUT CODE: finding code...")
		local code = acquireCode() or getFoundCode() or readCodeNoteDirect()
		if not code or #code ~= 4 then
			notify("Put Code", "Code not found", "info")
			return
		end
		local map = mapRoot()
		local pad = (map ~= workspace and map:FindFirstChild("Keypad"))
			or workspace:FindFirstChild("Keypad")
		if not pad then
			notify("Put Code", "Keypad Not Found", "alert")
			return
		end
		if not VIM then
			notify("Put Code", "No VirtualInputManager — can't click", "alert")
			return
		end
		-- Stand in front of the keypad so the digits are on screen.
		local _, pp = resolveTarget(pad)
		local hrp = myHRP()
		if pp and hrp then
			pcall(function() hrp.CFrame = CFrame.new(pp + Vector3.new(0, 1, 3)) end)
			task.wait(0.2)
			faceTowards(pp)
		end
		notify("Put Code", "Clicking digits with REAL mouse input: " .. code, "hash")
		if enterCodeReference(code, true) then
			setStatus("PUT CODE done (real clicks): " .. code)
		end
	end)
end

local function autoPutCodeLoop()
	while State.autoPutCode and State.running do
		local code = acquireCode() or getFoundCode() or readCodeNoteDirect() or scanPlayerGuiForCode()
		if code and #code == 4 then
			notify("Auto Put Code", "Code found: " .. code .. " — typing at panel...", "hash")
			putCodeNow()
			State.autoPutCode = false
			if UiRefs.autoPutCodeTgl then pcall(function() UiRefs.autoPutCodeTgl:Set(false) end) end
			break
		end
		task.wait(1)
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
	mSec:Colorpicker({
		Name = "Monster color", Default = State.colMonster, Flag = "ura_colmonster",
		Callback = function(v)
			State.colMonster = v
			applyKindColors("monster")
		end,
	})
	mSec:Paragraph({
		Title = "How it works",
		Content = "Monster ESP outlines the monster (workspace.VER) with name + distance. If it ever renames, enable NPC scan.",
	})

	local iSec = espItems:Section({ Name = "Keys & Code", Side = 1 })
	UiRefs.keysTgl = iSec:Toggle({
		Name = "Key ESP", Default = State.keys, Flag = "ura_keys",
		Callback = function(v)
			State.keys = v
			if v then fullScan() else clearKind("key") end
		end,
	})
	iSec:Colorpicker({
		Name = "Key color", Default = State.colKey, Flag = "ura_colkey",
		Callback = function(v)
			State.colKey = v
			applyKindColors("key")
		end,
	})
	UiRefs.codesTgl = iSec:Toggle({
		Name = "Code ESP (notes)", Default = State.codes, Flag = "ura_codes",
		Callback = function(v)
			State.codes = v
			if v then scanCodeTexts() else clearKind("code") end
		end,
	})
	iSec:Colorpicker({
		Name = "Code color", Default = State.colCode, Flag = "ura_colcode",
		Callback = function(v)
			State.colCode = v
			applyKindColors("code")
		end,
	})
	UiRefs.closetsTgl = iSec:Toggle({
		Name = "Closet ESP (hiding)", Default = State.closets, Flag = "ura_closets",
		Callback = function(v)
			State.closets = v
			if v then fullScan() else clearKind("closet") end
		end,
	})
	iSec:Colorpicker({
		Name = "Closet color", Default = State.colCloset, Flag = "ura_colcloset",
		Callback = function(v)
			State.colCloset = v
			applyKindColors("closet")
		end,
	})
	iSec:Paragraph({
		Title = "Code ESP",
		Content = "Marks the NOTE / PAPER where the code IS (CodeNote > Printed > Digits is read directly). It never marks the keypad where you type it.",
	})
	UiRefs.playerEspTgl = iSec:Toggle({
		Name = "Player ESP", Default = State.playerEsp, Flag = "ura_playeresp",
		Callback = function(v)
			State.playerEsp = v
			if v then fullScan() else clearKind("player") end
		end,
	})
	iSec:Colorpicker({
		Name = "Player color", Default = State.colPlayer, Flag = "ura_colplayer",
		Callback = function(v)
			State.colPlayer = v
			applyKindColors("player")
		end,
	})

	local vSec = espItems:Section({ Name = "Style", Side = 2 })
	vSec:Toggle({
		Name = "Chams (outline)", Default = State.chams, Flag = "ura_chams",
		Callback = function(v) State.chams = v end,
	})
	vSec:Toggle({
		Name = "Labels (name + dist)", Default = State.labels, Flag = "ura_labels",
		Callback = function(v) State.labels = v end,
	})
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
	movSec:Paragraph({
		Title = "Hotkeys",
		Content = "N toggles Noclip, V toggles Fly.",
	})
	movSec:Toggle({
		Name = "Anti Kill", Default = State.antiKill, Flag = "ura_antikill",
		Callback = function(v)
			State.antiKill = v
		end,
	})
	movSec:Slider({
		Name = "Trigger radius", Min = 5, Max = 50, Default = State.antiKillRadius, Suffix = "studs", Flag = "ura_akr",
		Callback = function(v) State.antiKillRadius = v end,
	})
	movSec:Slider({
		Name = "Flee distance", Min = 20, Max = 500, Default = State.antiKillFlee, Suffix = "studs", Flag = "ura_akf",
		Callback = function(v) State.antiKillFlee = v end,
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
	local godSec = movMain:Section({ Name = "Survival", Side = 2 })
	godSec:Toggle({
		Name = "Infinite Lives [PATCHED]", Default = State.godmode, Flag = "ura_godmode",
		Callback = function(v)
			applyGodmode(v)
		end,
	})
	godSec:Paragraph({
		Title = "How it works",
		Content = "Pins Humanoid health to max and locks any life/vida counter to 999. Fully effective when the game trusts the client; otherwise combine with Noclip/Fly so the monster never touches you.",
	})
	local worldSub = movTab:SubTab({ Name = "World", Icon = "globe" })
	local worldSec = worldSub:Section({ Name = "World", Side = 1 })
	worldSec:Toggle({
		Name = "Fullbright", Default = State.fullbright, Flag = "ura_fullbright",
		Callback = function(v)
			State.fullbright = v
			applyFullbright(v)
		end,
	})
	worldSec:Button({
		Name = "TP Spawn",
		Callback = function() teleportSpawn() end,
	})
	local intSec = worldSub:Section({ Name = "Interaction", Side = 2 })
	intSec:Toggle({
		Name = "Instant Interact (no hold)", Default = State.instantPrompt, Flag = "ura_instant",
		Callback = function(v)
			State.instantPrompt = v
			applyInstantPrompt(v)
		end,
	})
	intSec:Paragraph({
		Title = "Instant Interact",
		Content = "All E prompts complete instantly (no holding). Restored when disabled.",
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
	autoSec:Toggle({
		Name = "Auto Use Keys", Default = false, Flag = "ura_autokeys",
		Callback = function(v)
			State.autokeys = v
			if v then task.spawn(autoKeysLoop) end
		end,
	})
	autoSec:Button({
		Name = "Put Code Now",
		Callback = function() putCodeNow() end,
	})
	autoSec:Button({
		Name = "Put Code (REAL clicks)",
		Callback = function() putCodeWithButtons() end,
	})
	autoSec:Toggle({
		Name = "Keypad Buttons (click digits)",
		Default = false, Flag = "ura_panelbuttons",
		Callback = function(v)
			if v then showPanelButtons() else destroyPanelButtons() end
		end,
	})
	UiRefs.autoPutCodeTgl = autoSec:Toggle({
		Name = "Auto Put Code (when found)", Default = State.autoPutCode, Flag = "ura_autoputcode",
		Callback = function(v)
			State.autoPutCode = v
			if v then task.spawn(autoPutCodeLoop) end
		end,
	})
	autoSec:Paragraph({
		Title = "What it does",
		Content = "Auto Win: 1 clears entrance, 2 opens drawers, 3 grabs HiddenKey1-4 (inventory-checked), 4 opens the Cube door locks, 5 hunts the code, types it on the Keypad and fires the elevator. Auto Use Keys spends held keys on nearby exits. Put Code Now types the code once. View Code shows the code + copies it, no walking needed.",
	})
	local grabSec = autoMain:Section({ Name = "Grab", Side = 2 })
	grabSec:Slider({
		Name = "Collect distance", Min = 2, Max = 20, Default = State.collectDist, Suffix = "studs", Flag = "ura_collect",
		Callback = function(v) State.collectDist = v end,
	})
	grabSec:Button({
		Name = "View Code",
		Callback = function() viewCodeNow() end,
	})
	grabSec:Toggle({
		Name = "Insta Collect (walk near keys)", Default = State.instacollect, Flag = "ura_instacollect",
		Callback = function(v)
			State.instacollect = v
			if v then task.spawn(instaCollectLoop) end
		end,
	})
	grabSec:Slider({
		Name = "Pickup radius", Min = 6, Max = 40, Default = State.collectRadius, Suffix = "studs", Flag = "ura_pickup",
		Callback = function(v) State.collectRadius = v end,
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
		Name = "Copy map structure (debug)",
		Callback = function()
			task.spawn(function()
				local lines = {}
				local map = workspace:FindFirstChild("monochrome")
				table.insert(lines, "MAP folder: " .. (map and map:GetFullName() or "NOT FOUND"))
				table.insert(lines, "-- workspace children --")
				for _, ch in ipairs(workspace:GetChildren()) do
					table.insert(lines, ch.ClassName .. " | " .. ch.Name)
				end
				if map then
					table.insert(lines, "-- monochrome children --")
					for _, ch in ipairs(map:GetChildren()) do
						table.insert(lines, ch.ClassName .. " | " .. ch.Name)
					end
				end
				-- Anything that smells like a keypad/panel/digit/elevator:
				-- dump 2 levels of its tree.
				local hot = {}
				for _, inst in ipairs(workspace:GetDescendants()) do
					if not isOurEsp(inst) then
						local n = lowerName(inst)
						if string.find(n, "keypad", 1, true) or string.find(n, "key pad", 1, true)
							or string.find(n, "digit", 1, true) or string.find(n, "readout", 1, true)
							or string.find(n, "elevator", 1, true) or string.find(n, "panel", 1, true) then
							local root = inst
							for _ = 1, 4 do
								if root.Parent and root.Parent ~= workspace and root.Parent ~= map then
									root = root.Parent
								else
									break
								end
							end
							if not hot[root] then
								hot[root] = true
								table.insert(lines, "-- TREE of " .. root:GetFullName() .. " --")
								for _, d in ipairs(root:GetDescendants()) do
									local l = "  " .. d.ClassName .. " | " .. d.Name
									if d:IsA("TextLabel") or d:IsA("TextButton") then
										l = l .. " | text='" .. tostring(d.Text) .. "'"
									end
									table.insert(lines, l)
									if #lines > 300 then break end
								end
							end
						end
					end
					if #lines > 300 then break end
				end
				local out = table.concat(lines, "\n")
				pcall(function()
					if typeof(setclipboard) == "function" then
						setclipboard(out)
					end
				end)
				notify("Debug", "Map structure copied (" .. #lines .. " lines) — paste it in chat/Discord", "copy")
			end)
		end,
	})
	miscSec:Button({
		Name = "Copy Discord invite",
		Callback = function()
			pcall(function()
				if typeof(setclipboard) == "function" then
					setclipboard(DISCORD_INVITE)
				end
			end)
			notify("Discord", DISCORD_INVITE .. " — copied", "message-circle")
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

	local wm = window:Watermark({ Name = "URANIUM", Icon = "radioactive" })
	pcall(function()
		if wm and wm.Instance then
			local titleLbl = Instance.new("TextLabel")
			titleLbl.Name = "UraniumWatermarkTitle"
			titleLbl.Text = "URANIUM"
			titleLbl.Font = Enum.Font.GothamBold
			titleLbl.TextSize = 14
			titleLbl.TextColor3 = Color3.fromRGB(245, 245, 245)
			titleLbl.BackgroundTransparency = 1
			titleLbl.Size = UDim2.fromOffset(0, 16)
			titleLbl.AutomaticSize = Enum.AutomaticSize.X
			titleLbl.LayoutOrder = 1
			titleLbl.ZIndex = 62
			titleLbl.Parent = wm.Instance
		end
	end)
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

-- NOTE: Keybind() attached directly to a Toggle in this lib version binds the
-- toggle itself, so N/V keybinds are separate controls below the toggles.
-- (Attached above via movSec:Keybind.)

trackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.W then FlyKeys.W = true end
	if input.KeyCode == Enum.KeyCode.A then FlyKeys.A = true end
	if input.KeyCode == Enum.KeyCode.S then FlyKeys.S = true end
	if input.KeyCode == Enum.KeyCode.D then FlyKeys.D = true end
	if input.KeyCode == Enum.KeyCode.Space then FlyKeys.Up = true end
	if input.KeyCode == Enum.KeyCode.LeftShift then FlyKeys.Down = true end
	-- Hotkeys (ignored while typing in chat/game input)
	if not gpe then
		if input.KeyCode == Enum.KeyCode.N and UiRefs.noclipTgl then
			UiRefs.noclipTgl:Set(not State.noclip)
		elseif input.KeyCode == Enum.KeyCode.V and UiRefs.flyTgl then
			UiRefs.flyTgl:Set(not State.fly)
		end
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
					Tracked[inst] = { kind = "code", target = part, part = part, boxSize = part.Size, hl = hl, bb = bb, txt = txt, digits = digits, label = "CODE", root = inst }
				end
			end
		end)
	elseif inst:IsA("ProximityPrompt") and (State.codes or State.closets) then
		task.delay(0.5, function()
			if Tracked[inst] or not inWorkspace(inst) then return end
			if State.closets then
				local hideHost = hidePromptHost(inst)
				if hideHost and not Tracked[hideHost] and inWorkspace(hideHost) then
					local target, part = resolveTarget(hideHost)
					if target and part then
						local hl, bb, txt = makeEspObjects(target, part)
						Tracked[hideHost] = { kind = "closet", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, digits = nil, label = "CLOSET", root = hideHost }
						return
					end
				end
			end
			if not State.codes then return end
			local host = readPromptHost(inst)
			if host and not Tracked[host] and inWorkspace(host) then
				local target, part = resolveTarget(host)
				if target and part then
					local hl, bb, txt = makeEspObjects(target, part)
					Tracked[host] = { kind = "code", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, digits = extractDigits(host), label = "NOTE", root = host }
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

-- ===================== DISCORD GATE =====================
-- Blocks cheat initialization until the user clicks "Copy Invite & Start".
do
	local gateGui = Instance.new("ScreenGui")
	gateGui.Name = "UraniumGate"
	gateGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gateGui.ResetOnSpawn = false
	gateGui.IgnoreGuiInset = true
	local GetHui = gethui or function() return game:GetService("CoreGui") end
	pcall(function() gateGui.Parent = GetHui() end)
	if not gateGui.Parent then
		pcall(function() gateGui.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") end)
	end

	local bg = Instance.new("Frame")
	bg.Name = "Backdrop"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.ZIndex = 100
	bg.Parent = gateGui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(0, 390, 0, 230)
	card.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	card.BorderSizePixel = 0
	card.ZIndex = 101
	card.Parent = bg

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(88, 101, 242)
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = 0.2
	cardStroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Text = "URANIUM"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 0, 0, 18)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.ZIndex = 102
	title.Parent = card

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Text = "Join our Discord community to launch the cheat"
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 13
	subtitle.TextColor3 = Color3.fromRGB(175, 175, 185)
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.new(0, 0, 0, 48)
	subtitle.Size = UDim2.new(1, 0, 0, 20)
	subtitle.ZIndex = 102
	subtitle.Parent = card

	local linkBox = Instance.new("Frame")
	linkBox.Name = "LinkBox"
	linkBox.AnchorPoint = Vector2.new(0.5, 0)
	linkBox.Position = UDim2.new(0.5, 0, 0, 80)
	linkBox.Size = UDim2.new(0, 330, 0, 36)
	linkBox.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	linkBox.BorderSizePixel = 0
	linkBox.ZIndex = 102
	linkBox.Parent = card

	local linkCorner = Instance.new("UICorner")
	linkCorner.CornerRadius = UDim.new(0, 6)
	linkCorner.Parent = linkBox

	local linkStroke = Instance.new("UIStroke")
	linkStroke.Color = Color3.fromRGB(45, 45, 55)
	linkStroke.Thickness = 1
	linkStroke.Parent = linkBox

	local linkText = Instance.new("TextLabel")
	linkText.Name = "LinkText"
	linkText.Text = DISCORD_INVITE
	linkText.Font = Enum.Font.GothamBold
	linkText.TextSize = 14
	linkText.TextColor3 = Color3.fromRGB(114, 137, 218)
	linkText.BackgroundTransparency = 1
	linkText.Size = UDim2.new(1, 0, 1, 0)
	linkText.ZIndex = 103
	linkText.Parent = linkBox

	local copyBtn = Instance.new("TextButton")
	copyBtn.Name = "CopyButton"
	copyBtn.AnchorPoint = Vector2.new(0.5, 0)
	copyBtn.Position = UDim2.new(0.5, 0, 0, 134)
	copyBtn.Size = UDim2.new(0, 240, 0, 42)
	copyBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
	copyBtn.BorderSizePixel = 0
	copyBtn.Font = Enum.Font.GothamBold
	copyBtn.TextSize = 15
	copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	copyBtn.Text = "Copy Invite & Start"
	copyBtn.AutoButtonColor = true
	copyBtn.ZIndex = 103
	copyBtn.Parent = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = copyBtn

	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.Text = "Click the button to copy the link and unlock the script"
	info.Font = Enum.Font.Gotham
	info.TextSize = 11
	info.TextColor3 = Color3.fromRGB(130, 130, 140)
	info.BackgroundTransparency = 1
	info.Position = UDim2.new(0, 0, 0, 185)
	info.Size = UDim2.new(1, 0, 0, 18)
	info.ZIndex = 102
	info.Parent = card

	local passed = false
	copyBtn.MouseButton1Click:Connect(function()
		pcall(function()
			if typeof(setclipboard) == "function" then
				setclipboard(DISCORD_INVITE)
			end
		end)
		passed = true
		pcall(function() gateGui:Destroy() end)
	end)

	while not passed do
		task.wait(0.1)
	end
	task.wait(0.15)
end

Window = buildGui()
-- Save Zolar holders so Unload can fully destroy the GUI.
pcall(function()
	if getgenv and getgenv().Zolar then
		if getgenv().Zolar.Holder then SavedHolder = getgenv().Zolar.Holder.Instance end
		if getgenv().Zolar.PopupHolder then SavedPopup = getgenv().Zolar.PopupHolder.Instance end
	end
end)

local accDist, accCode, accText, accFb = 0, 0, 0, 0
local accAntiKill = 0
local noteFlag, noteFlagAt = "?", 0
trackConnection(RunService.Heartbeat:Connect(function(dt)
	if not State.running then return end
	-- Movement systems run every frame (game resets speed constantly)
	local hum = myHumanoid()
	if hum and hum.WalkSpeed ~= State.speed then
		applySpeed()
	end
	-- Infinite Lives frame-pin: if the server replicates damage faster than
	-- the HealthChanged signal fires, this clamps it back every frame.
	if State.godmode and hum and hum.Parent and hum.Health < hum.MaxHealth then
		pcall(function() hum.Health = hum.MaxHealth end)
	end
	-- Anti Kill: the monster crossed the trigger radius -> teleport away.
	-- While a key grab is active (CurrentGrabPos), dive UNDER THE FLOOR
	-- instead of fleeing 100 studs — the grab continues from safety.
	if State.antiKill or CurrentGrabPos then
		accAntiKill = accAntiKill + dt
		if accAntiKill >= 0.2 then
			accAntiKill = 0
			local hrp = myHRP()
			local mPos = monsterPosition()
			if hrp and mPos then
				local away = (hrp.Position - mPos).Magnitude
				if away <= State.antiKillRadius then
					if CurrentGrabPos then
						-- Under-floor dive: monster can't reach, prompts
						-- still fire (prepPrompt removed LOS + range limits).
						pcall(function() hrp.CFrame = CFrame.new(CurrentGrabPos - Vector3.new(0, UNDER_FLOOR_OFFSET, 0)) end)
						if os.clock() - lastDiveNotify > 4 then
							lastDiveNotify = os.clock()
							notify("Anti Kill", "Monster at " .. math.floor(away) .. " studs — diving under floor (grab continues)", "shield")
						end
					else
						local dir = (hrp.Position - mPos)
						if dir.Magnitude < 0.1 then
							dir = Vector3.new(0, 0, 1)
						end
						dir = Vector3.new(dir.X, 0, dir.Z)
						if dir.Magnitude < 0.1 then
							dir = Vector3.new(1, 0, 0)
						end
						dir = dir.Unit
						local dest = mPos + dir * State.antiKillFlee + Vector3.new(0, 3, 0)
						pcall(function() hrp.CFrame = CFrame.new(dest) end)
						notify("Anti Kill", "Monster at " .. math.floor(away) .. " studs — fled " .. State.antiKillFlee .. " studs", "run")
					end
				end
			end
		end
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
	if State.fullbright then
		accFb = accFb + dt
		if accFb >= 1 then
			accFb = 0
			enforceFullbright()
		end
	end
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
		if State.closets then pcall(scanClosetHosts) end
		if State.playerEsp then pcall(scanPlayers) end
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
			local m, k, c, h = countTargets()
			local code = getFoundCode()
			-- Cached CodeNote presence (recursive fallback is expensive).
			if os.clock() - noteFlagAt > 10 then
				noteFlagAt = os.clock()
				noteFlag = findCodeNote() and "Y" or "N"
			end
			local note = ""
			if game.PlaceId ~= TARGET_PLACE then
				note = " (outside MONOCHROME)"
			end
			local codeTxt = code and ("  code:" .. code) or ""
			pcall(function()
				StatusLabel:Set("monster:" .. m .. "  key:" .. k .. "  code:" .. c .. "  hide:" .. h .. "  note:" .. noteFlag .. codeTxt .. "  keys:" .. countKeysHeld() .. "/4" .. note)
			end)
		end
	end
end))

if game.PlaceId ~= TARGET_PLACE then
	notify("URANIUM", "Outside MONOCHROME — ESP still active", "info")
else
	notify("URANIUM loaded", "Press RightShift for the menu", "check")
end

-- Startup map check: if the game renamed key objects, say so immediately.
do
	local missing = {}
	if not findCodeNote() then missing[#missing + 1] = "CodeNote" end
	local verFound = false
	for _, ch in ipairs(workspace:GetChildren()) do
		if lowerName(ch) == "ver" then verFound = true break end
	end
	if not verFound then missing[#missing + 1] = "VER" end
	local hkFound = 0
	local map = mapRoot()
	for i = 1, HIDDEN_KEYS_TOTAL do
		if map:FindFirstChild(HIDDEN_KEY_PREFIX .. i) then hkFound = hkFound + 1 end
	end
	if hkFound == 0 then missing[#missing + 1] = "HiddenKey1-4" end
if #missing > 0 then
			notify("URANIUM", "Not found: " .. table.concat(missing, ", ") .. " — game may have renamed objects", "alert")
		end
	end

-- Discord invite on load (copied to clipboard so joining is one paste away).
pcall(function()
	if typeof(setclipboard) == "function" then
		setclipboard(DISCORD_INVITE)
	end
end)
notify("Join our Discord", DISCORD_INVITE .. " — invite copied to clipboard", "message-circle")

local Api = {}
Api.Window = Window
function Api.Unload()
	State.running = false
	State.autowin = false
	State.autokeys = false
	State.instacollect = false
	State.fly = false
	State.noclip = false
	State.fullbright = false
	State.instantPrompt = false
	State.godmode = false
	destroyPanelButtons()
	for _, c in ipairs(GodConns) do
		pcall(function() c:Disconnect() end)
	end
	GodConns = {}
	disableFly()
	applyFullbright(false)
	applyInstantPrompt(false)
	pcall(function()
		local hum = myHumanoid()
		if hum then hum.WalkSpeed = 16 end
	end)
	setNoclipParts(true)
	for _, conn in ipairs(Connections) do
		pcall(function() conn:Disconnect() end)
	end
	for inst in pairs(Tracked) do
		removeEntry(inst)
	end
	pcall(function() EspFolder:Destroy() end)
	if Window then pcall(function() Window:SetOpen(false) end) end
	if SavedHolder then pcall(function() SavedHolder:Destroy() end) end
	if SavedPopup then pcall(function() SavedPopup:Destroy() end) end
	SavedHolder, SavedPopup = nil, nil
end

if getgenv then
	getgenv().UraniumMono = Api
end

return Api
