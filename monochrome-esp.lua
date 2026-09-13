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
--               Style: chams, 2D corner boxes, snaplines, labels, colors.
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
local HasDrawing = typeof(Drawing) == "table"

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
	boxes = true, -- 2D corner boxes (needs Drawing)
	tracers = true, -- snaplines (needs Drawing)
	labels = true, -- name/distance billboards
	matChams = false, -- ForceField material overlay on every mark
	chamTransp = 0.4, -- material cham transparency
	chamFlat = true, -- tint chammed parts with the kind color
	shaderChams = false, -- fullscreen monochrome shader (ColorCorrection)
	shaderSat = -1, -- shader saturation (-1 = full monochrome)
	shaderContrast = 0.2, -- shader contrast boost
	noclip = false,
	fly = false,
	instacollect = false, -- grab keys the moment you walk into range
	collectRadius = 12, -- pickup radius for Insta Collect (studs)
	playerEsp = false, -- see other players (trolling tab)
	visit = false, -- visit-loop: TP to each player in turn
	visitDelay = 3,
	instantPrompt = false,
	fullbright = false,
	autowin = false,
	autokeys = false,
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

if not HasDrawing then
	State.boxes = false
	State.tracers = false
end

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
		return nil
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
	if not hit then return nil end
	local host = prompt.Parent
	if not host or isOurEsp(host) then return nil end
	if host:IsA("BasePart") then return host end
	if host:IsA("Model") or host:IsA("Tool") then return host end
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

local function boxSizeOf(target, part)
	if target and target:IsA("Model") then
		local ok, size = pcall(function() return target:GetExtentsSize() end)
		if ok and size then return size end
	end
	if part then return part.Size end
	return Vector3.new(4, 6, 2)
end

local EspFolder = nil

local function makeEspObjects(target, part)
	local col = WHITE
	local hl = Instance.new("Highlight")
	hl.Name = "Uranium_HL"
	hl.Adornee = target
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0
	hl.OutlineColor = col
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = State.chams
	hl.Parent = EspFolder

	local bb = Instance.new("BillboardGui")
	bb.Name = "Uranium_BB"
	bb.Adornee = part
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 220, 0, 44)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.Enabled = State.labels
	bb.Parent = EspFolder

	local txt = Instance.new("TextLabel")
	txt.Name = "Label"
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.Font = Enum.Font.GothamBlack
	txt.TextSize = State.textSize
	txt.TextColor3 = col
	txt.TextStrokeTransparency = 0
	txt.TextStrokeColor3 = BLACK
	txt.Text = ""
	txt.Parent = bb

	return hl, bb, txt
end

-- ---------- Drawing (2D corner boxes + snaplines) ----------
local function ensureDraw(e)
	if e.draw or not HasDrawing then return end
	local d = { c = {}, snap = nil, txt = nil }
	for i = 1, 8 do
		local l = Drawing.new("Line")
		l.Visible = false
		l.Thickness = 1.5
		d.c[i] = l
	end
	local s = Drawing.new("Line")
	s.Visible = false
	s.Thickness = 1
	d.snap = s
	local t = Drawing.new("Text")
	t.Visible = false
	t.Center = true
	t.Outline = true
	t.Font = 3 -- monospace: digits/distances stay aligned
	d.txt = t
	e.draw = d
end

local function hideDraw(e)
	local d = e.draw
	if not d then return end
	for i = 1, #d.c do d.c[i].Visible = false end
	d.snap.Visible = false
	d.txt.Visible = false
end

local function destroyDraw(e)
	local d = e.draw
	if not d then return end
	for i = 1, #d.c do pcall(function() d.c[i]:Remove() end) end
	pcall(function() d.snap:Remove() end)
	pcall(function() d.txt:Remove() end)
	e.draw = nil
end

