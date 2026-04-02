--[[
	DoorService - Gestión centralizada de puertas

	- Inicializa todas las puertas taggeadas como "Door" via CollectionService
	- Maneja interacción de jugadores (ProximityPrompt)
	- Expone API para que NPCs interactúen con puertas
	- Notifica cambios de geometría via GeometryVersion

	Estructura esperada del Model:
	▼ Door_Name (Model, Tag: "Door")
	  ● DoorPart          -- Part física que rota al abrir
	  ● SmashPart         -- Pared contra la que se empuja al personaje (portazo)
	  ● ProximityPrompt   -- Hijo de DoorPart, para interacción del jugador

	Atributos del Model:
	  isOpen (bool)        -- Estado inicial (default: false)
	  openAngle (number)   -- Grados de rotación (default: 90)
	  openTime (number)    -- Duración de animación en segundos (default: 0.8)
	  hingeSide (string)   -- Lado de la bisagra: "left" o "right" (default: "left")
	  autoClose (bool)     -- Si se cierra sola (default: false)
	  autoCloseDelay (number) -- Segundos antes de auto-cerrar (default: 3)
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Players = game:GetService("Players")

local GeometryVersion = require(script.Parent.GeometryVersion)
local DebugConfig = require(script.Parent.Parent.Config.DebugConfig)

local DoorService = {}

-- Registro de puertas: { [doorModel] = doorData }
local doors = {}

-- Referencia al Registry y config (se asignan en Init)
local registry = nil
local stunDuration = 3

-- ==============================================================================
-- HELPERS
-- ==============================================================================

-- Calcula el CFrame de la puerta para un ángulo dado, rotando sobre la bisagra
local function calculateDoorCFrame(closedCFrame, hingeOffset, angle)
	local hingePivot = closedCFrame * hingeOffset
	return hingePivot * CFrame.Angles(0, math.rad(angle), 0) * hingeOffset:Inverse()
end

-- ==============================================================================
-- DEBUG VISUAL
-- ==============================================================================

local SWEEP_ACTIVE_COLOR = Color3.fromRGB(255, 40, 40)
local SWEEP_ACTIVE_TRANSPARENCY = 0.5

local function createSweepDebug(data)
	if not DebugConfig.visuals or not DebugConfig.visuals.showDoorSweep then return end

	local debugFolder = workspace:FindFirstChild("_DoorDebug")
	if not debugFolder then
		debugFolder = Instance.new("Folder")
		debugFolder.Name = "_DoorDebug"
		debugFolder.Parent = workspace
	end

	local hingePos = (data.closedCFrame * data.hingeOffset).Position
	local hingeY = hingePos.Y
	local radius = data.doorPart.Size.X
	local height = data.doorPart.Size.Y
	local segments = 12
	local sweepAngle = math.rad(data.openAngle)

	-- Dirección base: del hinge hacia el borde libre de la puerta cerrada
	local freeEdgeLocal = CFrame.new(-data.hingeOffset.Position.X, 0, 0)
	local freeEdgeWorld = (data.closedCFrame * freeEdgeLocal).Position
	local baseDir = (freeEdgeWorld - hingePos) * Vector3.new(1, 0, 1)
	baseDir = baseDir.Unit

	-- Crear triángulos de relleno por cada lado, completamente transparentes
	data.sweepDebugParts = {[1] = {}, [-1] = {}}

	for _, sign in ipairs({1, -1}) do
		local parts = data.sweepDebugParts[sign]

		for i = 1, segments do
			local angle0 = sign * (sweepAngle * (i - 1) / segments)
			local angle1 = sign * (sweepAngle * i / segments)

			local dir0 = Vector3.new(
				baseDir.X * math.cos(angle0) - baseDir.Z * math.sin(angle0),
				0,
				baseDir.X * math.sin(angle0) + baseDir.Z * math.cos(angle0)
			)
			local dir1 = Vector3.new(
				baseDir.X * math.cos(angle1) - baseDir.Z * math.sin(angle1),
				0,
				baseDir.X * math.sin(angle1) + baseDir.Z * math.cos(angle1)
			)

			local p0 = hingePos
			local p1 = hingePos + dir0 * radius
			local p2 = hingePos + dir1 * radius

			-- Aproximar el triángulo con un Part orientado desde el hinge
			-- Usar un Part plano que cubra el sector
			local mid = (p0 + p1 + p2) / 3
			local forward = ((p1 + p2) / 2 - p0)
			local len = forward.Magnitude
			forward = forward.Unit
			local width = (p2 - p1).Magnitude

			local sector = Instance.new("Part")
			sector.Size = Vector3.new(width, height, len)
			sector.Color = SWEEP_ACTIVE_COLOR
			sector.Material = Enum.Material.ForceField
			sector.Transparency = 1
			sector.Anchored = true
			sector.CanCollide = false
			sector.CanTouch = false
			sector.CanQuery = false
			sector.CastShadow = false
			sector.CFrame = CFrame.lookAt(
				Vector3.new(mid.X, hingeY, mid.Z),
				Vector3.new(mid.X + forward.X, hingeY, mid.Z + forward.Z)
			)
			sector.Parent = debugFolder
			table.insert(parts, sector)
		end
	end
end

local function setSweepDebugActive(data, sign, active)
	if not data.sweepDebugParts then return end
	local parts = data.sweepDebugParts[sign]
	if not parts then return end
	local transparency = active and SWEEP_ACTIVE_TRANSPARENCY or 1
	for _, part in ipairs(parts) do
		part.Transparency = transparency
	end
end

-- ==============================================================================
-- INICIALIZACIÓN
-- ==============================================================================

function DoorService.Init()
	local Registry = require(script.Parent.Parent.NPCAISystem.Registry)
	registry = Registry.GetInstance()

	local NPCBaseConfig = require(script.Parent.Parent.Config.NPCBaseConfig)
	stunDuration = NPCBaseConfig.stunDuration or 3

	local taggedDoors = CollectionService:GetTagged("Door")

	for _, doorModel in ipairs(taggedDoors) do
		DoorService._RegisterDoor(doorModel)
	end

	-- Escuchar puertas añadidas/removidas dinámicamente
	CollectionService:GetInstanceAddedSignal("Door"):Connect(function(doorModel)
		DoorService._RegisterDoor(doorModel)
	end)

	CollectionService:GetInstanceRemovedSignal("Door"):Connect(function(doorModel)
		doors[doorModel] = nil
	end)

	print("DoorService: " .. #taggedDoors .. " puertas registradas")
end

function DoorService._RegisterDoor(doorModel)
	if not doorModel:IsA("Model") then
		warn("DoorService: " .. doorModel.Name .. " no es un Model")
		return
	end

	local doorPart = doorModel:FindFirstChild("DoorPart")
	if not doorPart then
		warn("DoorService: " .. doorModel.Name .. " no tiene DoorPart")
		return
	end

	local smashPart = doorModel:FindFirstChild("SmashPart")

	-- Leer configuración desde atributos del Model
	local isOpen = doorModel:GetAttribute("isOpen") or false
	local openAngle = doorModel:GetAttribute("openAngle") or 90
	local openTime = doorModel:GetAttribute("openTime") or 0.8
	local hingeSide = doorModel:GetAttribute("hingeSide") or "left"
	local autoClose = doorModel:GetAttribute("autoClose") or false
	local autoCloseDelay = doorModel:GetAttribute("autoCloseDelay") or 3

	-- Guardar CFrame cerrado como referencia
	local closedCFrame = doorPart.CFrame

	-- Calcular offset de la bisagra (borde izquierdo o derecho del eje X)
	local halfX = doorPart.Size.X / 2
	local hingeX = hingeSide == "right" and halfX or -halfX
	local hingeOffset = CFrame.new(hingeX, 0, 0)

	-- NumberValue para animar el ángulo con TweenService (permite arco real)
	local angleValue = Instance.new("NumberValue")
	angleValue.Name = "_DoorAngle"
	angleValue.Value = isOpen and openAngle or 0
	angleValue.Parent = doorModel

	local doorData = {
		model = doorModel,
		doorPart = doorPart,
		isOpen = isOpen,
		isAnimating = false,
		openAngle = openAngle,
		openTime = openTime,
		autoClose = autoClose,
		autoCloseDelay = autoCloseDelay,
		closedCFrame = closedCFrame,
		hingeOffset = hingeOffset,
		angleValue = angleValue,
		smashPart = smashPart,
		connection = nil,  -- RenderStepped/Heartbeat connection
	}

	doors[doorModel] = doorData

	-- Configurar ProximityPrompt (crear si no existe)
	local prompt = doorPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "Door"
		prompt.MaxActivationDistance = 6
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = doorPart
	end
	prompt.ActionText = isOpen and "Close" or "Open"
	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local openerPos = rootPart and rootPart.Position or nil
		DoorService.Toggle(doorModel, openerPos, character)
	end)

	-- Si empieza abierta, aplicar CFrame
	if isOpen then
		doorPart.CFrame = calculateDoorCFrame(closedCFrame, hingeOffset, openAngle)
		doorPart.CanCollide = false
	end

	createSweepDebug(doorData)
end

-- ==============================================================================
-- DETECCIÓN DE PORTAZO
-- ==============================================================================

-- Desplaza al personaje lateralmente (eje RightVector de la puerta) hasta la SmashPart.
-- Solo se mueve en el eje perpendicular a la cara de la puerta, nunca adelante/atrás.
local function applySmashKnockback(rootPart, smashPart, doorClosedCFrame)
	local rightAxis = (doorClosedCFrame.RightVector * Vector3.new(1, 0, 1)).Unit

	-- Proyectar SmashPart y personaje sobre el eje lateral de la puerta
	local smashProj = smashPart.Position:Dot(rightAxis)
	local charProj = rootPart.Position:Dot(rightAxis)
	local direction = smashProj > charProj and 1 or -1

	-- Limitar desplazamiento a la superficie de la SmashPart (no atravesar)
	local smashLocalRight = math.abs(smashPart.CFrame.RightVector:Dot(rightAxis))
	local smashLocalLook = math.abs(smashPart.CFrame.LookVector:Dot(rightAxis))
	local smashHalfLateral = (smashPart.Size.X / 2) * smashLocalRight
		+ (smashPart.Size.Z / 2) * smashLocalLook
	local characterMargin = 1.5
	local surfaceProj = smashProj - direction * (smashHalfLateral + characterMargin)

	local displacement = surfaceProj - charProj
	if math.abs(displacement) < 0.1 then return end

	local startPos = rootPart.Position
	local targetPos = startPos + rightAxis * displacement
	local distance = math.abs(displacement)
	local arcHeight = math.max(distance * 0.3, 1.5)

	-- Orientar de espaldas a la SmashPart (mirando hacia el centro del pasillo)
	local knockbackDir = (rightAxis * direction)
	local facingYaw = math.atan2(knockbackDir.X, knockbackDir.Z)

	-- Animación: arco parabólico lateral con rotación
	local duration = 0.3
	local steps = math.ceil(duration * 60)

	task.spawn(function()
		for i = 1, steps do
			if not rootPart.Parent then return end
			local t = i / steps

			-- Interpolación lateral + arco Y parabólico
			local pos = startPos:Lerp(targetPos, t)
			local arcY = arcHeight * 4 * t * (1 - t)
			pos = Vector3.new(pos.X, startPos.Y + arcY, pos.Z)

			rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, facingYaw, 0)
			task.wait()
		end

		-- Posición final exacta contra la pared
		rootPart.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, facingYaw, 0)
	end)
