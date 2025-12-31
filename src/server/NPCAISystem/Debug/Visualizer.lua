--[[
	Visualizer - Utilidades de debug visual para el sistema de NPCs

	Proporciona:
	- Visualización de nodos de navegación
	- Visualización de celdas del spatial hash
	- Visualización de conexiones
	- Debug visual de raycasts
	- Debug de paths de NPCs
	- Debug de última posición detectada
]]

local Visualizer = {}

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- ==============================================================================
-- HELPERS INTERNOS
-- ==============================================================================

-- Limpia una carpeta de debug existente
local function ClearDebugFolder(folderName)
	local folder = workspace:FindFirstChild(folderName)
	if folder then
		folder:Destroy()
	end
end

-- Crea una carpeta de debug nueva
local function CreateDebugFolder(folderName)
	ClearDebugFolder(folderName)
	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = workspace
	return folder
end

-- Crea un BillboardGui con TextLabel
local function CreateBillboardLabel(parent, text, options)
	options = options or {}

	local billboard = Instance.new("BillboardGui")
	billboard.Size = options.size or UDim2.fromOffset(50, 20)
	billboard.StudsOffset = options.offset or Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop = options.alwaysOnTop ~= false
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = options.textColor or Color3.new(1, 1, 1)
	label.Font = options.font or Enum.Font.SourceSansBold
	label.TextStrokeTransparency = options.strokeTransparency or 0.5
	label.TextStrokeColor3 = options.strokeColor or Color3.new(0, 0, 0)
	label.Parent = billboard

	if options.textScaled then
		label.TextScaled = true
	else
		label.TextSize = options.textSize or 14
	end

	return label, billboard
end

-- ==============================================================================
-- VISUALIZACIÓN DE NODOS
-- ==============================================================================

function Visualizer.DrawNodes(graph, options)
	options = options or {}
	local color = options.nodeColor or options.color or Color3.fromRGB(0, 255, 0)
	local size = options.nodeSize or options.size or 0.5
	local transparency = options.nodeTransparency or options.transparency or 0.3
	local showLabels = options.showLabels ~= false

	local folder = CreateDebugFolder("DEBUG_Nodes")
	local count = 0

	for name, node in pairs(graph.nodes) do
		-- Crear esfera para el nodo
		local sphere = Instance.new("Part")
		sphere.Name = name
		sphere.Shape = Enum.PartType.Ball
		sphere.Size = Vector3.new(size, size, size)
		sphere.Position = node.position
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.CanQuery = false
		sphere.Color = color
		sphere.Transparency = transparency
		sphere.Material = Enum.Material.Neon
		sphere.Parent = folder

		-- Etiqueta
		if showLabels then
			local _, billboard = CreateBillboardLabel(sphere, name, {
				textScaled = true,
			})

			-- Mostrar metadata si existe
			if node.metadata and node.metadata.floor ~= 0 then
				local floorLabel = Instance.new("TextLabel")
				floorLabel.Size = UDim2.fromScale(1, 0.4)
				floorLabel.Position = UDim2.fromScale(0, 0.6)
				floorLabel.BackgroundTransparency = 1
				floorLabel.Text = "Floor " .. node.metadata.floor
				floorLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
				floorLabel.TextScaled = true
				floorLabel.Font = Enum.Font.SourceSans
				floorLabel.TextStrokeTransparency = 0.5
				floorLabel.Parent = billboard
			end
		end

		count = count + 1
	end

	return folder
end

-- ==============================================================================
-- VISUALIZACIÓN DE CELDAS (SPATIAL HASH 2D POR PISO)
-- ==============================================================================

