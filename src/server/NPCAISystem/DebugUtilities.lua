local DebugUtilities = {}

-- ==============================================================================
-- VISUALIZACIÓN DE NODOS
-- ==============================================================================

function DebugUtilities.DrawNodes(graph, options)
	options = options or {}
	local color = options.nodeColor or options.color or Color3.fromRGB(0, 255, 0)
	local size = options.nodeSize or options.size or 0.5
	local transparency = options.nodeTransparency or options.transparency or 0.3
	local showLabels = options.showLabels ~= false

	-- Limpiar debug anterior
	local existingFolder = workspace:FindFirstChild("DEBUG_Nodes")
	if existingFolder then
		existingFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "DEBUG_Nodes"
	folder.Parent = workspace

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
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(100, 40)
			billboard.StudsOffset = Vector3.new(0, 1, 0)
			billboard.AlwaysOnTop = true
			billboard.Parent = sphere

			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = name
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextScaled = true
			label.Font = Enum.Font.SourceSansBold
			label.TextStrokeTransparency = 0.5
			label.Parent = billboard

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
-- VISUALIZACIÓN DE CELDAS (SPATIAL HASH)
-- ==============================================================================

function DebugUtilities.DrawCells(graph, options)
	if not graph.spatialGrid then
		return
	end

	options = options or {}
	local color = options.cellColor or options.color or Color3.fromRGB(100, 200, 255)
	local transparency = options.cellTransparency or options.transparency or 0.85
	local wireframe = options.cellWireframe ~= false
	local showLabels = options.showLabels ~= false

	-- Limpiar debug anterior
	local existingFolder = workspace:FindFirstChild("DEBUG_Cells")
	if existingFolder then
		existingFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "DEBUG_Cells"
	folder.Parent = workspace

	local count = 0

	for cellKey, nodes in pairs(graph.spatialGrid) do
		-- Parsear índices de celda desde la key
		local coords = string.split(cellKey, ",")
		local cellX = tonumber(coords[1])
		local cellY = tonumber(coords[2])
		local cellZ = tonumber(coords[3])

		-- Calcular posición central EXACTA de la celda desde su índice
		local centerPos = Vector3.new(
			cellX * graph.cellSizeX + graph.cellSizeX / 2,
			cellY * graph.cellSizeY + graph.cellSizeY / 2,
			cellZ * graph.cellSizeZ + graph.cellSizeZ / 2
		)

		local cellSize = Vector3.new(graph.cellSizeX, graph.cellSizeY, graph.cellSizeZ)

		-- Crear Part para la celda
		local cellPart = Instance.new("Part")
		cellPart.Name = "Cell_" .. cellKey
		cellPart.Size = cellSize
		cellPart.Position = centerPos
		cellPart.Anchored = true
		cellPart.CanCollide = false
		cellPart.CanQuery = false
		cellPart.Color = color
		cellPart.Material = Enum.Material.SmoothPlastic

		if wireframe then
			-- Modo wireframe (solo bordes)
			cellPart.Transparency = 1

			-- Crear SelectionBox para mostrar bordes
			local selectionBox = Instance.new("SelectionBox")
			selectionBox.Adornee = cellPart
			selectionBox.LineThickness = 0.05
			selectionBox.Color3 = color
			selectionBox.Transparency = 0.3
			selectionBox.Parent = cellPart
		else
			-- Modo sólido
			cellPart.Transparency = transparency
		end

		cellPart.Parent = folder

		-- Etiqueta con información
		if showLabels then
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(120, 50)
			billboard.StudsOffset = Vector3.new(0, cellSize.Y / 2 + 1, 0)
			billboard.AlwaysOnTop = true
			billboard.Parent = cellPart

			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = cellKey .. "\n(" .. #nodes .. " nodos)"
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextScaled = true
			label.Font = Enum.Font.SourceSansBold
			label.TextStrokeTransparency = 0.5
			label.Parent = billboard
		end

		count = count + 1
	end

	return folder
end

-- ==============================================================================
-- VISUALIZACIÓN DE CONEXIONES
-- ==============================================================================

