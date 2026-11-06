--[[
	Smoke test: loads Logic.lua, Core.lua and UI.lua against a STUBBED WoW API and drives
	the main flows. This only proves the Lua wiring and the safety checks in Core.Destroy
	behave as written against these stubs. It says nothing about the real client.
--]]

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; io.write('FAIL ' .. name .. ': ' .. tostring(err) .. '\n') end
end
local function eq(a, e, msg)
	if a ~= e then error((msg or 'differ') .. ': expected ' .. tostring(e) .. ', got ' .. tostring(a), 2) end
end


--[[ Generic frame stub ]]--

local Methods = {}
local function stub(name)
	return setmetatable({ name = name, scripts = {}, shown = false, lines = {} }, {
		__index = function(t, k)
			if Methods[k] then return Methods[k] end
			-- Unknown widget methods are no-ops; unknown plain fields are nil, like real frames.
			if type(k) == 'string' and k:match('^%u') then return function() end end
		end,
	})
end

function Methods.SetScript(self, k, f) self.scripts[k] = f end
function Methods.GetScript(self, k) return self.scripts[k] end
function Methods.Show(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Methods.Hide(self) self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function Methods.SetShown(self, v) if v then self:Show() else self:Hide() end end
function Methods.IsShown(self) return self.shown end
function Methods.IsVisible(self) return self.shown end
local anchoredTo = {}      -- region -> texture last SetAllPoints'd onto it
function Methods.CreateTexture(self) local t = stub('texture'); t.parent = self; return t end
function Methods.SetAllPoints(self, region)
	local prev = rawget(self, 'anchor')
	if prev and anchoredTo[prev] == self then anchoredTo[prev] = nil end
	self.anchor = region
	if region then anchoredTo[region] = self end
end
function Methods.CreateFontString() return stub('fontstring') end
function Methods.CreateAnimationGroup() return stub('anim') end
function Methods.CreateAnimation() return stub('anim') end
function Methods.GetFont() return 'font', 12, '' end
function Methods.GetWidth() return 37 end
function Methods.GetFrameLevel() return 5 end
function Methods.GetFrameStrata() return 'HIGH' end
function Methods.GetRight() return 100 end
function Methods.GetEffectiveScale() return 1 end
function Methods.SetText(self, t) self.text = t end
function Methods.SetPoint(self, point) local p = rawget(self, 'points') or {}; p[#p + 1] = point; self.points = p end
function Methods.GetName(self) return self.name end
function Methods.SetTexture(self, t) self.texture = t end
function Methods.SetColorTexture(self, r, g, b) self.color = { r, g, b } end
-- tooltip
function Methods.SetOwner(self, o) self.owner = o; self.lines = {} end
function Methods.IsOwned(self, o) return self.owner == o end
function Methods.AddLine(self, t) self.lines[#self.lines + 1] = t end
function Methods.AddDoubleLine(self, a, b) self.lines[#self.lines + 1] = a .. ' | ' .. b end
function Methods.SetBagItem(self, bag, slot) self.bagItem = bag .. ':' .. slot end
function Methods.GetThumbTexture(self) local t = rawget(self, 'thumb') or stub('thumb'); self.thumb = t; return t end


--[[ WoW globals ]]--

local log = {}
local function reset()
	log.deleted, log.popup, log.cleared, log.printed, log.sold = 0, nil, 0, {}, 0
end
reset()

local bags = {}            -- bags[bag][slot] = { itemID, stackCount, quality, isLocked, quest }
local items = {}           -- items[itemID] = { name, sellPrice, quality, classID }
local cursor = nil         -- { bag, slot } while holding
local combat = false

_G.UIParent = stub('UIParent')
_G.GameTooltip = stub('GameTooltip')
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.Enum = { ItemClass = { Questitem = 12 } }
_G.ITEM_QUALITY_COLORS = { [0] = { r = .6, g = .6, b = .6, hex = '|cff9d9d9d' }, [1] = { r = 1, g = 1, b = 1, hex = '|cffffffff' }, [2] = { r = 0, g = 1, b = 0, hex = '|cff1eff00' } }
_G.StaticPopupDialogs = { DELETE_GOOD_ITEM = {} }
_G.GetScreenWidth = function() return 1000 end
local shift = false
_G.IsShiftKeyDown = function() return shift end
_G.InCombatLockdown = function() return combat end
_G.CursorHasItem = function() return cursor ~= nil end
_G.ClearCursor = function() cursor = nil; log.cleared = log.cleared + 1 end
_G.DeleteCursorItem = function()
	assert(cursor, 'DeleteCursorItem with empty cursor')
	bags[cursor.bag][cursor.slot] = nil
	cursor = nil
	log.deleted = log.deleted + 1
end
_G.StaticPopup_Show = function(which, arg1) log.popup = { which = which, arg = arg1 }; return stub('popup') end
_G.print = function(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end log.printed[#log.printed + 1] = table.concat(t, ' ') end
_G.tinsert = table.insert

local timers = {}
_G.C_Timer = { After = function(_, f) timers[#timers + 1] = f end }
local function runTimers() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end

_G.C_CurrencyInfo = { GetCoinTextureString = function(c) return 'COIN(' .. c .. ')' end }
_G.C_Cursor = { GetCursorItem = function()
	if cursor then
		local c = cursor
		return { GetBagAndSlot = function() return c.bag, c.slot end }
	end
end }
_G.C_Container = {
	GetContainerNumSlots = function(bag) return bags[bag] and 4 or 0 end,
	GetContainerItemInfo = function(bag, slot)
		local s = bags[bag] and bags[bag][slot]
		if not s then return nil end
		local it = items[s.itemID]
		return { itemID = s.itemID, stackCount = s.stackCount, quality = it.quality, isLocked = s.isLocked,
		         hyperlink = '|cffffffff|Hitem:' .. s.itemID .. '|h[' .. it.name .. ']|h|r', itemName = it.name, iconFileID = 'icon' .. s.itemID }
	end,
	GetContainerItemQuestInfo = function(bag, slot)
		local s = bags[bag] and bags[bag][slot]
		return { isQuestItem = s and s.quest or false, isActive = false }
	end,
	PickupContainerItem = function(bag, slot) cursor = { bag = bag, slot = slot } end,
	UseContainerItem = function(bag, slot)
		assert(_G.MerchantFrame and _G.MerchantFrame.shown, 'UseContainerItem away from a vendor would USE the item')
		bags[bag][slot] = nil
		log.sold = (log.sold or 0) + 1
	end,
	GetContainerItemPurchaseInfo = function(bag, slot)
		local s = bags[bag] and bags[bag][slot]
		if s and s.refund then return { money = 1, itemCount = 0, refundSeconds = 3600, currencyCount = 0, hasEnchants = false } end
	end,
}
local requested = {}
_G.C_Item = {
	GetItemInfo = function(id)
		local it = items[id]
		if not it or it.uncached then return nil end
		return it.name, 'link' .. id, it.quality, 1, 1, 't', 's', 20, '', 1, it.sellPrice, it.classID or 0
	end,
	GetItemInfoInstant = function(id) return id, nil, nil, nil, 1 end,
	RequestLoadItemDataByID = function(id) requested[id] = true end,
	GetItemQualityColor = function() return 1, 1, 1, 'ffffffff' end,
}

local eventFrame
_G.CreateFrame = function(kind, name, parent, template)
	local f = stub(name or kind)
	f.template = template
	if template == 'BagnonButtonTemplate' then
		f.Icon = stub('texture') -- parentKey="Icon" in Bagnon/src/templates.xml
	end
	if name then _G[name] = f end
	if not eventFrame and kind == 'Frame' and not name then
		eventFrame = f
		f.RegisterEvent = function() end
	end
	return f
end
local function fire(event, ...) eventFrame.scripts.OnEvent(eventFrame, event, ...) end

-- Bagnon stub: one inventory frame with an ItemGroup holding buttons per bag/slot.
local layouts = 0
local invFrame = stub('BagnonInventory')
invFrame[0] = true
invFrame.id = 'inventory'
invFrame.shown = true
invFrame.Layout = function() layouts = layouts + 1 end
invFrame.IsCached = function() return false end
local group = { byBag = {} }
group.buttons = {}
for bag = 0, 1 do
	group.byBag[bag] = {}
	for slot = 1, 4 do
		local b = stub('item' .. bag .. slot)
		b.shown, b.alpha, b.restored = true, 1, 0
		b.bag = bag
		local id = slot
		b.GetID = function() return id end
		b.SetAlpha = function(self, a) self.alpha = a end
		b.UpdateBorder = function(self) self.alpha, self.desat = 1, false; self.restored = self.restored + 1 end
		group.byBag[bag][slot] = b
		group.buttons[#group.buttons + 1] = b
	end
end
_G.SetItemButtonDesaturated = function(b, d) b.desat = d end
rawset(invFrame, 'ItemGroup', group)

_G.Bagnon = {
	InventoryBags = { 0, 1 },
	Inventory = { GetExtraButtons = function(self) return { false } end },
	Frames = { Get = function(_, id) return invFrame end },
}


--[[ Load the addon like the client does ]]--

local ns = {}
for _, file in ipairs { 'Logic.lua', 'Core.lua', 'UI.lua' } do
	local chunk = assert(loadstring(io.open('Bagnon_Cheapest/' .. file):read('*a'), '@' .. file))
	chunk('Bagnon_Cheapest', ns)
end

items[100] = { name = 'Gray Junk', sellPrice = 3, quality = 0 }
items[200] = { name = 'Linen Cloth', sellPrice = 10, quality = 1 }
items[300] = { name = 'Green Sword', sellPrice = 50, quality = 2 }
items[400] = { name = 'Quest Thing', sellPrice = 1, quality = 1, classID = 12 }
items[500] = { name = 'Not Cached', sellPrice = 1, quality = 1, uncached = true }
items[600] = { name = 'Hearthstone', sellPrice = 0, quality = 1 }

local function fill()
	bags[0] = { [1] = { itemID = 200, stackCount = 20 }, [2] = { itemID = 100, stackCount = 2 },
	            [3] = { itemID = 300, stackCount = 1 }, [4] = { itemID = 400, stackCount = 1 } }
	bags[1] = { [1] = { itemID = 200, stackCount = 1 }, [2] = { itemID = 500, stackCount = 1 },
	            [3] = { itemID = 600, stackCount = 1 } }
end
fill()

fire('PLAYER_LOGIN')
runTimers()


--[[ Tests ]]--

test('login hooks Bagnon and adds the button', function()
	local list = Bagnon.Inventory.GetExtraButtons(invFrame)
	eq(#list, 1, 'false entries dropped, our button appended')
	eq(list[1], _G.Bagnon_CheapestButton)
	eq(layouts, 1, 'relayout on login')
end)

test('bank-like frames do not get the button', function()
	local list = Bagnon.Inventory.GetExtraButtons({ id = 'bank' })
	eq(#list, 0)
end)

test('scan ranks entries and skips quest, no-value, pending', function()
	local e = ns.Core.entries
	eq(#e, 3)
	eq(e[1].itemID, 100, 'gray 2 x 3c = 6c is cheapest')
	eq(e[2].itemID, 200, 'linen: cheapest stack is the single at 10c')
	eq(e[2].stacks, 2)
	eq(e[2].bag, 1)
	eq(e[2].value, 10)
	eq(e[3].itemID, 300)
end)

test('requested uncached item data', function()
	eq(requested[500], true)
	eq(ns.Core.pending, 1)
end)

test('GET_ITEM_INFO_RECEIVED for a waited item triggers one batched rescan', function()
	runTimers() -- flush anything queued by earlier tests
	items[500].uncached = nil
	fire('GET_ITEM_INFO_RECEIVED', 500, true)
	fire('BAG_UPDATE_DELAYED')
	fire('BAG_UPDATE_DELAYED')
	eq(#timers, 1, 'batched')
	runTimers()
	eq(ns.Core.pending, 0)
	eq(ns.Core.entries[1].itemID, 100, 'grey stays first')
	eq(ns.Core.entries[2].itemID, 500, '1c item is cheapest non-grey')
	items[500].uncached = true
	ns.Core.Scan()
end)

test('button shows cheapest icon, quality border, compact price', function()
	local b = _G.Bagnon_CheapestButton
	eq(b.price.text:find('^6') ~= nil, true, b.price.text)
	eq(b.price.text:find('c|r$') ~= nil, true, 'copper unit')
	eq(b.template, 'BagnonButtonTemplate', 'same template as Bagnon menu buttons')
	eq(rawget(b, 'border'), nil, 'no custom border')
end)

test('hover shows tooltip with next cheapest and highlights slot', function()
	local b = _G.Bagnon_CheapestButton
	b.scripts.OnEnter(b)
	eq(GameTooltip.bagItem, ns.Core.entries[1].bag .. ':' .. ns.Core.entries[1].slot)
	local text = table.concat(GameTooltip.lines, '\n')
	eq(text:find('Next cheapest') ~= nil, true, 'next cheapest section')
	b.scripts.OnLeave(b)
end)

local function shaded(b)
	local t = anchoredTo[b]
	return t ~= nil and t.shown and t.parent.shown
end

test('hover darkens every other slot with our overlay, leave clears it instantly', function()
	local e = ns.Core.entries[1]
	local target = group.byBag[e.bag][e.slot]
	local b = _G.Bagnon_CheapestButton
	b.scripts.OnEnter(b)
	eq(shaded(target), false, 'target not darkened')
	for _, other in ipairs(group.buttons) do
		if other ~= target then eq(shaded(other), true, other.name) end
		eq(other.alpha, 1, 'Bagnon button alpha untouched')
		eq(other.restored, 0, 'Bagnon UpdateBorder never called')
	end
	b.scripts.OnLeave(b)
	runTimers()
	for _, other in ipairs(group.buttons) do eq(shaded(other), false, 'panel closed: no shade') end
end)

test('moving between panel rows moves the shade with no leftovers', function()
	ns.UI.HighlightSlot(0, 1)
	ns.UI.HighlightSlot(0, 2)
	eq(shaded(group.byBag[0][2]), false, 'new target clear')
	eq(shaded(group.byBag[0][1]), true, 'old target now darkened')
	ns.UI.ClearHighlight()
	runTimers()
	for _, other in ipairs(group.buttons) do eq(shaded(other), false) end
end)

test('leaving a row then entering another never flashes back to normal', function()
	ns.UI.HighlightSlot(0, 1)
	ns.UI.ClearHighlight()              -- OnLeave of row 1
	ns.UI.HighlightSlot(0, 2)           -- OnEnter of row 2, before the delay
	runTimers()                         -- the stale clear must not fire
	eq(shaded(group.byBag[0][1]), true)
	eq(shaded(group.byBag[0][2]), false)
	ns.UI.ClearHighlight(); runTimers()
end)

test('hidden slots (filtered bag or search) are not shaded', function()
	group.byBag[1][4].shown = false
	ns.UI.HighlightSlot(0, 1)
	eq(shaded(group.byBag[1][4]), false)
	ns.UI.ClearHighlight(); runTimers()
	group.byBag[1][4].shown = true
end)

test('opening the panel rescans and renders immediately', function()
	local panel = _G.Bagnon_CheapestPanel
	if panel and panel.shown then ns.UI.TogglePanel() end
	ns.Core.entries = {}                -- stale/empty data before opening
	timers = {}
	ns.UI.TogglePanel()
	panel = _G.Bagnon_CheapestPanel
	eq(panel.rows[1].shown, true, 'filled on open without any other event')
	eq(panel.rows[1].entry.itemID, 100)
	ns.UI.TogglePanel()
end)

test('panel builds fully on the first open (slider present)', function()
	local panel = _G.Bagnon_CheapestPanel
	eq(type(rawget(panel, 'slider')), 'table')
	eq(type(panel.scripts.OnShow), 'function')
end)

test('plain click on the Bagnon button toggles the panel, does not destroy', function()
	reset()
	shift = false
	local b = _G.Bagnon_CheapestButton
	b.scripts.OnClick(b)
	eq(_G.Bagnon_CheapestPanel.shown, true)
	eq(log.deleted, 0)
	b.scripts.OnClick(b)
	eq(_G.Bagnon_CheapestPanel.shown, false)
end)

test('panel open, list view: only listed stacks stay bright, others stay dark', function()
	runTimers()
	ns.UI.TogglePanel(); runTimers()
	local listed = {}
	for _, e in ipairs(ns.Core.entries) do listed[group.byBag[e.bag][e.slot]] = true end
	for _, b in ipairs(group.buttons) do
		eq(shaded(b), not listed[b], b.name)
	end
	-- hover then leave returns to this baseline, still dark
	ns.UI.HighlightSlot(0, 2); ns.UI.ClearHighlight(); runTimers()
	for _, b in ipairs(group.buttons) do eq(shaded(b), not listed[b], 'baseline restored ' .. b.name) end
	ns.UI.TogglePanel(); runTimers()
	for _, b in ipairs(group.buttons) do eq(shaded(b), false, 'closing the panel clears') end
end)

test('panel open, excluded view: only excluded items stay bright; hover narrows to that item', function()
	Bagnon_CheapestDB.excluded[200] = true; ns.Core.Scan()  -- linen in bag0 slot1 and bag1 slot1
	ns.UI.TogglePanel(); runTimers()
	local panel = _G.Bagnon_CheapestPanel
	panel.toggle.scripts.OnClick(panel.toggle)
	for _, b in ipairs(group.buttons) do
		local s = bags[b.bag][b:GetID()]
		eq(shaded(b), not (s and s.itemID == 200), 'excluded baseline ' .. b.name)
	end
	panel.rows[1].scripts.OnEnter(panel.rows[1])
	eq(shaded(group.byBag[0][1]), false); eq(shaded(group.byBag[1][1]), false)
	eq(shaded(group.byBag[0][2]), true)
	panel.toggle.scripts.OnClick(panel.toggle)
	ns.UI.TogglePanel(); runTimers()
	Bagnon_CheapestDB.excluded[200] = nil; ns.Core.Scan()
end)

test('shift-click destroys a common stack directly', function()
	reset()
	local e = ns.Core.entries[1]
	local b = _G.Bagnon_CheapestButton
	shift = true
	b.scripts.OnClick(b)
	shift = false
	eq(log.deleted, 1)
	eq(e.itemID, 100)
	eq(bags[e.bag][e.slot], nil)
	eq(bags[0][1] ~= nil and bags[1][1] ~= nil, true, 'other stacks untouched')
	fill(); ns.Core.Scan()
end)

test('aborts when count changed since display', function()
	reset()
	local e = ns.Core.entries[1]
	bags[e.bag][e.slot].stackCount = 7
	eq(ns.Core.Destroy(e), false)
	eq(log.deleted, 0)
	eq(cursor, nil)
	fill(); ns.Core.Scan()
end)

test('aborts when item changed since display', function()
	reset()
	local e = ns.Core.entries[1]
	bags[e.bag][e.slot] = { itemID = 300, stackCount = 1 }
	eq(ns.Core.Destroy(e), false)
	eq(log.deleted, 0)
	fill(); ns.Core.Scan()
end)

test('aborts when cursor already holds an item', function()
	reset()
	cursor = { bag = 0, slot = 3 }
	eq(ns.Core.Destroy(ns.Core.entries[1]), false)
	eq(log.deleted, 0)
	eq(cursor.slot, 3, 'cursor left alone')
	cursor = nil
end)

test('aborts in combat', function()
	reset()
	combat = true
	fire('PLAYER_REGEN_DISABLED')
	eq(ns.Core.Destroy(ns.Core.entries[1]), false)
	eq(log.deleted, 0)
	combat = false
	fire('PLAYER_REGEN_ENABLED')
end)

test('uncommon item goes through Blizzard DELETE_GOOD_ITEM prompt, not direct delete', function()
	reset()
	local green
	for _, e in ipairs(ns.Core.entries) do if e.itemID == 300 then green = e end end
	eq(ns.Core.Destroy(green), true)
	eq(log.deleted, 0, 'no direct delete')
	eq(log.popup.which, 'DELETE_GOOD_ITEM')
	eq(cursor.slot, 3, 'item held for the prompt')
	ClearCursor()
end)

test('exclude removes from list and persists in saved DB; restore brings it back', function()
	local first = ns.Core.entries[1]
	ns.Core.Exclude(first)
	eq(Bagnon_CheapestDB.excluded[first.itemID], true)
	for _, e in ipairs(ns.Core.entries) do eq(e.itemID ~= first.itemID, true) end
	eq(#ns.Core.ExcludedEntries(), 1)
	ns.Core.Restore(first.itemID)
	eq(Bagnon_CheapestDB.excluded[first.itemID], nil)
	eq(ns.Core.entries[1].itemID, first.itemID)
end)

test('panel renders list, excluded view, right-click exclude and restore', function()
	ns.UI.TogglePanel()
	local panel = _G.Bagnon_CheapestPanel
	eq(panel.shown, true)
	local row = panel.rows[1]
	eq(row.entry.itemID, ns.Core.entries[1].itemID)
	eq(row.shown, true)
	eq(panel.rows[4].shown, false)

	local id = row.entry.itemID
	row.scripts.OnClick(row, 'RightButton')
	eq(Bagnon_CheapestDB.excluded[id], true)

	panel.toggle.scripts.OnClick(panel.toggle)
	eq(ns.UI.showExcluded, true)
	eq(panel.rows[1].entry.itemID, id)
	panel.rows[1].scripts.OnClick(panel.rows[1], 'RightButton')
	eq(Bagnon_CheapestDB.excluded[id], nil)
	panel.toggle.scripts.OnClick(panel.toggle)
end)

test('button icon follows the targeted item, question mark when empty', function()
	local b = _G.Bagnon_CheapestButton
	eq(ns.Core.entries[1].itemID, 100)
	eq(b.icon.texture, 'icon100')
	Bagnon_CheapestDB.excluded[100] = true; ns.Core.Scan()
	eq(b.icon.texture, 'icon' .. ns.Core.entries[1].itemID, 'next target icon')
	Bagnon_CheapestDB.excluded[100] = nil
	bags[0], bags[1] = {}, {}; ns.Core.Scan()
	eq(b.icon.texture, 'Interface/Icons/INV_Misc_QuestionMark', 'empty list')
	fill(); ns.Core.Scan()
end)

test('panel rows anchor only on their top edge (no TOP plus centre mix)', function()
	for i, row in ipairs(_G.Bagnon_CheapestPanel.rows) do
		for _, p in ipairs(row.points) do
			eq(p == 'TOPLEFT' or p == 'TOPRIGHT', true, 'row ' .. i .. ' point ' .. p)
		end
	end
end)

local function openVendor(tab)
	_G.MerchantFrame = stub('MerchantFrame')
	_G.MerchantFrame.shown = true
	_G.MerchantFrame.selectedTab = tab
end
local function closeVendor() _G.MerchantFrame.shown = false end

test('away from a vendor, Shift-click destroys (no sell)', function()
	reset(); _G.MerchantFrame = nil
	local b = _G.Bagnon_CheapestButton
	shift = true; b.scripts.OnClick(b); shift = false
	eq(log.deleted, 1); eq(log.sold, 0)
	fill(); ns.Core.Scan()
end)

test('at a vendor (Merchant tab), Shift-click sells instead of destroying', function()
	reset(); openVendor(1)
	local e = ns.Core.entries[1]
	local b = _G.Bagnon_CheapestButton
	b.scripts.OnEnter(b)
	local text = table.concat(GameTooltip.lines, string.char(10))
	eq(text:find('Sell this stack', 1, true) ~= nil, true, text)
	b.scripts.OnLeave(b); runTimers()
	shift = true; b.scripts.OnClick(b); shift = false
	eq(log.sold, 1); eq(log.deleted, 0)
	eq(bags[e.bag][e.slot], nil)
	eq(cursor, nil, 'cursor not used for selling')
	closeVendor(); fill(); ns.Core.Scan()
end)

test('at a vendor, panel left-click sells; green items sell without the DELETE prompt', function()
	reset(); openVendor(1)
	local green
	for _, e in ipairs(ns.Core.entries) do if e.itemID == 300 then green = e end end
	eq(ns.Core.Act(green), true)
	eq(log.sold, 1); eq(log.popup, nil); eq(log.deleted, 0)
	closeVendor(); fill(); ns.Core.Scan()
end)

test('vendor on Buyback tab: nothing is sold or destroyed', function()
	reset(); openVendor(2)
	eq(ns.Core.Act(ns.Core.entries[1]), false)
	eq(log.sold, 0); eq(log.deleted, 0)
	eq(table.concat(log.printed, ' '):find('Buyback') ~= nil, true)
	closeVendor()
end)

test('refundable item is not sold by the addon', function()
	reset(); openVendor(1)
	local e = ns.Core.entries[1]
	bags[e.bag][e.slot].refund = true
	eq(ns.Core.Act(e), false)
	eq(log.sold, 0)
	bags[e.bag][e.slot].refund = nil
	closeVendor()
end)

test('selling is blocked in combat and when the slot changed', function()
	reset(); openVendor(1)
	combat = true
	eq(ns.Core.Act(ns.Core.entries[1]), false)
	combat = false
	local e = ns.Core.entries[1]
	bags[e.bag][e.slot].stackCount = 9
	eq(ns.Core.Act(e), false)
	eq(log.sold, 0)
	closeVendor(); fill(); ns.Core.Scan()
end)

test('click hints use Bagnon mouse icons, with a plain-text fallback', function()
	local seen = {}
	Bagnon.Tipped = { MarkupTooltip = function(text)
		seen[#seen + 1] = text
		return (text:gsub('|LS', '<SHIFTLEFT>'):gsub('|L', '<LEFT>'):gsub('|R', '<RIGHT>')), nil
	end }
	local b = _G.Bagnon_CheapestButton
	b.scripts.OnEnter(b)
	local text = table.concat(GameTooltip.lines, string.char(10))
	eq(text:find('<SHIFTLEFT> Destroy this stack', 1, true) ~= nil, true, text)
	eq(text:find('<LEFT> Show list', 1, true) ~= nil, true)
	b.scripts.OnLeave(b); runTimers()

	Bagnon.Tipped = nil
	b.scripts.OnEnter(b)
	text = table.concat(GameTooltip.lines, string.char(10))
	eq(text:find('Shift-left-click: Destroy this stack', 1, true) ~= nil, true, text)
	eq(text:find('Left-click: Show list', 1, true) ~= nil, true)
	b.scripts.OnLeave(b); runTimers()
end)

test('slash scan prints ranked list', function()
	reset()
	SlashCmdList.BAGNONCHEAPEST('scan')
	local text = table.concat(log.printed, '\n')
	eq(text:find(' 1%. ') ~= nil, true)
	eq(text:find('stacks') ~= nil, true)
end)

io.write(('%d passed, %d failed\n'):format(passed, failed))
if failed > 0 then error('smoke tests failed', 0) end