end

-- Comprueba si un punto XZ está dentro del cuarto de círculo activo
local function isInsideSweepArc(point, hingePos, baseDir, sweepAngle, sign, radius)
	local toPoint = (point - hingePos) * Vector3.new(1, 0, 1)
	if toPoint.Magnitude > radius then return false end
	if toPoint.Magnitude < 0.01 then return true end

	local dir = toPoint.Unit
	local dot = baseDir.X * dir.X + baseDir.Z * dir.Z
	local cross = baseDir.X * dir.Z - baseDir.Z * dir.X
	local angle = math.atan2(cross, dot) * sign
	return angle >= 0 and angle <= sweepAngle
end

local function detectAndStunCharacters(data, activeSign, openerInstance)
	local hingePos = (data.closedCFrame * data.hingeOffset).Position
	local radius = data.doorPart.Size.X
	local sweepAngle = math.rad(data.openAngle)

	local freeEdgeLocal = CFrame.new(-data.hingeOffset.Position.X, 0, 0)
	local freeEdgeWorld = (data.closedCFrame * freeEdgeLocal).Position
	local baseDir = ((freeEdgeWorld - hingePos) * Vector3.new(1, 0, 1)).Unit

	local function tryStunModel(model)
		if model == openerInstance then return end
		local rootPart = model:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		if not isInsideSweepArc(rootPart.Position, hingePos, baseDir, sweepAngle, activeSign, radius) then return end

		-- NPC: estado Stunned (PlatformStand primero, para que el tween funcione)
		if registry then
			local npcData = registry:GetNPCByInstance(model)
			if npcData and npcData.controller.isActive and npcData.controller.currentState ~= "Stunned" then
				npcData.controller:ApplyStun()
				if data.smashPart then
					applySmashKnockback(rootPart, data.smashPart, data.closedCFrame)
				end
				return
			end
		end

		-- Player: inmovilizar durante stunDuration
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local savedWalkSpeed = humanoid.WalkSpeed
			local savedJumpPower = humanoid.JumpPower
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0

			if data.smashPart then
				applySmashKnockback(rootPart, data.smashPart, data.closedCFrame)
			end

			task.delay(stunDuration, function()
				if humanoid and humanoid.Parent then
					humanoid.WalkSpeed = savedWalkSpeed
					humanoid.JumpPower = savedJumpPower
				end
			end)
		end
	end

	-- Chequear NPCs
	if registry then
		registry:ForEach(function(_id, pawn, _controller)
			tryStunModel(pawn:GetInstance())
		end)
	end

	-- Chequear Players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			tryStunModel(player.Character)
		end
	end
