local NavigationGraph = {}
NavigationGraph.__index = NavigationGraph

function NavigationGraph.new(config)
	local self = setmetatable({}, NavigationGraph)
	self.nodes = {}
	self.connections = {}

	config = config or {}

	-- Spatial hashing 3D unificado: { ["x,y,z"] = {nodos} }
	-- Usa posiciones reales del grafo, sin depender del número de piso
	self.spatialGrid3D = {}
	self.cellSizeX = config.cellSizeX or 16
	self.cellSizeY = config.cellSizeY or 10   -- Resolución vertical: suficiente para separar pisos (≥2× la varianza Y de los nodos de un piso)
	self.cellSizeZ = config.cellSizeZ or 14

	-- Parámetros legacy (mantenidos para backward compat, ya no se usan en búsquedas)
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

function NavigationGraph:LoadFromFolderStructure(rootFolder, keepSourceParts)
	if not rootFolder then
		warn("NavigationGraph: Carpeta raíz no proporcionada")
		return nil
	end

	local stats = {
		loaded = 0,
		discarded = 0,
		floors = {},
		stairs = 0,
		connections = 0,
	}

	-- Lista de conexiones pendientes para procesar después de cargar todos los nodos
	local pendingConnections = {}

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
					}, rootFolder, pendingConnections)
					stats.loaded = stats.loaded + count
					stats.floors[floorNumber] = (stats.floors[floorNumber] or 0) + count
				end

			-- Detectar carpeta Stairs
			elseif folderName == "Stairs" then
				self:Log("loading", "Procesando carpeta Stairs")
				local count = self:LoadNodesFromFolder(folder, {
					isStair = true,
					-- floor se lee del atributo manual de cada nodo
				}, rootFolder, pendingConnections)
				stats.loaded = stats.loaded + count
				stats.stairs = count
			end
		end
	end

	-- Cargar conexiones desde los atributos
	-- Se fuerza bidireccionalidad en runtime: el plugin almacena conexiones por orden
	-- de distancia cortadas en MAX_CONNECTIONS_PER_NODE, lo que puede generar aristas
	-- unidireccionales (ej. gateway A→B existe pero B→A fue eliminado por el límite).
	-- Añadir la inversa garantiza que A* pueda recorrer el grafo en ambas direcciones.
	for _, conn in ipairs(pendingConnections) do
		local fromNode = self.nodes[conn.from]
		local toNode = self.nodes[conn.to]

		if fromNode and toNode then
			if not table.find(fromNode.connections, conn.to) then
				table.insert(fromNode.connections, conn.to)
				stats.connections = stats.connections + 1
			end
			-- Dirección inversa: garantiza bidireccionalidad aunque el plugin no la almacenara
			if not table.find(toNode.connections, conn.from) then
				table.insert(toNode.connections, conn.from)
			end
		end
	end

	-- Construir spatial hash 3D después de cargar
	self:BuildSpatialHash3D()

	-- Limpiar Parts originales (solo si no se mantienen para debug)
	if not keepSourceParts then
		rootFolder:Destroy()
	end

	-- Log resumen
	local floorList = {}
	for floor, count in pairs(stats.floors) do
		table.insert(floorList, "F" .. floor .. ":" .. count)
	end
	table.sort(floorList)

	print("NavigationGraph: " .. stats.loaded .. " nodos cargados (" ..
		table.concat(floorList, ", ") ..
		(stats.stairs > 0 and (", Stairs:" .. stats.stairs) or "") ..
		(keepSourceParts and ", Parts mantenidas" or "") .. "), " ..
		stats.connections .. " conexiones")

	if stats.discarded > 0 then
		warn("NavigationGraph: " .. stats.discarded .. " nodos descartados por colisión")
	end

	return stats
end

