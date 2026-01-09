--[[
	NodeGenerator Plugin - Interfaz gráfica para generar nodos de navegación

	Instalación:
	1. Ejecutar: rojo build plugin.project.json -o NodeGeneratorPlugin.rbxm
	2. Copiar NodeGeneratorPlugin.rbxm a la carpeta de plugins de Roblox:
	   - Windows: %LOCALAPPDATA%\Roblox\Plugins
	   - Mac: ~/Documents/Roblox/Plugins
	3. Reiniciar Studio
]]

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

-- ============================================================================
-- LÓGICA DE GENERACIÓN (copiada de NodeGenerator)
-- ============================================================================

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
	-- La base del nodo se alinea con la parte superior de la zona
	local baseY = pos.Y + size.Y / 2 + NODE_HALF

	local floor = zonePart:GetAttribute("floor") or 0
	local spacing = zonePart:GetAttribute("spacing") or globalSpacing

	local numNodesX, spacingX = calculateGridParams(usableSizeX, spacing)
	local numNodesZ, spacingZ = calculateGridParams(usableSizeZ, spacing)

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

	return nodeCount, numNodesX, numNodesZ
end

local function clearNodes()
	local existing = workspace:FindFirstChild(NODES_FOLDER_NAME)
	if existing then
		existing:Destroy()
		return true
	end
	return false
end

local function generateNodes(spacing)
	local zonesFolder = workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if not zonesFolder then
		return nil, "No se encontró carpeta '" .. ZONES_FOLDER_NAME .. "'"
	end

	local zones = {}
	for _, child in ipairs(zonesFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(zones, child)
		end
	end

	if #zones == 0 then
		return nil, "No hay Parts en " .. ZONES_FOLDER_NAME
	end

	clearNodes()

	local nodesRoot = Instance.new("Folder")
	nodesRoot.Name = NODES_FOLDER_NAME
	nodesRoot.Parent = workspace

	local totalNodes = 0
	local zoneResults = {}

	for _, zonePart in ipairs(zones) do
		local nodes, nx, nz = generateNodesInZone(zonePart, spacing, nodesRoot)
		totalNodes = totalNodes + nodes
		table.insert(zoneResults, {
			name = zonePart.Name,
			nodes = nodes,
			grid = nx .. "x" .. nz
		})
	end

	return {
		totalNodes = totalNodes,
		zonesCount = #zones,
		zones = zoneResults
	}
end

-- ============================================================================
-- INTERFAZ DEL PLUGIN
-- ============================================================================

local toolbar = plugin:CreateToolbar("Node Generator")
local button = toolbar:CreateButton(
	"Node Generator",
	"Generar nodos de navegación",
	"rbxassetid://6031251882" -- Icono de grid
)

-- Crear ventana del plugin
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, -- inicialmente cerrado
	false,
	300, -- ancho
	200, -- alto
	250, -- ancho mínimo
	150  -- alto mínimo
)

local widget = plugin:CreateDockWidgetPluginGui("NodeGeneratorWidget", widgetInfo)
widget.Title = "Node Generator"

-- UI
local frame = Instance.new("Frame")
frame.Size = UDim2.new(1, 0, 1, 0)
frame.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
frame.BorderSizePixel = 0
frame.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = frame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = frame

-- Título
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 20)
title.BackgroundTransparency = 1
title.Text = "Generador de Nodos"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.LayoutOrder = 1
title.Parent = frame

-- Spacing input container
local spacingContainer = Instance.new("Frame")
spacingContainer.Size = UDim2.new(1, 0, 0, 28)
spacingContainer.BackgroundTransparency = 1
spacingContainer.LayoutOrder = 2
spacingContainer.Parent = frame

local spacingLabel = Instance.new("TextLabel")
spacingLabel.Size = UDim2.new(0.5, 0, 1, 0)
spacingLabel.BackgroundTransparency = 1
spacingLabel.Text = "Spacing (studs):"
spacingLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
spacingLabel.TextSize = 14
spacingLabel.Font = Enum.Font.Gotham
spacingLabel.TextXAlignment = Enum.TextXAlignment.Left
spacingLabel.Parent = spacingContainer

local spacingInput = Instance.new("TextBox")
spacingInput.Size = UDim2.new(0.5, -5, 1, 0)
spacingInput.Position = UDim2.new(0.5, 5, 0, 0)
spacingInput.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
spacingInput.BorderSizePixel = 0
spacingInput.Text = tostring(DEFAULT_SPACING)
spacingInput.TextColor3 = Color3.fromRGB(255, 255, 255)
spacingInput.TextSize = 14
spacingInput.Font = Enum.Font.GothamMedium
spacingInput.Parent = spacingContainer

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 4)
inputCorner.Parent = spacingInput

-- Botones container
local buttonsContainer = Instance.new("Frame")
buttonsContainer.Size = UDim2.new(1, 0, 0, 32)
buttonsContainer.BackgroundTransparency = 1
buttonsContainer.LayoutOrder = 3
buttonsContainer.Parent = frame

local generateBtn = Instance.new("TextButton")
generateBtn.Size = UDim2.new(0.48, 0, 1, 0)
generateBtn.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
generateBtn.BorderSizePixel = 0
generateBtn.Text = "Generate"
generateBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
generateBtn.TextSize = 14
generateBtn.Font = Enum.Font.GothamBold
generateBtn.Parent = buttonsContainer

local generateCorner = Instance.new("UICorner")
generateCorner.CornerRadius = UDim.new(0, 4)
generateCorner.Parent = generateBtn

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0.48, 0, 1, 0)
clearBtn.Position = UDim2.new(0.52, 0, 0, 0)
clearBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
clearBtn.BorderSizePixel = 0
clearBtn.Text = "Clear"
clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
clearBtn.TextSize = 14
clearBtn.Font = Enum.Font.GothamBold
clearBtn.Parent = buttonsContainer

local clearCorner = Instance.new("UICorner")
clearCorner.CornerRadius = UDim.new(0, 4)
clearCorner.Parent = clearBtn

-- Status label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 40)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Listo"
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextWrapped = true
statusLabel.LayoutOrder = 4
statusLabel.Parent = frame

-- ============================================================================
-- EVENTOS
-- ============================================================================

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

generateBtn.MouseButton1Click:Connect(function()
	local spacing = tonumber(spacingInput.Text) or DEFAULT_SPACING

	statusLabel.Text = "Generando..."
	statusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)

	task.wait() -- Para que se actualice la UI

	local result, err = generateNodes(spacing)

	if result then
		statusLabel.Text = string.format(
			"%d nodos en %d zonas\nSpacing: %.2f studs",
			result.totalNodes,
			result.zonesCount,
			spacing
		)
		statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	else
		statusLabel.Text = "Error: " .. (err or "desconocido")
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	end
end)

clearBtn.MouseButton1Click:Connect(function()
	if clearNodes() then
		statusLabel.Text = "Nodos eliminados"
		statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	else
		statusLabel.Text = "No había nodos"
		statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	end
end)

-- Validar input numérico
spacingInput.FocusLost:Connect(function()
	local num = tonumber(spacingInput.Text)
	if not num or num <= 0 then
		spacingInput.Text = tostring(DEFAULT_SPACING)
	else
		spacingInput.Text = tostring(math.max(0.5, math.min(50, num)))
	end
end)
