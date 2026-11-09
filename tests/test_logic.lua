-- Unit tests for Bagnon_Cheapest/Logic.lua. Plain Lua 5.1, no WoW API.
-- Run: lua tests/test_logic.lua   (or: python tests/run.py)

local Logic = dofile('Bagnon_Cheapest/Logic.lua')

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print('FAIL ' .. name .. ': ' .. tostring(err))
	end
end

local function eq(actual, expected, msg)
	if actual ~= expected then
		error((msg or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
	end
end

local function rec(t)
	t.bag = t.bag or 0
	t.slot = t.slot or 1
	t.count = t.count or 1
	t.name = t.name or ('Item ' .. t.itemID)
	return t
end


--[[ StackValue ]]--

test('value is price times count', function()
	eq(Logic.StackValue(25, 4), 100)
end)

test('value with missing count counts as one', function()
	eq(Logic.StackValue(25, nil), 25)
end)

test('zero or missing sell price has no value', function()
	eq(Logic.StackValue(0, 5), nil)
	eq(Logic.StackValue(nil, 5), nil)
end)


--[[ Filtering ]]--

test('skips items with no sell price', function()
	local entries = Logic.BuildEntries({ rec{ itemID = 1, sellPrice = 0 } }, {})
	eq(#entries, 0)
end)

test('skips quest items', function()
	local entries = Logic.BuildEntries({ rec{ itemID = 1, sellPrice = 5, isQuest = true } }, {})
	eq(#entries, 0)
end)

test('skips excluded item IDs', function()
	local entries = Logic.BuildEntries({
		rec{ itemID = 1, sellPrice = 5 },
		rec{ itemID = 2, sellPrice = 9, slot = 2 },
	}, { [1] = true })
	eq(#entries, 1)
	eq(entries[1].itemID, 2)
end)

test('uncached items are counted as pending, not listed', function()
	local entries, pending = Logic.BuildEntries({
		rec{ itemID = 1, sellPrice = nil },
		rec{ itemID = 2, sellPrice = nil, slot = 2 },
		rec{ itemID = 3, sellPrice = 4, slot = 3 },
	}, {})
	eq(#entries, 1)
	eq(pending, 2)
end)

test('excluded uncached items are not counted as pending', function()
	local _, pending = Logic.BuildEntries({ rec{ itemID = 1, sellPrice = nil } }, { [1] = true })
	eq(pending, 0)
end)

test('nil input is an empty list', function()
	local entries, pending = Logic.BuildEntries(nil, nil)
	eq(#entries, 0)
	eq(pending, 0)
end)


--[[ Grouping ]]--

test('groups stacks by item ID and keeps the cheapest stack', function()
	local entries = Logic.BuildEntries({
		rec{ itemID = 7, sellPrice = 10, count = 20, bag = 0, slot = 1 },
		rec{ itemID = 7, sellPrice = 10, count = 3,  bag = 1, slot = 5 },
		rec{ itemID = 7, sellPrice = 10, count = 12, bag = 2, slot = 2 },
	}, {})
	eq(#entries, 1)
	local e = entries[1]
	eq(e.stacks, 3, 'stack count')
	eq(e.count, 3, 'cheapest stack count')
	eq(e.value, 30, 'cheapest stack value')
	eq(e.bag, 1)
	eq(e.slot, 5)
end)

test('stack count is correct when cheapest stack comes first', function()
	local entries = Logic.BuildEntries({
		rec{ itemID = 7, sellPrice = 10, count = 1, slot = 1 },
		rec{ itemID = 7, sellPrice = 10, count = 5, slot = 2 },
	}, {})
	eq(entries[1].stacks, 2)
	eq(entries[1].slot, 1)
end)

test('equal stacks pick the lowest bag then slot', function()
	local entries = Logic.BuildEntries({
		rec{ itemID = 7, sellPrice = 10, count = 5, bag = 2, slot = 1 },
		rec{ itemID = 7, sellPrice = 10, count = 5, bag = 0, slot = 9 },
		rec{ itemID = 7, sellPrice = 10, count = 5, bag = 0, slot = 4 },
	}, {})
	eq(entries[1].bag, 0)
	eq(entries[1].slot, 4)
end)


--[[ Sorting ]]--

test('sorts by stack value, lowest first', function()
	local entries = Logic.BuildEntries({
		rec{ itemID = 1, sellPrice = 100, count = 1, slot = 1 },
		rec{ itemID = 2, sellPrice = 1,   count = 5, slot = 2 },
		rec{ itemID = 3, sellPrice = 30,  count = 1, slot = 3 },
	}, {})
	eq(entries[1].itemID, 2)
	eq(entries[2].itemID, 3)
	eq(entries[3].itemID, 1)
end)

test('ranking uses the cheapest stack, not the total', function()
	-- item 1: many stacks totalling a lot, but one tiny stack worth 2c
	local entries = Logic.BuildEntries({
		rec{ itemID = 1, sellPrice = 1, count = 200, slot = 1 },
		rec{ itemID = 1, sellPrice = 1, count = 2,   slot = 2 },
		rec{ itemID = 2, sellPrice = 5, count = 1,   slot = 3 },
	}, {})
	eq(entries[1].itemID, 1)
	eq(entries[1].value, 2)
end)

local mixed = {
	rec{ itemID = 1, sellPrice = 1,   quality = 1, slot = 1 },
	rec{ itemID = 2, sellPrice = 500, quality = 0, slot = 2 },
	rec{ itemID = 3, sellPrice = 5,   quality = 2, slot = 3 },
	rec{ itemID = 4, sellPrice = 50,  quality = 0, slot = 4 },
}

test('by default grey items rank first, even when worth more', function()
	local entries = Logic.BuildEntries(mixed, {})
	eq(entries[1].itemID, 4, 'cheapest grey')
	eq(entries[2].itemID, 2, 'other grey')
	eq(entries[3].itemID, 1, 'then cheapest non-grey')
	eq(entries[4].itemID, 3)
end)

test('unknown quality is not treated as grey', function()
	local entries = Logic.BuildEntries({
		rec{ itemID = 1, sellPrice = 1, quality = nil, slot = 1 },
		rec{ itemID = 2, sellPrice = 9, quality = 0,   slot = 2 },
	}, {})
	eq(entries[1].itemID, 2)
end)

test('anyQuality ranks by stack value alone', function()
	local entries = Logic.BuildEntries(mixed, {}, true)
	eq(entries[1].itemID, 1, 'cheapest, a white item')
	eq(entries[2].itemID, 3, 'a green worth less than any grey')
	eq(entries[3].itemID, 4)
	eq(entries[4].itemID, 2)
end)

test('button entries keep order and stop at the quality limit', function()
	local entries = Logic.BuildEntries(mixed, {}, true)
	local ids = function(list) local t = {} for i, e in ipairs(list) do t[i] = e.itemID end return table.concat(t, ',') end
	eq(ids(Logic.ButtonEntries(entries, 0)), '4,2', 'Poor: greys only')
	eq(ids(Logic.ButtonEntries(entries, 1)), '1,4,2', 'Common adds whites')
	eq(ids(Logic.ButtonEntries(entries, 4)), '1,3,4,2', 'Epic: everything')
	eq(ids(Logic.ButtonEntries(entries, nil)), '4,2', 'missing limit means Poor')
	eq(#Logic.ButtonEntries({ { itemID = 9, quality = nil } }, 4), 0, 'unknown quality never offered')
end)

test('ties broken by name then item ID', function()
	local entries = Logic.BuildEntries({
		rec{ itemID = 9, sellPrice = 5, name = 'Bravo', slot = 1 },
		rec{ itemID = 8, sellPrice = 5, name = 'Alpha', slot = 2 },
		rec{ itemID = 3, sellPrice = 5, name = 'Alpha', slot = 3 },
	}, {})
	eq(entries[1].itemID, 3)
	eq(entries[2].itemID, 8)
	eq(entries[3].itemID, 9)
end)

test('slice returns the next four after the first', function()
	local list = { 'a', 'b', 'c', 'd', 'e', 'f' }
	local s = Logic.Slice(list, 2, 4)
	eq(#s, 4)
	eq(s[1], 'b')
	eq(s[4], 'e')
	eq(#Logic.Slice({ 'a', 'b' }, 2, 4), 1)
	eq(#Logic.Slice({}, 2, 4), 0)
end)


--[[ Exclusions ]]--

test('exclude and restore round trip', function()
	local db = {}
	eq(Logic.Exclude(db, 42, 'Thing'), true)
	eq(db.excluded[42], true)
	eq(db.names[42], 'Thing')
	eq(Logic.Restore(db, 42), true)
	eq(db.excluded[42], nil)
	eq(Logic.Restore(db, 42), false)
end)

test('exclude rejects non-numeric IDs', function()
	local db = {}
	eq(Logic.Exclude(db, '42'), false)
	eq(db.excluded, nil)
end)

test('excluded entries sorted by display name, ignoring links and case', function()
	local db = { excluded = { [1] = true, [2] = true, [3] = true }, names = {
		[1] = '|cff9d9d9d|Hitem:1::|h[zebra]|h|r',
		[2] = 'Apple',
		[3] = '|cffffffff|Hitem:3::|h[Mango]|h|r',
	} }
	local list = Logic.ExcludedEntries(db)
	eq(list[1].itemID, 2)
	eq(list[2].itemID, 3)
	eq(list[3].itemID, 1)
end)

test('excluded entries prefer live name lookup, then saved, then item:ID', function()
	local db = { excluded = { [5] = true, [6] = true, [7] = true }, names = { [6] = 'Saved' } }
	local list = Logic.ExcludedEntries(db, function(id) if id == 5 then return 'Live' end end)
	local byID = {}
	for _, e in ipairs(list) do byID[e.itemID] = e.name end
	eq(byID[5], 'Live')
	eq(byID[6], 'Saved')
	eq(byID[7], 'item:7')
end)

test('strip link', function()
	eq(Logic.StripLink('|cff1eff00|Hitem:123::::|h[Green Thing]|h|r'), 'Green Thing')
	eq(Logic.StripLink('Plain'), 'Plain')
	eq(Logic.StripLink(nil), '')
end)


--[[ Safety ]]--

local shown = { itemID = 10, count = 4, bag = 0, slot = 3 }

test('verify passes when id and count match', function()
	eq(Logic.VerifySlot(shown, { itemID = 10, stackCount = 4 }), true)
end)

test('verify fails when slot emptied', function()
	local ok, why = Logic.VerifySlot(shown, nil)
	eq(ok, false); eq(why, 'empty')
end)

test('verify fails when item changed', function()
	local ok, why = Logic.VerifySlot(shown, { itemID = 11, stackCount = 4 })
	eq(ok, false); eq(why, 'itemchanged')
end)

test('verify fails when count changed', function()
	local ok, why = Logic.VerifySlot(shown, { itemID = 10, stackCount = 5 })
	eq(ok, false); eq(why, 'countchanged')
end)

test('verify fails when slot locked', function()
	local ok, why = Logic.VerifySlot(shown, { itemID = 10, stackCount = 4, isLocked = true })
	eq(ok, false); eq(why, 'locked')
end)

test('confirm prompt needed for uncommon and above, and unknown quality', function()
	eq(Logic.NeedsConfirm(0), false)
	eq(Logic.NeedsConfirm(1), false)
	eq(Logic.NeedsConfirm(2), true)
	eq(Logic.NeedsConfirm(4), true)
	eq(Logic.NeedsConfirm(nil), true)
end)


--[[ Money ]]--

test('split money', function()
	local g, s, c = Logic.SplitMoney(123456)
	eq(g, 12); eq(s, 34); eq(c, 56)
end)

test('format money', function()
	eq(Logic.FormatMoney(123456), '12g 34s 56c')
	eq(Logic.FormatMoney(4500), '45s')
	eq(Logic.FormatMoney(10003), '1g 3c')
	eq(Logic.FormatMoney(0), '0c')
	eq(Logic.FormatMoney(nil), '0c')
end)

test('compact money uses largest denomination', function()
	local a, u = Logic.CompactMoney(123456); eq(a, 12); eq(u, 'g')
	a, u = Logic.CompactMoney(250);          eq(a, 2);  eq(u, 's')
	a, u = Logic.CompactMoney(7);            eq(a, 7);  eq(u, 'c')
end)


print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then
	error('tests failed', 0)
end
