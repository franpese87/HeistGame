local NavigationGraph = {}
NavigationGraph.__index = NavigationGraph

function NavigationGraph.new(config)
	local self = setmetatable({}, NavigationGraph)
	self.nodes = {}
	self.connections = {}

	config = config or {}

	-- Spatial hashing 2D por piso
	self.spatialGrids = {}  -- { [floor] = { ["x,z"] = {nodos} } }
	self.cellSizeX = config.cellSizeX or 16
	self.cellSizeZ = config.cellSizeZ or 14

	-- Configuración de altura de pisos (para inferir piso desde posición Y)
	self.floorHeight = config.floorHeight or 10
	self.floorBaseY = config.floorBaseY or 0

	-- Debug logging
	local debugConfig = config.debug or {}
	self.logFlags = {
		nodeSearch = debugConfig.nodeSearch or false,
		astar = debugConfig.astar or false,
		loading = debugConfig.loading or false,
	}

	return self
end

function NavigationGraph:Log(category, message)
	if self.logFlags[category] then
		print("[NavigationGraph][" .. category .. "] " .. message)
	end
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
-- CARGA DE NODOS DESDE ESTRUCTURA DE CARPETAS
-- ==============================================================================

--[[
	Estructura esperada:
	▼ NavigationNodes
	  ▼ Floor_0
	    ► (subcarpetas opcionales)
	    ● Nodos...
	  ▼ Floor_1
	    ● Nodos...
	  ▼ Stairs
	    ▼ Escalera_Principal
	      ● Nodos (requieren atributo 'floor' manual)
]]

function NavigationGraph:LoadFromFolderStructure(rootFolder, options)
	options = options or {}
	local shouldDestroyParts = options.destroyParts ~= false

	if not rootFolder then
		warn("NavigationGraph: Carpeta raíz no proporcionada")
		return nil
	end

	local stats = {
		loaded = 0,
		discarded = 0,
		floors = {},
		stairs = 0,
	}

	-- Procesar carpetas Floor_X
	for _, folder in ipairs(rootFolder:GetChildren()) do
		if folder:IsA("Folder") then
			local folderName = folder.Name

			-- Detectar carpetas Floor_X
			if string.match(folderName, "^Floor_%-?%d+") then
				local floorNumber = tonumber(string.match(folderName, "Floor_(%-?%d+)"))
				if floorNumber then
					self:Log("loading", "Procesando " .. folderName .. " (floor=" .. floorNumber .. ")")
					local count = self:LoadNodesFromFolder(folder, {
						floor = floorNumber,
						isStair = false,
					}, rootFolder)
					stats.loaded = stats.loaded + count
					stats.floors[floorNumber] = (stats.floors[floorNumber] or 0) + count
				end

			-- Detectar carpeta Stairs
			elseif folderName == "Stairs" then
				self:Log("loading", "Procesando carpeta Stairs")
				local count = self:LoadNodesFromFolder(folder, {
					isStair = true,
					-- floor se lee del atributo manual de cada nodo
				}, rootFolder)
				stats.loaded = stats.loaded + count
				stats.stairs = count
			end
		end
	end

	-- Construir spatial hash 2D después de cargar
	self:BuildSpatialHash2D()

	-- Limpiar Parts si se solicita
	if shouldDestroyParts then
		rootFolder:Destroy()
	else
		self:SetPartsDebugMode(rootFolder)
	end

	-- Log resumen
	local floorList = {}
	for floor, count in pairs(stats.floors) do
		table.insert(floorList, "F" .. floor .. ":" .. count)
	end
	table.sort(floorList)

	print("NavigationGraph: " .. stats.loaded .. " nodos cargados (" ..
		table.concat(floorList, ", ") ..
		(stats.stairs > 0 and (", Stairs:" .. stats.stairs) or "") .. ")")

	if stats.discarded > 0 then
		warn("NavigationGraph: " .. stats.discarded .. " nodos descartados por colisión")
	end

	return stats
end

-- Función auxiliar: Carga nodos recursivamente desde una carpeta
function NavigationGraph:LoadNodesFromFolder(folder, inheritedMetadata, rootFolder)
	local count = 0

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			-- Validar posición
			if self:IsPositionWalkable(child.Position, rootFolder) then
				-- Construir metadata
				local metadata = {
					floor = inheritedMetadata.floor or child:GetAttribute("floor") or 0,
					isStair = inheritedMetadata.isStair or false,
				}

				-- Para nodos de escalera, el floor DEBE venir del atributo manual
				if inheritedMetadata.isStair then
					local manualFloor = child:GetAttribute("floor")
					if manualFloor == nil then
						warn("NavigationGraph: Nodo de escalera '" .. child.Name .. "' sin atributo 'floor'")
					end
					metadata.floor = manualFloor or 0
				end

				self:AddNode(child.Name, child.Position, metadata)
				count = count + 1
			end

		elseif child:IsA("Folder") then
			-- Recursión en subcarpetas
			count = count + self:LoadNodesFromFolder(child, inheritedMetadata, rootFolder)
		end
	end

	return count
