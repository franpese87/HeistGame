-- Debug visual y logging para el sistema de NPCs (solo en Studio)

return {
	-- ==============================================================================
	-- VISUALIZACION DEL GRAFO DE NAVEGACION
	-- ==============================================================================

	-- Flag maestro: activa la visualizacion al iniciar
	visualizeOnStartup = true,

	-- Elementos a visualizar
	showNodes = true,
	showCells = false,
	showConnections = false,

	-- ==============================================================================
	-- DEBUG VISUAL DE NPCs
	-- ==============================================================================
	visuals = {
		-- Sistema de vision (VisionSensor)
		-- Pipeline: Distancia -> Cono -> Line of Sight
		showVisionDebug = true,

		-- Smart Observation (raycasts de validación de ángulos)
		showSmartObservation = true,

		-- Otros sistemas
		showNoiseSpheres = true,
		showNPCPaths = true,
		showLastSeenPosition = true,
		showStateIndicator = true,
	},

	-- ==============================================================================
	-- LOGGING (Console)
	-- ==============================================================================
	logging = {
		stateChanges = true,
		detection = true,
	},
}