function Visualizer.DrawCells(graph, options)
	if not graph.spatialGrids or not next(graph.spatialGrids) then
		warn("Visualizer.DrawCells: No hay spatial grids para dibujar")
		return
	end

	options = options or {}
	local transparency = options.cellTransparency or options.transparency or 0.85
	local wireframe = options.cellWireframe ~= false
	local showLabels = options.showLabels ~= false
	local cellHeight = options.cellHeight or graph.floorHeight or 10

	-- Colores por piso
	local floorColors = {
		[0] = Color3.fromRGB(100, 200, 255),  -- Azul
		[1] = Color3.fromRGB(100, 255, 100),  -- Verde
		[2] = Color3.fromRGB(255, 200, 100),  -- Naranja
		[-1] = Color3.fromRGB(200, 100, 255), -- Morado
	}
	local defaultColor = Color3.fromRGB(150, 150, 150)

	local folder = CreateDebugFolder("DEBUG_Cells")
	local count = 0

	-- Iterar por cada piso
	for floor, grid in pairs(graph.spatialGrids) do
		local floorFolder = Instance.new("Folder")
		floorFolder.Name = "Floor_" .. floor
		floorFolder.Parent = folder

		local color = floorColors[floor] or defaultColor

		-- Calcular Y base para este piso
		local floorBaseY = (graph.floorBaseY or 0) + floor * (graph.floorHeight or 10)

		for cellKey, nodes in pairs(grid) do
			-- Parsear índices de celda desde la key (ahora solo X,Z)
			local coords = string.split(cellKey, ",")
			local cellX = tonumber(coords[1])
			local cellZ = tonumber(coords[2])

			-- Calcular posición central de la celda 2D
			local centerPos = Vector3.new(
				cellX * graph.cellSizeX + graph.cellSizeX / 2,
				floorBaseY + cellHeight / 2,
				cellZ * graph.cellSizeZ + graph.cellSizeZ / 2
			)

			local cellSize = Vector3.new(graph.cellSizeX, cellHeight, graph.cellSizeZ)

			-- Crear Part para la celda
			local cellPart = Instance.new("Part")
			cellPart.Name = "Cell_F" .. floor .. "_" .. cellKey
			cellPart.Size = cellSize
			cellPart.Position = centerPos
			cellPart.Anchored = true
			cellPart.CanCollide = false
			cellPart.CanQuery = false
			cellPart.Color = color
			cellPart.Material = Enum.Material.SmoothPlastic

			if wireframe then
				cellPart.Transparency = 1
				local selectionBox = Instance.new("SelectionBox")
				selectionBox.Adornee = cellPart
				selectionBox.LineThickness = 0.05
				selectionBox.Color3 = color
				selectionBox.Transparency = 0.3
				selectionBox.Parent = cellPart
			else
				cellPart.Transparency = transparency
			end

			cellPart.Parent = floorFolder

			-- Etiqueta con información
			if showLabels then
				CreateBillboardLabel(cellPart, "F" .. floor .. " " .. cellKey .. "\n(" .. #nodes .. " nodos)", {
					size = UDim2.fromOffset(120, 50),
					offset = Vector3.new(0, cellHeight / 2 + 1, 0),
					textScaled = true,
				})
			end

			count = count + 1
		end
	end

	return folder
end

-- ==============================================================================
-- VISUALIZACIÓN DE CONEXIONES
-- ==============================================================================

function Visualizer.DrawConnections(graph, options)
	options = options or {}
	local color = options.connectionColor or options.color or Color3.fromRGB(153, 202, 255)
	local width = options.connectionWidth or options.width or 0.1

	local folder = CreateDebugFolder("DEBUG_Connections")
	local count = 0
	local drawnConnections = {}

	for name, node in pairs(graph.nodes) do
		for _, connectedName in ipairs(node.connections) do
			-- Evitar dibujar la misma conexión dos veces
			local connectionKey1 = name .. "→" .. connectedName
			local connectionKey2 = connectedName .. "→" .. name

			if not drawnConnections[connectionKey1] and not drawnConnections[connectionKey2] then
				local connectedNode = graph.nodes[connectedName]

				if connectedNode then
					-- Crear attachments en posiciones de los nodos
					local att0 = Instance.new("Attachment")
					att0.WorldPosition = node.position
					att0.Parent = folder

					local att1 = Instance.new("Attachment")
					att1.WorldPosition = connectedNode.position
					att1.Parent = folder

					-- Crear beam entre ellos
					local beam = Instance.new("Beam")
					beam.Attachment0 = att0
					beam.Attachment1 = att1
					beam.Color = ColorSequence.new(color)
					beam.Width0 = width
					beam.Width1 = width
					beam.FaceCamera = true
					beam.Parent = att0

					drawnConnections[connectionKey1] = true
					count = count + 1
				end
			end
		end
	end

	return folder
end

-- ==============================================================================
-- VISUALIZACIÓN COMPLETA
-- ==============================================================================

function Visualizer.DrawAll(graph, options)
	options = options or {}

	if options.showNodes ~= false then
		Visualizer.DrawNodes(graph, options)
	end

	if options.showCells ~= false then
		Visualizer.DrawCells(graph, options)
	end

	if options.showConnections ~= false then
		Visualizer.DrawConnections(graph, options)
	end
end

