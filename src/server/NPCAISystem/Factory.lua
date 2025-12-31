--[[
	Factory - Creación y configuración de NPCs

	Proporciona:
	- Creación de grafos de navegación
	- Spawn de NPCs con Pawn y Controller
	- Spawn masivo desde listas de configuración
]]

local Pawn = require(script.Parent.NPC.Pawn)
local Registry = require(script.Parent.Registry)
local Controller = require(script.Parent.NPC.Controller)

local Factory = {}

--[[
	CreateNavigationGraphFromFolder - Crea un grafo de navegación desde carpetas

	Parámetros:
	- nodesFolder: Carpeta raíz "NavigationNodes" con estructura:
	    ▼ NavigationNodes
	      ▼ Floor_0, Floor_1, etc.
	      ▼ Stairs

	- options:
	    - destroyParts: (bool) Destruir Parts después de cargar (default: true)
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
	local NavigationGraph = require(script.Parent.NavigationGraph)

	-- Configuración del grafo
	local graphConfig = {
		cellSizeX = options.cellSizeX or 16,
		cellSizeZ = options.cellSizeZ or 14,
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

	-- Cargar nodos
	if hasFloorFolders then
		-- Nueva estructura de carpetas
		graph:LoadFromFolderStructure(nodesFolder, {
			destroyParts = options.destroyParts ~= false,
		})
	else
		-- Legacy: carpeta plana con Parts
		local shouldDestroyParts = options.destroyParts
		if shouldDestroyParts == nil then
			shouldDestroyParts = true
		end
		graph:LoadFromParts(nodesFolder, shouldDestroyParts)
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
	local Visualizer = require(script.Parent.Debug.Visualizer)
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
				Visualizer.EnableNPCDebug(controller, {
					showRaycast = DebugConfig.visuals.showVisionRays,
					raycastDuration = 0.1,
					showPath = DebugConfig.visuals.showNPCPaths,
					pathDuration = DebugConfig.visuals.pathDuration or 3,
					showLastSeenPosition = DebugConfig.visuals.showLastSeenPosition,
					showDebugLabels = DebugConfig.visuals.showDebugLabels,
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

return Factory
