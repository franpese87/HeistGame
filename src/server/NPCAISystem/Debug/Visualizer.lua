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

	-- Si NavigationNodes existe, las Parts ya están en workspace (generadas por el plugin)
	-- No necesitamos hacer nada, solo retornar la carpeta existente
	local existingFolder = workspace:FindFirstChild("NavigationNodes")
	if existingFolder then
		return existingFolder
	end

	-- Fallback: crear Parts si no existe NavigationNodes (no debería ocurrir con el nuevo flujo)
	local color = options.nodeColor or options.color or Color3.fromRGB(0, 255, 0)
	local size = options.nodeSize or options.size or 0.5
	local transparency = options.nodeTransparency or options.transparency or 0.3

	local folder = CreateDebugFolder("DEBUG_Nodes")
	local count = 0

	for name, node in pairs(graph.nodes) do
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

	-- Intentar reutilizar los Beams del plugin si existen
	local navNodes = workspace:FindFirstChild("NavigationNodes")
	if navNodes then
		local pluginBeams = navNodes:FindFirstChild("_ConnectionBeams")
		if pluginBeams then
			-- Verificar que los Beams son válidos (tienen al menos 1 Beam hijo)
			local hasValidBeams = false
			for _, child in ipairs(pluginBeams:GetChildren()) do
				if child:IsA("Beam") then
					hasValidBeams = true
					break
				end
			end

			if hasValidBeams then
				-- Los Beams del plugin ya existen y son válidos
				print("[Visualizer] Reutilizando Beams del plugin (_ConnectionBeams)")
				return pluginBeams
			else
				-- La carpeta existe pero está vacía - el usuario desactivó el toggle
				-- NO crear nuevos Beams, respetar la decisión del usuario
				print("[Visualizer] Carpeta _ConnectionBeams vacía (toggle desactivado), no creando conexiones")
				return pluginBeams -- Retornar la carpeta vacía para no crear duplicados
			end
		end
	end

	-- Si no existe la carpeta _ConnectionBeams, no crear nada
	-- Las conexiones solo se visualizan si se activa el toggle en el plugin
	print("[Visualizer] No hay Beams del plugin. Usa 'Toggle Connection View' en el plugin para visualizar conexiones")
	return nil
end

-- ==============================================================================
-- VISUALIZACIÓN COMPLETA
-- ==============================================================================

function Visualizer.DrawAll(graph, options)
	options = options or {}

	-- Determinar si debemos mantener los Beams del plugin
	local shouldKeepPluginBeams = (options.showNodes ~= false) and (options.showConnections ~= false)

	-- Si NO debemos mantener los Beams del plugin, eliminarlos
	if not shouldKeepPluginBeams then
		local navNodes = workspace:FindFirstChild("NavigationNodes")
		if navNodes then
			local pluginBeams = navNodes:FindFirstChild("_ConnectionBeams")
			if pluginBeams then
				pluginBeams:Destroy()
				print("[Visualizer] Eliminados Beams del plugin (showNodes o showConnections desactivado)")
			end

			-- Limpiar Attachments de los nodos
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
	end

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

	-- Limpiar también los Beams del plugin si existen
	local navNodes = workspace:FindFirstChild("NavigationNodes")
	if navNodes then
		local pluginBeams = navNodes:FindFirstChild("_ConnectionBeams")
		if pluginBeams then
			pluginBeams:Destroy()
			print("[Visualizer] Eliminados Beams del plugin (_ConnectionBeams)")
		end

		-- Limpiar Attachments de los nodos (BeamConn_*)
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
		pathColor = options.pathColor or Color3.fromRGB(255, 165, 0),
		showLastSeenPosition = options.showLastSeenPosition or false,
		showDebugLabels = options.showDebugLabels ~= false,
	}
end

function Visualizer.DisableNPCDebug(ai)
	ai.debugEnabled = false
end

-- ==============================================================================
-- VISUALIZACIÓN DE PATHS DE NPCs
-- ==============================================================================

-- Atributos usados en las Parts para tracking:
-- _pathOriginalColor: Color3 - color original antes de ser modificado
-- _pathRefCount: number - cuántos NPCs están usando este nodo

-- Cache de nodos modificados por NPC (lista de Parts)
local activePathParts = {}

-- Busca la Part de un nodo en NavigationNodes (búsqueda recursiva)
local function findNodePart(nodeName)
	if not nodeName then return nil end

	local navNodes = workspace:FindFirstChild("NavigationNodes")
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

-- Libera los nodos de un NPC y restaura colores si ya no hay referencias
local function releasePathParts(parts)
	if not parts then return end

	for _, part in ipairs(parts) do
		if part and part.Parent then
			local refCount = (part:GetAttribute("_pathRefCount") or 1) - 1
			if refCount <= 0 then
				-- Restaurar color original
				local originalColor = part:GetAttribute("_pathOriginalColor")
				if originalColor then
					part.Color = originalColor
				end
				part:SetAttribute("_pathOriginalColor", nil)
				part:SetAttribute("_pathRefCount", nil)
			else
				part:SetAttribute("_pathRefCount", refCount)
			end
		end
	end
end

function Visualizer.DrawNPCPath(npcName, path, startIndex, options)
	if not path or #path == 0 then return end

	-- Requiere NavigationNodes en workspace para visualizar
	if not workspace:FindFirstChild("NavigationNodes") then return end

	options = options or {}
	local color = options.color or Color3.fromRGB(255, 165, 0)

	-- Liberar nodos del path anterior
	releasePathParts(activePathParts[npcName])

	-- Lista de Parts modificadas en este path
	local modifiedParts = {}

	-- Cambiar el color de los nodos del path
	local actualStartIndex = startIndex or 1
	for i = actualStartIndex, #path do
		local node = path[i]
		local nodePart = findNodePart(node.name)

		if nodePart then
			-- Guardar color original solo si es la primera referencia
			if not nodePart:GetAttribute("_pathOriginalColor") then
				nodePart:SetAttribute("_pathOriginalColor", nodePart.Color)
				nodePart:SetAttribute("_pathRefCount", 0)
			end
			nodePart:SetAttribute("_pathRefCount", nodePart:GetAttribute("_pathRefCount") + 1)

			-- Cambiar color
			nodePart.Color = color
			table.insert(modifiedParts, nodePart)
		end
	end

	-- Guardar referencia
	activePathParts[npcName] = modifiedParts

	return modifiedParts
end

function Visualizer.ClearNPCPath(npcName)
	releasePathParts(activePathParts[npcName])
	activePathParts[npcName] = nil
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

function Visualizer.PrintSystemReport(npcManager, navGraph, spawnedNPCs, baseConfig)
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

	local nodesKept = workspace:FindFirstChild("NavigationNodes") ~= nil
	print("    Nodos en workspace: " .. (nodesKept and "Mantenidos (debug)" or "Destruidos (optimizado)"))

	print(string.rep("=", 60) .. "\n")
end

return Visualizer
