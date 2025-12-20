local NPCAISystem = {}

-- Cargar todos los módulos del sistema
NPCAISystem.NavigationGraph = require(script.NavigationGraph)
NPCAISystem.Controller = require(script.NPCAIController)
NPCAISystem.Manager = require(script.NPCManager)
NPCAISystem.Setup = require(script.Setup)
NPCAISystem.DebugUtilities = require(script.DebugUtilities)

return NPCAISystem