-- Función auxiliar: Carga nodos recursivamente desde una carpeta
function NavigationGraph:LoadNodesFromFolder(folder, inheritedMetadata, rootFolder, pendingConnections)
	local count = 0

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			-- Solo cargar nodos marcados como walkable por el plugin
			if child:GetAttribute("walkable") == true then
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

				-- Leer conexiones del atributo (generadas por el plugin)
				local connectionsStr = child:GetAttribute("connections")
				if connectionsStr and connectionsStr ~= "" then
					for _, connName in ipairs(string.split(connectionsStr, ",")) do
						table.insert(pendingConnections, {
							from = child.Name,
							to = connName
						})
					end
				end
			end

		elseif child:IsA("Folder") then
			-- Recursión en subcarpetas
			count = count + self:LoadNodesFromFolder(child, inheritedMetadata, rootFolder, pendingConnections)
		end
	end

	return count
end

-- ==============================================================================
-- CARGA DE NODOS DESDE PARTS (LEGACY - mantener compatibilidad)
-- ==============================================================================

function NavigationGraph:LoadFromParts(partsFolder, keepSourceParts)
	if not partsFolder then
		warn("⚠️ Folder de nodos no proporcionado")
		return
	end

	local loadedNodes = {}
	local discardedNodes = {}

	for _, part in ipairs(partsFolder:GetChildren()) do
		if part:IsA("BasePart") then
			-- Solo cargar nodos marcados como walkable por el plugin
			if part:GetAttribute("walkable") == true then
				-- Leer metadata de atributos si existen
				local metadata = {
					floor = part:GetAttribute("floor") or 0,
					isStair = part:GetAttribute("isStair") or false,
				}

				self:AddNode(part.Name, part.Position, metadata)
				table.insert(loadedNodes, part.Name)
			else
				table.insert(discardedNodes, part.Name)
			end
		end
	end

	-- Destruir las Parts originales (solo si no se mantienen para debug)
	if not keepSourceParts then
		partsFolder:Destroy()
	end

	-- Construir spatial hash 3D automáticamente después de cargar nodos
	self:BuildSpatialHash3D()

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

function NavigationGraph:BuildSpatialHash3D()
	self.spatialGrid3D = {}
	self.floorYRanges = {}  -- { [floor] = { minY, maxY, avgY } } — mantenido para GetFloorFromPosition

	-- Primer paso: calcular rangos Y reales por piso (para GetFloorFromPosition)
	for _, node in pairs(self.nodes) do
		local floor = node.metadata.floor or 0
		if not self.floorYRanges[floor] then
			self.floorYRanges[floor] = { minY = math.huge, maxY = -math.huge, sumY = 0, count = 0 }
		end
		local r = self.floorYRanges[floor]
		if node.position.Y < r.minY then
			r.minY = node.position.Y
		end
		if node.position.Y > r.maxY then
			r.maxY = node.position.Y
		end
		r.sumY = r.sumY + node.position.Y
		r.count = r.count + 1
	end
	for _, r in pairs(self.floorYRanges) do
		r.avgY = r.sumY / r.count
	end

	-- Segundo paso: construir rejilla 3D (X, Y, Z)
	-- cellSizeY controla la resolución vertical: debe separar pisos apilados
	-- sin fragmentar un mismo piso (default: 4 studs)
	for _, node in pairs(self.nodes) do
		local cellX = math.floor(node.position.X / self.cellSizeX)
		local cellY = math.floor(node.position.Y / self.cellSizeY)
		local cellZ = math.floor(node.position.Z / self.cellSizeZ)
		local cellKey = cellX .. "," .. cellY .. "," .. cellZ

		if not self.spatialGrid3D[cellKey] then
			self.spatialGrid3D[cellKey] = {}
		end

		table.insert(self.spatialGrid3D[cellKey], node)
	end

	-- Log estadísticas
	local totalCells = 0
	local totalNodes = 0
	for _, nodes in pairs(self.spatialGrid3D) do
		totalCells = totalCells + 1
		totalNodes = totalNodes + #nodes
	end

	self:Log("loading", "SpatialHash3D: " .. totalCells .. " celdas, " .. totalNodes
		.. " nodos (cellSizeY=" .. self.cellSizeY .. ")")
end

