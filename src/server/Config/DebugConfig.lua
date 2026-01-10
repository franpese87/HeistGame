-- Configuración de debug visual y logging
-- Solo se aplica en Studio

return {
	-- ==============================================================================
	-- VISUALIZACIÓN DEL GRAFO
	-- ==============================================================================
	visualizeOnStartup = true,

	-- Qué visualizar
	showNodes = true,
	showCells = false,
	showConnections = false,

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
	-- DEBUG VISUAL (SENSORS Y PATHS)
	-- ==============================================================================
	visuals = {
		showVisionRays = true,     -- Muestra las líneas de visión (Verde/Rojo)
		showNoiseSpheres = true,   -- Muestra esferas donde se generan ruidos
		showNPCPaths = true,       -- Muestra la ruta actual del NPC cambiando color de nodos
		showLastSeenPosition = true, -- Muestra esfera en la última posición detectada del target
		showDebugLabels = true,    -- Muestra etiquetas de texto en lastSeenPosition
	},

	-- ==============================================================================
	-- LOGGING DE NPC AI (Console Debug)
	-- Activar solo las categorías necesarias para debugging
	-- ==============================================================================
	logging = {
		-- Transiciones de estado (Patrolling → Chasing → Returning, etc.)
		stateChanges = true,

		-- Sistema de detección (accumulator, coyote time, target acquisition/loss)
		detection = true,

		-- Cálculo y seguimiento de rutas (pathfinding A*, seguimiento de nodos)
		pathfinding = true,

		-- Estado RETURNING específico (bug conocido: navegación al volver a patrulla)
		returning = true,

		-- Búsqueda de nodos en el grafo (GetNearestNode, spatial hash)
		nodeSearch = true,

		-- Algoritmo A* detallado (iteraciones, nodos explorados)
		astar = true,
	},
}
