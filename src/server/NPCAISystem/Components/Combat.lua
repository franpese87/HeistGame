--[[
	Combat - Componente de combate para NPCs

	Gestiona:
	- Rangos de ataque
	- Cooldowns
	- Daño
]]

local Combat = {}
Combat.__index = Combat

function Combat.new(npc, config)
	local self = setmetatable({}, Combat)

	self.npc = npc

	-- Configuración
	config = config or {}
	self.attackRange = config.attackRange or 5
	self.attackDamage = config.attackDamage or 10
	self.attackCooldown = config.attackCooldown or 1

	-- Estado
	self.lastAttackTime = 0

	return self
end

function Combat:CanAttack(target)
	if not target then return false end

	-- Check cooldown
	if os.clock() - self.lastAttackTime < self.attackCooldown then
		return false
	end

	-- Check distancia
	local myRoot = self.npc:FindFirstChild("HumanoidRootPart")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")

	if not myRoot or not targetRoot then return false end

	local distance = (myRoot.Position - targetRoot.Position).Magnitude
	return distance <= (self.attackRange + 1) -- Pequeño buffer para asegurar hits
end

function Combat:TryAttack(target)
	if not self:CanAttack(target) then
		return false
	end

	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	if targetHumanoid and targetHumanoid.Health > 0 then
		targetHumanoid:TakeDamage(self.attackDamage)
		self.lastAttackTime = os.clock()
		return true
	end

	return false
end

return Combat
