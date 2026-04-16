--[[
	NodeGenerator Plugin - Interfaz gráfica para generar nodos de navegación

	Instalación:
	1. Ejecutar: rojo build plugin.project.json -o NodeGeneratorPlugin.rbxm
	2. Copiar NodeGeneratorPlugin.rbxm a la carpeta de plugins de Roblox:
	   - Windows: %LOCALAPPDATA%\Roblox\Plugins
	   - Mac: ~/Documents/Roblox/Plugins
	3. Reiniciar Studio
]]

local CollectionService = game:GetService("CollectionService")

local ZONES_FOLDER_NAME = "NodeZones"
local NODES_FOLDER_NAME = "NavigationNodes"
local DEFAULT_SPACING = 2

-- Configuración de conexiones
local MAX_CONNECTION_DISTANCE = 20
local MAX_CONNECTIONS_PER_NODE = 8

-- Color para nodos caminables
local WALKABLE_COLOR = Color3.fromRGB(0, 255, 0)

-- Color para nodos NO caminables (rojo semi-transparente)
local NON_WALKABLE_COLOR = Color3.fromRGB(255, 50, 50)
local NON_WALKABLE_TRANSPARENCY = 0.7

-- ============================================================================
-- LÓGICA DE GENERACIÓN (copiada de NodeGenerator)
-- ============================================================================

-- Crea o reutiliza una carpeta Floor_X_ZoneName por zona
local function getOrCreateZoneFolder(nodesRoot, floor, zoneName)
	local folderName = "Floor_" .. floor .. "_" .. zoneName
	local existing = nodesRoot:FindFirstChild(folderName)
	if existing then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = nodesRoot
	return folder
end

local NODE_SIZE = 1 -- Tamaño del nodo (cubo 1x1x1)
local NODE_HALF = NODE_SIZE / 2

-- Configuración de navegación
-- AGENT_RADIUS: Radio de seguridad alrededor de obstáculos. El plugin hace raycasts
-- en múltiples direcciones para verificar que no hay obstáculos dentro de este radio.
-- Valor típico para humanoides de Roblox: 1.5-2.0 studs (ancho ~2 studs, radio ~1)
local DEFAULT_AGENT_RADIUS = 1.5

-- Direcciones para raycasts (8 direcciones cardinales en el plano XZ)
local RAYCAST_DIRECTIONS = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
	Vector3.new(1, 0, 1).Unit,
	Vector3.new(1, 0, -1).Unit,
	Vector3.new(-1, 0, 1).Unit,
	Vector3.new(-1, 0, -1).Unit,
}

local function isPositionWalkable(position, ignoreList, agentRadius)
	local searchRadius = math.max(agentRadius, 0.5)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignoreList or {}

	-- Paso 1: Buscar partes colisionables cercanas y verificar distancia
	local partsInRadius = workspace:GetPartBoundsInRadius(position, searchRadius + 2, overlapParams)

	for _, part in ipairs(partsInRadius) do
		if part.CanCollide then
			local relativePos = part.CFrame:PointToObjectSpace(position)
			local halfSize = part.Size / 2

			-- Verificar si estamos DENTRO de la parte
			if math.abs(relativePos.X) < halfSize.X and
			   math.abs(relativePos.Y) < halfSize.Y and
			   math.abs(relativePos.Z) < halfSize.Z then
				return false -- Nodo dentro de geometría sólida
			end

			-- Verificar si estamos demasiado CERCA de la parte (dentro del agentRadius)
			-- Solo para partes que son obstáculos LATERALES (paredes, columnas), no suelo
			local partMaxY = part.Position.Y + halfSize.Y

			-- Ignorar partes que están completamente debajo del nodo (suelo)
			-- El nodo está "encima" si su base (nodeY - 0.5) está por encima del tope de la parte
			local nodeBaseY = position.Y - NODE_HALF
			local isAbovePart = nodeBaseY >= partMaxY - 0.1

			-- Solo verificar distancia lateral si el nodo NO está encima de la parte
			if not isAbovePart then
				-- Calcular distancia al borde más cercano en el plano XZ
				local distX = math.max(0, math.abs(relativePos.X) - halfSize.X)
				local distZ = math.max(0, math.abs(relativePos.Z) - halfSize.Z)
				local distToBorder = math.sqrt(distX * distX + distZ * distZ)

				if distToBorder < agentRadius then
					return false -- Nodo demasiado cerca del borde de la parte
				end
			end
		end
	end

	-- Paso 2: Raycasts adicionales para formas complejas (cilindros, wedges, etc.)
	if agentRadius > 0 then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = ignoreList or {}

		for _, direction in ipairs(RAYCAST_DIRECTIONS) do
			local result = workspace:Raycast(position, direction * agentRadius, rayParams)
			if result then
				return false -- Hay un obstáculo dentro del radio de seguridad
			end
		end
	end

	return true
