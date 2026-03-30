--!strict
-- Inventory.luau
-- Manages the tools and loot a player carries during a heist.
--
-- Tool examples: Lockpick, Drill, Keycard, HackDevice, Disguise
-- Loot examples: Painting, Jewel, CashBag, HardDrive

local Inventory = {}

export type ItemCategory = "Tool" | "Loot" | "Disguise"

export type Item = {
	id: string,            -- unique identifier e.g. "lockpick"
	displayName: string,
	category: ItemCategory,
	weight: number,        -- heavier = slower movement, more noise
	uses: number?,         -- nil = unlimited; >0 = consumable
}

export type PlayerInventory = {
	items: { Item },
	maxWeight: number,
	currentWeight: number,
	equippedTool: string?, -- item id of the currently equipped tool
}

--- Well-known items available in the game.
local ITEM_DEFINITIONS: { [string]: Item } = {
	lockpick = {
		id = "lockpick",
		displayName = "Lockpick",
		category = "Tool",
		weight = 0.5,
		uses = 3,
	},
	drill = {
		id = "drill",
		displayName = "Power Drill",
		category = "Tool",
		weight = 3.0,
		uses = nil,
	},
	keycard = {
		id = "keycard",
		displayName = "Stolen Keycard",
		category = "Tool",
		weight = 0.1,
		uses = nil,
	},
	hack_device = {
		id = "hack_device",
		displayName = "Hacking Device",
		category = "Tool",
		weight = 1.0,
		uses = nil,
	},
	disguise_guard = {
		id = "disguise_guard",
		displayName = "Guard Uniform",
		category = "Disguise",
		weight = 1.5,
		uses = nil,
	},
	cash_bag = {
		id = "cash_bag",
		displayName = "Cash Bag",
		category = "Loot",
		weight = 5.0,
		uses = nil,
	},
	jewel = {
		id = "jewel",
		displayName = "Jewel",
		category = "Loot",
		weight = 0.5,
		uses = nil,
	},
	painting = {
		id = "painting",
		displayName = "Painting",
		category = "Loot",
		weight = 4.0,
		uses = nil,
	},
	hard_drive = {
		id = "hard_drive",
		displayName = "Hard Drive",
		category = "Loot",
		weight = 1.0,
		uses = nil,
	},
}

--- Returns item definition by id, or nil if unknown.
function Inventory.getItemDef(id: string): Item?
	return ITEM_DEFINITIONS[id]
end

--- Creates an empty inventory for a player.
function Inventory.newInventory(maxWeight: number?): PlayerInventory
	return {
		items         = {},
		maxWeight     = maxWeight or 20,
		currentWeight = 0,
		equippedTool  = nil,
	}
end

--- Attempts to add an item. Returns true on success, false if overweight.
function Inventory.addItem(inv: PlayerInventory, itemId: string): boolean
	local def = ITEM_DEFINITIONS[itemId]
	if not def then return false end
	if inv.currentWeight + def.weight > inv.maxWeight then return false end
	table.insert(inv.items, table.clone(def) :: Item)
	inv.currentWeight = inv.currentWeight + def.weight
	return true
end

--- Removes the first occurrence of an item by id. Returns removed item or nil.
function Inventory.removeItem(inv: PlayerInventory, itemId: string): Item?
	for i, item in inv.items do
		if item.id == itemId then
			table.remove(inv.items, i)
			inv.currentWeight = math.max(0, inv.currentWeight - item.weight)
			if inv.equippedTool == itemId then
				inv.equippedTool = nil
			end
			return item
		end
	end
	return nil
end

--- Returns true if the player has at least one of the given item.
function Inventory.hasItem(inv: PlayerInventory, itemId: string): boolean
	for _, item in inv.items do
		if item.id == itemId then return true end
	end
	return false
end

--- Equips a tool from the inventory. Returns false if item not present.
function Inventory.equipTool(inv: PlayerInventory, itemId: string): boolean
	if not Inventory.hasItem(inv, itemId) then return false end
	local def = ITEM_DEFINITIONS[itemId]
	if not def or def.category == "Loot" then return false end
	inv.equippedTool = itemId
	return true
end

--- Consumes one use of the equipped tool. Removes item when uses hit 0.
--- Returns false if equipped tool has no uses remaining or nothing equipped.
function Inventory.useEquippedTool(inv: PlayerInventory): boolean
	if not inv.equippedTool then return false end
	for i, item in inv.items do
		if item.id == inv.equippedTool then
			if item.uses == nil then return true end -- unlimited
			item.uses = (item.uses :: number) - 1
			if (item.uses :: number) <= 0 then
				table.remove(inv.items, i)
				inv.currentWeight = math.max(0, inv.currentWeight - item.weight)
				inv.equippedTool = nil
			end
			return true
		end
	end
	return false
end

--- Returns the speed penalty multiplier (0-1) based on carried weight.
--- Full load (maxWeight) → 0.5× speed.
function Inventory.speedMultiplier(inv: PlayerInventory): number
	local ratio = math.clamp(inv.currentWeight / inv.maxWeight, 0, 1)
	return 1 - (ratio * 0.5)
end

return Inventory
