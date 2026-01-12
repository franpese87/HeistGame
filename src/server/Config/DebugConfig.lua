-- Debug visual y logging para el sistema de NPCs (solo en Studio)

return {
	-- ==============================================================================
	-- VISUALIZACION DEL GRAFO DE NAVEGACION
	-- ==============================================================================

	-- Flag maestro: activa la visualizacion al iniciar
	visualizeOnStartup = false,

	-- Elementos a visualizar
	showNodes = true,
	showCells = false,
	showConnections = true,

	-- Estilo de celdas del spatial hash
	cellTransparency = 0.85,
	cellWireframe = true,

	-- ==============================================================================
	-- DEBUG VISUAL DE NPCs
	-- ==============================================================================
	visuals = {
		-- Sistema de vision (VisionSensor)
		-- Pipeline: Distancia -> Cono -> Line of Sight
		showVisionDebug = true,

		-- Otros sistemas
		showNoiseSpheres = true,
		showNPCPaths = true,
		showLastSeenPosition = true,
		showDebugLabels = true,
	},

	-- ==============================================================================
	-- LOGGING (Console)
	-- ==============================================================================
	logging = {
		stateChanges = true,
		detection = true,
	},
}
