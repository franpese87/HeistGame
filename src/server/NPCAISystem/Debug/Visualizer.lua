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

local DebugConfig = require(script.Parent.Parent.Parent.Config.DebugConfig)

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
	-- Los nodos son generados por el plugin NodeGenerator
	-- Esta función solo retorna la carpeta existente
	local existingFolder = workspace:FindFirstChild("NavigationNodes")
	return existingFolder
end

-- ==============================================================================
-- VISUALIZACIÓN DE CELDAS (SPATIAL HASH 3D)
-- ==============================================================================

function Visualizer.DrawCells(graph, _options)
	if not graph.spatialGrid3D or not next(graph.spatialGrid3D) then
		warn("Visualizer.DrawCells: No hay spatial grid 3D para dibujar")
		return
	end

	-- Color dinámico por número de piso: hue distribuido uniformemente en HSV
	-- Funciona para cualquier número de piso sin tabla hardcodeada
	local colorCache = {}
	local function getFloorColor(floor)
		if colorCache[floor] then
			return colorCache[floor]
		end
		-- Distribuye hues usando proporción áurea para máxima separación visual
		local hue = ((floor * 0.618033988) % 1 + 1) % 1
		local color = Color3.fromHSV(hue, 0.65, 0.95)
		colorCache[floor] = color
		return color
	end

	local folder = CreateDebugFolder("DEBUG_Cells")
	-- Subcarpeta por piso para organización en el explorador de Studio
	local floorFolders = {}
	local function getFloorFolder(floor)
		if floorFolders[floor] then
			return floorFolders[floor]
		end
		local f = Instance.new("Folder")
		f.Name = "Floor_" .. floor
		f.Parent = folder
		floorFolders[floor] = f
		return f
	end

	for cellKey, nodes in pairs(graph.spatialGrid3D) do
		-- Parsear índices 3D desde la key "cellX,cellY,cellZ"
		local coords = string.split(cellKey, ",")
		local cellX = tonumber(coords[1])
		local cellY = tonumber(coords[2])
		local cellZ = tonumber(coords[3])

		-- Calcular posición central de la celda 3D
		local centerPos = Vector3.new(
			cellX * graph.cellSizeX + graph.cellSizeX / 2,
			cellY * graph.cellSizeY + graph.cellSizeY / 2,
			cellZ * graph.cellSizeZ + graph.cellSizeZ / 2
		)

		local cellSize = Vector3.new(graph.cellSizeX, graph.cellSizeY, graph.cellSizeZ)

		-- Inferir piso del primer nodo de la celda y obtener su color
		local floor = nodes[1] and nodes[1].metadata and nodes[1].metadata.floor or 0
		local color = getFloorColor(floor)

		local cellPart = Instance.new("Part")
		cellPart.Name = "Cell_" .. cellKey
		cellPart.Size = cellSize
		cellPart.Position = centerPos
		cellPart.Anchored = true
		cellPart.CanCollide = false
		cellPart.CanQuery = false
		cellPart.Color = color
		cellPart.Material = Enum.Material.SmoothPlastic
		cellPart.Transparency = 1

		local selectionBox = Instance.new("SelectionBox")
		selectionBox.Adornee = cellPart
		selectionBox.LineThickness = 0.05
		selectionBox.Color3 = color
		selectionBox.Transparency = 0.3
		selectionBox.Parent = cellPart

		cellPart.Parent = getFloorFolder(floor)
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
	}
end

function Visualizer.DisableNPCDebug(ai)
	ai.debugEnabled = false
end

-- ==============================================================================
-- VISUALIZACIÓN DE PATHS DE NPCs (Nodos encendidos mientras están en path)
-- ==============================================================================

-- Cache de nodos encendidos por NPC: { [npcName] = { Part, Part, ... } }
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

