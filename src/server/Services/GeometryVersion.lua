--[[
	GeometryVersion - Contador global de cambios en la geometría del nivel

	Sistemas dinámicos (puertas, plataformas, etc.) incrementan este contador
	cuando cambian de estado. Los sistemas que cachean datos basados en geometría
	(orientaciones de observación, etc.) comparan contra este valor para saber
	si su cache es válido.

	Uso:
		-- Al cambiar geometría (ej: puerta se abre/cierra):
		GeometryVersion.Increment()

		-- Al validar cache:
		if cachedVersion == GeometryVersion.Get() then ... end
]]

local GeometryVersion = {}

local version = 0

function GeometryVersion.Get()
	return version
end

function GeometryVersion.Increment()
	version = version + 1
end

return GeometryVersion