local function drawEntry(e, origin)
	local d = e.draw
	if not d then return end
	if not e.part or not inWorkspace(e.root) then
		hideDraw(e)
		return
	end
	local showBox = State.boxes and HasDrawing
	local showTrac = State.tracers and HasDrawing
	if (not showBox and not showTrac) or not isKindEnabled(e.kind) then
		hideDraw(e)
		return
	end
	local dist = (e.part.Position - origin).Magnitude
	if dist > State.maxDist or not Camera then
		hideDraw(e)
		return
	end
	local sz = e.boxSize or e.part.Size
	local top3 = e.part.Position + Vector3.new(0, sz.Y / 2, 0)
	local bot3 = e.part.Position - Vector3.new(0, sz.Y / 2, 0)
	local t2, vt = Camera:WorldToViewportPoint(top3)
	local b2, vb = Camera:WorldToViewportPoint(bot3)
	if (not vt and not vb) or t2.Z < 0 or b2.Z < 0 then
		hideDraw(e)
		return
	end
	local h = math.max(math.abs(t2.Y - b2.Y), 4)
	local w = h * 0.55
	local cx = (t2.X + b2.X) / 2
	local ty = math.min(t2.Y, b2.Y)
	local lx, rx, by = cx - w / 2, cx + w / 2, ty + h
	local cl = math.max(math.min(w, h) * 0.25, 3)
	local col = kindColor(e.kind)
	local pts = {
		{ lx, ty, lx + cl, ty }, { lx, ty, lx, ty + cl },
		{ rx - cl, ty, rx, ty }, { rx, ty, rx, ty + cl },
		{ lx, by - cl, lx, by }, { lx, by, lx + cl, by },
		{ rx - cl, by, rx, by }, { rx, by, rx, by - cl },
	}
	for i = 1, 8 do
		local l = d.c[i]
		l.Color = col
		l.From = Vector2.new(pts[i][1], pts[i][2])
		l.To = Vector2.new(pts[i][3], pts[i][4])
		l.Visible = showBox
	end
	if showTrac then
		local vs = Camera.ViewportSize
		d.snap.Color = col
		d.snap.From = Vector2.new(vs.X / 2, vs.Y)
		d.snap.To = Vector2.new(cx, by)
		d.snap.Visible = true
	else
		d.snap.Visible = false
	end
	if showBox then
		-- Drawing text only when billboard labels are OFF: otherwise the
		-- name + distance shows twice (this was the "double name" bug).
		if State.labels then
			d.txt.Visible = false
		else
			local title = e.kind == "code" and (e.digits and ("CODE " .. e.digits) or "NOTE") or kindTitle(e.kind)
			d.txt.Color = col
			d.txt.Size = State.textSize
			d.txt.Text = title .. "  " .. tostring(math.floor(dist)) .. "m"
			d.txt.Position = Vector2.new(cx, ty - State.textSize - 6)
			d.txt.Visible = true
		end
	else
		d.txt.Visible = false
	end
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
					Tracked[d] = { kind = "code", target = part, part = part, boxSize = part.Size, hl = hl, bb = bb, txt = txt, digits = digits, label = "CODE", root = d }
				end
			end
		elseif d:IsA("ProximityPrompt") and not Tracked[d] then
			-- A "hide" prompt marks its host as a closet first.
			local hideHost = hidePromptHost(d)
			if hideHost and not Tracked[hideHost] and State.closets then
				local target, part = resolveTarget(hideHost)
				if target and part then
					local hl, bb, txt = makeEspObjects(target, part)
					Tracked[hideHost] = { kind = "closet", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, digits = nil, label = "CLOSET", root = hideHost }
				end
			end
			-- A "read this" prompt marks its host as a code location.
			local host = readPromptHost(d)
			if host and not Tracked[host] then
				local target, part = resolveTarget(host)
				if target and part then
					local hl, bb, txt = makeEspObjects(target, part)
					Tracked[host] = { kind = "code", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, digits = extractDigits(host), label = "NOTE", root = host }
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
						Tracked[d] = { kind = "code", target = part, part = part, boxSize = part.Size, hl = hl, bb = bb, txt = txt, digits = string.sub(val, 1, 8), label = "CODE", root = d }
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

-- Forward: material-cham restore, assigned by the chams engine below
-- (removeEntry runs before that code textually).
local restoreChamForFn = nil

local function removeEntry(inst)
	local e = Tracked[inst]
	if e then
		-- Restore material-cham parts (engine assigned below).
		if e.target and restoreChamForFn then
			pcall(restoreChamForFn, e.target)
		end
		destroyDraw(e)
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
	if kind == "closet" then return State.closets end
	if kind == "player" then return State.playerEsp end
	return false
end