--[[
	GetFloorFromPosition - Infiere el piso más probable a partir de la posición Y.

	Usa los rangos Y reales de los nodos cargados. Si varios pisos están a la
	misma altura (zonas distintas), este método puede no ser determinista;
	en ese caso se recomienda usar GetNearestNode sin parámetro floor para que
	busque automáticamente en todos los pisos.
]]
function NavigationGraph:GetFloorFromPosition(position)
	if self.floorYRanges and next(self.floorYRanges) then
		local bestFloor = nil
		local bestDist = math.huge
		for floor, range in pairs(self.floorYRanges) do
			local dist = math.abs(position.Y - range.avgY)
			if dist < bestDist then
				bestDist = dist
				bestFloor = floor
			end
		end
		return bestFloor or 0
	end
	-- Fallback: fórmula legacy (solo útil si los pisos están apilados verticalmente)
	return math.floor((position.Y - self.floorBaseY) / self.floorHeight)
end

-- Obtener estadísticas del spatial hash
function NavigationGraph:GetSpatialHashStats()
	local stats = {
		totalCells = 0,
		totalNodes = 0,
		avgNodesPerCell = 0,
	}

	for _, nodes in pairs(self.spatialGrid3D) do
		stats.totalCells = stats.totalCells + 1
		stats.totalNodes = stats.totalNodes + #nodes
	end

	if stats.totalCells > 0 then
		stats.avgNodesPerCell = stats.totalNodes / stats.totalCells
	end

	return stats
end

-- ==============================================================================
-- BÚSQUEDA DE NODOS (CON SPATIAL HASHING 2D)
-- ==============================================================================

--[[
	GetNearestNode busca el nodo más cercano usando spatial hash 3D.

	Parámetros:
	- position: Vector3 de la posición a buscar
	- floor: (opcional) Si se especifica, solo devuelve nodos de ese piso
	- options: (opcional) Tabla con opciones adicionales (reservado para uso futuro)
]]
function NavigationGraph:GetNearestNode(position, floor, _options)
	if not self.spatialGrid3D or not next(self.spatialGrid3D) then
		self:Log("nodeSearch", "SpatialGrid3D vacío, usando búsqueda linear")
		return self:GetNearestNodeLinear(position, floor)
	end

	local result = self:SearchGrid3D(position)

	-- Si se especifica floor, verificar que el resultado coincide
	-- Si no coincide, buscar el más cercano en ese floor específico
	if floor ~= nil and result.node and result.node.metadata.floor ~= floor then
		result.node = self:GetNearestNodeLinear(position, floor)
		result.distance = result.node and (result.node.position - position).Magnitude or math.huge
	end

	-- Fallback linear si el 3D hash no encontró nada (celdas vacías)
	if not result.node then
		result.node = self:GetNearestNodeLinear(position, floor)
	end

	-- Log resultado
	if result.node then
		self:Log("nodeSearch", "Encontrado: " .. result.node.name ..
			" (floor=" .. (result.node.metadata.floor or "?") ..
			", dist=" .. string.format("%.1f", result.distance) ..
			", checked=" .. result.nodesChecked .. ")")
	else
		self:Log("nodeSearch", "NO ENCONTRADO cerca de " ..
			string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z))
	end

	return result.node
end

-- Búsqueda en la rejilla 3D (vecindad 3×3×3 = 27 celdas)
function NavigationGraph:SearchGrid3D(position)
	local result = {
		node = nil,
		distance = math.huge,
		nodesChecked = 0,
	}

	local cellX = math.floor(position.X / self.cellSizeX)
	local cellY = math.floor(position.Y / self.cellSizeY)
	local cellZ = math.floor(position.Z / self.cellSizeZ)

	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local key = (cellX + dx) .. "," .. (cellY + dy) .. "," .. (cellZ + dz)
				local nodesInCell = self.spatialGrid3D[key]

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
	end

	return result
end

