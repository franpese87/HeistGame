--[[
	DoorService - Gestión centralizada de puertas

	- Inicializa todas las puertas taggeadas como "Door" via CollectionService
	- Maneja interacción de jugadores (ProximityPrompt)
	- Expone API para que NPCs interactúen con puertas
	- Notifica cambios de geometría via GeometryVersion

	Estructura esperada del Model:
	▼ Door_Name (Model, Tag: "Door")
	  ● DoorPart          -- Part física que rota al abrir
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

local GeometryVersion = require(script.Parent.GeometryVersion)

local DoorService = {}

-- Registro de puertas: { [doorModel] = doorData }
local doors = {}

-- ==============================================================================
-- HELPERS
-- ==============================================================================

-- Calcula el CFrame de la puerta para un ángulo dado, rotando sobre la bisagra
local function calculateDoorCFrame(closedCFrame, hingeOffset, angle)
	local hingePivot = closedCFrame * hingeOffset
	return hingePivot * CFrame.Angles(0, math.rad(angle), 0) * hingeOffset:Inverse()
end

-- ==============================================================================
-- INICIALIZACIÓN
-- ==============================================================================

function DoorService.Init()
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
		connection = nil,  -- RenderStepped/Heartbeat connection
	}

	doors[doorModel] = doorData

	-- Configurar ProximityPrompt
	local prompt = doorPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = isOpen and "Close" or "Open"
		prompt.Triggered:Connect(function(player)
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local openerPos = rootPart and rootPart.Position or nil
			DoorService.Toggle(doorModel, openerPos)
		end)
	end

	-- Si empieza abierta, aplicar CFrame
	if isOpen then
		doorPart.CFrame = calculateDoorCFrame(closedCFrame, hingeOffset, openAngle)
		doorPart.CanCollide = false
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

	-- Actualizar CFrame cada frame basado en el ángulo actual
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

function DoorService.Open(doorModel, openerPosition)
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
		-- Si el que abre está en el lado positivo del LookVector, abrir en negativo (alejar)
		if dot > 0 then
			angle = -angle
		end
	end

	-- Actualizar ProximityPrompt
	local prompt = data.doorPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = "Close"
	end

	animateDoor(data, angle, Enum.EasingDirection.Out, function()
		data.isAnimating = false
		data.doorPart.CanCollide = false
		GeometryVersion.Increment()

		-- Auto-cerrar si está configurado
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

function DoorService.Toggle(doorModel, openerPosition)
	local data = doors[doorModel]
	if not data or data.isAnimating then return end

	if data.isOpen then
		DoorService.Close(doorModel)
	else
		DoorService.Open(doorModel, openerPosition)
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