-- Enciende un nodo (Material.Neon + opaco)
local function turnOnNode(nodePart)
	if not nodePart or not nodePart.Parent then return end

	-- Guardar estado original solo si es la primera vez que se enciende
	if not nodePart:GetAttribute("_pathOriginalMaterial") then
		nodePart:SetAttribute("_pathOriginalMaterial", nodePart.Material.Name)
		nodePart:SetAttribute("_pathOriginalTransparency", nodePart.Transparency)
		nodePart:SetAttribute("_pathRefCount", 0)
	end

	-- Incrementar ref count
	local refCount = nodePart:GetAttribute("_pathRefCount") + 1
	nodePart:SetAttribute("_pathRefCount", refCount)

	-- Encender (Material.Neon + semi-transparente para emisión natural)
	nodePart.Material = Enum.Material.Neon
	nodePart.Transparency = 0.4
end

-- Apaga un nodo (restaura estado original si no hay más referencias)
local function turnOffNode(nodePart)
	if not nodePart or not nodePart.Parent then return end

	local refCount = nodePart:GetAttribute("_pathRefCount")
	if not refCount then return end

	refCount = refCount - 1
	nodePart:SetAttribute("_pathRefCount", refCount)

	-- Solo restaurar si no hay más NPCs usando este nodo
	if refCount <= 0 then
		local originalMaterial = nodePart:GetAttribute("_pathOriginalMaterial")
		local originalTransparency = nodePart:GetAttribute("_pathOriginalTransparency")

		if originalMaterial then
			nodePart.Material = Enum.Material[originalMaterial]
		end
		if originalTransparency then
			nodePart.Transparency = originalTransparency
		end

		-- Limpiar atributos
		nodePart:SetAttribute("_pathOriginalMaterial", nil)
		nodePart:SetAttribute("_pathOriginalTransparency", nil)
		nodePart:SetAttribute("_pathRefCount", nil)
	end
end

-- Apaga todos los nodos de un NPC
local function releasePathParts(npcName)
	local parts = activePathParts[npcName]
	if not parts then return end

	for _, part in ipairs(parts) do
		turnOffNode(part)
	end

	activePathParts[npcName] = nil
end

-- Enciende los nodos del path actual del NPC
function Visualizer.DrawNPCPath(npcName, path, startIndex, _options)
	if not path or #path == 0 then return end
	if not workspace:FindFirstChild("NavigationNodes") then return end

	-- Apagar nodos del path anterior
	releasePathParts(npcName)

	-- Encender nodos del nuevo path
	local parts = {}
	local actualStartIndex = startIndex or 1

	for i = actualStartIndex, #path do
		local node = path[i]
		local nodePart = findNodePart(node.name)

		if nodePart then
			turnOnNode(nodePart)
			table.insert(parts, nodePart)
		end
	end

	activePathParts[npcName] = parts
end

-- Apaga los nodos del path de un NPC
function Visualizer.ClearNPCPath(npcName)
	releasePathParts(npcName)
end

-- ==============================================================================
-- VISUALIZACIÓN DE ÚLTIMA POSICIÓN DETECTADA
-- ==============================================================================

-- Cache de esferas activas por NPC
local activeLastSeenSpheres = {}