end

-- ==============================================================================
-- ANIMACIÓN (rotación sobre bisagra frame a frame)
-- ==============================================================================

local function animateDoor(data, targetAngle, easingDirection, onComplete)
	-- Desconectar animación anterior si existe
	if data.connection then
		data.connection:Disconnect()
		data.connection = nil
	end

	-- Tween del ángulo (NumberValue)
	local tweenInfo = TweenInfo.new(data.openTime, Enum.EasingStyle.Quad, easingDirection)
	local tween = TweenService:Create(data.angleValue, tweenInfo, {Value = targetAngle})

	-- Actualizar CFrame cada frame
	data.connection = RunService.Heartbeat:Connect(function()
		data.doorPart.CFrame = calculateDoorCFrame(
			data.closedCFrame,
			data.hingeOffset,
			data.angleValue.Value
		)
	end)

	tween:Play()

	tween.Completed:Connect(function()
		if data.connection then
			data.connection:Disconnect()
			data.connection = nil
		end
		-- Asegurar CFrame final exacto
		data.doorPart.CFrame = calculateDoorCFrame(data.closedCFrame, data.hingeOffset, targetAngle)

		if onComplete then
			onComplete()
		end
	end)
end

-- ==============================================================================
-- API PÚBLICA
-- ==============================================================================

