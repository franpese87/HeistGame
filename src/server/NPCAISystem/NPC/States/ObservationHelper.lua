--[[
	ObservationHelper - Logica compartida de observacion rotacional

	Usado por ObservingState e InvestigatingState para:
	- Encontrar la mejor orientacion (raycasting 8 direcciones)
	- Filtrar angulos de observacion validos (no bloqueados por paredes)
	- Rotar entre angulos con timer

	No es un estado, es un helper sin estado propio.
	Todo el estado vive en el Controller (ctx).
]]

local GeometryVersion = require(script.Parent.Parent.Parent.Parent.Services.GeometryVersion)

local ObservationHelper = {}

-- ==============================================================================
-- SMART ORIENTATION (8-direction raycast)
-- ==============================================================================

-- Encuentra la orientacion base con mayor espacio libre
function ObservationHelper.FindBestOrientation(position, raycastParams)
	local visionHeight = 2
	local rayOrigin = position + Vector3.new(0, visionHeight, 0)
	local scanDistance = 50

	local testAngles = {0, 45, 90, 135, 180, 225, 270, 315}
	local raycastResults = {}

	for _, angle in ipairs(testAngles) do
		local direction = CFrame.Angles(0, math.rad(angle), 0).LookVector
		local rayDirection = direction * scanDistance
		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		local freeDistance = result and result.Distance or scanDistance

		table.insert(raycastResults, {
			angle = angle,
			freeDistance = freeDistance,
		})
	end

	-- Agrupacion por FOV: grupos deslizantes de 3 rayos consecutivos
	local rayGroups = {}
	for i = 1, #raycastResults do
		local group = { centerIndex = i, rays = {} }

		for offset = -1, 1 do
			local index = i + offset
			if index < 1 then index = index + #raycastResults
			elseif index > #raycastResults then index = index - #raycastResults end
			table.insert(group.rays, raycastResults[index])
		end

		local totalDistance = 0
		local maxDistance = 0
		for _, ray in ipairs(group.rays) do
			totalDistance = totalDistance + ray.freeDistance
			if ray.freeDistance > maxDistance then
				maxDistance = ray.freeDistance
			end
		end

		group.averageDistance = totalDistance / #group.rays
		group.maxDistance = maxDistance
		group.score = (maxDistance * 0.7) + (group.averageDistance * 0.3)
		table.insert(rayGroups, group)
	end

	local bestGroup = rayGroups[1]
	for _, group in ipairs(rayGroups) do
		if group.score > bestGroup.score then
			bestGroup = group
		end
	end

	local bestDirection = raycastResults[bestGroup.centerIndex]
	return CFrame.new(position) * CFrame.Angles(0, math.rad(bestDirection.angle), 0)
end

-- ==============================================================================
-- ANGLE VALIDATION
-- ==============================================================================

-- Valida si un angulo de observacion es util (no bloqueado por pared cercana)
function ObservationHelper.IsAngleValid(baseCFrame, angle, position, raycastParams, validationDistance)
	if not baseCFrame then return true end

	local rotatedCFrame = baseCFrame * CFrame.Angles(0, math.rad(angle), 0)
	local direction = rotatedCFrame.LookVector
	local visionHeight = 2
	local rayOrigin = position + Vector3.new(0, visionHeight, 0)
	local rayDirection = direction * validationDistance

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	return result == nil or result.Distance >= validationDistance
end

-- Filtra angulos validos desde una lista, retorna al menos {0}
function ObservationHelper.FilterValidAngles(angles, baseCFrame, position, raycastParams, validationDistance)
	local validAngles = {}
	for _, angle in ipairs(angles) do
		if ObservationHelper.IsAngleValid(baseCFrame, angle, position, raycastParams, validationDistance) then
			table.insert(validAngles, angle)
		end
	end
	if #validAngles == 0 then
		validAngles = {0}
	end
	return validAngles
end

-- ==============================================================================
-- OBSERVATION CACHE (para nodos de patrulla)
-- ==============================================================================

-- Obtiene orientacion y angulos validos, usando cache si disponible
function ObservationHelper.GetOrComputeOrientation(ctx, nodeIndex)
	local currentGeoVersion = GeometryVersion.Get()
	local cached = ctx.observationCache[nodeIndex]

	if cached and cached.geometryVersion == currentGeoVersion then
		return cached.orientation, cached.validAngles
	end

	-- Cache invalido: calcular
	local position = ctx.pawn:GetPosition()
	local orientation = ObservationHelper.FindBestOrientation(position, ctx.raycastParams)
	local validAngles = ObservationHelper.FilterValidAngles(
		ctx.observationAngles, orientation, position,
		ctx.raycastParams, ctx.observationValidationDistance
	)

	ctx.observationCache[nodeIndex] = {
		orientation = orientation,
		validAngles = validAngles,
		geometryVersion = currentGeoVersion,
	}

	return orientation, validAngles
end

return ObservationHelper
