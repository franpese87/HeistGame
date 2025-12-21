local CombatSystem = {}
CombatSystem.__index = CombatSystem

function CombatSystem.new(npc, config)
	local self = setmetatable({}, CombatSystem)

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

function CombatSystem:CanAttack(target)
	if not target then return false end
	
	-- Check cooldown
	if tick() - self.lastAttackTime < self.attackCooldown then
		return false
	end

	-- Check distancia
	local myRoot = self.npc:FindFirstChild("HumanoidRootPart")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	
	if not myRoot or not targetRoot then return false end

	local distance = (myRoot.Position - targetRoot.Position).Magnitude
	return distance <= (self.attackRange + 1) -- Pequeño buffer para asegurar hits
end

function CombatSystem:TryAttack(target)
	if not self:CanAttack(target) then
		return false
	end

	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	if targetHumanoid and targetHumanoid.Health > 0 then
		targetHumanoid:TakeDamage(self.attackDamage)
		self.lastAttackTime = tick()
		return true
	end

	return false
end

return CombatSystem