end

-- Función auxiliar: Modo debug para Parts (transparentes, sin colisión)
function NavigationGraph:SetPartsDebugMode(folder)
	for _, child in ipairs(folder:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Transparency = 0.8
			child.CanCollide = false
			child.CanQuery = false
		end
	end
end

-- ==============================================================================
-- CARGA DE NODOS DESDE PARTS (LEGACY - mantener compatibilidad)
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
				-- Leer metadata de atributos si existen (soporta ambas capitalizaciones)
				local metadata = {
					floor = part:GetAttribute("floor") or part:GetAttribute("Floor") or 0,
					isStair = part:GetAttribute("isStair") or part:GetAttribute("IsStair") or false,
				}

				-- Guardar en memoria solo si es válido
				self:AddNode(part.Name, part.Position, metadata)
				table.insert(loadedNodes, part.Name)
			else
				-- Descartar nodo por colisión con geometría
				table.insert(discardedNodes, part.Name)
			end
		end
	end
	
	-- Destruir o transparentar las Parts
	if shouldDestroyParts then
		partsFolder:Destroy()
	else
		-- Hacerlas transparentes para debug
		for _, part in ipairs(partsFolder:GetChildren()) do
			if part:IsA("BasePart") then
				part.Transparency = 0.8
				part.CanCollide = false
				part.CanQuery = false
			end
		end
	end

	-- Construir spatial hash automáticamente después de cargar nodos
	self:BuildSpatialHash2D()

	-- Warn solo si hay nodos descartados
	if #discardedNodes > 0 then
		warn("NavigationGraph: " .. #discardedNodes .. " nodos descartados por colisión")
	end

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
-- AUTO-CONEXIÓN (Optimizada para arquitectura 2.5D)
-- ==============================================================================

--[[
	AutoConnect genera conexiones entre nodos siguiendo estas reglas:

	1. Nodos del mismo piso: Se conectan si están dentro de maxDistance y
	   tienen línea de visión (si useRaycast=true)

	2. Nodos de escalera: Se conectan entre sí (dentro de la misma escalera)
	   Y con nodos de piso adyacentes

	3. Conexiones entre pisos: Solo ocurren a través de nodos de escalera
]]
function NavigationGraph:AutoConnect(options)
	options = options or {}
	local maxDistance = options.maxDistance or 20
	local maxStairDistance = options.maxStairDistance or 10
	local useRaycast = options.useRaycast or false
	local maxConnectionsPerNode = options.maxConnectionsPerNode or 6
	local ignoreList = options.ignoreList or {}

	local stats = {
		sameFloor = 0,
		stairConnections = 0,
		total = 0,
	}

	-- Agrupar nodos por piso para optimizar búsqueda
	local nodesByFloor = {}
	local stairNodes = {}

	for _, node in pairs(self.nodes) do
		local floor = node.metadata.floor or 0

		if node.metadata.isStair then
			table.insert(stairNodes, node)
		end

		if not nodesByFloor[floor] then
			nodesByFloor[floor] = {}
		end
		table.insert(nodesByFloor[floor], node)
	end

	-- FASE 1: Conectar nodos dentro del mismo piso
	for _, nodesInFloor in pairs(nodesByFloor) do
		for _, fromNode in ipairs(nodesInFloor) do
			local candidates = {}

			for _, toNode in ipairs(nodesInFloor) do
				if fromNode.name ~= toNode.name then
					local distance = (fromNode.position - toNode.position).Magnitude

					if distance <= maxDistance then
						local canConnect = self:CanConnect(fromNode, toNode, useRaycast, ignoreList)

						if canConnect then
							table.insert(candidates, {node = toNode, distance = distance})
						end
					end
				end
			end

			-- Ordenar por distancia y conectar los más cercanos
			table.sort(candidates, function(a, b)
				return a.distance < b.distance
			end)

			local connectionsForNode = #fromNode.connections
			for _, candidate in ipairs(candidates) do
				if connectionsForNode >= maxConnectionsPerNode then break end

				if not table.find(fromNode.connections, candidate.node.name) then
					self:AddConnection(fromNode.name, candidate.node.name, true)
					stats.sameFloor = stats.sameFloor + 1
					stats.total = stats.total + 1
					connectionsForNode = connectionsForNode + 1
				end
			end
		end
	end

	-- FASE 2: Conectar nodos de escalera con nodos de piso adyacentes
	for _, stairNode in ipairs(stairNodes) do
		local stairFloor = stairNode.metadata.floor or 0
		local nodesInFloor = nodesByFloor[stairFloor] or {}

		for _, floorNode in ipairs(nodesInFloor) do
			if stairNode.name ~= floorNode.name and not floorNode.metadata.isStair then
				local distance = (stairNode.position - floorNode.position).Magnitude

				if distance <= maxStairDistance then
					local canConnect = self:CanConnect(stairNode, floorNode, useRaycast, ignoreList)

					if canConnect and not table.find(stairNode.connections, floorNode.name) then
						self:AddConnection(stairNode.name, floorNode.name, true)
						stats.stairConnections = stats.stairConnections + 1
						stats.total = stats.total + 1
					end
				end
			end
		end
	end

	-- FASE 3: Conectar nodos de escalera entre sí (del mismo grupo de escalera)
	for i, stairNode1 in ipairs(stairNodes) do
		for j, stairNode2 in ipairs(stairNodes) do
			if i < j then
				local distance = (stairNode1.position - stairNode2.position).Magnitude

				if distance <= maxStairDistance then
					local canConnect = self:CanConnect(stairNode1, stairNode2, useRaycast, ignoreList)

					if canConnect and not table.find(stairNode1.connections, stairNode2.name) then
						self:AddConnection(stairNode1.name, stairNode2.name, true)
						stats.stairConnections = stats.stairConnections + 1
						stats.total = stats.total + 1
					end
				end
			end
		end
	end

	self:Log("loading", "AutoConnect: " .. stats.total .. " conexiones (" ..
		stats.sameFloor .. " mismo piso, " ..
		stats.stairConnections .. " escaleras)")

	return stats.total
end

-- Función auxiliar: Verificar si dos nodos pueden conectarse
function NavigationGraph:CanConnect(fromNode, toNode, useRaycast, ignoreList)
	if not useRaycast then
		return true
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignoreList or {}

	local direction = toNode.position - fromNode.position
	local result = workspace:Raycast(fromNode.position, direction, rayParams)

	-- Si no hay hit, o el hit está más lejos que el destino, hay línea de visión
	if not result then
		return true
	end

	local hitDistance = (result.Position - fromNode.position).Magnitude
	local targetDistance = direction.Magnitude

	return hitDistance >= targetDistance * 0.95
end

-- ==============================================================================
-- SPATIAL HASHING 2D POR PISO
-- ==============================================================================

function NavigationGraph:BuildSpatialHash2D()
	self.spatialGrids = {}

	-- Construir una rejilla 2D (X,Z) por cada piso
	for _, node in pairs(self.nodes) do
		local floor = node.metadata.floor or 0

		-- Crear rejilla para este piso si no existe
		if not self.spatialGrids[floor] then
			self.spatialGrids[floor] = {}
		end

		-- Calcular celda 2D (solo X y Z)
		local cellX = math.floor(node.position.X / self.cellSizeX)
		local cellZ = math.floor(node.position.Z / self.cellSizeZ)
		local cellKey = cellX .. "," .. cellZ

		if not self.spatialGrids[floor][cellKey] then
			self.spatialGrids[floor][cellKey] = {}
		end

		table.insert(self.spatialGrids[floor][cellKey], node)
	end

	-- Log estadísticas
	local floorCount = 0
	local totalCells = 0
	for _, grid in pairs(self.spatialGrids) do
		floorCount = floorCount + 1
		for _ in pairs(grid) do
			totalCells = totalCells + 1
		end
	end

	self:Log("loading", "SpatialHash2D: " .. floorCount .. " pisos, " .. totalCells .. " celdas totales")
end

-- Función auxiliar: Inferir piso desde posición Y
function NavigationGraph:GetFloorFromPosition(position)
	return math.floor((position.Y - self.floorBaseY) / self.floorHeight)
end

-- Obtener estadísticas del spatial hash
function NavigationGraph:GetSpatialHashStats()
	local stats = {
		floors = {},
		totalCells = 0,
		totalNodes = 0,
	}

	for floor, grid in pairs(self.spatialGrids) do
		local cellCount = 0
		local nodeCount = 0

		for _, nodes in pairs(grid) do
			cellCount = cellCount + 1
			nodeCount = nodeCount + #nodes
		end

		stats.floors[floor] = {
			cells = cellCount,
			nodes = nodeCount,
			avgNodesPerCell = cellCount > 0 and (nodeCount / cellCount) or 0,
		}
		stats.totalCells = stats.totalCells + cellCount
		stats.totalNodes = stats.totalNodes + nodeCount
	end

	return stats
end

-- ==============================================================================
-- BÚSQUEDA DE NODOS (CON SPATIAL HASHING 2D)
-- ==============================================================================

--[[
	GetNearestNode busca el nodo más cercano usando spatial hash 2D.

	Parámetros:
	- position: Vector3 de la posición a buscar
	- floor: (opcional) Número de piso. Si no se proporciona, se infiere de position.Y
	- options: (opcional) Tabla con opciones adicionales:
	    - searchAllFloors: Si true, busca en todos los pisos (para pathfinding entre pisos)
	    - includeStairs: Si true, incluye nodos de escalera en la búsqueda
]]
function NavigationGraph:GetNearestNode(position, floor, options)
	options = options or {}

	-- Inferir piso si no se proporciona
	if floor == nil then
		floor = self:GetFloorFromPosition(position)
	end

	-- Si no hay spatial hash o se pide buscar en todos los pisos, usar búsqueda especial
	if not self.spatialGrids or not next(self.spatialGrids) then
		self:Log("nodeSearch", "SpatialGrids vacío, usando búsqueda linear")
		return self:GetNearestNodeLinear(position, floor, options)
	end

	-- Búsqueda en el piso especificado
	local result = self:SearchFloorGrid(position, floor)

	-- Si no encontramos nada y se permite buscar en otros pisos
	if not result.node and options.searchAllFloors then
		self:Log("nodeSearch", "No encontrado en floor " .. floor .. ", buscando en otros pisos")
		result = self:GetNearestNodeLinear(position, nil, options)
	end

	-- Log resultado
	if result.node then
		self:Log("nodeSearch", "Encontrado: " .. result.node.name ..
			" (floor=" .. (result.node.metadata.floor or "?") ..
			", dist=" .. string.format("%.1f", result.distance) ..
			", checked=" .. result.nodesChecked .. ")")
	else
		self:Log("nodeSearch", "NO ENCONTRADO cerca de " ..
			string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z) ..
			" floor=" .. floor)
	end

	return result.node
end

-- Búsqueda optimizada en la rejilla 2D de un piso específico
function NavigationGraph:SearchFloorGrid(position, floor)
	local result = {
		node = nil,
		distance = math.huge,
		nodesChecked = 0,
	}

	local grid = self.spatialGrids[floor]
	if not grid then
		return result
	end

	local cellX = math.floor(position.X / self.cellSizeX)
	local cellZ = math.floor(position.Z / self.cellSizeZ)

	-- Buscar en 3x3 grid (9 celdas vecinas) - 3x más rápido que 3D
	for dx = -1, 1 do
		for dz = -1, 1 do
			local key = (cellX + dx) .. "," .. (cellZ + dz)
			local nodesInCell = grid[key]

			if nodesInCell then
				for _, node in ipairs(nodesInCell) do
					result.nodesChecked = result.nodesChecked + 1
					local distance = (node.position - position).Magnitude

					if distance < result.distance then
						result.distance = distance
						result.node = node
					end
				end
			end
		end
	end

	return result
end

-- Búsqueda linear (fallback o para búsquedas entre pisos)
function NavigationGraph:GetNearestNodeLinear(position, floor, options)
	options = options or {}
	local result = {
		node = nil,
		distance = math.huge,
		nodesChecked = 0,
	}

	for _, node in pairs(self.nodes) do
		-- Filtrar por piso si se especifica
		if floor == nil or node.metadata.floor == floor then
			result.nodesChecked = result.nodesChecked + 1
			local distance = (node.position - position).Magnitude

			if distance < result.distance then
				result.distance = distance
				result.node = node
			end
		end
	end

	return result.node, result
end

-- ==============================================================================
-- PATHFINDING (A*)
-- ==============================================================================

function NavigationGraph:GetPathBetweenNodes(startNode, endNode)
	if not startNode or not endNode then
		self:Log("astar", "A* ABORTADO: nodos nil")
		return nil
	end
	if startNode.name == endNode.name then
		self:Log("astar", "A* TRIVIAL: mismo nodo")
		return {endNode}
	end

	local openSet = {startNode}
	local closedSet = {}
	local cameFrom = {}
	local gScore = {[startNode.name] = 0}
	local fScore = {[startNode.name] = (startNode.position - endNode.position).Magnitude}
	local iterations = 0
	local maxIterations = 500 -- Prevenir loops infinitos

	while #openSet > 0 do
		iterations = iterations + 1
		if iterations > maxIterations then
			self:Log("astar", "A* TIMEOUT: " .. startNode.name .. " → " .. endNode.name .. " (>" .. maxIterations .. " iteraciones)")
			return nil
		end

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
			self:Log("astar", "A* OK: " .. startNode.name .. " → " .. endNode.name .. " (" .. #path .. " nodos, " .. iterations .. " iter)")
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

	self:Log("astar", "A* FALLIDO: " .. startNode.name .. " → " .. endNode.name .. " (sin ruta, " .. iterations .. " iter, " .. #closedSet .. " explorados)")
	return nil
end

-- ==============================================================================
-- UTILIDADES
-- ==============================================================================

function NavigationGraph:GetNodesCount()
	local count = 0
	for _ in pairs(self.nodes) do
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


return NavigationGraph