--[[
	DrawLastSeenPosition - Dibuja un cilindro a ras de suelo en la última posición detectada

	El cilindro hace fadeout progresivo durante toda su duración (coincide con investigationDuration).
	Si se actualiza la posición, el cilindro anterior desaparece rápidamente.
	Se muestra siempre a ras de suelo independientemente de la altura de la posición (jugador saltando, etc).

	Parámetros:
	- npcName: Nombre del NPC para identificar el cilindro
	- position: Vector3 posición donde dibujar (se proyecta al suelo)
	- options:
	    - duration: Tiempo total de vida (default: 15, igual que investigationDuration)
	    - color: Color del cilindro (default: rojo)
	    - size: Radio del cilindro (default: 3, ancho de humanoide R6)
	    - startTransparency: Transparencia inicial (default: 0.3)
]]
function Visualizer.DrawLastSeenPosition(npcName, position, options)
	options = options or {}
	local duration = options.duration or 15
	local color = options.color or Color3.fromRGB(255, 100, 100)
	local size = options.size or 3  -- Radio de 3 studs (ancho de humanoide R6)
	local startTransparency = options.startTransparency or 0.3
	local quickFadeDuration = 0.4

	if not position then return end

	-- Fade out rápido del cilindro anterior si existe
	local existingData = activeLastSeenSpheres[npcName]
	if existingData and existingData.sphere and existingData.sphere.Parent then
		local oldCylinder = existingData.sphere
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
		local quickTween = TweenService:Create(oldCylinder, quickTweenInfo, { Transparency = 1 })
		quickTween:Play()

		if oldLabel and oldLabel.Parent then
			local quickLabelTween = TweenService:Create(oldLabel, quickTweenInfo, {
				TextTransparency = 1,
				TextStrokeTransparency = 1
			})
			quickLabelTween:Play()
		end

		Debris:AddItem(oldCylinder, quickFadeDuration + 0.1)
	end

	-- Crear nuevo cilindro a ras de suelo (como el rango de visión)
	local cylinder = Instance.new("Part")
	cylinder.Name = "DEBUG_LastSeen_" .. npcName
	cylinder.Shape = Enum.PartType.Cylinder
	cylinder.Size = Vector3.new(0.3, size * 2, size * 2)  -- altura, diámetro, diámetro
	cylinder.Anchored = true
	cylinder.CanCollide = false
	cylinder.CanQuery = false
	cylinder.Color = color
	cylinder.Transparency = startTransparency
	cylinder.Material = Enum.Material.Neon

	-- Posicionar a ras de suelo
	local groundY = position.Y - 2.5  -- Aproximado a ras de suelo
	cylinder.CFrame = CFrame.new(position.X, groundY, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	cylinder.Parent = workspace

	-- Etiqueta
	local labelTween = nil
	local label = CreateBillboardLabel(cylinder, "Last Seen", {
		size = UDim2.fromOffset(80, 25),
		offset = Vector3.new(0, size / 2 + 0.5, 0),
		textSize = 12,
		strokeTransparency = 0,
		strokeColor = color,
	})

	-- Fadeout progresivo durante toda la duración
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local cylinderTween = TweenService:Create(cylinder, tweenInfo, { Transparency = 1 })
	cylinderTween:Play()

	labelTween = TweenService:Create(label, tweenInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1
	})
	labelTween:Play()

	-- Guardar referencia con datos del tween
	activeLastSeenSpheres[npcName] = {
		sphere = cylinder,
		label = label,
		tween = cylinderTween,
		labelTween = labelTween,
	}

	-- Destruir y limpiar después de la duración
	task.delay(duration + 0.1, function()
		if activeLastSeenSpheres[npcName] and activeLastSeenSpheres[npcName].sphere == cylinder then
			if cylinder and cylinder.Parent then
				cylinder:Destroy()
			end
			activeLastSeenSpheres[npcName] = nil
		end
	end)

	return cylinder
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

	-- Estadísticas del spatial hash 3D
	if navGraph.spatialGrid3D and next(navGraph.spatialGrid3D) then
		local hashStats = navGraph:GetSpatialHashStats()
		print("Spatial Hash 3D:")
		print("   Celdas ocupadas: " .. hashStats.totalCells)
		if hashStats.totalCells > 0 then
			print("   Nodos por celda (promedio): " .. string.format("%.1f", hashStats.avgNodesPerCell))
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
	print("    Deteccion: instantanea (reactionTime: " .. baseConfig.reactionTime .. "s)")
	print("    Rango de deteccion: " .. baseConfig.detectionRange .. " studs")
	print("    Cono de vision: " .. baseConfig.observationConeAngle .. " grados")
	print("    Sistema de observacion: " .. #baseConfig.observationAngles .. " angulos x " .. baseConfig.observationTimePerAngle .. "s = " .. (#baseConfig.observationAngles * baseConfig.observationTimePerAngle) .. "s por nodo")
	print("    Navegacion: grafo (acercamiento directo a " .. baseConfig.directApproachDistance .. " studs)")
	print("    Indicador de estado: " .. (DebugConfig.visuals.showStateIndicator and "Activado" or "Desactivado"))

	local nodesKept = workspace:FindFirstChild("NavigationNodes") ~= nil
	print("    Nodos en workspace: " .. (nodesKept and "Mantenidos (debug)" or "Destruidos (optimizado)"))

	print(string.rep("=", 60) .. "\n")
end

return Visualizer
