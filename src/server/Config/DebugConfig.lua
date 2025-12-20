-- Configuración de debug visual y logging
-- Solo se aplica en Studio

return {
	-- ==============================================================================
	-- VISUALIZACIÓN DEL GRAFO
	-- ==============================================================================
	keepNodesInWorkspace = false,
	visualizeOnStartup = true,

	-- Qué visualizar
	showNodes = true,
	showCells = true,
	showConnections = true,

	-- Estilo visual - Nodos
	nodeColor = Color3.fromRGB(0, 255, 0),
	nodeSize = 0.5,
	nodeTransparency = 0.3,

	-- Estilo visual - Celdas
	cellColor = Color3.fromRGB(100, 200, 255),
	cellTransparency = 0.85,
	cellWireframe = true,

	-- Estilo visual - Conexiones
	connectionColor = Color3.fromRGB(153, 202, 255),
	connectionWidth = 0.1,

	-- ==============================================================================
	-- LOGGING DE NPC AI (Console Debug)
	-- Activar solo las categorías necesarias para debugging
	-- ==============================================================================
	logging = {
		-- Transiciones de estado (Patrolling → Chasing → Returning, etc.)
		stateChanges = false,

		-- Sistema de detección (accumulator, coyote time, target acquisition/loss)
		detection = false,

		-- Cálculo y seguimiento de rutas (pathfinding A*, seguimiento de nodos)
		pathfinding = false,

		-- Estado RETURNING específico (bug conocido: navegación al volver a patrulla)
		returning = false,

		-- Búsqueda de nodos en el grafo (GetNearestNode, spatial hash)
		nodeSearch = false,

		-- Algoritmo A* detallado (iteraciones, nodos explorados)
		astar = false,
	},
}