function Visualizer.ClearAll()
	local folders = { "DEBUG_Nodes", "DEBUG_Cells", "DEBUG_Connections", "NavigationDebug" }

	for _, folderName in ipairs(folders) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			folder:Destroy()
		end
	end
end

-- ==============================================================================
-- VISUALIZACIÓN DE RAYCAST (para NPCs)
-- ==============================================================================

function Visualizer.VisualizeRaycast(origin, direction, result, options)
	options = options or {}
	local duration = options.duration or 0.1
	local hitColor = options.hitColor or Color3.fromRGB(255, 0, 0)
	local missColor = options.missColor or Color3.fromRGB(0, 255, 0)
	local width = options.width or 0.1

	local endPoint = origin + direction
	if result then
		endPoint = result.Position
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(width, width, (origin - endPoint).Magnitude)
	part.CFrame = CFrame.lookAt(origin, endPoint) * CFrame.new(0, 0, -(origin - endPoint).Magnitude / 2)
	part.Color = result and hitColor or missColor
	part.Material = Enum.Material.Neon
	part.Transparency = 0.5
	part.Parent = workspace

	Debris:AddItem(part, duration)
end

-- ==============================================================================
-- DEBUG POR NPC
-- ==============================================================================

function Visualizer.EnableNPCDebug(ai, options)
	options = options or {}
	ai.debugEnabled = true
	ai.debugConfig = {
		showRaycast = options.showRaycast or false,
		raycastDuration = options.raycastDuration or 0.1,
		showPath = options.showPath or false,
		pathDuration = options.pathDuration or 3,
		pathColor = options.pathColor or Color3.fromRGB(255, 165, 0),
		showLastSeenPosition = options.showLastSeenPosition or false,
		showDebugLabels = options.showDebugLabels ~= false, -- Default true
	}
end

function Visualizer.DisableNPCDebug(ai)
	ai.debugEnabled = false
end

-- ==============================================================================
-- VISUALIZACIÓN DE PATHS DE NPCs
-- ==============================================================================

-- Cache de paths activos por NPC para fade out
local activePathFolders = {}

local function fadeOutFolder(folder, fadeDuration)
	if not folder or not folder.Parent then return end

	local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, part in ipairs(folder:GetDescendants()) do
		if part:IsA("BasePart") then
			local targetTransparency = 1
			local tween = TweenService:Create(part, tweenInfo, { Transparency = targetTransparency })
			tween:Play()
		elseif part:IsA("TextLabel") then
			local tween = TweenService:Create(part, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween:Play()
		end
	end

	-- Destruir después del fade
	Debris:AddItem(folder, fadeDuration + 0.1)
end

function Visualizer.DrawNPCPath(npcName, path, startIndex, options)
	options = options or {}
	local duration = options.duration or 3
	local color = options.color or Color3.fromRGB(255, 165, 0)
	local nodeSize = options.nodeSize or 0.8
	local lineWidth = options.lineWidth or 0.15
	local fadeDuration = options.fadeDuration or 0.5
	local showLabels = options.showLabels ~= false

	if not path or #path == 0 then return end

	-- Fade out del path anterior si existe
	local existingFolder = activePathFolders[npcName]
	if existingFolder and existingFolder.Parent then
		-- Cambiar nombre para evitar conflictos
		existingFolder.Name = "DEBUG_Path_" .. npcName .. "_old"
		fadeOutFolder(existingFolder, fadeDuration)
	end

	-- Crear nuevo folder para este path
	local folder = Instance.new("Folder")
	folder.Name = "DEBUG_Path_" .. npcName
	folder.Parent = workspace

	-- Guardar referencia
	activePathFolders[npcName] = folder

	-- Dibujar nodos del path
	for i = startIndex or 1, #path do
		local node = path[i]
		local isCurrentTarget = (i == startIndex)

		-- Esfera para el nodo
		local sphere = Instance.new("Part")
		sphere.Shape = Enum.PartType.Ball
		sphere.Size = Vector3.new(nodeSize, nodeSize, nodeSize) * (isCurrentTarget and 1.5 or 1)
		sphere.Position = node.position + Vector3.new(0, 0.5, 0)
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.CanQuery = false
		sphere.Color = isCurrentTarget and Color3.fromRGB(0, 255, 0) or color
		sphere.Transparency = 0.3
		sphere.Material = Enum.Material.Neon
		sphere.Parent = folder

		-- Número del nodo (solo si showLabels)
		if showLabels then
			CreateBillboardLabel(sphere, tostring(i), {
				size = UDim2.fromOffset(30, 20),
				offset = Vector3.new(0, 1, 0),
				strokeTransparency = 0,
			})
		end

		-- Línea al siguiente nodo
		if i < #path then
			local nextNode = path[i + 1]
			local startPos = node.position + Vector3.new(0, 0.5, 0)
			local endPos = nextNode.position + Vector3.new(0, 0.5, 0)
			local distance = (endPos - startPos).Magnitude

			local line = Instance.new("Part")
			line.Size = Vector3.new(lineWidth, lineWidth, distance)
			line.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance / 2)
			line.Anchored = true
			line.CanCollide = false
			line.CanQuery = false
			line.Color = color
			line.Transparency = 0.5
			line.Material = Enum.Material.Neon
			line.Parent = folder
		end
	end

	-- Auto-fade y destruir después de duration segundos
	task.delay(duration, function()
		if folder and folder.Parent and activePathFolders[npcName] == folder then
			fadeOutFolder(folder, fadeDuration)
			activePathFolders[npcName] = nil
		end
	end)

	return folder