end

local function calculateGridParams(usableSize, desiredSpacing)
	if usableSize <= 0 then
		return 1, 0
	end

	local numNodes = math.max(1, math.round(usableSize / desiredSpacing) + 1)
	local actualSpacing = 0
	if numNodes > 1 then
		actualSpacing = usableSize / (numNodes - 1)
	end

	return numNodes, actualSpacing
end

-- nodeCountByFloor: tabla { [floor] = count } para mantener índices únicos por piso entre zonas
local function generateNodesInZone(zonePart, globalSpacing, nodesRoot, zonesFolder, agentRadius, nodeCountByFloor)
	local pos = zonePart.Position
	local size = zonePart.Size

	-- Usar el área completa de la zona (sin padding en bordes)
	-- Las partes de límite del nivel serán detectadas por los raycasts de agentRadius
	local usableSizeX = size.X
	local usableSizeZ = size.Z

	-- Posición inicial desde el borde de la zona
	local minX = pos.X - size.X / 2
	local minZ = pos.Z - size.Z / 2
	-- La base del nodo se alinea con la parte superior de la zona
	local baseY = pos.Y + size.Y / 2 + NODE_HALF

	local floor = zonePart:GetAttribute("floor") or 0
	local spacing = zonePart:GetAttribute("spacing") or globalSpacing

	local numNodesX, spacingX = calculateGridParams(usableSizeX, spacing)
	local numNodesZ, spacingZ = calculateGridParams(usableSizeZ, spacing)

	-- Cada zona obtiene su propia subcarpeta Floor_X_ZoneName
	local zoneFolder = getOrCreateZoneFolder(nodesRoot, floor, zonePart.Name)
	-- startIndex global por piso garantiza nombres únicos entre zonas del mismo piso
	local startIndex = nodeCountByFloor[floor] or 0

	-- Lista de elementos a ignorar en el chequeo de colisión
	local ignoreList = {nodesRoot, zonesFolder}

	-- Filtramos todas las instancias de puerta para hacer caminable la zona en la que esta aparece.
	for _, door in ipairs(CollectionService:GetTagged("Door")) do
		table.insert(ignoreList, door)
	end

	-- Filtramos todas las instancias de NPC para hacer caminable la zona en la que este aparece.
	for _, npc in ipairs(CollectionService:GetTagged("NPC")) do
		table.insert(ignoreList, npc)
	end

	local walkableCount = 0
	local nonWalkableCount = 0
	local totalNodes = 0

	for ix = 0, numNodesX - 1 do
		for iz = 0, numNodesZ - 1 do
			local x = minX + ix * spacingX
			local z = minZ + iz * spacingZ
			local nodePosition = Vector3.new(x, baseY, z)

			totalNodes = totalNodes + 1

			-- Crear el nodo siempre
			local node = Instance.new("Part")
			node.Name = "Node_" .. floor .. "_" .. (startIndex + totalNodes)
			node.Size = Vector3.new(1, 1, 1)
			node.Position = nodePosition
			node.Anchored = true
			node.CanCollide = false
			node.CanQuery = false
			node:SetAttribute("floor", floor)
			node.Material = Enum.Material.SmoothPlastic

			-- Verificar si es caminable y aplicar aspecto visual correspondiente
			local isWalkable = isPositionWalkable(nodePosition, ignoreList, agentRadius)
			node:SetAttribute("walkable", isWalkable)

			if isWalkable then
				node.Color = WALKABLE_COLOR
				node.Transparency = 0.85
				walkableCount = walkableCount + 1
			else
				node.Color = NON_WALKABLE_COLOR
				node.Transparency = NON_WALKABLE_TRANSPARENCY
				nonWalkableCount = nonWalkableCount + 1
			end

			node.Parent = zoneFolder
		end
	end

	-- Actualizar contador global del piso para que la siguiente zona use índices únicos
	nodeCountByFloor[floor] = startIndex + totalNodes

	return walkableCount, nonWalkableCount, numNodesX, numNodesZ
