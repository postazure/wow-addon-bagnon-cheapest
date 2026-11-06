--[[
	Bag scanning, saved exclusions, destroy/sell, slash command.
--]]

local _, ns = ...
local Logic = ns.Logic
local Core = {}
ns.Core = Core

local SCAN_DELAY = 0.15
local QUEST_ITEM_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12

Core.entries = {}
Core.pending = 0
local waiting = {} -- item IDs requested with RequestLoadItemDataByID
local scanQueued = false


--[[ Helpers ]]--

function Core.Print(...)
	print('|cff33ff99Bagnon_Cheapest|r:', ...)
end

function Core.Money(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper or 0)
	end
	return Logic.FormatMoney(copper)
end

function Core.QualityColor(quality)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b, color.hex
	end
	if quality and C_Item.GetItemQualityColor then
		local r, g, b, hex = C_Item.GetItemQualityColor(quality)
		if r then return r, g, b, hex and ('|c' .. hex) end
	end
	return 1, 1, 1, '|cffffffff'
end

function Core.InventoryBags()
	if Bagnon and Bagnon.InventoryBags then
		return Bagnon.InventoryBags
	end
	local bags = {}
	for bag = BACKPACK_CONTAINER or 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
		bags[#bags + 1] = bag
	end
	return bags
end

local function isQuestItem(bag, slot, classID)
	if classID == QUEST_ITEM_CLASS then
		return true
	end
	local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	return quest and (quest.isQuestItem or quest.questID) and true or false
end


--[[ Scanning ]]--

function Core.ReadSlot(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then
		return nil
	end

	local itemID = info.itemID
	local name, link, quality, _, _, _, _, _, _, icon, sellPrice, classID = C_Item.GetItemInfo(itemID)
	if name == nil then
		sellPrice = nil
		if not waiting[itemID] then
			waiting[itemID] = true
			C_Item.RequestLoadItemDataByID(itemID)
		end
	elseif info.hasNoValue then
		sellPrice = 0
	end

	return {
		bag = bag, slot = slot, itemID = itemID,
		count = info.stackCount or 1,
		sellPrice = sellPrice,
		quality = info.quality or quality,
		isQuest = isQuestItem(bag, slot, classID),
		name = info.itemName or name,
		link = info.hyperlink or link,
		icon = info.iconFileID or icon,
	}
end

function Core.Scan()
	scanQueued = false
	local records = {}
	for _, bag in ipairs(Core.InventoryBags()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local rec = Core.ReadSlot(bag, slot)
			if rec then
				records[#records + 1] = rec
			end
		end
	end

	Core.entries, Core.pending = Logic.BuildEntries(records, Bagnon_CheapestDB.excluded)
	if ns.UI then
		ns.UI.Refresh()
	end
	return Core.entries
end

function Core.QueueScan()
	if not scanQueued then
		scanQueued = true
		C_Timer.After(SCAN_DELAY, Core.Scan)
	end
end


--[[ Exclusions ]]--

function Core.Exclude(entry)
	if Logic.Exclude(Bagnon_CheapestDB, entry.itemID, entry.link or entry.name) then
		Core.Print('Excluded', entry.link or entry.name or entry.itemID, '- right-click it under "Show excluded" to restore.')
		Core.Scan()
	end
end

function Core.Restore(itemID)
	if Logic.Restore(Bagnon_CheapestDB, itemID) then
		Core.Scan()
	end
end

function Core.ExcludedEntries()
	return Logic.ExcludedEntries(Bagnon_CheapestDB, function(itemID)
		local _, link = C_Item.GetItemInfo(itemID)
		return link
	end)
end


--[[ Destroy or sell ]]--

local failures = {
	empty = 'that slot is now empty',
	itemchanged = 'a different item is in that slot now',
	countchanged = 'the stack size changed',
	locked = 'the item is locked (being moved or traded)',
}

-- Same test as Blizzard's bags: sell on the Merchant tab, never on Buyback.
function Core.VendorState()
	if MerchantFrame and MerchantFrame:IsShown() then
		return MerchantFrame.selectedTab == 1 and 'sell' or 'buyback'
	end
end

-- Returns the fresh slot info if it's still safe to act, otherwise tells the player why not.
local function precheck(entry, verb)
	if not entry then
		return nil
	end
	if InCombatLockdown() then
		Core.Print(('Not %sing items in combat.'):format(verb))
		return nil
	end
	if CursorHasItem() then
		Core.Print('Your cursor is already holding an item. Put it down first.')
		return nil
	end
	if Bagnon_CheapestDB.excluded[entry.itemID] then
		Core.Scan()
		return nil
	end

	local current = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
	local ok, why = Logic.VerifySlot(entry, current)
	if not ok then
		Core.Print(('Did not %s anything:'):format(verb), failures[why] or why, '- list refreshed.')
		Core.Scan()
		return nil
	end
	if isQuestItem(entry.bag, entry.slot) then
		Core.Print(('Did not %s anything: that is a quest item.'):format(verb))
		Core.Scan()
		return nil
	end
	return current
end

function Core.Destroy(entry)
	local current = precheck(entry, 'destroy')
	if not current then
		return false
	end

	C_Container.PickupContainerItem(entry.bag, entry.slot)

	local held = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
	local heldBag, heldSlot
	if held and held.GetBagAndSlot then
		heldBag, heldSlot = held:GetBagAndSlot()
	end
	if not CursorHasItem() or (held and (heldBag ~= entry.bag or heldSlot ~= entry.slot)) then
		ClearCursor()
		Core.Print('Did not destroy anything: could not pick up that slot.')
		Core.Scan()
		return false
	end

	local link = current.hyperlink or entry.link
	if Logic.NeedsConfirm(current.quality or entry.quality) then
		-- Blizzard's own prompt deletes on accept and clears the cursor on cancel.
		if not StaticPopup_Show('DELETE_GOOD_ITEM', link) then
			ClearCursor()
			Core.Print('Could not open the delete confirmation, nothing destroyed.')
			return false
		end
		return true
	end

	DeleteCursorItem()
	Core.Print('Destroyed', link, 'x' .. (current.stackCount or 1), '(' .. Core.Money(entry.value) .. ')')
	return true
end

function Core.Sell(entry)
	local current = precheck(entry, 'sell')
	if not current then
		return false
	end

	-- Refundable items get a Blizzard confirmation when sold by hand; leave those to the player.
	local purchase = C_Container.GetContainerItemPurchaseInfo(entry.bag, entry.slot, false)
	if purchase and purchase.refundSeconds and purchase.refundSeconds > 0 then
		Core.Print('Did not sell:', current.hyperlink or entry.link, 'can still be refunded. Sell it by hand.')
		return false
	end

	C_Container.UseContainerItem(entry.bag, entry.slot)
	Core.Print('Sold', current.hyperlink or entry.link, 'x' .. (current.stackCount or 1), 'for', Core.Money(entry.value))
	return true
end

function Core.Act(entry)
	local vendor = Core.VendorState()
	if vendor == 'sell' then
		return Core.Sell(entry)
	elseif vendor == 'buyback' then
		Core.Print('The vendor is on its Buyback tab. Switch to the Merchant tab to sell.')
		return false
	end
	return Core.Destroy(entry)
end


--[[ Slash command ]]--

local function printScan()
	local entries = Core.Scan()
	if #entries == 0 then
		Core.Print('Nothing to list.', Core.pending > 0 and (Core.pending .. ' item(s) still loading, try again.') or '')
		return
	end
	Core.Print(('%d item(s), cheapest stack first:'):format(#entries))
	for i, e in ipairs(entries) do
		print(('%2d. %s x%d  %s  (bag %d slot %d)%s'):format(
			i, e.link or e.name or ('item:' .. e.itemID), e.count, Core.Money(e.value), e.bag, e.slot,
			e.stacks > 1 and ('  [' .. e.stacks .. ' stacks]') or ''))
	end
	if Core.pending > 0 then
		Core.Print(Core.pending .. ' item(s) still loading, not listed yet.')
	end
end

SLASH_BAGNONCHEAPEST1 = '/bcheap'
SlashCmdList.BAGNONCHEAPEST = function(msg)
	local cmd = (msg or ''):lower():match('^%s*(%S*)')
	if cmd == 'scan' then
		printScan()
	elseif cmd == '' then
		if ns.UI then ns.UI.TogglePanel() end
	else
		Core.Print('/bcheap - toggle the panel')
		Core.Print('/bcheap scan - print the ranked list to chat')
	end
end


--[[ Events ]]--

local events = CreateFrame('Frame')

function events:PLAYER_LOGIN()
	Bagnon_CheapestDB = Bagnon_CheapestDB or {}
	Bagnon_CheapestDB.excluded = Bagnon_CheapestDB.excluded or {}
	Bagnon_CheapestDB.names = Bagnon_CheapestDB.names or {}

	if ns.UI then
		ns.UI.Init()
	end

	self:RegisterEvent('BAG_UPDATE_DELAYED')
	self:RegisterEvent('GET_ITEM_INFO_RECEIVED')
	self:RegisterEvent('PLAYER_REGEN_ENABLED')
	self:RegisterEvent('PLAYER_REGEN_DISABLED')
	self:RegisterEvent('MERCHANT_SHOW')
	self:RegisterEvent('MERCHANT_CLOSED')
	Core.QueueScan()
end

function events:BAG_UPDATE_DELAYED()
	Core.QueueScan()
end

function events:GET_ITEM_INFO_RECEIVED(itemID)
	if waiting[itemID] then
		waiting[itemID] = nil
		Core.QueueScan()
	end
end

function events:MERCHANT_SHOW()
	if ns.UI then ns.UI.Refresh() end
end
events.MERCHANT_CLOSED = events.MERCHANT_SHOW

function events:PLAYER_REGEN_DISABLED()
	if ns.UI then ns.UI.OnCombat(true) end
end

function events:PLAYER_REGEN_ENABLED()
	if ns.UI then ns.UI.OnCombat(false) end
end

events:SetScript('OnEvent', function(self, event, ...) self[event](self, ...) end)
events:RegisterEvent('PLAYER_LOGIN')