-- ===================== MATERIAL CHAMS =====================
-- ForceField overlay over every marked target, originals restored on
-- remove/disable/unload. Engine sits here so updateEntry/addEntry (below)
-- and removeEntry (above, via restoreChamForFn) can all reach it.
local ChamOrig = {} -- [BasePart] = {mat, color, transp}

local function chamParts(target)
	local parts = {}
	if typeof(target) ~= "Instance" then return parts end
	if target:IsA("BasePart") then
		parts[1] = target
	elseif target:IsA("Model") then
		local ok, descs = pcall(function() return target:GetDescendants() end)
		if ok then
			for i = 1, #descs do
				if descs[i]:IsA("BasePart") then parts[#parts + 1] = descs[i] end
			end
		end
	end
	return parts
end

local function applyChamToTarget(target, col)
	for _, part in ipairs(chamParts(target)) do
		if not ChamOrig[part] and not isOurEsp(part) then
			local ok, m, c, t = pcall(function()
				return part.Material, part.Color, part.Transparency
			end)
			if ok then
				ChamOrig[part] = { mat = m, color = c, transp = t }
				pcall(function()
					part.Material = Enum.Material.ForceField
					if State.chamFlat then part.Color = col end
					part.Transparency = State.chamTransp
				end)
			end
		end
	end
end

restoreChamForFn = function(target)
	for _, part in ipairs(chamParts(target)) do
		local o = ChamOrig[part]
		if o then
			ChamOrig[part] = nil
			pcall(function()
				if part.Parent then
					part.Material = o.mat
					part.Color = o.color
					part.Transparency = o.transp
				end
			end)
		end
	end
end

local function applyMaterialChams(on, quiet)
	State.matChams = on
	if not on then
		for part, o in pairs(ChamOrig) do
			ChamOrig[part] = nil
			pcall(function()
				if part.Parent then
					part.Material = o.mat
					part.Color = o.color
					part.Transparency = o.transp
				end
			end)
		end
		for _, e in pairs(Tracked) do
			e.chammed = nil
		end
		return
	end
	for _, e in pairs(Tracked) do
		if e.target and isKindEnabled(e.kind) then
			e.chammed = true
			applyChamToTarget(e.target, kindColor(e.kind))
		end
	end
	local n = 0
	for _ in pairs(ChamOrig) do n = n + 1 end
	if on and not quiet then
		if n == 0 then
			notify("URANIUM", "Material chams: no targets — enable an ESP kind first", "info")
		else
			notify("URANIUM", "Material chams ON (" .. n .. " parts)", "sparkles")
		end
	end
end

-- Re-apply after transparency / flat / color changes.
local function refreshChamsIfOn()
	if not State.matChams then return end
	applyMaterialChams(false, true)
	applyMaterialChams(true, true)
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
	local hl, bb, txt = makeEspObjects(target, part)
	local digits = nil
	if kind == "code" then
		digits = extractDigits(inst)
	end
	Tracked[inst] = { kind = kind, target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, draw = nil, digits = digits, label = label, root = inst }
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
			Tracked[inst] = { kind = kind, target = nil, part = nil, boxSize = nil, hl = nil, bb = nil, txt = nil, draw = nil, digits = nil, label = label, root = inst }
			return
		end
	end
	local hl, bb, txt = makeEspObjects(target, part)
	local digits = nil
	if kind == "code" then
		digits = extractDigits(inst)
	end
	Tracked[inst] = { kind = kind, target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, draw = nil, digits = digits, label = label, root = inst }
end

-- Structural closet pass: Hide prompts AND Hide click detectors anywhere
-- in the hierarchy (hiding may not use ProximityPrompts at all).
local function scanClosetHosts()
	if not State.closets then return end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") and not isOurEsp(inst) then
			local host = hidePromptHost(inst)
			if host and not Tracked[host] and inWorkspace(host) then
				local target, part = resolveTarget(host)
				if target and part then
					local hl, bb, txt = makeEspObjects(target, part)
					Tracked[host] = { kind = "closet", target = target, part = part, boxSize = boxSizeOf(target, part), hl = hl, bb = bb, txt = txt, digits = nil, label = "CLOSET", root = host }
				end
			end
		elseif inst:IsA("ClickDetector") and not isOurEsp(inst) then
			local host = inst.Parent
			if typeof(host) == "Instance" and not Tracked[host] and inWorkspace(host)
				and (host:IsA("BasePart") or host:IsA("Model") or host:IsA("Tool")) then
				local hay = lowerName(inst) .. " " .. lowerName(host)
				if matchesAny(hay, HIDE_WORDS) or matchesAny(hay, CLOSET_NAMES) then
					pcall(forceEntry, host, "closet", "CLOSET")
				end
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
	-- Drawing objects are created lazily here: without this call boxes and
	-- snaplines never render (this was the "boxes don't work" bug).
	if HasDrawing and (State.boxes or State.tracers) then
		ensureDraw(e)
	end
	-- Material chams for entries that appeared while the toggle is on.
	if State.matChams and e.target and not e.chammed and isKindEnabled(e.kind) then
		e.chammed = true
		applyChamToTarget(e.target, kindColor(e.kind))
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
	e.hl.Enabled = State.chams
	e.bb.Enabled = State.labels
	local col = kindColor(e.kind)
	pcall(function() e.hl.OutlineColor = col end)
	pcall(function() e.txt.TextColor3 = col end)
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

-- ===================== SHADER CHAMS =====================
-- Fullscreen monochrome FX (a ColorCorrectionEffect in Lighting): the whole
-- game renders desaturated with boosted contrast while ESP marks pop.
local function ensureShader()
	if not State.shaderChams then return end
	local cc = Lighting:FindFirstChild("UraniumShader")
	if not (typeof(cc) == "Instance" and cc:IsA("ColorCorrectionEffect")) then
		if typeof(cc) == "Instance" then pcall(function() cc:Destroy() end) end
		local ok, fx = pcall(Instance.new, "ColorCorrectionEffect")
		if not ok or not fx then return end
		cc = fx
		cc.Name = "UraniumShader"
		pcall(function() cc.Parent = Lighting end)
	end
	pcall(function()
		cc.Saturation = State.shaderSat
		cc.Contrast = State.shaderContrast
		cc.Brightness = 0
		cc.Enabled = true
	end)
end

local function applyShaderChams(on)
	State.shaderChams = on
	if not on then
		local cc = Lighting:FindFirstChild("UraniumShader")
		if cc then pcall(function() cc:Destroy() end) end
		return
	end
	ensureShader()
end

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
	GodConns[#GodConns + 1] = LocalPlayer.CharacterAdded:Connect(function(char)
		if not State.godmode then return end
		task.wait(1)
		if not State.godmode or not State.running then return end
		armGodHumanoid(char:FindFirstChildOfClass("Humanoid"))
		for _, v in ipairs(livesValueCandidates()) do
			lockLivesValue(v)
		end
	end)
	notify("URANIUM", "Infinite Lives ON (health + lives locked)", "heart")
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
local function firePrompt(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return end
	if not prompt.Enabled then return end
	if typeof(fireproximityprompt) == "function" then
		pcall(fireproximityprompt, prompt)
		task.wait((prompt.HoldDuration or 0) + 0.3)
		return
	end
	local began = false
	pcall(function()
		prompt:InputHoldBegin()
		began = true
	end)
	if began then
		task.wait((prompt.HoldDuration or 0) + 0.2)
		pcall(function() prompt:InputHoldEnd() end)
		task.wait(0.3)
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
	-- ...or any model holding Digit1-4 children (name may have changed).
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and not isOurEsp(inst) then
			local hits = 0
			for w = 1, 4 do
				if inst:FindFirstChild("Digit" .. w) then hits = hits + 1 end
			end
			if hits >= 3 then return inst end
		end
	end
	return nil
end

local function findCodeNote()
	local note = mapRoot():FindFirstChild("CodeNote")
	if note then return note end
	return workspace:FindFirstChild("CodeNote", true)
end

-- Direct read of the real paper: CodeNote > Printed > Digits (plain
-- TextLabel, no SurfaceGui). Returns the digit string or nil.
local function readCodeNoteDirect()
	local note = findCodeNote()
	if not note then return nil end
	local printed = note:FindFirstChild("Printed")
	local digitsObj = (printed and printed:FindFirstChild("Digits"))
		or note:FindFirstChild("Digits", true)
	if digitsObj and (digitsObj:IsA("TextLabel") or digitsObj:IsA("TextButton")) then
		local m = nil
		pcall(function() m = digitsInString(digitsObj.Text) end)
		if m then return m end
	end
	return extractDigits(note)
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

-- Read the real paper first (CodeNote > Printed > Digits), then tracked
-- marks, then every NOTE (fires Read prompts) + UI + world scan.
local function acquireCode()
	local direct = readCodeNoteDirect()
	if direct and #direct == 4 then return direct end
	local code = getFoundCode()
	if code and #code == 4 then return code end
	for _, e in pairs(Tracked) do
		if e.kind == "code" and e.root and inWorkspace(e.root) then
			firePromptsIn(e.root)
		end
	end
	fireAllReadPrompts(20)
	task.wait(0.6)
	code = scanPlayerGuiForCode() or getFoundCode()
	if code then return code end
	if direct then return direct end
	scanCodeTexts()
	return getFoundCode() or readCodeNoteDirect()
end

local function enterCodeAtPanel(panel, code)
	pressPanelDigits(panel, code)
	task.wait(0.8)
	firePromptsIn(panel)
	task.wait(0.8)
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

local function pressPanelDigits(panelModel, code)
	-- Fast path: the real Keypad (Digit1-4, each with Readout + a "Digit"
	-- child holding the ClickDetector). Click the right digit until its
	-- Readout shows the wanted char, like the reference script does.
	local pad = keypadModel()
	if pad and typeof(fireclickdetector) == "function" then
		local structural = true
		for w = 1, #code do
			if not State.autowin then return end
			local want = string.sub(code, w, w)
			local digitW = pad:FindFirstChild("Digit" .. w)
			if not digitW then structural = false break end
			local clicker = digitW:FindFirstChild("Digit") or digitW
			local det = clicker:FindFirstChildOfClass("ClickDetector")
				or digitW:FindFirstChildOfClass("ClickDetector", true)
			local readout = digitW:FindFirstChild("Readout", true)
			if not det then structural = false break end
			for _ = 1, 20 do
				if not State.autowin then return end
				local shown = nil
				if readout and (readout:IsA("TextLabel") or readout:IsA("TextButton")) then
					pcall(function() shown = readout.Text end)
				end
				if shown == want then break end
				pcall(fireclickdetector, det)
				task.wait(0.35)
			end
		end
		if structural then return end
	end
	-- Generic fallback: single-shot ClickDetectors, digit-part screen
	-- clicks on the real Keypad, or VIM clicks on digit buttons.
	local panel = panelModel or pad
	if not panel then return end
	local clicks, buttons = panelDigitControls(panel)
	for i = 1, #code do
		if not State.autowin then return end
		local digit = string.sub(code, i, i)
		local det = clicks[digit]
		if det and typeof(fireclickdetector) == "function" then
			pcall(fireclickdetector, det)
		else
			local dw = pad and pad:FindFirstChild("Digit" .. i) or nil
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
		task.wait(0.45)
	end
end

-- Structural key grab: HiddenKey{i} > KeyPrompt. Teleports onto the
-- prompt part, fires, verifies via inventory count or removal, then goes
-- back to the given home position (or stays where it started).
local function grabHiddenKey(hk, homeOverride)
	if typeof(hk) ~= "Instance" then return false end
	local before = countKeysHeld()
	local prompt = keyPromptIn(hk)
	local part = keyPartIn(hk)
	if not prompt or not part then return false end
	prepPrompt(prompt)
	local hrp = myHRP()
	local home = homeOverride or ((hrp and hrp.CFrame) or nil)
	for _ = 1, 4 do
		if not State.autowin or not State.running then return false end
		if not inWorkspace(hk) then return true end
		waitRespawn()
		if not State.autowin then return false end
		hrp = myHRP()
		if hrp and inWorkspace(part) then
			pcall(function() hrp.CFrame = part.CFrame + Vector3.new(0, 1, 4) end)
			task.wait(0.5)
		end
		if not State.autowin then return false end
		firePrompt(prompt)
		task.wait(0.6)
		pressE(0.4)
		task.wait(0.3)
		if not inWorkspace(hk) or countKeysHeld() > before then
			hrp = myHRP()
			if hrp and home then pcall(function() hrp.CFrame = home end) end
			return true
		end
	end
	hrp = myHRP()
	if hrp and home then pcall(function() hrp.CFrame = home end) end
	return (not inWorkspace(hk)) or countKeysHeld() > before
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
			task.wait(0.15)
		end
		-- Leftovers the structural pass missed.
		if State.autowin and State.running and countKeysHeld() < KEYS_NEEDED then
			local guard = 0
			while State.autowin and State.running and countKeysHeld() < KEYS_NEEDED and guard < 15 do
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
				task.wait(0.15)
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
				local part = promptRootPart(lp)
				if part then instantTP(part.Position + Vector3.new(0, 3, 0)) end
				if not State.autowin then break end
				firePrompt(lp)
				task.wait(0.3)
				firePrompt(lp)
				task.wait(0.25)
			end
		end
		for _, t in ipairs(scanLockPrompts(20)) do
			if not State.autowin then break end
			waitRespawn()
			if not State.autowin then break end
			equipKeyTool()
			prepPrompt(t.prompt)
			instantTP(t.pos + Vector3.new(0, 3, 0))
			if not State.autowin then break end
			firePrompt(t.prompt)
			task.wait(0.3)
			firePrompt(t.prompt)
			task.wait(0.25)
		end
		do
			local h = myHRP()
			if h and home then pcall(function() h.CFrame = home end) end
		end
		if not State.autowin then break end

		-- 3/4: read the code text.
		setStatus("AUTO WIN 3/4: reading code")
		notify("Auto Win", "Step 3/4: reading code", "eye")
		local code = acquireCode()
		do
			local tries = 0
			while (not code) and State.autowin and State.running and tries < 3 do
				tries = tries + 1
				setStatus("AUTO WIN 3/4: reading code (" .. tries .. "/3)")
				for _, e in pairs(Tracked) do
					if not State.autowin then break end
					if e.kind == "code" and e.root and inWorkspace(e.root) then
						firePromptsIn(e.root)
					end
				end
				fireAllReadPrompts(20)
				task.wait(0.8)
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
		instantTP(panelPos + Vector3.new(0, 4, 0))
		enterCodeAtPanel(panel, code)
		for i = 1, 3 do
			if not State.autowin then break end
			local ep = elevatorPrompt()
			if ep then
				prepPrompt(ep)
				firePrompt(ep)
			else
				firePromptsIn(panel)
			end
			task.wait(0.6)
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

-- Insta Collect: grab nearby keys the moment you walk into range (no TP,
-- no Auto Win needed). Goes straight for the HiddenKey container's real
-- KeyPrompt, then any key-like prompt within 8 studs of the key.
local function instaCollectLoop()
	local cool = {}
	while State.instacollect and State.running do
		local hrp = myHRP()
		if hrp then
			local origin = hrp.Position
			local pressed = false
			for inst, e in pairs(Tracked) do
				if not State.instacollect then break end
				if e.kind == "key" and e.part and inWorkspace(inst) then
					if (e.part.Position - origin).Magnitude <= State.collectRadius then
						local last = cool[inst] or 0
						if os.clock() - last >= 0.8 then
							cool[inst] = os.clock()
							-- Direct: walk up to the HiddenKey container.
							local node = e.root or inst
							for i = 1, 4 do
								if typeof(node) ~= "Instance" then break end
								if string.find(lowerName(node), "hiddenkey", 1, true) then
									local kp = keyPromptIn(node)
									if kp then
										prepPrompt(kp)
										firePrompt(kp)
										pressed = true
									end
									break
								end
								if node == workspace or node == game then break end
								node = node.Parent
							end
							if fireKeyPromptsNear(e.part.Position, 8) then
								pressed = true
							end
						end
					end
				end
			end
			if pressed then
				pressE(0.3)
			end
		end
		task.wait(0.15)
	end
end

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
		pcall(function() hrp.CFrame = CFrame.new(panelPos + Vector3.new(0, 4, 0)) end)
		task.wait(0.3)
		setStatus("PUT CODE: entering " .. code)
		notify("Put Code", "Entering " .. code, "hash")
		-- Temporarily allow digit pressing outside autowin
		State.autowin = true
		pressPanelDigits(panel, code)
		State.autowin = false
		task.wait(0.6)
		firePromptsIn(panel)
		setStatus("PUT CODE done: " .. code)
		notify("Put Code done", "Code: " .. code, "check")
	end)
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
			refreshChamsIfOn()
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
			refreshChamsIfOn()
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
			refreshChamsIfOn()
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
			refreshChamsIfOn()
		end,
	})
	iSec:Paragraph({
		Title = "Code ESP",
		Content = "Marks the NOTE / PAPER where the code IS (CodeNote > Printed > Digits is read directly). It never marks the keypad where you type it.",
	})

	local vSec = espItems:Section({ Name = "Style", Side = 2 })
	vSec:Toggle({
		Name = "Chams (outline)", Default = State.chams, Flag = "ura_chams",
		Callback = function(v) State.chams = v end,
	})
	vSec:Toggle({
		Name = "2D boxes", Default = State.boxes, Flag = "ura_boxes",
		Callback = function(v)
			if v and not HasDrawing then
				notify("URANIUM", "Drawing unavailable on this executor", "info")
				return
			end
			State.boxes = v
		end,
	})
	vSec:Toggle({
		Name = "Snaplines", Default = State.tracers, Flag = "ura_tracers",
		Callback = function(v)
			if v and not HasDrawing then
				notify("URANIUM", "Drawing unavailable on this executor", "info")
				return
			end
			State.tracers = v
		end,
	})
	vSec:Toggle({
		Name = "Labels (name + dist)", Default = State.labels, Flag = "ura_labels",
		Callback = function(v) State.labels = v end,
	})
	vSec:Toggle({
		Name = "Material chams", Default = State.matChams, Flag = "ura_matchams",
		Callback = function(v)
			applyMaterialChams(v)
		end,
	})
	vSec:Slider({
		Name = "Cham transparency", Min = 0, Max = 0.9, Default = State.chamTransp, Flag = "ura_chamtransp",
		Callback = function(v)
			State.chamTransp = v
			refreshChamsIfOn()
		end,
	})
	vSec:Toggle({
		Name = "Flat cham color", Default = State.chamFlat, Flag = "ura_chamflat",
		Callback = function(v)
			State.chamFlat = v
			refreshChamsIfOn()
		end,
	})
	vSec:Toggle({
		Name = "Shader chams (mono FX)", Default = State.shaderChams, Flag = "ura_shader",
		Callback = function(v)
			applyShaderChams(v)
		end,
	})
	vSec:Slider({
		Name = "Shader saturation", Min = -1, Max = 1, Default = State.shaderSat, Flag = "ura_shadersat",
		Callback = function(v)
			State.shaderSat = v
			if State.shaderChams then ensureShader() end
		end,
	})
	vSec:Slider({
		Name = "Shader contrast", Min = -1, Max = 1, Default = State.shaderContrast, Flag = "ura_shadercon",
		Callback = function(v)
			State.shaderContrast = v
			if State.shaderChams then ensureShader() end
		end,
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
		Name = "Infinite Lives", Default = State.godmode, Flag = "ura_godmode",
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

	window:Watermark({ Name = "URANIUM" })
	return window
end

local function visitLoop()
	while State.visit and State.running do
		local others = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
				others[#others + 1] = plr
			end
		end
		if #others > 0 then
			local target = others[math.random(#others)]
			local hrp = myHRP()
			if hrp and target.Character then
				pcall(function() hrp.CFrame = target.Character.HumanoidRootPart.CFrame + Vector3.new(3, 0, 0) end)
				notify("Visit", "Visiting " .. target.Name, "user")
			end
		end
		local delay = State.visitDelay or 3
		for i = 1, delay * 10 do
			if not State.visit or not State.running then break end
			task.wait(0.1)
		end
	end
end

-- ===================== TROLL TAB =====================

local function buildTrollTab()
	local trollTab = Window:Tab({ Name = "Trolling", Icon = "skull" })
	local trollMain = trollTab:SubTab({ Name = "Main", Icon = "user" })
	
	local trollSec = trollMain:Section({ Name = "Players", Side = 1 })
	UiRefs.playerEspTgl = trollSec:Toggle({
		Name = "Player ESP", Default = State.playerEsp, Flag = "ura_playeresp",
		Callback = function(v)
			State.playerEsp = v
			if v then fullScan() else clearKind("player") end
		end,
	})
	trollSec:Colorpicker({
		Name = "Player color", Default = State.colPlayer, Flag = "ura_colplayer",
		Callback = function(v)
			State.colPlayer = v
			applyKindColors("player")
		end,
	})
	trollSec:Button({
		Name = "TP to Monster (VER)",
		Callback = function()
			local ver = workspace:FindFirstChild("VER")
			if ver then
				local _, part = resolveTarget(ver)
				if part then
					local hrp = myHRP()
					if hrp then
						pcall(function() hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0) end)
						notify("Troll", "Teleported to monster", "skull")
					end
				else
					notify("Troll", "Monster found but no part to TP to", "alert")
				end
			else
				notify("Troll", "VER not found in workspace", "alert")
			end
		end,
	})
	trollSec:Button({
		Name = "TP Monster to Me",
		Callback = function()
			local ver = workspace:FindFirstChild("VER")
			local hrp = myHRP()
			if ver and hrp then
				local _, part = resolveTarget(ver)
				if part then
					pcall(function() part.CFrame = hrp.CFrame + Vector3.new(5, 0, 0) end)
					notify("Troll", "Monster teleported to you", "skull")
				end
			else
				notify("Troll", "VER or you not found", "alert")
			end
		end,
	})
	trollSec:Toggle({
		Name = "Visit loop (TP to each player)", Default = State.visit, Flag = "ura_visit",
		Callback = function(v)
			State.visit = v
			if v then task.spawn(visitLoop) end
		end,
	})
	trollSec:Slider({
		Name = "Visit delay", Min = 1, Max = 10, Default = 3, Suffix = "s", Flag = "ura_visitdelay",
		Callback = function(v) State.visitDelay = v end,
	})
	
	local baitSec = trollMain:Section({ Name = "Bait", Side = 2 })
	baitSec:Button({
		Name = "Bait TP (random player to you)",
		Callback = function()
			local others = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
					others[#others + 1] = plr
				end
			end
			if #others == 0 then
				notify("Bait", "No other players found", "info")
				return
			end
			local target = others[math.random(#others)]
			local hrp = myHRP()
			if hrp and target.Character then
				pcall(function() target.Character.HumanoidRootPart.CFrame = hrp.CFrame + Vector3.new(3, 0, 0) end)
				notify("Bait", "Teleported " .. target.Name .. " to you", "user")
			end
		end,
	})
	baitSec:Button({
		Name = "Bait TP (you to random player)",
		Callback = function()
			local others = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
					others[#others + 1] = plr
				end
			end
			if #others == 0 then
				notify("Bait", "No other players found", "info")
				return
			end
			local target = others[math.random(#others)]
			local hrp = myHRP()
			if hrp and target.Character then
				pcall(function() hrp.CFrame = target.Character.HumanoidRootPart.CFrame + Vector3.new(3, 0, 0) end)
				notify("Bait", "Teleported you to " .. target.Name, "user")
			end
		end,
	})
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

Window = buildGui()
buildTrollTab()
-- Save Zolar holders so Unload can fully destroy the GUI.
pcall(function()
	if getgenv and getgenv().Zolar then
		if getgenv().Zolar.Holder then SavedHolder = getgenv().Zolar.Holder.Instance end
		if getgenv().Zolar.PopupHolder then SavedPopup = getgenv().Zolar.PopupHolder.Instance end
	end
end)

local accDist, accCode, accText, accFb = 0, 0, 0, 0
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
	if State.fullbright or State.shaderChams then
		accFb = accFb + dt
		if accFb >= 1 then
			accFb = 0
			if State.fullbright then enforceFullbright() end
			if State.shaderChams then ensureShader() end
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

-- 2D boxes / snaplines render loop (Drawing only)
if HasDrawing then
	trackConnection(RunService.RenderStepped:Connect(function()
		if not State.running then return end
		if not Camera then return end
		local origin = rootPosition()
		for _, e in pairs(Tracked) do
			if e.part and e.boxSize then
				pcall(drawEntry, e, origin)
			elseif e.draw then
				hideDraw(e)
			end
		end
	end))
end

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
	State.matChams = false
	State.shaderChams = false
	applyMaterialChams(false, true)
	applyShaderChams(false)
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