function DoorService.Open(doorModel, openerPosition, openerInstance)
	local data = doors[doorModel]
	if not data or data.isOpen or data.isAnimating then return end

	data.isAnimating = true
	data.isOpen = true
	doorModel:SetAttribute("isOpen", true)

	-- Determinar dirección de apertura según el lado del que abre
	local angle = data.openAngle
	if openerPosition then
		local doorPos = data.closedCFrame.Position
		local doorLook = data.closedCFrame.LookVector
		local toOpener = (openerPosition - doorPos)
		local dot = doorLook:Dot(toOpener)
		if dot > 0 then
			angle = -angle
		end
	end

	-- Actualizar ProximityPrompt
	local prompt = data.doorPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = "Close"
	end

	data.doorPart.CanCollide = false

	-- Determinar qué cuarto de círculo debug corresponde a esta apertura.
	-- Comparamos la dirección del borde libre cerrado vs abierto en XZ global.
	local hingePos = (data.closedCFrame * data.hingeOffset).Position
	local freeEdgeLocal = CFrame.new(-data.hingeOffset.Position.X, 0, 0)
	local closedFreeEdge = (data.closedCFrame * freeEdgeLocal).Position
	local finalFreeEdge = (calculateDoorCFrame(data.closedCFrame, data.hingeOffset, angle) * freeEdgeLocal).Position
	local baseDir = (closedFreeEdge - hingePos) * Vector3.new(1, 0, 1)
	local finalDir = (finalFreeEdge - hingePos) * Vector3.new(1, 0, 1)
	local cross = baseDir.X * finalDir.Unit.Z - baseDir.Z * finalDir.Unit.X
	local activeSign = cross >= 0 and 1 or -1
	setSweepDebugActive(data, activeSign, true)
	detectAndStunCharacters(data, activeSign, openerInstance)

	animateDoor(data, angle, Enum.EasingDirection.Out, function()
		data.isAnimating = false
		setSweepDebugActive(data, activeSign, false)
		GeometryVersion.Increment()

		if data.autoClose then
			task.delay(data.autoCloseDelay, function()
				if data.isOpen and not data.isAnimating then
					DoorService.Close(doorModel)
				end
			end)
		end
	end)
