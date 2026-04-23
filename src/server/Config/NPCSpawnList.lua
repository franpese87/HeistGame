-- [DEPRECADO] Este archivo ya no se usa en el flujo principal.
-- Los NPCs ahora se colocan directamente en el nivel con tag "NPC"
-- y se configuran via Attributes en el modelo (ver Factory.InitializeWorldNPCs).
--
-- Se mantiene como referencia y para spawning programático en runtime
-- via Factory.SpawnAllNPCs / Factory.SpawnAndSetupNPC.
--
-- Lista de NPCs a spawnear con sus configuraciones específicas
-- Cada entrada puede sobrescribir valores de NPCBaseConfig

return {
	{
		name = "Guard_1",
		patrolRoute = { "Node_0_965", "Node_0_227" },
	},

	{
		name = "Guard_2",
		patrolRoute = { "Node_0_951", "Node_0_928" },
		weaponType = "taser",
	},
}
