-- ============================================================
--  MONOCHROME ESP (standalone)
--  Juego: MONOCHROME (PlaceId 134208374070897)
--
--  NO necesita Uranium ni ninguna libreria. Proyecto 100% aparte.
--  Uso:
--    loadstring(game:HttpGet("https://raw.githubusercontent.com/Korsac2026/monochrome/main/monochrome-esp.lua"))()
--
--  Incluye:
--    1) Monster ESP : detecta al monstruo y lo marca (contorno + nombre + distancia)
--    2) Key ESP     : marca la ubicacion de las llaves del mapa
--    3) Code ESP    : marca keypads / notas / cajas y lee el codigo
--                     si aparece en algun texto (pantalla, nota, prompt)
--  Todo en blanco y negro (monocromo). RightShift muestra/oculta la GUI.
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

-- Paleta monocroma
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PANEL = Color3.fromRGB(12, 12, 12)
local ROW_OFF = Color3.fromRGB(28, 28, 28)
local ROW_ON = Color3.fromRGB(225, 225, 225)
local TXT_ON = Color3.fromRGB(235, 235, 235)
local TXT_DIM = Color3.fromRGB(150, 150, 150)

-- Nombres que delatan al monstruo (minusculas, coincidencia parcial)
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
-- Carpetas que, si contienen un humanoide, es el monstruo
local MONSTER_FOLDERS = {
	"monster", "monsters", "monstruo", "entity", "entities",
	"npcs", "enemies", "killers", "bosses", "ai", "enemy",
}
-- Nombres de llaves
local KEY_NAMES = { "key", "llave", "keycard" }
-- Nombres de objetos con codigo, por prioridad (etiqueta + palabras)
local CODE_KINDS = {
	{ label = "KEYPAD", words = { "keypad", "teclado" } },
	{ label = "NOTE", words = { "note", "nota", "paper", "papel", "diary", "diario", "notebook", "libreta", "cuaderno", "clue", "pista", "hint", "document", "documento", "file", "archivo" } },
	{ label = "LOCK", words = { "padlock", "candado", "lock", "cerradura", "locker", "casillero", "safe", "cajafuerte", "vault", "boveda" } },
	{ label = "PC", words = { "computer", "computadora", "ordenador", "terminal", "panel" } },
	{ label = "CODE", words = { "code", "codigo", "password", "contrasena", "passcode", "pincode", "pin", "cipher", "cifra", "cifrado", "digit", "digito" } },
}

local DIST_STEPS = { 150, 300, 500, 1000, 999999 }
local DIST_LABELS = { "150m", "300m", "500m", "1000m", "INF" }

local State = {
	running = true,
	monster = true,
	keys = true,
	codes = true,
	npcScan = false, -- marca CUALQUIER humanoide no-jugador como monstruo
	distStep = 3, -- indice en DIST_STEPS (500m)
}

local Tracked = {} -- [instancia] = {kind, target, part, hl, bb, txt, digits, label}
local Connections = {}

