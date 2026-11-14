--[[
	Options page in Blizzard's Settings (Options > AddOns > Bagnon Cheapest).
--]]

local _, ns = ...
local Core = ns.Core
local Options = {}
ns.Options = Options

local TITLE = 'Bagnon Cheapest'

local function register(category, key, name, default, onChange)
	local setting = Settings.RegisterAddOnSetting(category, 'Bagnon_Cheapest_' .. key, key,
		Bagnon_CheapestDB, type(default), name, default)
	setting:SetValueChangedCallback(function()
		if onChange then onChange() end
		Core.Scan()
	end)
	return setting
end

function Options.Init()
	if Options.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	local db = Bagnon_CheapestDB
	local category = Settings.RegisterVerticalLayoutCategory(TITLE)

	Settings.CreateDropdown(category,
		register(category, 'buttonMaxQuality', 'Button picks from', Core.DEFAULTS.buttonMaxQuality),
		function()
			local container = Settings.CreateControlTextContainer()
			for q = 0, Core.MAX_BUTTON_QUALITY do
				container:Add(q, Core.QualityName(q) .. (q == 0 and ' (junk only)' or ' and below'))
			end
			return container:GetData()
		end,
		'Which items the bag button (and its Shift-click) may pick.\n\n'
			.. 'Poor: grey junk only, for quickly clearing junk.\n'
			.. 'Higher: also white, green... items up to that quality.\n\n'
			.. 'The list panel always shows every quality.')

	-- The ranking reads anyQuality; the checkbox is its opposite, so "on" is the default.
	if db.greyFirst == nil then
		db.greyFirst = not db.anyQuality
	end
	Settings.CreateCheckbox(category,
		register(category, 'greyFirst', 'Grey items first', true, function()
			db.anyQuality = not db.greyFirst
		end),
		'On: grey junk always comes first, then everything else by vendor value.\n\n'
			.. 'Off: rank everything by vendor value alone, so a cheap white item can come before a grey one.')

	Settings.RegisterAddOnCategory(category)
	Options.category = category
end

function Options.Open()
	if Options.category and Settings.OpenToCategory then
		Settings.OpenToCategory(Options.category:GetID())
	else
		Core.Print('Options are not available on this client.')
	end
end
