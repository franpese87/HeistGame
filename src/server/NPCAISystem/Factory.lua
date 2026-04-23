--[[
	Factory - Creación y configuración de NPCs

	Proporciona:
	- Creación de grafos de navegación
	- Spawn de NPCs con Pawn y Controller
	- Spawn masivo desde listas de configuración
	- Descubrimiento e inicialización de NPCs colocados en nivel
]]

local CollectionService = game:GetService("CollectionService")

local Pawn = require(script.Parent.NPC.Pawn)
local Registry = require(script.Parent.Registry)
local Controller = require(script.Parent.NPC.Controller)

-- Estados válidos de la FSM (para validar allowedStates)
local VALID_STATES = {
	Patrolling = true,
	Observing = true,
	Alerted = true,
	Chasing = true,
	Attacking = true,
	Investigating = true,
	Returning = true,
	Stunned = true,
}

local Factory = {}

-- ==============================================================================
-- HELPERS PRIVADOS (lectura de configuración desde Attributes)
-- ==============================================================================

--[[
	_ReadNPCConfig - Lee Attributes del modelo NPC y los mergea sobre baseConfig.
	Solo acepta valores cuyo tipo coincida con el default en baseConfig.
]]
function Factory._ReadNPCConfig(npcModel, baseConfig)
	local finalConfig = table.clone(baseConfig)

	for key, defaultValue in pairs(baseConfig) do
		local attrValue = npcModel:GetAttribute(key)
		if attrValue ~= nil then
			if typeof(attrValue) == typeof(defaultValue) then
				finalConfig[key] = attrValue
			else
				warn("[NPCFactory] " .. npcModel.Name .. ": Attribute '" .. key
					.. "' tiene tipo " .. typeof(attrValue) .. ", esperado "
					.. typeof(defaultValue) .. ". Usando default.")
			end
		end
	end

	return finalConfig
end

