local NavigationGraph = {}
NavigationGraph.__index = NavigationGraph

function NavigationGraph.new()
	local self = setmetatable({}, NavigationGraph)
	self.nodes = {}
	self.connections = {}

	-- Spatial hashing (construir con BuildSpatialHash3D)
	self.spatialGrid = nil
	self.cellSizeX = 16  -- Tamaño fijo: 20 studs
	self.cellSizeY = 10  -- Tamaño fijo: 10 studs
	self.cellSizeZ = 14  -- Tamaño fijo: 20 studs

	return self
end

-- ==============================================================================
-- VALIDACIÓN DE POSICIONES
-- ==============================================================================

function NavigationGraph:IsPositionWalkable(position, ignoreFolder)
	-- Verificar si hay geometría sólida ocupando el espacio del nodo
	-- Usar GetPartBoundsInRadius para detectar partes en el mismo espacio
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {ignoreFolder}

	-- Verificar en un radio de 0.7 studs alrededor del nodo (aproximadamente el radio de un humanoide)
	local checkRadius = 0.7
	local partsInRadius = workspace:GetPartBoundsInRadius(position, checkRadius, overlapParams)

	-- Si hay partes sólidas ocupando este espacio, el nodo está dentro de algo
	for _, part in ipairs(partsInRadius) do
		if part.CanCollide then
			-- Verificar que la parte realmente está EN el nodo, no solo cerca
			-- Comprobar si el centro del nodo está dentro del bounding box de la parte
			local relativePos = part.CFrame:PointToObjectSpace(position)
			local halfSize = part.Size / 2

			-- Si el nodo está dentro de los límites de la parte
			if math.abs(relativePos.X) < halfSize.X and
			   math.abs(relativePos.Y) < halfSize.Y and
			   math.abs(relativePos.Z) < halfSize.Z then
				return false -- Nodo dentro de geometría sólida
			end
		end
	end

	return true -- Nodo válido (no está dentro de geometría)
end

-- ==============================================================================
-- CARGA DE NODOS DESDE PARTS
-- ==============================================================================

