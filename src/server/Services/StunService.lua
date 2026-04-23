--[[
	StunService - Lógica centralizada de aturdimiento para Humanoids

	Encapsula el patrón: guardar velocidades → inmovilizar → restaurar tras duración.
	Usado tanto por NPCs (Controller) como por players (DoorService).
]]

local StunService = {}

-- Humanoids actualmente stunneados: { [Humanoid] = { walkSpeed, jumpPower } }
local activeStuns = {}

-- Aplica stun a un Humanoid: inmoviliza y programa restauración automática.
-- Si el Humanoid ya está stunneado, reinicia el timer sin re-guardar los valores originales.
function StunService.Apply(humanoid, duration)
	if not humanoid or not humanoid.Parent then return end
	if humanoid.Health <= 0 then return end

	if not activeStuns[humanoid] then
		activeStuns[humanoid] = {
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
		}
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	-- Programar restauración (si se llama de nuevo, el nuevo delay sobreescribe)
	-- Si duration es math.huge, el caller gestiona la restauración manualmente
	if duration and duration < math.huge then
		task.delay(duration, function()
			StunService.Remove(humanoid)
		end)
	end
end

-- Restaura el Humanoid a sus valores originales inmediatamente.
function StunService.Remove(humanoid)
	local saved = activeStuns[humanoid]
	if not saved then return end

	activeStuns[humanoid] = nil

	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = saved.walkSpeed
		humanoid.JumpPower = saved.jumpPower
	end
end

-- Consulta si un Humanoid está actualmente stunneado.
function StunService.IsStunned(humanoid)
	return activeStuns[humanoid] ~= nil
end

return StunService