function DebugUtilities.DrawConnections(graph, options)
	options = options or {}
	local color = options.connectionColor or options.color or Color3.fromRGB(153, 202, 255)
	local width = options.connectionWidth or options.width or 0.1

	-- Limpiar debug anterior
	local existingFolder = workspace:FindFirstChild("DEBUG_Connections")
	if existingFolder then
		existingFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "DEBUG_Connections"
	folder.Parent = workspace

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

function DebugUtilities.DrawAll(graph, options)
	options = options or {}

	if options.showNodes ~= false then
		DebugUtilities.DrawNodes(graph, options)
	end

	if options.showCells ~= false then
		DebugUtilities.DrawCells(graph, options)
	end

	if options.showConnections ~= false then
		DebugUtilities.DrawConnections(graph, options)
	end
end

function DebugUtilities.ClearAll()
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

function DebugUtilities.VisualizeRaycast(origin, direction, result, options)
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

	game:GetService("Debris"):AddItem(part, duration)
end

-- ==============================================================================
-- DEBUG POR NPC
-- ==============================================================================

function DebugUtilities.EnableNPCDebug(ai, options)
	options = options or {}
	ai.debugEnabled = true
	ai.debugConfig = {
		showRaycast = options.showRaycast or false,
		raycastDuration = options.raycastDuration or 0.1,
	}
end

function DebugUtilities.DisableNPCDebug(ai)
	ai.debugEnabled = false
end

-- ==============================================================================
-- REPORTE DEL SISTEMA
-- ==============================================================================

function DebugUtilities.PrintSystemReport(npcManager, navGraph, spawnedNPCs, baseConfig, debugConfig)
	print("\n" .. string.rep("=", 60))
	print("🎉 SISTEMA COMPLETAMENTE INICIALIZADO")
	print(string.rep("=", 60))

	-- Estadísticas generales
	print("📊 Total de NPCs: " .. npcManager:GetNPCCount())
	print("🗺️  Total de nodos: " .. navGraph:GetNodesCount())
	print("🔗 Total de conexiones: " .. navGraph:GetConnectionCount())

	-- Estadísticas del spatial hash
	if navGraph.spatialGrid then
		local cellCount = 0
		local totalNodesInCells = 0
		for _, nodes in pairs(navGraph.spatialGrid) do
			cellCount = cellCount + 1
			totalNodesInCells = totalNodesInCells + #nodes
		end
		print("🔲 Spatial Hash:")
		print("   Celdas ocupadas: " .. cellCount)
		print("   Nodos por celda (promedio): " .. string.format("%.1f", totalNodesInCells / cellCount))
	end

	-- Lista de NPCs spawneados
	print("\n📋 NPCs spawneados:")
	for i, npcData in ipairs(spawnedNPCs) do
		local route = table.concat(npcData.config.patrolRoute, " → ")
		print("  " .. i .. ". " .. npcData.npc.Name .. " | Ruta: " .. route)
	end

	-- Configuración
	print("\n⚙️  Configuración:")
	print("    • Detección: " .. baseConfig.minDetectionTime .. "s (" ..
		math.ceil(baseConfig.minDetectionTime * 30) .. " frames @ 30 FPS)")
	print("    • Rango de detección: " .. baseConfig.detectionRange .. " studs")
	print("    • Cono de visión: " .. baseConfig.observationConeRays .. " rayos × " ..
		baseConfig.observationConeAngle .. "°")
	print("    • Sistema de observación: " .. #baseConfig.observationAngles ..
		" ángulos × " .. baseConfig.observationTimePerAngle .. "s = " ..
		(#baseConfig.observationAngles * baseConfig.observationTimePerAngle) .. "s por nodo")
	print("    • Navegación: " .. baseConfig.navigationMode .. " (cambio directo a " ..
		baseConfig.graphChaseDistance .. " studs)")
	print("    • Indicador de estado: " .. (baseConfig.showStateIndicator and "Activado" or "Desactivado"))
	print("    • Nodos en workspace: " .. (debugConfig.keepNodesInWorkspace and "Mantenidos (debug)" or "Destruidos (optimizado)"))

	print(string.rep("=", 60) .. "\n")
end

return DebugUtilities