function NavigationGraph:LoadFromParts(partsFolder, shouldDestroyParts)
	shouldDestroyParts = shouldDestroyParts ~= false
	
	if not partsFolder then
		warn("⚠️ Folder de nodos no proporcionado")
		return
	end
	
	local loadedNodes = {}
	local discardedNodes = {}

	for _, part in ipairs(partsFolder:GetChildren()) do
		if part:IsA("BasePart") then
			-- Validar si el nodo está en zona caminable (sin estar encerrado)
			local isWalkable = self:IsPositionWalkable(part.Position, partsFolder)

			if isWalkable then
				-- Leer metadata de atributos si existen
				local metadata = {
					floor = part:GetAttribute("Floor") or 0,
					isStair = part:GetAttribute("IsStair") or false,
					isRamp = part:GetAttribute("IsRamp") or false,
				}

				-- Guardar en memoria solo si es válido
				self:AddNode(part.Name, part.Position, metadata)
				table.insert(loadedNodes, part.Name)

				print("📍 Nodo cargado: " .. part.Name)
			else
				-- Descartar nodo por colisión con geometría
				table.insert(discardedNodes, part.Name)
				warn("❌ Nodo descartado (colisión): " .. part.Name)
			end
		end
	end
	
	-- Destruir o transparentar las Parts
	if shouldDestroyParts then
		partsFolder:Destroy()
		print("🗑️ Parts de nodos destruidas (ahora en memoria)")
	else
		-- Hacerlas transparentes para debug
		for _, part in ipairs(partsFolder:GetChildren()) do
			if part:IsA("BasePart") then
				part.Transparency = 0.8
				part.CanCollide = false
				part.CanQuery = false
			end
		end
		print("👻 Parts de nodos transparentes (modo debug)")
	end
	
	-- Estadísticas de carga
	print("\n📊 Resumen de carga de nodos:")
	print("   ✅ Nodos válidos cargados: " .. #loadedNodes)
	if #discardedNodes > 0 then
		print("   ❌ Nodos descartados (colisión): " .. #discardedNodes)
	end
	print("   📦 Total en memoria: " .. #loadedNodes)

	-- Construir spatial hash automáticamente después de cargar nodos
	self:BuildSpatialHash3D()

	return loadedNodes
end

-- ==============================================================================
-- GESTIÓN DE NODOS
-- ==============================================================================

function NavigationGraph:AddNode(nodeName, position, metadata)
	if self.nodes[nodeName] then
		warn("⚠️ Nodo duplicado: " .. nodeName)
		return false
	end

	self.nodes[nodeName] = {
		name = nodeName,
		position = position,
		connections = {},
		metadata = metadata or {
			floor = 0,
			isStair = false,
			isRamp = false,
		}
	}
	return true
end

function NavigationGraph:AddConnection(fromName, toName, bidirectional)
	bidirectional = bidirectional == nil and true or bidirectional

	local fromNode = self.nodes[fromName]
	local toNode = self.nodes[toName]

	if not fromNode or not toNode then
		warn("⚠️ Nodos no encontrados: " .. fromName .. " → " .. toName)
		return false
	end

	if not table.find(fromNode.connections, toName) then
		table.insert(fromNode.connections, toName)
	end

	if bidirectional and not table.find(toNode.connections, fromName) then
		table.insert(toNode.connections, fromName)
	end

	return true
end

-- ==============================================================================
-- AUTO-CONEXIÓN
-- ==============================================================================

function NavigationGraph:AutoConnect(options)
	options = options or {}
	local mode = options.mode or "distance"
	local maxDistance = options.maxDistance or 50
	local useRaycast = options.useRaycast or false
	local maxConnectionsPerNode = options.maxConnectionsPerNode or 6
	local ignoreList = options.ignoreList or {}

	local connections = 0
	local attempts = 0

	for fromName, fromNode in pairs(self.nodes) do
		local candidates = {}

		for toName, toNode in pairs(self.nodes) do
			if fromName ~= toName then
				local distance = (fromNode.position - toNode.position).Magnitude

				if distance <= maxDistance then
					attempts = attempts + 1
					local canConnect = true

					if useRaycast then
						local rayParams = RaycastParams.new()
						rayParams.FilterType = Enum.RaycastFilterType.Exclude
						rayParams.FilterDescendantsInstances = ignoreList

						local result = workspace:Raycast(fromNode.position, toNode.position - fromNode.position, rayParams)

						if result then
							canConnect = false
						end
					end

					if canConnect then
						table.insert(candidates, {name = toName, distance = distance})
					end
				end
			end
		end

		table.sort(candidates, function(a, b) return a.distance < b.distance end)

		local connectionsForNode = 0
		for _, candidate in ipairs(candidates) do
			if connectionsForNode >= maxConnectionsPerNode then break end

			if not table.find(fromNode.connections, candidate.name) then
				self:AddConnection(fromName, candidate.name, true)
				connections = connections + 1
				connectionsForNode = connectionsForNode + 1
			end
		end
	end

	print("🎯 Auto-conectados " .. connections .. " conexiones (\" .. mode .. \", max dist: " .. maxDistance .. ", raycast: " .. tostring(useRaycast) .. ")")
	return connections
end

-- ==============================================================================
-- SPATIAL HASHING 3D
-- ==============================================================================

function NavigationGraph:BuildSpatialHash3D()
	self.spatialGrid = {}

	-- Construir grid 3D usando el origen del workspace (0,0,0)
	-- Celdas de 21×21×10 studs
	for name, node in pairs(self.nodes) do
		local cellX = math.floor(node.position.X / self.cellSizeX)
		local cellY = math.floor(node.position.Y / self.cellSizeY)
		local cellZ = math.floor(node.position.Z / self.cellSizeZ)
		local cellKey = cellX .. "," .. cellY .. "," .. cellZ

		if not self.spatialGrid[cellKey] then
			self.spatialGrid[cellKey] = {}
		end

		table.insert(self.spatialGrid[cellKey], node)
	end

	local cellCount = 0
	for _ in pairs(self.spatialGrid) do cellCount = cellCount + 1 end

	print("🔲 Spatial hash 3D construido:")
	print("   Tamaño celda: " .. self.cellSizeX .. " × " .. self.cellSizeY .. " × " .. self.cellSizeZ .. " studs")
	print("   Origen de referencia: Workspace (0, 0, 0)")
	print("   Total celdas ocupadas: " .. cellCount)
end

-- ==============================================================================
-- BÚSQUEDA DE NODOS (CON SPATIAL HASHING)
-- ==============================================================================

function NavigationGraph:GetNearestNode(position, options)
	-- Si no hay spatial hash, usar búsqueda linear
	if not self.spatialGrid then
		return self:GetNearestNodeLinear(position)
	end
	
	options = options or {}
	local preferSameFloor = options.preferSameFloor or false
	local currentFloor = options.floor

	local cellX = math.floor(position.X / self.cellSizeX)
	local cellY = math.floor(position.Y / self.cellSizeY)
	local cellZ = math.floor(position.Z / self.cellSizeZ)
	
	local nearestNode = nil
	local nearestSameFloor = nil
	local shortestDistance = math.huge
	local shortestSameFloorDistance = math.huge
	
	-- Buscar en 3x3x3 grid (27 celdas vecinas)
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local key = (cellX + dx) .. "," .. (cellY + dy) .. "," .. (cellZ + dz)
				local nodesInCell = self.spatialGrid[key]
				
				if nodesInCell then
					for _, node in ipairs(nodesInCell) do
						local distance = (node.position - position).Magnitude
						
						-- Mejor nodo en general
						if distance < shortestDistance then
							shortestDistance = distance
							nearestNode = node
						end
						
						-- Mejor nodo del mismo piso
						if preferSameFloor and currentFloor then
							if node.metadata.floor == currentFloor and distance < shortestSameFloorDistance then
								shortestSameFloorDistance = distance
								nearestSameFloor = node
							end
						end
					end
				end
			end
		end
	end
	
	-- Preferir nodo del mismo piso si está razonablemente cerca
	if preferSameFloor and nearestSameFloor and shortestSameFloorDistance < shortestDistance * 1.5 then
		return nearestSameFloor
	end
	
	return nearestNode
end

function NavigationGraph:GetNearestNodeLinear(position)
	local nearestNode = nil
	local shortestDistance = math.huge

	for name, node in pairs(self.nodes) do
		local distance = (node.position - position).Magnitude
		if distance < shortestDistance then
			shortestDistance = distance
			nearestNode = node
		end
	end

	return nearestNode
end

-- ==============================================================================
-- PATHFINDING (A*)
-- ==============================================================================

function NavigationGraph:GetPathBetweenNodes(startNode, endNode)
	if not startNode or not endNode then return nil end
	if startNode.name == endNode.name then return {endNode} end

	local openSet = {startNode}
	local closedSet = {}
	local cameFrom = {}
	local gScore = {[startNode.name] = 0}
	local fScore = {[startNode.name] = (startNode.position - endNode.position).Magnitude}

	while #openSet > 0 do
		table.sort(openSet, function(a, b)
			return (fScore[a.name] or math.huge) < (fScore[b.name] or math.huge)
		end)

		local current = table.remove(openSet, 1)

		if current.name == endNode.name then
			local path = {current}
			while cameFrom[current.name] do
				current = cameFrom[current.name]
				table.insert(path, 1, current)
			end
			return path
		end

		table.insert(closedSet, current)

		for _, neighborName in ipairs(current.connections) do
			local neighbor = self.nodes[neighborName]

			if neighbor and not table.find(closedSet, neighbor) then
				local tentative_gScore = gScore[current.name] + (current.position - neighbor.position).Magnitude

				if not table.find(openSet, neighbor) then
					table.insert(openSet, neighbor)
				elseif tentative_gScore >= (gScore[neighbor.name] or math.huge) then
					continue
				end

				cameFrom[neighbor.name] = current
				gScore[neighbor.name] = tentative_gScore
				fScore[neighbor.name] = gScore[neighbor.name] + (neighbor.position - endNode.position).Magnitude
			end
		end
	end

	return nil
end

-- ==============================================================================
-- DEBUG VISUAL - NODOS
-- ==============================================================================

function NavigationGraph:DebugDrawNodes(options)
	options = options or {}
	local color = options.color or Color3.fromRGB(0, 255, 0)
	local size = options.size or 0.5
	local transparency = options.transparency or 0.3
	local showLabels = options.showLabels ~= false
	
	-- Limpiar debug anterior
	local existingFolder = workspace:FindFirstChild("DEBUG_Nodes")
	if existingFolder then existingFolder:Destroy() end
	
	local folder = Instance.new("Folder")
	folder.Name = "DEBUG_Nodes"
	folder.Parent = workspace
	
	local count = 0
	
	for name, node in pairs(self.nodes) do
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
			billboard.Size = UDim2.new(0, 100, 0, 40)
			billboard.StudsOffset = Vector3.new(0, 1, 0)
			billboard.AlwaysOnTop = true
			billboard.Parent = sphere
			
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
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
				floorLabel.Size = UDim2.new(1, 0, 0.4, 0)
				floorLabel.Position = UDim2.new(0, 0, 0.6, 0)
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
	
	print("✅ Debug: " .. count .. " nodos visualizados")
	return folder
end

-- ==============================================================================
-- DEBUG VISUAL - CELDAS
-- ==============================================================================

function NavigationGraph:DebugDrawCells(options)
	if not self.spatialGrid then
		warn("⚠️ Spatial grid no construido")
		return
	end
	
	options = options or {}
	local color = options.color or Color3.fromRGB(100, 200, 255)
	local transparency = options.transparency or 0.85
	local wireframe = options.wireframe ~= false
	local showLabels = options.showLabels ~= false
	
	-- Limpiar debug anterior
	local existingFolder = workspace:FindFirstChild("DEBUG_Cells")
	if existingFolder then existingFolder:Destroy() end
	
	local folder = Instance.new("Folder")
	folder.Name = "DEBUG_Cells"
	folder.Parent = workspace
	
	local count = 0
	
	for cellKey, nodes in pairs(self.spatialGrid) do
		-- Parsear índices de celda desde la key
		local coords = string.split(cellKey, ",")
		local cellX = tonumber(coords[1])
		local cellY = tonumber(coords[2])
		local cellZ = tonumber(coords[3])

		-- Calcular posición central EXACTA de la celda desde su índice
		-- Fórmula: centro = índice × tamaño + tamaño/2 (desde origen workspace 0,0,0)
		local centerPos = Vector3.new(
			cellX * self.cellSizeX + self.cellSizeX / 2,
			cellY * self.cellSizeY + self.cellSizeY / 2,
			cellZ * self.cellSizeZ + self.cellSizeZ / 2
		)

		local cellSize = Vector3.new(self.cellSizeX, self.cellSizeY, self.cellSizeZ)
		
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
			billboard.Size = UDim2.new(0, 120, 0, 50)
			billboard.StudsOffset = Vector3.new(0, cellSize.Y / 2 + 1, 0)
			billboard.AlwaysOnTop = true
			billboard.Parent = cellPart
			
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
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
	
	print("✅ Debug: " .. count .. " celdas visualizadas")
	return folder
end

-- ==============================================================================
-- DEBUG VISUAL - CONEXIONES
-- ==============================================================================

function NavigationGraph:DebugDrawConnections(options)
	options = options or {}
	local color = options.color or Color3.fromRGB(153, 202, 255)
	local width = options.width or 0.1
	
	-- Limpiar debug anterior
	local existingFolder = workspace:FindFirstChild("DEBUG_Connections")
	if existingFolder then existingFolder:Destroy() end
	
	local folder = Instance.new("Folder")
	folder.Name = "DEBUG_Connections"
	folder.Parent = workspace
	
	local count = 0
	local drawnConnections = {}
	
	for name, node in pairs(self.nodes) do
		for _, connectedName in ipairs(node.connections) do
			-- Evitar dibujar la misma conexión dos veces
			local connectionKey1 = name .. "→" .. connectedName
			local connectionKey2 = connectedName .. "→" .. name
			
			if not drawnConnections[connectionKey1] and not drawnConnections[connectionKey2] then
				local connectedNode = self.nodes[connectedName]
				
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
	
	print("✅ Debug: " .. count .. " conexiones visualizadas")
	return folder
end

-- ==============================================================================
-- DEBUG VISUAL - TODO
-- ==============================================================================

function NavigationGraph:DebugDrawAll(options)
	options = options or {}
	
	print("\n" .. string.rep("=", 60))
	print("🎨 VISUALIZACIÓN COMPLETA DEL GRAFO")
	print(string.rep("=", 60))
	
	if options.showNodes ~= false then
		self:DebugDrawNodes({
			color = options.nodeColor,
			size = options.nodeSize,
			transparency = options.nodeTransparency,
			showLabels = true
		})
	end
	
	if options.showCells ~= false then
		self:DebugDrawCells({
			color = options.cellColor,
			transparency = options.cellTransparency,
			wireframe = options.cellWireframe,
			showLabels = true
		})
	end
	
	if options.showConnections ~= false then
		self:DebugDrawConnections({
			color = options.connectionColor,
			width = options.connectionWidth
		})
	end
	
	print(string.rep("=", 60) .. "\n")
end

function NavigationGraph:DebugClearAll()
	local folders = {
		"DEBUG_Nodes",
		"DEBUG_Cells",
		"DEBUG_Connections",
		"NavigationDebug"
	}
	
	local cleared = 0
	for _, folderName in ipairs(folders) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			folder:Destroy()
			cleared = cleared + 1
		end
	end
	
	print("🧹 Debug limpiado (" .. cleared .. " folders removidos)")
end

-- ==============================================================================
-- UTILIDADES
-- ==============================================================================

function NavigationGraph:GetNodesCount()
	local count = 0
	for _, node in pairs(self.nodes) do
		count += 1
	end
	return count
end

function NavigationGraph:GetConnectionCount()
	local count = 0
	for _, node in pairs(self.nodes) do
		count = count + #node.connections
	end
	return math.floor(count / 2)
end

function NavigationGraph:DebugPrint()
	print("📊 === NAVIGATION GRAPH DEBUG ===")
	print("Total nodos: " .. self:GetNodesCount())
	print("Total conexiones: " .. self:GetConnectionCount())

	-- Estadísticas del spatial hash
	if self.spatialGrid then
		local cellCount = 0
		local totalNodesInCells = 0
		for _, nodes in pairs(self.spatialGrid) do
			cellCount = cellCount + 1
			totalNodesInCells = totalNodesInCells + #nodes
		end
		print("🔲 Spatial Hash:")
		print("   Celdas ocupadas: " .. cellCount)
		print("   Nodos por celda (promedio): " .. string.format("%.1f", totalNodesInCells / cellCount))

		print("================================")
	end
end

return NavigationGraph