end

local function clearNodes()
	local existing = workspace:FindFirstChild(NODES_FOLDER_NAME)
	if existing then
		existing:Destroy()
		return true
	end
	return false
end

-- ============================================================================
-- LÓGICA DE CONEXIONES
-- ============================================================================

local function canConnect(fromPos, toPos, nodesRoot)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	-- Ignorar DoorParts para que las conexiones atraviesen puertas
	local doorsFolder = workspace:FindFirstChild("Doors")
	local filterList = {nodesRoot}
	if doorsFolder then
		table.insert(filterList, doorsFolder)
	end
	rayParams.FilterDescendantsInstances = filterList

	local direction = toPos - fromPos
	local result = workspace:Raycast(fromPos, direction, rayParams)

	if not result then
		return true
	end

	local hitDistance = (result.Position - fromPos).Magnitude
	local targetDistance = direction.Magnitude

	return hitDistance >= targetDistance * 0.95
end

local function autoConnectNodes(nodesRoot)
	local connectionCount = 0

	-- Recolectar solo nodos CAMINABLES agrupados por piso
	local nodesByFloor = {}
	for _, floorFolder in ipairs(nodesRoot:GetChildren()) do
		if floorFolder:IsA("Folder") then
			local floorNumber = tonumber(string.match(floorFolder.Name, "Floor_(%-?%d+)"))
			if floorNumber then
				-- Usar "or {}" para acumular nodos de múltiples zonas del mismo piso
				nodesByFloor[floorNumber] = nodesByFloor[floorNumber] or {}
				for _, node in ipairs(floorFolder:GetChildren()) do
					-- Solo incluir nodos marcados como caminables
					if node:IsA("BasePart") and node:GetAttribute("walkable") == true then
						table.insert(nodesByFloor[floorNumber], node)
					end
				end
			end
		end
	end

	-- Conectar nodos dentro del mismo piso
	for _, nodesInFloor in pairs(nodesByFloor) do
		for _, fromNode in ipairs(nodesInFloor) do
			local candidates = {}

			for _, toNode in ipairs(nodesInFloor) do
				if fromNode ~= toNode then
					local distance = (fromNode.Position - toNode.Position).Magnitude

					if distance <= MAX_CONNECTION_DISTANCE then
						if canConnect(fromNode.Position, toNode.Position, nodesRoot) then
							table.insert(candidates, {node = toNode, distance = distance})
						end
					end
				end
			end

			-- Ordenar por distancia y tomar los más cercanos
			table.sort(candidates, function(a, b)
				return a.distance < b.distance
			end)

			-- Guardar conexiones como atributo (lista de nombres separados por coma)
			local connections = {}
			for i, candidate in ipairs(candidates) do
				if i > MAX_CONNECTIONS_PER_NODE then break end
				table.insert(connections, candidate.node.Name)
				connectionCount = connectionCount + 1
			end

			if #connections > 0 then
				fromNode:SetAttribute("connections", table.concat(connections, ","))
			end
		end
	end

	return connectionCount
end

