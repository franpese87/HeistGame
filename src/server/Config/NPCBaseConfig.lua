-- Configuración base compartida por todos los NPCs
-- Los NPCs individuales pueden sobrescribir estos valores

return {
	-- Detección y combate
	detectionRange = 20,
	attackRange = 3,
	loseTargetTime = 1,
	reactionTime = 0.8,  -- Tiempo en estado ALERTED antes de CHASING
	attackCooldown = 1,
	attackDamage = 10,
	visionHeight = 2,

	-- Velocidades
	patrolSpeed = 8,
	chaseSpeed = 8,

	-- Sistema de cono de visión
	observationConeAngle = 90,

	-- Sistema de observación con rotación suave
	observationAngles = { -45, 0, 45, 0 },
	observationTimePerAngle = 1.5,
	-- investigationDuration se calcula automáticamente como:
	-- #observationAngles × observationTimePerAngle (ej: 4 × 1.5 = 6s)

	-- Rotación por capas durante observación (deben sumar 1.0)
	-- Distribuye el ángulo entre cabeza y torso
	observationHeadRatio = 0.7,   -- 70% del ángulo para la cabeza
	observationTorsoRatio = 0.3,  -- 30% del ángulo para el torso

	-- Navegación
	-- Distancia a la que el NPC deja de usar el grafo y se acerca directamente al target para atacar
	directApproachDistance = 8,

	-- Path Smoothing (Line-of-Sight post-processing)
	-- Elimina nodos intermedios del path cuando hay línea de visión directa
	enablePathSmoothing = true,
	-- Radio del agente para raycasts de LOS (debe coincidir con el ancho del NPC)
	agentRadius = 1.0,

	-- Indicador visual de estado (debug)
	stateIndicatorOffset = 4,
}
