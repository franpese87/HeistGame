-- Lista de NPCs a spawnear con sus configuraciones específicas
-- Cada entrada puede sobrescribir valores de NPCBaseConfig

return {
	{
		name = "Guard_1",
		patrolRoute = { "Node_0_94", "Node_0_424" },
	},

	{
		name = "Guard_2",
		patrolRoute = { "Node_0_405", "Node_0_415" },
		weaponType = "taser",
	},
}
