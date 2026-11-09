--[[
	Pure logic, no WoW API calls (unit tested outside the game).

	A slot record describes one occupied bag slot:
		{ bag, slot, itemID, count, sellPrice, quality, isQuest, name, link, icon }
	sellPrice is the per-item vendor price in copper, or nil while item data is loading.
--]]

local Logic = {}

local floor, sort = math.floor, table.sort


--[[ Value ]]--

function Logic.StackValue(sellPrice, count)
	if type(sellPrice) ~= 'number' or sellPrice <= 0 then
		return nil
	end
	count = (type(count) == 'number' and count > 0) and count or 1
	return sellPrice * count
end

function Logic.IsCandidate(rec, excluded)
	if not rec or not rec.itemID then
		return false, 'empty'
	end
	if excluded and excluded[rec.itemID] then
		return false, 'excluded'
	end
	if rec.isQuest then
		return false, 'quest'
	end
	if rec.sellPrice == nil then
		return false, 'pending'
	end
	if not Logic.StackValue(rec.sellPrice, rec.count) then
		return false, 'novalue'
	end
	return true
end


--[[ Grouping and sorting ]]--

local function cheaper(a, b)
	if a.value ~= b.value then return a.value < b.value end
	if a.count ~= b.count then return a.count < b.count end
	if a.bag ~= b.bag then return a.bag < b.bag end
	return a.slot < b.slot
end

local function byValue(a, b)
	if a.value ~= b.value then return a.value < b.value end
	local an, bn = a.name or '', b.name or ''
	if an ~= bn then return an < bn end
	return a.itemID < b.itemID
end

local function greyFirst(a, b)
	local ag, bg = a.quality == 0, b.quality == 0
	if ag ~= bg then return ag end
	return byValue(a, b)
end

-- One entry per item ID: its cheapest stack plus the number of stacks.
-- Grey items come first unless anyQuality is set.
-- Also returns how many records were skipped while their item data loads.
function Logic.BuildEntries(records, excluded, anyQuality)
	local byItem, pending = {}, 0

	for _, rec in ipairs(records or {}) do
		local ok, reason = Logic.IsCandidate(rec, excluded)
		if ok then
			local stack = {
				itemID = rec.itemID, bag = rec.bag, slot = rec.slot,
				count = rec.count or 1, value = Logic.StackValue(rec.sellPrice, rec.count),
				quality = rec.quality, name = rec.name, link = rec.link, icon = rec.icon,
			}

			local entry = byItem[rec.itemID]
			if not entry then
				stack.stacks = 1
				byItem[rec.itemID] = stack
			elseif cheaper(stack, entry) then
				stack.stacks = entry.stacks + 1
				byItem[rec.itemID] = stack
			else
				entry.stacks = entry.stacks + 1
			end
		elseif reason == 'pending' then
			pending = pending + 1
		end
	end

	local entries = {}
	for _, entry in pairs(byItem) do
		entries[#entries + 1] = entry
	end
	sort(entries, anyQuality and byValue or greyFirst)
	return entries, pending
end

-- The entries the bag button may offer: quality at or below maxQuality.
-- Unknown quality only passes when every quality does.
function Logic.ButtonEntries(entries, maxQuality)
	local out = {}
	for _, e in ipairs(entries) do
		if (e.quality or math.huge) <= (maxQuality or 0) then
			out[#out + 1] = e
		end
	end
	return out
end

function Logic.Slice(entries, first, n)
	local out = {}
	for i = first, math.min(#entries, first + n - 1) do
		out[#out + 1] = entries[i]
	end
	return out
end


--[[ Exclusions ]]--

function Logic.Exclude(db, itemID, label)
	if type(itemID) ~= 'number' then return false end
	db.excluded = db.excluded or {}
	db.names = db.names or {}
	db.excluded[itemID] = true
	if label then
		db.names[itemID] = label
	end
	return true
end

function Logic.Restore(db, itemID)
	if db.excluded and db.excluded[itemID] then
		db.excluded[itemID] = nil
		return true
	end
	return false
end

function Logic.ExcludedEntries(db, nameOf)
	local out = {}
	for itemID in pairs(db.excluded or {}) do
		local name = (nameOf and nameOf(itemID)) or (db.names and db.names[itemID]) or ('item:' .. itemID)
		out[#out + 1] = { itemID = itemID, name = name }
	end
	sort(out, function(a, b)
		local an, bn = Logic.StripLink(a.name):lower(), Logic.StripLink(b.name):lower()
		if an ~= bn then return an < bn end
		return a.itemID < b.itemID
	end)
	return out
end

-- "|cff...|Hitem:...|h[Name]|h|r" -> "Name"
function Logic.StripLink(text)
	text = tostring(text or '')
	text = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
	text = text:gsub('|H.-|h(.-)|h', '%1')
	return (text:gsub('^%[(.*)%]$', '%1'))
end


--[[ Safety ]]--

-- Compares a fresh read of the slot with what was shown to the player.
function Logic.VerifySlot(entry, current)
	if not entry then return false, 'noentry' end
	if not current or not current.itemID then return false, 'empty' end
	if current.itemID ~= entry.itemID then return false, 'itemchanged' end
	if (current.stackCount or 1) ~= (entry.count or 1) then return false, 'countchanged' end
	if current.isLocked then return false, 'locked' end
	return true
end

Logic.CONFIRM_QUALITY = 2 -- Uncommon and better go through Blizzard's typed DELETE prompt

function Logic.NeedsConfirm(quality)
	return type(quality) ~= 'number' or quality >= Logic.CONFIRM_QUALITY
end


--[[ Money ]]--

function Logic.SplitMoney(copper)
	copper = floor(tonumber(copper) or 0)
	if copper < 0 then copper = 0 end
	return floor(copper / 10000), floor(copper / 100) % 100, copper % 100
end

function Logic.FormatMoney(copper)
	local g, s, c = Logic.SplitMoney(copper)
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. 'g' end
	if s > 0 then parts[#parts + 1] = s .. 's' end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. 'c' end
	return table.concat(parts, ' ')
end

-- Largest denomination only, e.g. 12345 -> 1, 'g'
function Logic.CompactMoney(copper)
	local g, s, c = Logic.SplitMoney(copper)
	if g > 0 then return g, 'g' end
	if s > 0 then return s, 's' end
	return c, 'c'
end


local _, ns = ...
if type(ns) == 'table' then
	ns.Logic = Logic
end
return Logic
