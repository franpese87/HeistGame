--[[
	NodeGenerator - Herramienta de Studio para generar nodos de navegación

	USO (desde Command Bar de Studio):
		local gen = require(game.ServerScriptService.Server.Tools.NodeGenerator)
		gen.Generate()      -- spacing por defecto: 2
		gen.Generate(5)     -- spacing personalizado

	LIMPIAR NODOS:
		gen.Clear()

	REQUISITOS:
		- Carpeta "NodeZones" en workspace con Parts delimitadoras
		- Cada Part debe tener atributo 'floor' (number)
		- Opcional: atributo 'spacing' en la Part para override

	COMPORTAMIENTO:
		- Nodos son cubos 1x1x1
		- Se generan en la base de cada zona
		- Spacing se ajusta para distribución uniforme en los límites
]]

local NodeGenerator = {}

local ZONES_FOLDER_NAME = "NodeZones"
local NODES_FOLDER_NAME = "NavigationNodes"
local DEFAULT_SPACING = 2

-- Colores por piso
local FLOOR_COLORS = {
	[0] = Color3.fromRGB(0, 255, 0),
	[1] = Color3.fromRGB(0, 150, 255),
	[2] = Color3.fromRGB(255, 150, 0),
	[3] = Color3.fromRGB(255, 0, 150),
}

local function getFloorColor(floor)
	return FLOOR_COLORS[floor] or Color3.fromRGB(150, 150, 150)
end

local function getOrCreateFloorFolder(nodesRoot, floor)
	local folderName = "Floor_" .. floor
	local existing = nodesRoot:FindFirstChild(folderName)
	if existing then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = nodesRoot
	return folder
end

local function countExistingNodes(floorFolder)
	local count = 0
	for _, child in ipairs(floorFolder:GetChildren()) do
		if child:IsA("BasePart") then
			count = count + 1
		end
	end
	return count
end

local NODE_SIZE = 1 -- Tamaño del nodo (cubo 1x1x1)
local NODE_HALF = NODE_SIZE / 2

local function calculateGridParams(usableSize, desiredSpacing)
	if usableSize <= 0 then
		return 1, 0
	end

	local numNodes = math.max(1, math.round(usableSize / desiredSpacing) + 1)
	local actualSpacing = 0
	if numNodes > 1 then
		actualSpacing = usableSize / (numNodes - 1)
	end

	return numNodes, actualSpacing
end

local function generateNodesInZone(zonePart, globalSpacing, nodesRoot)
	local pos = zonePart.Position
	local size = zonePart.Size

	-- Calcular área usable restando el tamaño del nodo (margen de 0.5 en cada lado)
	local usableSizeX = math.max(0, size.X - NODE_SIZE)
	local usableSizeZ = math.max(0, size.Z - NODE_SIZE)

	-- Posición inicial con offset para que el borde del nodo toque el borde de la zona
	local minX = pos.X - size.X / 2 + NODE_HALF
	local minZ = pos.Z - size.Z / 2 + NODE_HALF
	local baseY = pos.Y - size.Y / 2 + NODE_HALF

	local floor = zonePart:GetAttribute("floor")
	if floor == nil then
		warn("  [!] '" .. zonePart.Name .. "' sin atributo 'floor', usando 0")
		floor = 0
	end

	local spacing = zonePart:GetAttribute("spacing") or globalSpacing

	local numNodesX, spacingX = calculateGridParams(usableSizeX, spacing)
	local numNodesZ, spacingZ = calculateGridParams(usableSizeZ, spacing)

	print(string.format("  [%s] %.0fx%.0f -> %dx%d nodos (spacing: %.2f)",
		zonePart.Name, size.X, size.Z, numNodesX, numNodesZ, (spacingX + spacingZ) / 2))

	local floorFolder = getOrCreateFloorFolder(nodesRoot, floor)
	local startIndex = countExistingNodes(floorFolder)

	local nodeCount = 0
	for ix = 0, numNodesX - 1 do
		for iz = 0, numNodesZ - 1 do
			local x = minX + ix * spacingX
			local z = minZ + iz * spacingZ

			nodeCount = nodeCount + 1

			local node = Instance.new("Part")
			node.Name = "Node_" .. floor .. "_" .. (startIndex + nodeCount)
			node.Size = Vector3.new(1, 1, 1)
			node.Position = Vector3.new(x, baseY, z)
			node.Anchored = true
			node.CanCollide = false
			node.CanQuery = false
			node.Color = getFloorColor(floor)
			node.Material = Enum.Material.Neon
			node.Transparency = 0.3
			node:SetAttribute("floor", floor)
			node.Parent = floorFolder
		end
	end

	return nodeCount
end

function NodeGenerator.Clear()
	local existing = workspace:FindFirstChild(NODES_FOLDER_NAME)
	if existing then
		existing:Destroy()
		print("NodeGenerator: Nodos eliminados")
	end
end

function NodeGenerator.Generate(spacing)
	spacing = spacing or DEFAULT_SPACING

	local zonesFolder = workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if not zonesFolder then
		warn("NodeGenerator: No se encontró carpeta '" .. ZONES_FOLDER_NAME .. "' en workspace")
		return nil
	end

	local zones = {}
	for _, child in ipairs(zonesFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(zones, child)
		end
	end

	if #zones == 0 then
		warn("NodeGenerator: No hay Parts en " .. ZONES_FOLDER_NAME)
		return nil
	end

	-- Limpiar nodos existentes
	NodeGenerator.Clear()

	-- Crear carpeta de nodos
	local nodesRoot = Instance.new("Folder")
	nodesRoot.Name = NODES_FOLDER_NAME
	nodesRoot.Parent = workspace

	print("NodeGenerator: Generando con spacing " .. spacing .. "...")

	local totalNodes = 0
	for _, zonePart in ipairs(zones) do
		local nodes = generateNodesInZone(zonePart, spacing, nodesRoot)
		totalNodes = totalNodes + nodes
	end

	print("NodeGenerator: " .. totalNodes .. " nodos generados en " .. #zones .. " zonas")

	return nodesRoot
end

return NodeGenerator
