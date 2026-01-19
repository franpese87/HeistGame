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

	-- Smart observation - validación de entorno
	observationValidationDistance = 8,  -- Distancia mínima de espacio libre (studs)

	-- Rotación por capas durante observación (deben sumar 1.0)
	-- Distribuye el ángulo entre cabeza y torso
	observationHeadRatio = 0.7,   -- 70% del ángulo para la cabeza
	observationTorsoRatio = 0.3,  -- 30% del ángulo para el torso

	-- Rotación en combate
	attackRotationSpeed = 0.15,  -- Alpha para LerpCFrame en ATTACKING (0.1-0.3)

	-- Rotación por capas en estado ALERTED (deben sumar 1.0)
	alertedHeadRatio = 0.8,   -- 80% del ángulo para la cabeza (reacción rápida)
	alertedTorsoRatio = 0.2,  -- 20% del ángulo para el torso

	-- Head tracking durante CHASING
	enableHeadTrackingDuringChase = true,  -- Toggle para activar/desactivar
	headTrackingMaxAngle = 90,             -- Límite de rotación de cabeza (grados)

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
