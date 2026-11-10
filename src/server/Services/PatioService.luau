-- Patio rules (server only). Pure functions on player data, so tests can run them directly.
--   data.inventory = { [itemId] = count }       items you own but haven't placed
--   data.patio     = { s1 = itemId, s2 = ... }  what stands on each of your 4 patio spots
-- (string keys "s1".."s4": DataStores don't like arrays with holes)
-- Coin items are bought here; Robux items are granted by ShopService after Roblox's payment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local PatioService = {}

local function ensure(data)
	data.inventory = data.inventory or {}
	data.patio = data.patio or {}
	data.patioColors = data.patioColors or {} -- { s1 = "red" } for colorable items (flags)
end

local function spotKey(spot): string?
	if type(spot) ~= "number" or spot ~= math.floor(spot) or spot < 1 or spot > Config.PATIO_SPOTS then
		return nil
	end
	return "s" .. spot
end

-- Adds one item to the inventory (used by coin buys AND Robux grants). Returns false when full.
function PatioService.give(data, itemId: string): boolean
	ensure(data)
	local have = data.inventory[itemId] or 0
	if have >= Config.PATIO_MAX_OWNED then
		return false
	end
	data.inventory[itemId] = have + 1
	return true
end

function PatioService.take(data, itemId: string)
	ensure(data)
	local have = data.inventory[itemId] or 0
	data.inventory[itemId] = if have > 1 then have - 1 else nil
end

function PatioService.buy(data, itemId)
	local item = type(itemId) == "string" and Config.PatioById[itemId]
	if not item then
		return false, "Bad request"
	end
	if not item.price then
		return false, item.name .. " is a Robux item"
	end
	if data.coins < item.price then
		return false, ("%s costs %d coins"):format(item.name, item.price)
	end
	if not PatioService.give(data, item.id) then
		return false, ("You already have %d %s"):format(Config.PATIO_MAX_OWNED, item.name)
	end
	data.coins -= item.price
	return true, item.name .. " bought! Go to your tank and press E on a sand circle to place it."
end

-- Puts an owned item on a spot. Anything already there goes back to the inventory.
-- colorKey: only for colorable items (flags), one of Config.PATIO_COLORS keys.
function PatioService.place(data, spot, itemId, colorKey)
	ensure(data)
	local key = spotKey(spot)
	local item = type(itemId) == "string" and Config.PatioById[itemId]
	if not key or not item then
		return false, "Bad request"
	end
	if item.colorable then
		colorKey = colorKey or Config.PATIO_DEFAULT_COLOR
		if type(colorKey) ~= "string" or not Config.PatioColorByKey[colorKey] then
			return false, "Bad request"
		end
	else
		colorKey = nil
	end
	local old = data.patio[key]
	if old == item.id then
		-- same item already on this spot: only a recolour is allowed (needs no item in the inventory)
		if colorKey and data.patioColors[key] ~= colorKey then
			data.patioColors[key] = colorKey -- same flag, new colour: no inventory change
			return true, ("%s is now %s"):format(item.name, Config.PatioColorByKey[colorKey].name)
		end
		return false, item.name .. " is already there"
	end
	if (data.inventory[item.id] or 0) <= 0 then
		return false, "You don't have a " .. item.name .. " yet"
	end
	if old and (data.inventory[old] or 0) >= Config.PATIO_MAX_OWNED then
		return false, "Pick up what's there first (your inventory is full of those)"
	end
	PatioService.take(data, item.id)
	if old then
		PatioService.give(data, old) -- swap: the old item goes back to the inventory
	end
	data.patio[key] = item.id
	data.patioColors[key] = colorKey
	return true, item.name .. " placed!"
end

function PatioService.pickUp(data, spot)
	ensure(data)
	local key = spotKey(spot)
	if not key then
		return false, "Bad request"
	end
	local old = data.patio[key]
	if not old then
		return false, "Nothing here"
	end
	if not PatioService.give(data, old) then
		return false, "Your inventory is full of those"
	end
	data.patio[key] = nil
	data.patioColors[key] = nil
	local item = Config.PatioById[old]
	return true, (if item then item.name else old) .. " picked up"
end

function PatioService.publicState(data)
	ensure(data)
	return { inventory = data.inventory, patio = data.patio, colors = data.patioColors }
end

return PatioService