local function generateNodes(spacing, agentRadius)
	agentRadius = agentRadius or DEFAULT_AGENT_RADIUS

	local zonesFolder = workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if not zonesFolder then
		return nil, "No se encontró carpeta '" .. ZONES_FOLDER_NAME .. "'"
	end

	local zones = {}
	for _, child in ipairs(zonesFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(zones, child)
		end
	end

	if #zones == 0 then
		return nil, "No hay Parts en " .. ZONES_FOLDER_NAME
	end

	-- Validar que todas las zonas tienen el atributo 'floor' definido
	local missingFloor = {}
	for _, zone in ipairs(zones) do
		if zone:GetAttribute("floor") == nil then
			table.insert(missingFloor, zone.Name)
		end
	end
	if #missingFloor > 0 then
		warn("[NodeGenerator] Zonas sin atributo 'floor' (usarán 0): " .. table.concat(missingFloor, ", "))
	end

	clearNodes()

	local nodesRoot = Instance.new("Folder")
	nodesRoot.Name = NODES_FOLDER_NAME
	nodesRoot.Parent = workspace

	local totalWalkable = 0
	local totalNonWalkable = 0
	local zoneResults = {}
	-- Contador global de nodos por piso — garantiza nombres únicos entre zonas del mismo piso
	local nodeCountByFloor = {}

	for _, zonePart in ipairs(zones) do
		local walkable, nonWalkable, nx, nz = generateNodesInZone(zonePart, spacing, nodesRoot, zonesFolder, agentRadius, nodeCountByFloor)
		totalWalkable = totalWalkable + walkable
		totalNonWalkable = totalNonWalkable + nonWalkable
		table.insert(zoneResults, {
			name = zonePart.Name,
			walkable = walkable,
			nonWalkable = nonWalkable,
			grid = nx .. "x" .. nz
		})
	end

	-- Auto-conectar solo nodos caminables
	local totalConnections = autoConnectNodes(nodesRoot)

	return {
		totalWalkable = totalWalkable,
		totalNonWalkable = totalNonWalkable,
		totalNodes = totalWalkable + totalNonWalkable,
		totalConnections = totalConnections,
		zonesCount = #zones,
		zones = zoneResults,
		missingFloor = missingFloor,
	}
end

-- ============================================================================
-- INTERFAZ DEL PLUGIN
-- ============================================================================

local toolbar = plugin:CreateToolbar("Node Generator")
local button = toolbar:CreateButton(
	"Node Generator",
	"Generar nodos de navegación",
	"rbxassetid://6031251882" -- Icono de grid
)

-- Crear ventana del plugin
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, -- inicialmente cerrado
	false,
	300, -- ancho
	260, -- alto
	250, -- ancho mínimo
	240  -- alto mínimo
)

local widget = plugin:CreateDockWidgetPluginGui("NodeGeneratorWidget", widgetInfo)
widget.Title = "Node Generator"

-- UI
local frame = Instance.new("Frame")
frame.Size = UDim2.new(1, 0, 1, 0)
frame.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
frame.BorderSizePixel = 0
frame.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = frame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = frame

-- Título
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 20)
title.BackgroundTransparency = 1
title.Text = "Generador de Nodos"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.LayoutOrder = 1
title.Parent = frame

-- Spacing input container
local spacingContainer = Instance.new("Frame")
spacingContainer.Size = UDim2.new(1, 0, 0, 28)
spacingContainer.BackgroundTransparency = 1
spacingContainer.LayoutOrder = 2
spacingContainer.Parent = frame

local spacingLabel = Instance.new("TextLabel")
spacingLabel.Size = UDim2.new(0.5, 0, 1, 0)
spacingLabel.BackgroundTransparency = 1
spacingLabel.Text = "Spacing (studs):"
spacingLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
spacingLabel.TextSize = 14
spacingLabel.Font = Enum.Font.Gotham
spacingLabel.TextXAlignment = Enum.TextXAlignment.Left
spacingLabel.Parent = spacingContainer

local spacingInput = Instance.new("TextBox")
spacingInput.Size = UDim2.new(0.5, -5, 1, 0)
spacingInput.Position = UDim2.new(0.5, 5, 0, 0)
spacingInput.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
spacingInput.BorderSizePixel = 0
spacingInput.Text = tostring(DEFAULT_SPACING)
spacingInput.TextColor3 = Color3.fromRGB(255, 255, 255)
spacingInput.TextSize = 14
spacingInput.Font = Enum.Font.GothamMedium
spacingInput.Parent = spacingContainer

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 4)
inputCorner.Parent = spacingInput

-- Agent Radius input container
local radiusContainer = Instance.new("Frame")
radiusContainer.Size = UDim2.new(1, 0, 0, 28)
radiusContainer.BackgroundTransparency = 1
radiusContainer.LayoutOrder = 3
radiusContainer.Parent = frame

local radiusLabel = Instance.new("TextLabel")
radiusLabel.Size = UDim2.new(0.5, 0, 1, 0)
radiusLabel.BackgroundTransparency = 1
radiusLabel.Text = "Agent Radius:"
radiusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
radiusLabel.TextSize = 14
radiusLabel.Font = Enum.Font.Gotham
radiusLabel.TextXAlignment = Enum.TextXAlignment.Left
radiusLabel.Parent = radiusContainer

