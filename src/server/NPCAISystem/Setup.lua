local Setup = {}

function Setup.CreateNavigationGraphFromFolder(nodesFolder, options)
	options = options or {}
	local NavigationGraph = require(script.Parent.NavigationGraph)

	-- Pasar config de logging al NavigationGraph
	local loggingConfig = options.logging or {}
	local graph = NavigationGraph.new(loggingConfig)

	if not nodesFolder then
		return graph
	end

	-- Usar el nuevo sistema LoadFromParts
	local shouldDestroyParts = options.destroyParts
	if shouldDestroyParts == nil then
		shouldDestroyParts = true  -- Por defecto, destruir Parts
	end
	
	graph:LoadFromParts(nodesFolder, shouldDestroyParts)

	-- Auto-conectar si se especificó modo
	if options.mode then
		graph:AutoConnect(options)
	end

	return graph
end

function Setup.GetPatrolNodesFromNames(nodesFolder, nodeNames)
	local nodes = {}

	for _, nodeName in ipairs(nodeNames) do
		local node = nodesFolder:FindFirstChild(nodeName)
		if node and node:IsA("BasePart") then
			table.insert(nodes, node)
		end
	end

	return nodes
end

function Setup.SpawnAndSetupNPC(manager, template, graph, patrolRouteNames, config, parentFolder)
	if not template then
		return nil, nil
	end

	local npc = template:Clone()
	npc.Parent = parentFolder or workspace

	local NPCAIController = require(script.Parent.NPCAIController)

	local patrolNodes = {}
	if patrolRouteNames and #patrolRouteNames > 0 then
		-- Buscar nodos en el grafo (ahora están en memoria)
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

	local ai = NPCAIController.new(npc, graph, config)

	if ai then
		manager:RegisterNPC(ai)

		if #patrolNodes > 0 then
			local startNode = patrolNodes[1]
			npc:PivotTo(CFrame.new(startNode.Position))
		end
	end

	return npc, ai
end

function Setup.SpawnAllNPCs(manager, template, graph, npcSpawnList, baseConfig)
	local DebugUtilities = require(script.Parent.DebugUtilities)
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
		local npc, ai = Setup.SpawnAndSetupNPC(
			manager,
			template,
			graph,
			npcConfig.patrolRoute,
			finalConfig,
			npcsFolder
		)

		if npc and ai then
			npc.Name = npcConfig.name or ("NPC_" .. i)

			-- Activar debug visual (solo en Studio)
			if isStudio then
				DebugUtilities.EnableNPCDebug(ai, {
					showRaycast = true,
					raycastDuration = 0.1,
				})
			end

			table.insert(spawnedNPCs, { npc = npc, ai = ai, config = npcConfig })
		end

		-- Pequeño delay entre spawns para evitar colisiones
		task.wait(0.1)
	end

	return spawnedNPCs
end

return Setup
