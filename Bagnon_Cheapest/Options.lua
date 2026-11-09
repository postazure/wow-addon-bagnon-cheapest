--[[
	Options page in Blizzard's Settings (Options > AddOns > Bagnon Cheapest).
--]]

local _, ns = ...
local Core = ns.Core
local Options = {}
ns.Options = Options

local TITLE = 'Bagnon Cheapest'

local function register(category, key, name)
	local setting = Settings.RegisterAddOnSetting(category, 'Bagnon_Cheapest_' .. key, key,
		Bagnon_CheapestDB, type(Core.DEFAULTS[key]), name, Core.DEFAULTS[key])
	setting:SetValueChangedCallback(function() Core.Scan() end)
	return setting
end

function Options.Init()
	if Options.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory(TITLE)

	Settings.CreateCheckbox(category, register(category, 'anyQuality', 'Cheapest first, any quality'),
		'Rank purely by vendor value.\n\nWhen off, grey items always come first, then everything else by value.')

	Settings.CreateDropdown(category, register(category, 'buttonMaxQuality', 'Button shows up to'), function()
		local container = Settings.CreateControlTextContainer()
		for q = 0, Core.MAX_BUTTON_QUALITY do
			container:Add(q, Core.QualityName(q))
		end
		return container:GetData()
	end, 'The highest item quality the bag button offers.\n\nPoor keeps Shift-click to grey items only. The list panel always shows every quality.')

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