local radiusInput = Instance.new("TextBox")
radiusInput.Size = UDim2.new(0.5, -5, 1, 0)
radiusInput.Position = UDim2.new(0.5, 5, 0, 0)
radiusInput.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
radiusInput.BorderSizePixel = 0
radiusInput.Text = tostring(DEFAULT_AGENT_RADIUS)
radiusInput.TextColor3 = Color3.fromRGB(255, 255, 255)
radiusInput.TextSize = 14
radiusInput.Font = Enum.Font.GothamMedium
radiusInput.Parent = radiusContainer

local radiusCorner = Instance.new("UICorner")
radiusCorner.CornerRadius = UDim.new(0, 4)
radiusCorner.Parent = radiusInput

-- Botones container
local buttonsContainer = Instance.new("Frame")
buttonsContainer.Size = UDim2.new(1, 0, 0, 32)
buttonsContainer.BackgroundTransparency = 1
buttonsContainer.LayoutOrder = 4
buttonsContainer.Parent = frame

local generateBtn = Instance.new("TextButton")
generateBtn.Size = UDim2.new(0.48, 0, 1, 0)
generateBtn.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
generateBtn.BorderSizePixel = 0
generateBtn.Text = "Generate"
generateBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
generateBtn.TextSize = 14
generateBtn.Font = Enum.Font.GothamBold
generateBtn.Parent = buttonsContainer

local generateCorner = Instance.new("UICorner")
generateCorner.CornerRadius = UDim.new(0, 4)
generateCorner.Parent = generateBtn

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0.48, 0, 1, 0)
clearBtn.Position = UDim2.new(0.52, 0, 0, 0)
clearBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
clearBtn.BorderSizePixel = 0
clearBtn.Text = "Clear"
clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
clearBtn.TextSize = 14
clearBtn.Font = Enum.Font.GothamBold
clearBtn.Parent = buttonsContainer

local clearCorner = Instance.new("UICorner")
clearCorner.CornerRadius = UDim.new(0, 4)
clearCorner.Parent = clearBtn

-- Status label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 40)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Listo"
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextWrapped = true
statusLabel.LayoutOrder = 5
statusLabel.Parent = frame

-- ============================================================================
-- EDITOR MODE - Visualización de Conexiones con Beams
-- ============================================================================

local EditorMode = {
	active = false,
	beamsFolder = nil,
}

-- Busca un nodo por nombre en NavigationNodes
local function findNodeByName(nodeName)
	local navNodes = workspace:FindFirstChild(NODES_FOLDER_NAME)
	if not navNodes then return nil end

	local function searchInFolder(folder)
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") and child.Name == nodeName then
				return child
			elseif child:IsA("Folder") then
				local found = searchInFolder(child)
				if found then return found end
			end
		end
		return nil
	end

	return searchInFolder(navNodes)
end

function EditorMode:Enable()
	if self.active then return end

	local navNodes = workspace:FindFirstChild(NODES_FOLDER_NAME)
	if not navNodes then
		statusLabel.Text = "No hay NavigationNodes"
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		return
	end

	self.active = true

	-- Crear folder para los Beams dentro de NavigationNodes
	self.beamsFolder = Instance.new("Folder")
	self.beamsFolder.Name = "_ConnectionBeams"
	self.beamsFolder.Parent = navNodes

	local beamCount = 0

	-- Recorrer todos los nodos y crear Beams para sus conexiones
	local function processFolder(folder)
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") and child:GetAttribute("walkable") == true then
				local connectionsStr = child:GetAttribute("connections")
				if connectionsStr and connectionsStr ~= "" then
					for _, targetName in ipairs(string.split(connectionsStr, ",")) do
						local targetNode = findNodeByName(targetName)
						if targetNode then
							-- Crear Attachments
							local att0 = Instance.new("Attachment")
							att0.Name = "BeamConn_" .. targetName
							att0.Parent = child

							local att1 = Instance.new("Attachment")
							att1.Name = "BeamConn_" .. child.Name
							att1.Parent = targetNode

							-- Crear Beam
							local beam = Instance.new("Beam")
							beam.Attachment0 = att0
							beam.Attachment1 = att1
							beam.Width0 = 0.15
							beam.Width1 = 0.15
							beam.FaceCamera = true
							beam.Color = ColorSequence.new(Color3.fromRGB(100, 200, 255))
							beam.Transparency = NumberSequence.new(0.3)
							beam.Parent = self.beamsFolder

							beamCount = beamCount + 1
						end
					end
				end
			elseif child:IsA("Folder") then
				processFolder(child)
			end
		end
	end

	processFolder(navNodes)

	statusLabel.Text = string.format("Editor Mode: %d conexiones visibles", beamCount)
	statusLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