local function trackConnection(conn)
	Connections[#Connections + 1] = conn
	return conn
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

-- Clasifica una instancia del workspace. Devuelve kind ("monster"/"key"/"code"), etiqueta, o nil.
local function classify(inst)
	if typeof(inst) ~= "Instance" then return nil end
	if not inst:IsA("Model") and not inst:IsA("Tool") and not inst:IsA("BasePart") then
		return nil
	end
	if isUnderPlayer(inst) then return nil end
	-- Las partes sueltas dentro de un modelo ya se evalian por el modelo
	if inst:IsA("BasePart") and inst.Parent and (inst.Parent:IsA("Model") or inst.Parent:IsA("Tool")) then
		return nil
	end

	local name = lowerName(inst)

	-- Monstruo: por nombre
	if (inst:IsA("Model") or inst:IsA("BasePart")) and matchesAny(name, MONSTER_NAMES) then
		return "monster", "MONSTER"
	end
	-- Monstruo: humanoide dentro de carpeta sospechosa
	if inst:IsA("Model") and not isPlayerCharacter(inst) and hasHumanoid(inst) and hasMonsterFolderAncestor(inst) then
		return "monster", "MONSTER"
	end
	-- Monstruo: escaneo total de NPCs (opcional)
	if State.npcScan and inst:IsA("Model") and not isPlayerCharacter(inst) and hasHumanoid(inst) then
		return "monster", "MONSTER"
	end
	-- Llaves
	if matchesAny(name, KEY_NAMES) then
		return "key", "KEY"
	end
	-- Codigos
	for i = 1, #CODE_KINDS do
		if matchesAny(name, CODE_KINDS[i].words) then
			return "code", CODE_KINDS[i].label
		end
	end
	return nil
end

-- Resuelve que adornar: devuelve target (Model/BasePart para el Highlight)
-- y una BasePart para el billboard y medir distancia.
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

-- Lee digitos (3+) dentro del objeto: pantallas, notas, prompts, valores.
local function extractDigits(root)
	local found = nil
	local ok, descendants = pcall(function() return root:GetDescendants() end)
	if not ok or type(descendants) ~= "table" then return nil end
	for i = 1, #descendants do
		local d = descendants[i]
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local s = d.Text or ""
			local m = string.match(s, "%d%d%d+")
			if m then
				found = string.sub(m, 1, 8)
				break
			end
		elseif d:IsA("ProximityPrompt") then
			local s = tostring(d.ObjectText or "") .. " " .. tostring(d.ActionText or "")
			local m = string.match(s, "%d%d%d+")
			if m then
				found = string.sub(m, 1, 8)
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
		-- Aun sin partes (streaming): guarda pendiente, se resuelve en el loop
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
end

local function rootPosition()
	local char = LocalPlayer and LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
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

local function updateEntry(e, origin, maxDist, refreshDigits)
	local root = e.root
	if not root or not inWorkspace(root) then
		return false -- marcar para borrar
	end
	-- Resolver partes pendientes (streaming)
	if not e.target or not e.part then
		local target, part = resolveTarget(root)
		if target and part and EspFolder then
			local hl, bb, txt = makeEspObjects(target, part)
			e.target, e.part, e.hl, e.bb, e.txt = target, part, hl, bb, txt
			if e.kind == "code" then e.digits = extractDigits(root) end
		else
			return true -- sigue pendiente
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
	if e.kind == "code" and refreshDigits then
		e.digits = extractDigits(root)
	end
	local title = e.label
	if e.kind == "code" and e.digits then
		title = e.label .. " " .. e.digits
	end
	e.txt.Text = title .. "\n" .. tostring(math.floor(dist)) .. "m"
	return true
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
	btn.Size = UDim2.new(1, -16, 0, 34)
	btn.Position = UDim2.new(0, 8, 0, 44 + (order - 1) * 38)
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
	local function paint()
		btn.BackgroundColor3 = on and ROW_ON or ROW_OFF
		btn.TextColor3 = on and BLACK or TXT_ON
		state.TextColor3 = on and BLACK or TXT_DIM
		state.Text = on and "ON" or "OFF"
	end
	paint()
	btn.MouseButton1Click:Connect(function()
		on = not on
		paint()
		callback(on)
	end)
	return btn, function(v)
		on = v
		paint()
	end
end

local function buildGui()
	local parent = uiParent()
	local screen = Instance.new("ScreenGui")
	screen.Name = "MonochromeESP"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 9999
	screen.Parent = parent

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.new(0, 250, 0, 316)
	main.Position = UDim2.new(0, 24, 0.5, -158)
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

	-- Arrastre por la barra de titulo
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

	-- Filas
	makeRow(main, 1, "MONSTER ESP", State.monster, function(v)
		State.monster = v
		if v then fullScan() else clearKind("monster") end
	end)
	makeRow(main, 2, "KEY ESP", State.keys, function(v)
		State.keys = v
		if v then fullScan() else clearKind("key") end
	end)
	makeRow(main, 3, "CODE ESP", State.codes, function(v)
		State.codes = v
		if v then fullScan() else clearKind("code") end
	end)
	makeRow(main, 4, "NPC SCAN (todo humanoide)", State.npcScan, function(v)
		State.npcScan = v
		clearKind("monster")
		if State.monster then fullScan() end
	end)

	-- Distancia maxima (cicla)
	local distBtn = Instance.new("TextButton")
	distBtn.Size = UDim2.new(1, -16, 0, 34)
	distBtn.Position = UDim2.new(0, 8, 0, 44 + 4 * 38)
	distBtn.BackgroundColor3 = ROW_OFF
	distBtn.BorderSizePixel = 0
	distBtn.AutoButtonColor = false
	distBtn.Font = Enum.Font.GothamBold
	distBtn.TextSize = 13
	distBtn.TextXAlignment = Enum.TextXAlignment.Left
	distBtn.TextColor3 = TXT_ON
	distBtn.Parent = main
	local distCorner = Instance.new("UICorner")
	distCorner.CornerRadius = UDim.new(0, 6)
	distCorner.Parent = distBtn
	local function paintDist()
		distBtn.Text = "  MAX DIST: " .. DIST_LABELS[State.distStep]
	end
	paintDist()
	distBtn.MouseButton1Click:Connect(function()
		State.distStep = State.distStep + 1
		if State.distStep > #DIST_STEPS then State.distStep = 1 end
		paintDist()
	end)

	StatusLabel = Instance.new("TextLabel")
	StatusLabel.Size = UDim2.new(1, -16, 0, 30)
	StatusLabel.Position = UDim2.new(0, 8, 1, -58)
	StatusLabel.BackgroundTransparency = 1
	StatusLabel.Font = Enum.Font.Code
	StatusLabel.TextSize = 12
	StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	StatusLabel.TextColor3 = TXT_DIM
	StatusLabel.Text = "iniciando..."
	StatusLabel.Parent = main

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -16, 0, 18)
	hint.Position = UDim2.new(0, 8, 1, -26)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Code
	hint.TextSize = 11
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = TXT_DIM
	hint.Text = "RightShift: mostrar / ocultar"
	hint.Parent = main

	return screen, main, close, onDragChanged, onDragEnded
