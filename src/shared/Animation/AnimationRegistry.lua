--[[
	AnimationRegistry - Registro centralizado de IDs de animación

	Módulo de datos puros. Define sets de animaciones reutilizables
	por NPCs y players. Permite overrides por entidad.

	IMPORTANTE al crear animaciones custom:
	- Brazos y piernas: animar libremente
	- Neck (cabeza): NO incluir keyframes de rotación horizontal
	  (la rotación la controla ProceduralRotation via C0)
	- Se pueden incluir micro-movimientos de cabeza (inclinación, sacudida)
	  porque el Animator escribe en Transform, que se compone con C0
	- RootJoint: evitar rotaciones en animaciones de idle/observación
	  (RotateLayered lo controla proceduralmente en esos estados)
]]

local AnimationRegistry = {}

-- Animaciones R6 default de Roblox
AnimationRegistry.R6_DEFAULT = {
	idle = "rbxassetid://180435571",
	walk = "rbxassetid://180426354",
	run  = "rbxassetid://180426354",
}

AnimationRegistry.R6_DEFAULT_SPEEDS = {
	idle = 1.0,
	walk = 1.0,
	run  = 1.5,
}

-- Animaciones R15 default de Roblox
AnimationRegistry.R15_DEFAULT = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	run  = "rbxassetid://507767714",
}

AnimationRegistry.R15_DEFAULT_SPEEDS = {
	idle = 1.0,
	walk = 1.0,
	run  = 1.5,
}

-- Detecta el tipo de rig de un modelo (R6 o R15)
function AnimationRegistry.GetRigType(character)
	if character:FindFirstChild("UpperTorso") then
		return "R15"
	end
	return "R6"
end

-- Devuelve el set de animaciones apropiado según el rig
function AnimationRegistry.GetDefaultForRig(character)
	if AnimationRegistry.GetRigType(character) == "R15" then
		return AnimationRegistry.R15_DEFAULT, AnimationRegistry.R15_DEFAULT_SPEEDS
	end
	return AnimationRegistry.R6_DEFAULT, AnimationRegistry.R6_DEFAULT_SPEEDS
end

-- Mezcla un set base con overrides específicos por entidad
function AnimationRegistry.Merge(base, overrides)
	local result = table.clone(base)
	if overrides then
		for key, value in pairs(overrides) do
			result[key] = value
		end
	end
	return result
end

return AnimationRegistry