end

function EditorMode:Disable()
	if not self.active then return end

	self.active = false

	-- Eliminar Beams y Attachments
	if self.beamsFolder and self.beamsFolder.Parent then
		self.beamsFolder:Destroy()
	end
	self.beamsFolder = nil

	-- Limpiar Attachments de los nodos
	local navNodes = workspace:FindFirstChild(NODES_FOLDER_NAME)
	if navNodes then
		local function cleanAttachments(folder)
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("BasePart") then
					for _, att in ipairs(child:GetChildren()) do
						if att:IsA("Attachment") and string.match(att.Name, "^BeamConn_") then
							att:Destroy()
						end
					end
				elseif child:IsA("Folder") then
					cleanAttachments(child)
				end
			end
		end
		cleanAttachments(navNodes)
	end

	statusLabel.Text = "Editor Mode desactivado"
	statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
end

-- ============================================================================
-- EVENTOS
-- ============================================================================

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

generateBtn.MouseButton1Click:Connect(function()
	local spacing = tonumber(spacingInput.Text) or DEFAULT_SPACING
	local agentRadius = tonumber(radiusInput.Text) or DEFAULT_AGENT_RADIUS

	statusLabel.Text = "Generando..."
	statusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)

	task.wait() -- Para que se actualice la UI

	local result, err = generateNodes(spacing, agentRadius)

	if result then
		local nonWalkableText = ""
		if result.totalNonWalkable > 0 then
			nonWalkableText = string.format(" + %d no-walkable", result.totalNonWalkable)
		end
		local warningText = ""
		if #result.missingFloor > 0 then
			warningText = "\n⚠ sin 'floor': " .. table.concat(result.missingFloor, ", ")
		end
		statusLabel.Text = string.format(
			"%d walkable%s\n%d conexiones, %d zonas%s",
			result.totalWalkable,
			nonWalkableText,
			result.totalConnections,
			result.zonesCount,
			warningText
		)
		statusLabel.TextColor3 = #result.missingFloor > 0
			and Color3.fromRGB(255, 200, 100)  -- Amarillo si hay warnings
			or Color3.fromRGB(100, 255, 100)   -- Verde si todo OK
	else
		statusLabel.Text = "Error: " .. (err or "desconocido")
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	end
end)

clearBtn.MouseButton1Click:Connect(function()
	-- Resetear estado de Editor Mode si estaba activo
	-- (Los Beams se auto-destruyen al eliminar NavigationNodes)
	if EditorMode.active then
		EditorMode.active = false
		EditorMode.beamsFolder = nil
	end

	if clearNodes() then
		statusLabel.Text = "Nodos eliminados"
		statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	else
		statusLabel.Text = "No había nodos"
		statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	end
end)

-- Validar inputs numéricos
spacingInput.FocusLost:Connect(function()
	local num = tonumber(spacingInput.Text)
	if not num or num <= 0 then
		spacingInput.Text = tostring(DEFAULT_SPACING)
	else
		spacingInput.Text = tostring(math.max(0.5, math.min(50, num)))
	end
end)

radiusInput.FocusLost:Connect(function()
	local num = tonumber(radiusInput.Text)
	if not num or num < 0 then
		radiusInput.Text = tostring(DEFAULT_AGENT_RADIUS)
	else
		-- Rango válido: 0 (sin padding) a 5 studs
		radiusInput.Text = tostring(math.max(0, math.min(5, num)))
	end
end)

-- Botón para toggle Editor Mode (UI)
local editorBtn = Instance.new("TextButton")
editorBtn.Size = UDim2.new(1, 0, 0, 32)
editorBtn.BackgroundColor3 = Color3.fromRGB(100, 150, 200)
editorBtn.BorderSizePixel = 0
editorBtn.Text = "Toggle Connection View"
editorBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
editorBtn.TextSize = 14
editorBtn.Font = Enum.Font.GothamMedium
editorBtn.LayoutOrder = 6
editorBtn.Parent = frame

local editorCorner = Instance.new("UICorner")
editorCorner.CornerRadius = UDim.new(0, 4)
editorCorner.Parent = editorBtn

editorBtn.MouseButton1Click:Connect(function()
	if EditorMode.active then
		EditorMode:Disable()
	else
		EditorMode:Enable()
	end
end)
