local Setup = {}

function Setup.CreateNavigationGraphFromFolder(nodesFolder, options)
	options = options or {}
	local NavigationGraph = require(script.Parent.NavigationGraph)
	local graph = NavigationGraph.new()

	if not nodesFolder then
		warn("⚠️ Folder de nodos no proporcionado")
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
		else
			warn("⚠️ Nodo de patrullaje no encontrado: " .. nodeName)
		end
	end

	return nodes
end

-- TODO: Añadir métodos para spawnear y configurar NPCs

return Setup