--[[
	GetNearestNodeCandidates - Devuelve hasta maxResults nodos cercanos ordenados por distancia.

	Usado como fallback cuando A* falla con el nodo más cercano: permite al caller
	iterar por candidatos alternativos hasta encontrar uno conectado al destino.
]]
function NavigationGraph:GetNearestNodeCandidates(position, maxResults)
	maxResults = maxResults or 5

	local cellX = math.floor(position.X / self.cellSizeX)
	local cellY = math.floor(position.Y / self.cellSizeY)
	local cellZ = math.floor(position.Z / self.cellSizeZ)

	local candidates = {}

	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local key = (cellX + dx) .. "," .. (cellY + dy) .. "," .. (cellZ + dz)
				local nodesInCell = self.spatialGrid3D[key]
				if nodesInCell then
					for _, node in ipairs(nodesInCell) do
						table.insert(candidates, {
							node = node,
							distance = (node.position - position).Magnitude,
						})
					end
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	local result = {}
	for i = 1, math.min(maxResults, #candidates) do
		result[i] = candidates[i].node
	end
	return result
end

-- Búsqueda linear (fallback o para búsquedas entre pisos)
function NavigationGraph:GetNearestNodeLinear(position, floor)
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
-- BÚSQUEDA DE NODO ÓPTIMO HACIA TARGET
-- ==============================================================================

--[[
	GetNearestNodeTowardsTarget busca el mejor nodo de inicio para pathfinding
	cuando el NPC está en una intersección de múltiples nodos equidistantes.

	En lugar de elegir el nodo más cercano al NPC, busca candidatos cercanos
	y selecciona el que esté más cerca del target (mejor dirección).

	Parámetros:
	- npcPosition: Vector3 posición actual del NPC
	- targetPosition: Vector3 posición del objetivo
	- floor: (opcional) Número de piso
	- candidateRadius: (opcional) Radio para buscar nodos candidatos (default: 8)
]]
function NavigationGraph:GetNearestNodeTowardsTarget(npcPosition, targetPosition, floor, candidateRadius)
	candidateRadius = candidateRadius or 8  -- Debe ser mayor que la separación entre nodos (7 studs)

	local cellX = math.floor(npcPosition.X / self.cellSizeX)
	local cellY = math.floor(npcPosition.Y / self.cellSizeY)
	local cellZ = math.floor(npcPosition.Z / self.cellSizeZ)

	-- Recolectar candidatos en vecindad 3×3×3 del spatial hash 3D
	local candidates = {}

	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local key = (cellX + dx) .. "," .. (cellY + dy) .. "," .. (cellZ + dz)
				local nodesInCell = self.spatialGrid3D[key]
				if nodesInCell then
					for _, node in ipairs(nodesInCell) do
						-- Filtrar por piso si se especificó
						if floor == nil or node.metadata.floor == floor then
							local distToNpc = (node.position - npcPosition).Magnitude
							if distToNpc <= candidateRadius then
								table.insert(candidates, {
									node = node,
									distToNpc = distToNpc,
									distToTarget = (node.position - targetPosition).Magnitude,
								})
							end
						end
					end
				end
			end
		end
	end

	-- Si no hay candidatos, usar método estándar (sin restricción de piso)
	if #candidates == 0 then
		self:Log("nodeSearch", "No candidates in radius " .. candidateRadius .. ", using standard search")
		return self:GetNearestNode(npcPosition, floor)
	end

	-- Si solo hay un candidato, devolverlo
	if #candidates == 1 then
		return candidates[1].node
	end

	-- Filtrar: solo mantener los que están cerca del mínimo (dentro de 2 studs del más cercano)
	table.sort(candidates, function(a, b)
		return a.distToNpc < b.distToNpc
	end)

	local minDistToNpc = candidates[1].distToNpc
	local closeCandidates = {}

	for _, candidate in ipairs(candidates) do
		-- Considerar "cercanos" los que estén a menos de 2 studs de diferencia del más cercano
		if candidate.distToNpc <= minDistToNpc + 2 then
			table.insert(closeCandidates, candidate)
		end
	end

	-- Entre los candidatos cercanos, elegir el que esté más cerca del target
	local bestCandidate = closeCandidates[1]
	for _, candidate in ipairs(closeCandidates) do
		if candidate.distToTarget < bestCandidate.distToTarget then
			bestCandidate = candidate
		end
	end

	self:Log("nodeSearch", "TowardsTarget: " .. #candidates .. " candidates, " ..
		#closeCandidates .. " close, selected " .. bestCandidate.node.name ..
		" (distNpc=" .. string.format("%.1f", bestCandidate.distToNpc) ..
		", distTarget=" .. string.format("%.1f", bestCandidate.distToTarget) .. ")")

	return bestCandidate.node
end

-- ==============================================================================
-- MIN-HEAP (Binary Heap para A* open set)
-- ==============================================================================
-- Extrae el nodo con menor fScore en O(log n) en lugar de O(n log n) con sort.
-- Estructura: array donde heap[1] siempre es el mínimo.
-- Hijo izquierdo de i = 2i, hijo derecho = 2i+1, padre de i = floor(i/2).

local MinHeap = {}
MinHeap.__index = MinHeap

function MinHeap.new()
	return setmetatable({
		data = {},      -- Array de nodos
		index = {},     -- nodeName → posición en data (para decrease-key O(log n))
		size = 0,
	}, MinHeap)
end

function MinHeap:Insert(node, priority)
	self.size = self.size + 1
	self.data[self.size] = {node = node, priority = priority}
	self.index[node.name] = self.size
	self:_siftUp(self.size)
end

function MinHeap:Pop()
	if self.size == 0 then return nil end

	local top = self.data[1]
	self.index[top.node.name] = nil

	if self.size == 1 then
		self.data[1] = nil
		self.size = 0
		return top.node
	end

	self.data[1] = self.data[self.size]
	self.data[self.size] = nil
	self.size = self.size - 1
	self.index[self.data[1].node.name] = 1
	self:_siftDown(1)

	return top.node
end

function MinHeap:DecreasePriority(nodeName, newPriority)
	local pos = self.index[nodeName]
	if not pos then return end
	self.data[pos].priority = newPriority
	self:_siftUp(pos)
end

function MinHeap:Contains(nodeName)
	return self.index[nodeName] ~= nil
end

function MinHeap:IsEmpty()
	return self.size == 0
end

function MinHeap:_siftUp(pos)
	local data = self.data
	local index = self.index
	local entry = data[pos]

	while pos > 1 do
		local parentPos = math.floor(pos / 2)
		local parent = data[parentPos]

		if entry.priority >= parent.priority then
			break
		end

		data[pos] = parent
		index[parent.node.name] = pos
		pos = parentPos
	end

	data[pos] = entry
	index[entry.node.name] = pos
end

function MinHeap:_siftDown(pos)
	local data = self.data
	local index = self.index
	local size = self.size
	local entry = data[pos]

	while true do
		local left = pos * 2
		local right = left + 1
		local smallest = pos

		if left <= size and data[left].priority < data[smallest].priority then
			smallest = left
		end
		if right <= size and data[right].priority < data[smallest].priority then
			smallest = right
		end

		if smallest == pos then
			break
		end

		data[pos] = data[smallest]
		index[data[pos].node.name] = pos
		pos = smallest
	end

	data[pos] = entry
	index[entry.node.name] = pos
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

	local openSet = MinHeap.new()
	local closedSet = {}  -- Diccionario: closedSet[nodeName] = true
	local cameFrom = {}
	local gScore = {[startNode.name] = 0}

	local startF = (startNode.position - endNode.position).Magnitude
	openSet:Insert(startNode, startF)

	local iterations = 0
	local maxIterations = 500

	while not openSet:IsEmpty() do
		iterations = iterations + 1
		if iterations > maxIterations then
			self:Log("astar", "A* TIMEOUT: " .. startNode.name .. " → " .. endNode.name .. " (>" .. maxIterations .. " iteraciones)")
			return nil
		end

		local current = openSet:Pop()

		if current.name == endNode.name then
			local path = {current}
			while cameFrom[current.name] do
				current = cameFrom[current.name]
				table.insert(path, 1, current)
			end
			self:Log("astar", "A* OK: " .. startNode.name .. " → " .. endNode.name .. " (" .. #path .. " nodos, " .. iterations .. " iter)")
			return path
		end

		closedSet[current.name] = true

		for _, neighborName in ipairs(current.connections) do
			local neighbor = self.nodes[neighborName]

			if neighbor and not closedSet[neighborName] then
				local tentative_gScore = gScore[current.name] + (current.position - neighbor.position).Magnitude

				if not openSet:Contains(neighborName) then
					gScore[neighborName] = tentative_gScore
					local f = tentative_gScore + (neighbor.position - endNode.position).Magnitude
					openSet:Insert(neighbor, f)
					cameFrom[neighborName] = current
				elseif tentative_gScore < (gScore[neighborName] or math.huge) then
					gScore[neighborName] = tentative_gScore
					local f = tentative_gScore + (neighbor.position - endNode.position).Magnitude
					openSet:DecreasePriority(neighborName, f)
					cameFrom[neighborName] = current
				end
			end
		end
	end

	local closedCount = 0
	for _ in pairs(closedSet) do
		closedCount = closedCount + 1
	end
	self:Log("astar", "A* FALLIDO: " .. startNode.name .. " → " .. endNode.name .. " (sin ruta, " .. iterations .. " iter, " .. closedCount .. " explorados)")
	return nil
end

-- ==============================================================================
-- PATH SMOOTHING (Line-of-Sight Post-processing)
-- ==============================================================================

--[[
	Suaviza un path eliminando nodos intermedios cuando hay línea de visión directa.
	Usa "string-pulling" simplificado: desde cada nodo, busca el nodo más lejano
	visible y salta directamente a él.

	Parámetros:
	- path: Array de nodos retornado por GetPathBetweenNodes
	- agentRadius: Radio del agente para el raycast (opcional, default 0.5)

	Retorna:
	- Path suavizado (nuevo array, no modifica el original)
	- nil si el path es nil o vacío
]]
function NavigationGraph:SmoothPath(path, agentRadius)
	if not path or #path <= 2 then
		return path
	end

	agentRadius = agentRadius or 0.5

	-- Configurar raycast params
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {workspace:FindFirstChild("NavigationNodes")}

	-- Función helper para verificar línea de visión entre dos posiciones
	local function hasLineOfSight(fromPos, toPos)
		local direction = toPos - fromPos
		local distance = direction.Magnitude

		-- Raycast principal (centro)
		local result = workspace:Raycast(fromPos, direction, rayParams)
		if result and (result.Position - fromPos).Magnitude < distance * 0.95 then
			return false
		end

		-- Raycasts laterales para considerar el ancho del agente
		if agentRadius > 0 then
			local right = direction:Cross(Vector3.new(0, 1, 0)).Unit * agentRadius
			local up = Vector3.new(0, agentRadius * 0.5, 0)

			-- Raycast derecho
			local resultRight = workspace:Raycast(fromPos + right, direction, rayParams)
			if resultRight and (resultRight.Position - (fromPos + right)).Magnitude < distance * 0.95 then
				return false
			end

			-- Raycast izquierdo
			local resultLeft = workspace:Raycast(fromPos - right, direction, rayParams)
			if resultLeft and (resultLeft.Position - (fromPos - right)).Magnitude < distance * 0.95 then
				return false
			end

			-- Raycast superior (para rampas/escaleras)
			local resultUp = workspace:Raycast(fromPos + up, direction, rayParams)
			if resultUp and (resultUp.Position - (fromPos + up)).Magnitude < distance * 0.95 then
				return false
			end
		end

		return true
	end

	local smoothed = {path[1]}
	local current = 1
	local originalLength = #path

	while current < #path do
		local farthestVisible = current + 1

		-- Verificar que estamos en el mismo piso antes de intentar suavizar
		local currentFloor = path[current].metadata and path[current].metadata.floor
		local isStair = path[current].metadata and path[current].metadata.isStair

		-- No suavizar si estamos en escaleras (importante mantener todos los waypoints)
		if not isStair then
			-- Buscar el nodo más lejano con LOS directo (iterando desde el final)
			for i = #path, current + 2, -1 do
				local targetFloor = path[i].metadata and path[i].metadata.floor
				local targetIsStair = path[i].metadata and path[i].metadata.isStair

				-- Solo considerar nodos en el mismo piso y que no sean escaleras
				if currentFloor == targetFloor and not targetIsStair then
					if hasLineOfSight(path[current].position, path[i].position) then
						farthestVisible = i
						break
					end
				end
			end
		end

		table.insert(smoothed, path[farthestVisible])
		current = farthestVisible
	end

	local removedNodes = originalLength - #smoothed
	if removedNodes > 0 then
		self:Log("astar", "PATH SMOOTHING: " .. originalLength .. " → " .. #smoothed .. " nodos (eliminados " .. removedNodes .. ")")
	end

	return smoothed
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