end

function Visualizer.ClearNPCPath(npcName)
	local folder = activePathFolders[npcName]
	if folder and folder.Parent then
		fadeOutFolder(folder, 0.3)
		activePathFolders[npcName] = nil
	end
end

-- ==============================================================================
-- VISUALIZACIÓN DE ÚLTIMA POSICIÓN DETECTADA
-- ==============================================================================

-- Cache de esferas activas por NPC
local activeLastSeenSpheres = {}

--[[
	DrawLastSeenPosition - Dibuja una esfera en la última posición detectada

	La esfera hace fadeout progresivo durante toda su duración (coincide con investigationDuration).
	Si se actualiza la posición, la esfera anterior desaparece rápidamente.

	Parámetros:
	- npcName: Nombre del NPC para identificar la esfera
	- position: Vector3 posición donde dibujar
	- options:
	    - duration: Tiempo total de vida (default: 15, igual que investigationDuration)
	    - color: Color de la esfera (default: rojo)
	    - size: Tamaño de la esfera (default: 2)
	    - startTransparency: Transparencia inicial (default: 0.3)
	    - showLabels: Mostrar etiqueta de texto (default: true)
]]
function Visualizer.DrawLastSeenPosition(npcName, position, options)
	options = options or {}
	local duration = options.duration or 15
	local color = options.color or Color3.fromRGB(255, 100, 100)
	local size = options.size or 2
	local startTransparency = options.startTransparency or 0.3
	local showLabels = options.showLabels ~= false
	local quickFadeDuration = 0.4

	if not position then return end

	-- Fade out rápido de la esfera anterior si existe
	local existingData = activeLastSeenSpheres[npcName]
	if existingData and existingData.sphere and existingData.sphere.Parent then
		local oldSphere = existingData.sphere
		local oldLabel = existingData.label

		-- Cancelar el tween anterior
		if existingData.tween then
			existingData.tween:Cancel()
		end
		if existingData.labelTween then
			existingData.labelTween:Cancel()
		end

		-- Fade out rápido
		local quickTweenInfo = TweenInfo.new(quickFadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local quickTween = TweenService:Create(oldSphere, quickTweenInfo, { Transparency = 1 })
		quickTween:Play()

		if oldLabel and oldLabel.Parent then
			local quickLabelTween = TweenService:Create(oldLabel, quickTweenInfo, {
				TextTransparency = 1,
				TextStrokeTransparency = 1
			})
			quickLabelTween:Play()
		end

		Debris:AddItem(oldSphere, quickFadeDuration + 0.1)
	end

	-- Crear nueva esfera
	local sphere = Instance.new("Part")
	sphere.Name = "DEBUG_LastSeen_" .. npcName
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(size, size, size)
	sphere.Position = position
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.Color = color
	sphere.Transparency = startTransparency
	sphere.Material = Enum.Material.Neon
	sphere.Parent = workspace

	-- Etiqueta (opcional)
	local label = nil
	local labelTween = nil

	if showLabels then
		label = CreateBillboardLabel(sphere, "Last Seen", {
			size = UDim2.fromOffset(80, 25),
			offset = Vector3.new(0, size / 2 + 0.5, 0),
			textSize = 12,
			strokeTransparency = 0,
			strokeColor = color,
		})
	end

	-- Fadeout progresivo durante toda la duración
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local sphereTween = TweenService:Create(sphere, tweenInfo, { Transparency = 1 })
	sphereTween:Play()

	if label then
		labelTween = TweenService:Create(label, tweenInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1
		})
		labelTween:Play()
	end

	-- Guardar referencia con datos del tween
	activeLastSeenSpheres[npcName] = {
		sphere = sphere,
		label = label,
		tween = sphereTween,
		labelTween = labelTween,
	}

	-- Destruir y limpiar después de la duración
	task.delay(duration + 0.1, function()
		if activeLastSeenSpheres[npcName] and activeLastSeenSpheres[npcName].sphere == sphere then
			if sphere and sphere.Parent then
				sphere:Destroy()
			end
			activeLastSeenSpheres[npcName] = nil
		end
	end)

	return sphere
