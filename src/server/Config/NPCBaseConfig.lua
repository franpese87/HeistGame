-- Configuración base compartida por todos los NPCs
-- Los NPCs individuales pueden sobrescribir estos valores

return {
	-- Detección y combate
	detectionRange = 20,
	attackRange = 3,
	loseTargetTime = 1,
	minDetectionTime = 0.3,
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

	-- Navegación
	navigationMode = "hybrid",
	graphChaseDistance = 20,
	pathRecalculateInterval = 1.0,

	-- Indicador visual de estado (debug)
	showStateIndicator = true,
	stateIndicatorOffset = 4,
}
