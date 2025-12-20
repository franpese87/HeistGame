local NPCManager = {}
NPCManager.__index = NPCManager

function NPCManager.new()
	local self = setmetatable({}, NPCManager)
	self.npcs = {}
	self.isRunning = false
	self.updateRate = 1/30
	return self
end

function NPCManager:Start()
	if self.isRunning then
		return
	end

	self.isRunning = true

	task.spawn(function()
		while self.isRunning do
			local startTime = tick()

			for _, ai in ipairs(self.npcs) do
				if ai.isActive then
					local success, err = pcall(function()
						ai:Update(self.updateRate)
					end)

					if not success then
						warn("❌ Error actualizando NPC " .. ai.npc.Name .. ": " .. tostring(err))
					end
				end
			end

			local elapsed = tick() - startTime
			local sleepTime = math.max(0, self.updateRate - elapsed)
			task.wait(sleepTime)
		end
	end)
end

function NPCManager:Stop()
	self.isRunning = false
end

function NPCManager:RegisterNPC(ai)
	if not ai then
		return false
	end

	table.insert(self.npcs, ai)
	return true
end

function NPCManager:UnregisterNPC(ai)
	for i, npc in ipairs(self.npcs) do
		if npc == ai then
			table.remove(self.npcs, i)
			return true
		end
	end
	return false
end

function NPCManager:GetNPCCount()
	return #self.npcs
end

function NPCManager:DestroyAll()
	for _, ai in ipairs(self.npcs) do
		ai:Destroy()
	end
	self.npcs = {}
end

return NPCManager