end

function Visualizer.ClearLastSeenPosition(npcName)
	local data = activeLastSeenSpheres[npcName]
	if data and data.sphere and data.sphere.Parent then
		-- Cancelar tweens
		if data.tween then
			data.tween:Cancel()
		end
		if data.labelTween then
			data.labelTween:Cancel()
		end

		-- Fade out rápido
		local quickTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(data.sphere, quickTweenInfo, { Transparency = 1 })
		tween:Play()

		if data.label and data.label.Parent then
			local labelTween = TweenService:Create(data.label, quickTweenInfo, {
				TextTransparency = 1,
				TextStrokeTransparency = 1
			})
			labelTween:Play()
		end

		Debris:AddItem(data.sphere, 0.4)
		activeLastSeenSpheres[npcName] = nil
	end
end

-- ==============================================================================
-- REPORTE DEL SISTEMA
-- ==============================================================================

function Visualizer.PrintSystemReport(npcManager, navGraph, spawnedNPCs, baseConfig, debugConfig)
	print("\n" .. string.rep("=", 60))
	print("SISTEMA COMPLETAMENTE INICIALIZADO")
	print(string.rep("=", 60))

	-- Estadísticas generales
	print("Total de NPCs: " .. npcManager:GetNPCCount())
	print("Total de nodos: " .. navGraph:GetNodesCount())
	print("Total de conexiones: " .. navGraph:GetConnectionCount())

	-- Estadísticas del spatial hash 2D (por piso)
	if navGraph.spatialGrids and next(navGraph.spatialGrids) then
		local floorCount = 0
		local totalCells = 0
		local totalNodesInCells = 0

		for _, grid in pairs(navGraph.spatialGrids) do
			floorCount = floorCount + 1
			for _, nodes in pairs(grid) do
				totalCells = totalCells + 1
				totalNodesInCells = totalNodesInCells + #nodes
			end
		end

		print("Spatial Hash 2D:")
		print("   Pisos con grids: " .. floorCount)
		print("   Celdas ocupadas (total): " .. totalCells)
		if totalCells > 0 then
			print("   Nodos por celda (promedio): " .. string.format("%.1f", totalNodesInCells / totalCells))
		end
	end

	-- Lista de NPCs spawneados
	print("\nNPCs spawneados:")
	for i, npcData in ipairs(spawnedNPCs) do
		local route = table.concat(npcData.config.patrolRoute, " -> ")
		print("  " .. i .. ". " .. npcData.npc.Name .. " | Ruta: " .. route)
	end

	-- Configuración
	print("\nConfiguracion:")
	print("    Deteccion: " .. baseConfig.minDetectionTime .. "s (" ..
		math.ceil(baseConfig.minDetectionTime * 30) .. " frames @ 30 FPS)")
	print("    Rango de deteccion: " .. baseConfig.detectionRange .. " studs")
	print("    Cono de vision: " .. baseConfig.observationConeAngle .. " grados")
	print("    Sistema de observacion: " .. #baseConfig.observationAngles ..
		" angulos x " .. baseConfig.observationTimePerAngle .. "s = " ..
		(#baseConfig.observationAngles * baseConfig.observationTimePerAngle) .. "s por nodo")
	print("    Navegacion: grafo (acercamiento directo a " .. baseConfig.directApproachDistance .. " studs)")
	print("    Indicador de estado: " .. (baseConfig.showStateIndicator and "Activado" or "Desactivado"))
	print("    Nodos en workspace: " .. (debugConfig.keepNodesInWorkspace and "Mantenidos (debug)" or "Destruidos (optimizado)"))

	print(string.rep("=", 60) .. "\n")
end

return Visualizer