--[[
	_ParsePatrolRoute - Lee el Attribute "patrolRoute" y lo parsea a array de nombres.
	Retorna {} si no existe o está vacío.
]]
function Factory._ParsePatrolRoute(npcModel)
	local routeStr = npcModel:GetAttribute("patrolRoute")
	if not routeStr or typeof(routeStr) ~= "string" or routeStr == "" then
		return {}
	end

	local nodeNames = {}
	for _, part in ipairs(string.split(routeStr, ",")) do
		local trimmed = string.match(part, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			table.insert(nodeNames, trimmed)
		end
	end
	
	return nodeNames
end

--[[
	_ParseAllowedStates - Lee el Attribute "allowedStates" y lo convierte a set.
	Retorna nil si vacío (= todos los estados permitidos).
	Retorna set { ["Patrolling"] = true, ... } si tiene valores válidos.
]]
function Factory._ParseAllowedStates(npcModel)
	local statesStr = npcModel:GetAttribute("allowedStates")
	if not statesStr or typeof(statesStr) ~= "string" or statesStr == "" then
		return nil
	end

	local statesSet = {}
	local hasValid = false

	for _, part in ipairs(string.split(statesStr, ",")) do
		local trimmed = string.match(part, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			if VALID_STATES[trimmed] then
				statesSet[trimmed] = true
				hasValid = true
			else
				warn("[NPCFactory] " .. npcModel.Name .. ": Estado '" .. trimmed
					.. "' en allowedStates no es válido, ignorado.")
			end
		end
	end

	return hasValid and statesSet or nil
end

-- ==============================================================================
-- GRAFO DE NAVEGACIÓN
-- ==============================================================================

--[[
	CreateNavigationGraphFromFolder - Crea un grafo de navegación desde carpetas

	Parámetros:
	- nodesFolder: Carpeta raíz "NavigationNodes" con estructura:
	    ▼ NavigationNodes
	      ▼ Floor_0, Floor_1, etc.
	      ▼ Stairs

	- options:
	    - cellSizeX: (number) Tamaño de celda X para spatial hash (default: 16)
	    - cellSizeZ: (number) Tamaño de celda Z para spatial hash (default: 14)
	    - floorHeight: (number) Altura de cada piso (default: 10)
	    - floorBaseY: (number) Y base del piso 0 (default: 0)
	    - mode: (string) Si se especifica, auto-conecta nodos
	    - maxDistance: (number) Distancia máxima para conexiones (default: 20)
	    - maxStairDistance: (number) Distancia para conexiones de escalera (default: 10)
	    - useRaycast: (bool) Usar raycast para validar conexiones (default: false)
	    - ignoreList: (table) Instancias a ignorar en raycast
	    - debug: (table) Configuración de logging { nodeSearch, astar, loading }
]]
function Factory.CreateNavigationGraphFromFolder(nodesFolder, options)
	options = options or {}
	local NavigationGraph = require(script.Parent.Parent.Services.NavigationGraph)

	-- Eliminar NodeZones primero para no interferir con raycasts
	local nodeZones = workspace:FindFirstChild("NodeZones")
	if nodeZones then
		nodeZones:Destroy()
	end

	-- Configuración del grafo
	local graphConfig = {
		cellSizeX = options.cellSizeX or 25,
		cellSizeY = options.cellSizeY or 10,
		cellSizeZ = options.cellSizeZ or 25,
		floorHeight = options.floorHeight or 10,
		floorBaseY = options.floorBaseY or 0,
		debug = options.debug or options.logging or {},
	}

	local graph = NavigationGraph.new(graphConfig)

	if not nodesFolder then
		return graph
	end

	-- Detectar si es estructura nueva (con Floor_X) o legacy (Parts planas)
	local hasFloorFolders = false
	for _, child in ipairs(nodesFolder:GetChildren()) do
		if child:IsA("Folder") and string.match(child.Name, "^Floor_%-?%d+") then
			hasFloorFolders = true
			break
		end
	end

	-- Mantener Parts si showNodes está activo (para debug visual)
	local keepSourceParts = options.keepSourceParts or false

	-- Cargar nodos
	if hasFloorFolders then
		-- Nueva estructura de carpetas
		graph:LoadFromFolderStructure(nodesFolder, keepSourceParts)
	else
		-- Legacy: carpeta plana con Parts
		graph:LoadFromParts(nodesFolder, keepSourceParts)
	end

	-- Auto-conectar si se especificó modo
	if options.mode then
		graph:AutoConnect({
			maxDistance = options.maxDistance or 20,
			maxStairDistance = options.maxStairDistance or 10,
			useRaycast = options.useRaycast or false,
			maxConnectionsPerNode = options.maxConnectionsPerNode or 6,
			ignoreList = options.ignoreList or {},
		})
	end

	return graph
end

--[[
	SpawnAndSetupNPC - Crea un NPC con Pawn y Controller

	Retorna: npc (Instance), pawn (Pawn), controller (Controller), id (number)
]]
function Factory.SpawnAndSetupNPC(template, graph, patrolRouteNames, config, parentFolder)
	if not template then
		return nil, nil, nil, nil
	end

	local npc = template:Clone()
	npc.Parent = parentFolder or workspace

	-- Asignar ownership de red al servidor para evitar stuttering
	local rootPart = npc:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart:SetNetworkOwner(nil)
	end

	-- 1. Crear Pawn (representación física)
	local pawn = Pawn.new(npc, config)
	if not pawn then
		npc:Destroy()
		return nil, nil, nil, nil
	end

	-- 2. Preparar nodos de patrulla
	local patrolNodes = {}
	if patrolRouteNames and #patrolRouteNames > 0 then
		for _, nodeName in ipairs(patrolRouteNames) do
			local nodeData = graph.nodes[nodeName]
			if nodeData then
				local nodeObj = {
					Name = nodeName,
					Position = nodeData.position
				}
				table.insert(patrolNodes, nodeObj)
			end
		end
	end

	config = config or {}
	config.patrolNodes = patrolNodes

	-- 3. Crear Controller (cerebro)
	local controller = Controller.new(pawn, graph, config)
	if not controller then
		pawn:Destroy()
		npc:Destroy()
		return nil, nil, nil, nil
	end

	-- 4. Registrar en el Registry singleton
	local registry = Registry.GetInstance()
	local id = registry:RegisterNPC(pawn, controller)

	-- 5. Posicionar en inicio
	if #patrolNodes > 0 then
		local startNode = patrolNodes[1]
		npc:PivotTo(CFrame.new(startNode.Position))
	end

	return npc, pawn, controller, id
end

--[[
	SpawnAllNPCs - Spawn múltiples NPCs desde una lista de configuración

	Retorna: tabla con { npc, pawn, controller, id, config } por cada NPC
]]
function Factory.SpawnAllNPCs(template, graph, npcSpawnList, baseConfig)
	local isStudio = game:GetService("RunService"):IsStudio()

	local spawnedNPCs = {}
	local npcsFolder = workspace:FindFirstChild("NPCs")

	if not npcsFolder then
		npcsFolder = Instance.new("Folder")
		npcsFolder.Name = "NPCs"
		npcsFolder.Parent = workspace
	end

	for i, npcConfig in ipairs(npcSpawnList) do
		-- Combinar baseConfig con configuración específica del NPC
		local finalConfig = table.clone(baseConfig)

		-- Sobrescribir con valores específicos (excepto name y patrolRoute)
		for key, value in pairs(npcConfig) do
			if key ~= "name" and key ~= "patrolRoute" then
				finalConfig[key] = value
			end
		end

		-- Spawn del NPC
		local npc, pawn, controller, id = Factory.SpawnAndSetupNPC(
			template,
			graph,
			npcConfig.patrolRoute,
			finalConfig,
			npcsFolder
		)

		if npc and pawn and controller then
			npc.Name = npcConfig.name or ("NPC_" .. i)

			-- Activar debug visual (solo en Studio)
			if isStudio then
				local DebugConfig = require(script.Parent.Parent.Config.DebugConfig)
				controller:EnableDebug({
					showRaycast = DebugConfig.visuals.showVisionRays,
					raycastDuration = 0.1,
					showPath = DebugConfig.visuals.showNPCPaths,
					showLastSeenPosition = DebugConfig.visuals.showLastSeenPosition,
				})
			end

			table.insert(spawnedNPCs, {
				npc = npc,
				pawn = pawn,
				controller = controller,
				id = id,
				config = npcConfig
			})
		end

		-- Pequeño delay entre spawns para evitar colisiones
		task.wait(0.1)
	end

	return spawnedNPCs
end

-- ==============================================================================
-- WORLD-PLACED NPCs (descubrimiento e inicialización desde nivel)
-- ==============================================================================

--[[
	InitializePlacedNPC - Inicializa un NPC ya colocado en el mundo (sin clonar).

	Lee su configuración de Attributes en el modelo.
	Retorna: tabla { npc, pawn, controller, id, config } o nil si falla.
]]
function Factory.InitializePlacedNPC(npcModel, graph, baseConfig)
	-- 1. Validar partes requeridas
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local rootPart = npcModel:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		warn("[NPCFactory] " .. npcModel.Name .. ": Missing Humanoid or HumanoidRootPart, skipping")
		return nil
	end

	-- 2. Leer config de Attributes, mergeada sobre baseConfig
	local config = Factory._ReadNPCConfig(npcModel, baseConfig)

	-- 3. Parsear patrol route
	local patrolRouteNames = Factory._ParsePatrolRoute(npcModel)

	-- 4. Parsear allowed states: siempre sobreescribir lo que _ReadNPCConfig puso.
	-- _ReadNPCConfig deja config.allowedStates = "" (string vacía del baseConfig),
	-- que es truthy y bloquearía todas las transiciones en ChangeState.
	-- _ParseAllowedStates devuelve nil (todos los estados permitidos) o un set.
	config.allowedStates = Factory._ParseAllowedStates(npcModel)

	-- 5. Asignar ownership de red al servidor
	rootPart:SetNetworkOwner(nil)

	-- 6. Crear Pawn (representación física)
	local pawn = Pawn.new(npcModel, config)
	if not pawn then
		warn("[NPCFactory] " .. npcModel.Name .. ": Pawn creation failed, skipping")
		return nil
	end

	-- 7. Resolver nodos de patrulla desde el grafo
	local patrolNodes = {}
	for _, nodeName in ipairs(patrolRouteNames) do
		local nodeData = graph.nodes[nodeName]
		if nodeData then
			table.insert(patrolNodes, {
				Name = nodeName,
				Position = nodeData.position,
			})
		else
			warn("[NPCFactory] " .. npcModel.Name .. ": Patrol node '" .. nodeName .. "' not found in nav graph")
		end
	end
	config.patrolNodes = patrolNodes

	-- 8. Crear Controller (cerebro)
	local controller = Controller.new(pawn, graph, config)
	if not controller then
		pawn:Destroy()
		warn("[NPCFactory] " .. npcModel.Name .. ": Controller creation failed, skipping")
		return nil
	end

	-- 9. Registrar en el Registry singleton
	local registry = Registry.GetInstance()
	local id = registry:RegisterNPC(pawn, controller)

	-- 10. Opcional: snap al primer nodo de patrulla
	if npcModel:GetAttribute("snapToFirstPatrolNode") and #patrolNodes > 0 then
		npcModel:PivotTo(CFrame.new(patrolNodes[1].Position))
	end

	return {
		npc = npcModel,
		pawn = pawn,
		controller = controller,
		id = id,
		config = { name = npcModel.Name, patrolRoute = patrolRouteNames },
	}
end

--[[
	InitializeWorldNPCs - Descubre e inicializa todos los NPCs con tag "NPC" en el nivel.

	Retorna: tabla con { npc, pawn, controller, id, config } por cada NPC inicializado.
]]
function Factory.InitializeWorldNPCs(graph, baseConfig)
	local isStudio = game:GetService("RunService"):IsStudio()

	local taggedNPCs = CollectionService:GetTagged("NPC")
	local spawnedNPCs = {}

	for i, npcModel in ipairs(taggedNPCs) do

		local result = Factory.InitializePlacedNPC(npcModel, graph, baseConfig)

		if result then
			-- Activar debug visual (solo en Studio)
			if isStudio then
				local DebugConfig = require(script.Parent.Parent.Config.DebugConfig)
				result.controller:EnableDebug({
					showRaycast = DebugConfig.visuals.showVisionRays,
					raycastDuration = 0.1,
					showPath = DebugConfig.visuals.showNPCPaths,
					showLastSeenPosition = DebugConfig.visuals.showLastSeenPosition,
				})
			end

			table.insert(spawnedNPCs, result)
		end

		-- Pequeño delay entre inits para evitar problemas de física
		if i < #taggedNPCs then
			task.wait(0.1)
		end
	end

	print("[NPCFactory] Initialized " .. #spawnedNPCs .. "/" .. #taggedNPCs .. " world NPCs")
	return spawnedNPCs
end

return Factory
