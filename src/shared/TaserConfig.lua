-- Configuración del arma Taser
-- Valores de balance ajustables para proyectil, cooldown y stun

return {
	-- Proyectil
	projectileSpeed = 60,        -- studs/s
	projectileRadius = 0.3,      -- radio de la Part (hitbox)
	maxRange = 80,               -- studs antes de autodestruirse

	-- Balance
	cooldown = 4,                -- segundos entre disparos
	stunDuration = 3,            -- segundos de stun al impactar

	-- Visual
	projectileColor = Color3.fromRGB(100, 180, 255),  -- azul eléctrico
	projectileYOffset = 0,       -- offset Y desde RootPart del shooter (0 = altura de cadera)

	-- Animación (genéricas de Roblox como placeholder — reemplazar con animaciones custom de taser)
	-- Hold/Aim: loop mientras Tool equipado (player) o en ATTACKING (NPC)
	toolholdAnimationId = "rbxassetid://507770239",  -- Roblox "Point" R15 default (aim pose aproximada)
	-- Shoot: one-shot al disparar
	shootAnimationId = "rbxassetid://507770453",     -- Roblox "Wave" R15 default (action aproximada)

	-- Modelo de la tool (jugador)
	toolModelId = "rbxassetid://179399313",  -- Roblox Taser (catalog free model)
	                                         -- Si está vacío, se usa el modelo procedural (cilindro azul)
}
