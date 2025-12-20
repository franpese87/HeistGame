local NavigationGraph = {}
NavigationGraph.__index = NavigationGraph

function NavigationGraph.new(debugConfig)
	local self = setmetatable({}, NavigationGraph)
	self.nodes = {}
	self.connections = {}

	-- Spatial hashing (construir con BuildSpatialHash3D)
	self.spatialGrid = nil
	self.cellSizeX = 16  -- Tamaño fijo: 16 studs
	self.cellSizeY = 10  -- Tamaño fijo: 10 studs
	self.cellSizeZ = 14  -- Tamaño fijo: 14 studs

	-- Debug logging
	debugConfig = debugConfig or {}
	self.logFlags = {
		nodeSearch = debugConfig.nodeSearch or false,
		astar = debugConfig.astar or false,
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
-- AUTO-CONEXIÓN
-- ==============================================================================

function NavigationGraph:AutoConnect(options)
	options = options or {}
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

		table.sort(candidates, function(a, b)
			return a.distance < b.distance
		end)

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

	return connections
end

-- ==============================================================================
-- SPATIAL HASHING 3D
-- ==============================================================================

function NavigationGraph:BuildSpatialHash3D()
	self.spatialGrid = {}

	-- Construir grid 3D usando el origen del workspace (0,0,0)
	-- Celdas de 16x10x14 studs
	for _, node in pairs(self.nodes) do
		local cellX = math.floor(node.position.X / self.cellSizeX)
		local cellY = math.floor(node.position.Y / self.cellSizeY)
		local cellZ = math.floor(node.position.Z / self.cellSizeZ)
		local cellKey = cellX .. "," .. cellY .. "," .. cellZ

		if not self.spatialGrid[cellKey] then
			self.spatialGrid[cellKey] = {}
		end

		table.insert(self.spatialGrid[cellKey], node)
	end

end

-- ==============================================================================
-- BÚSQUEDA DE NODOS (CON SPATIAL HASHING)
-- ==============================================================================

function NavigationGraph:GetNearestNode(position, options)
	-- Si no hay spatial hash, usar búsqueda linear
	if not self.spatialGrid then
		self:Log("nodeSearch", "SpatialGrid nil, usando búsqueda linear")
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
	local nodesChecked = 0

	-- Buscar en 3x3x3 grid (27 celdas vecinas)
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local key = (cellX + dx) .. "," .. (cellY + dy) .. "," .. (cellZ + dz)
				local nodesInCell = self.spatialGrid[key]

				if nodesInCell then
					for _, node in ipairs(nodesInCell) do
						nodesChecked = nodesChecked + 1
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
		self:Log("nodeSearch", "Encontrado (mismo piso): " .. nearestSameFloor.name .. " (dist=" .. string.format("%.1f", shortestSameFloorDistance) .. ", checked=" .. nodesChecked .. ")")
		return nearestSameFloor
	end

	if nearestNode then
		self:Log("nodeSearch", "Encontrado: " .. nearestNode.name .. " (dist=" .. string.format("%.1f", shortestDistance) .. ", checked=" .. nodesChecked .. ")")
	else
		self:Log("nodeSearch", "NO ENCONTRADO en celda " .. cellX .. "," .. cellY .. "," .. cellZ .. " (checked=" .. nodesChecked .. ")")
	end

	return nearestNode
end

function NavigationGraph:GetNearestNodeLinear(position)
	local nearestNode = nil
	local shortestDistance = math.huge

	for _, node in pairs(self.nodes) do
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
