--[[
	Animation - Módulo compartido de animaciones

	Re-exporta los submódulos:
	- Controller: Gestión de AnimationTracks (play/stop/speed)
	- ProceduralRotation: Rotación de Motor6Ds (cabeza/torso via C0)
	- Registry: Registro de IDs de animación

	Accesible desde server y client via:
	  local Animation = require(ReplicatedStorage.Shared.Animation)
]]

return {
	Controller = require(script.AnimationController),
	ProceduralRotation = require(script.ProceduralRotation),
	Registry = require(script.AnimationRegistry),
}