end

function DoorService.Close(doorModel)
	local data = doors[doorModel]
	if not data or not data.isOpen or data.isAnimating then return end

	data.isAnimating = true
	data.isOpen = false
	doorModel:SetAttribute("isOpen", false)

	-- Actualizar ProximityPrompt
	local prompt = data.doorPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = "Open"
	end

	-- Restaurar colisión antes de cerrar para que bloquee
	data.doorPart.CanCollide = true

	animateDoor(data, 0, Enum.EasingDirection.In, function()
		data.isAnimating = false
		GeometryVersion.Increment()
	end)
end

function DoorService.Toggle(doorModel, openerPosition, openerInstance)
	local data = doors[doorModel]
	if not data or data.isAnimating then return end

	if data.isOpen then
		DoorService.Close(doorModel)
	else
		DoorService.Open(doorModel, openerPosition, openerInstance)
	end
end

-- ==============================================================================
-- CONSULTAS (para NPCs)
-- ==============================================================================

-- Busca si un raycast hit pertenece a una puerta registrada
function DoorService.GetDoorFromPart(part)
	if not part then return nil end

	-- Buscar el Model padre que sea una puerta registrada
	local current = part
	while current do
		if doors[current] then
			return current
		end
		current = current.Parent
	end
	return nil
end

function DoorService.IsClosed(doorModel)
	local data = doors[doorModel]
	if not data then return false end
	return not data.isOpen and not data.isAnimating
end

function DoorService.IsAnimating(doorModel)
	local data = doors[doorModel]
	if not data then return false end
	return data.isAnimating
end

function DoorService.GetOpenTime(doorModel)
	local data = doors[doorModel]
	if not data then return 0 end
	return data.openTime
end

return DoorService