end

-- ===================== ARRANQUE =====================

EspFolder = Instance.new("Folder")
EspFolder.Name = "MonoESP"
EspFolder.Parent = uiParent()

local DragChanged, DragEnded
Gui, _, CloseBtn, DragChanged, DragEnded = buildGui()
local MainFrame = Gui:FindFirstChild("Main")

trackConnection(UserInputService.InputChanged:Connect(DragChanged))
trackConnection(UserInputService.InputEnded:Connect(DragEnded))

CloseBtn.MouseButton1Click:Connect(function()
	if getgenv and getgenv().MonochromeESP then
		pcall(function() getgenv().MonochromeESP.Unload() end)
		getgenv().MonochromeESP = nil
	end
end)

trackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.RightShift and MainFrame then
		MainFrame.Visible = not MainFrame.Visible
	end
end))

trackConnection(workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") or inst:IsA("Tool") then
		pcall(addEntry, inst)
	elseif inst:IsA("BasePart") and inst.Parent and not (inst.Parent:IsA("Model") or inst.Parent:IsA("Tool")) then
		pcall(addEntry, inst)
	end
end))

trackConnection(workspace.DescendantRemoving:Connect(function(inst)
	if Tracked[inst] then
		removeEntry(inst)
	end
end))

fullScan()

local accDist, accCode = 0, 0
trackConnection(RunService.Heartbeat:Connect(function(dt)
	if not State.running then return end
	accDist = accDist + dt
	accCode = accCode + dt
	local doDist = accDist >= 0.3
	local doCode = accCode >= 1.5
	if not doDist and not doCode then return end
	if doDist then accDist = 0 end
	if doCode then accCode = 0 end
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
		local m, k, c = countTargets()
		local placeNote = ""
		if game.PlaceId ~= TARGET_PLACE then
			placeNote = " (fuera de MONOCHROME)"
		end
		StatusLabel.Text = "monster:" .. m .. "  key:" .. k .. "  code:" .. c .. placeNote
	end
end))

local Api = {}
function Api.Unload()
	State.running = false
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
