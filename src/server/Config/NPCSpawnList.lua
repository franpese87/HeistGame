-- Lista de NPCs a spawnear con sus configuraciones específicas
-- Cada entrada puede sobrescribir valores de NPCBaseConfig

return {
	{
		name = "Guard_1",
		patrolRoute = { "Node_0_964", "Node_0_226" },
	},

	{
		name = "Guard_2",
		patrolRoute = { "Node_0_928", "Node_0_951" },
		weaponType = "taser",
	},
}
