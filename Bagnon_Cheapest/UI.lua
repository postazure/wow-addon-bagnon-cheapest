--[[
	The button on Bagnon's inventory frame, slot shading and the list panel.
--]]

local _, ns = ...
local Logic, Core = ns.Logic, ns.Core
local UI = {}
ns.UI = UI

local NUM_ROWS = 12
local ROW_HEIGHT = 18
local PANEL_WIDTH = 320
local COIN_COLORS = { g = 'ffffd700', s = 'ffc7c7cf', c = 'ffeda55f' }
local EMPTY_ICON = 'Interface/Icons/INV_Misc_QuestionMark'

UI.inCombat = false


--[[ Helpers ]]--

local function inventoryFrame()
	local frame = Bagnon and Bagnon.Frames and Bagnon.Frames:Get('inventory')
	if frame and frame[0] then
		return frame
	end
end

local function viewingOtherCharacter()
	local frame = inventoryFrame()
	return frame and frame.IsCached and frame:IsCached()
end

local function anchorTooltip(owner)
	local right = owner:GetRight() and owner:GetRight() > (GetScreenWidth() / owner:GetEffectiveScale() / 2)
	GameTooltip:SetOwner(owner, right and 'ANCHOR_LEFT' or 'ANCHOR_RIGHT')
end

local function coloredName(entry)
	local _, _, _, hex = Core.QualityColor(entry.quality)
	return (hex or '|cffffffff') .. (Logic.StripLink(entry.link or entry.name or ('item:' .. entry.itemID))) .. '|r'
end

-- Bagnon's mouse icons: |L left, |R right, |LS shift+left, |RS shift+right.
local FALLBACK_MARKUP = { ['|LS'] = 'Shift-left-click:', ['|RS'] = 'Shift-right-click:', ['|L'] = 'Left-click:', ['|R'] = 'Right-click:' }

local function clickHint(text)
	local tipped = Bagnon and Bagnon.Tipped
	if tipped and tipped.MarkupTooltip then
		return (tipped.MarkupTooltip(text))
	end
	return (text:gsub('(%|%u+)', FALLBACK_MARKUP))
end

local function actionVerb()
	return Core.VendorState() == 'sell' and 'Sell' or 'Destroy'
end

local function addActionHint(markup)
	local vendor = Core.VendorState()
	if viewingOtherCharacter() then
		GameTooltip:AddLine('Viewing another character: disabled.', 1, 0.3, 0.3)
	elseif UI.inCombat then
		GameTooltip:AddLine('In combat: disabled.', 1, 0.3, 0.3)
	elseif vendor == 'buyback' then
		GameTooltip:AddLine('Vendor is on Buyback: switch to the Merchant tab to sell.', 1, 0.82, 0)
	else
		GameTooltip:AddLine(clickHint(markup .. ' ' .. actionVerb() .. ' this stack'), 0.5, 1, 0.5)
	end
end

local function smallFont(fs, size)
	local font, _, flags = fs:GetFont()
	if font then
		fs:SetFont(font, size, flags)
	end
end

local function addBorder(frame, r, g, b, a)
	for _, points in ipairs {
		{ 'TOPLEFT', 'TOPRIGHT', nil, 1 }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', nil, 1 },
		{ 'TOPLEFT', 'BOTTOMLEFT', 1, nil }, { 'TOPRIGHT', 'BOTTOMRIGHT', 1, nil },
	} do
		local t = frame:CreateTexture(nil, 'BORDER')
		t:SetColorTexture(r, g, b, a)
		t:SetPoint(points[1])
		t:SetPoint(points[2])
		if points[3] then t:SetWidth(points[3]) end
		if points[4] then t:SetHeight(points[4]) end
	end
end


--[[ Slot shading ]]--

-- Dark textures laid over Bagnon's item buttons; the buttons themselves are never touched.
-- Hovering keeps one slot bright. While the panel is open, listed (or excluded) items stay
-- bright and everything else stays dark.

local panel
local glow, shade
local shades = {}
local SHADE_ALPHA = 0.7
local CLEAR_DELAY = 0.08
local clearToken = 0

local function createGlow()
	shade = CreateFrame('Frame', nil, UIParent)
	shade:Hide()

	glow = CreateFrame('Frame', nil, UIParent)
	glow:Hide()

	local tex = glow:CreateTexture(nil, 'OVERLAY')
	tex:SetTexture('Interface/Buttons/UI-ActionButton-Border')
	tex:SetBlendMode('ADD')
	tex:SetVertexColor(1, 0.85, 0.1)
	tex:SetAllPoints()

	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping('BOUNCE')
	local fade = pulse:CreateAnimation('Alpha')
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.35)
	fade:SetDuration(0.45)
	glow.pulse = pulse
end

local function inventoryGrid()
	local frame = inventoryFrame()
	if not frame or not frame:IsShown() or viewingOtherCharacter() then
		return
	end
	local group = rawget(frame, 'ItemGroup') -- plain frame.ItemGroup is the class until created
	if group and group.buttons then
		return frame, group
	end
end

local function slotItemID(button)
	local info = C_Container.GetContainerItemInfo(button.bag, button:GetID())
	return info and info.itemID
end

local function hideGlow()
	glow.pulse:Stop()
	glow:Hide()
end

local function hideShade()
	shade:Hide()
end

local function shadeWhere(frame, group, keepBright)
	shade:SetParent(frame)
	shade:ClearAllPoints()
	shade:SetAllPoints(frame)
	shade:SetFrameStrata(frame:GetFrameStrata())
	shade:SetFrameLevel(frame:GetFrameLevel() + 30)

	local n = 0
	for _, button in ipairs(group.buttons) do
		if button:IsVisible() and not keepBright(button) then
			n = n + 1
			local tex = shades[n]
			if not tex then
				tex = shade:CreateTexture(nil, 'OVERLAY')
				tex:SetColorTexture(0, 0, 0, SHADE_ALPHA)
				shades[n] = tex
			end
			tex:ClearAllPoints()
			tex:SetAllPoints(button)
			tex:Show()
		end
	end
	for i = n + 1, #shades do
		shades[i]:Hide()
	end
	shade:Show()
end

local function showGlow(frame, button)
	local pad = button:GetWidth() * 0.45
	glow:SetParent(frame)
	glow:ClearAllPoints()
	glow:SetPoint('TOPLEFT', button, 'TOPLEFT', -pad, pad)
	glow:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', pad, -pad)
	glow:SetFrameStrata(frame:GetFrameStrata())
	glow:SetFrameLevel(frame:GetFrameLevel() + 40)
	glow:Show()
	glow.pulse:Play()
end

function UI.ApplyBaseline()
	clearToken = clearToken + 1
	UI.hovering = false
	hideGlow()

	local frame, group = inventoryGrid()
	if not frame or not panel or not panel:IsShown() then
		hideShade()
		return
	end

	if UI.showExcluded then
		local excluded = Bagnon_CheapestDB.excluded
		shadeWhere(frame, group, function(button)
			local id = slotItemID(button)
			return id and excluded[id]
		end)
	else
		local listed = {}
		for _, e in ipairs(Core.entries) do
			listed[e.bag .. ':' .. e.slot] = true
		end
		shadeWhere(frame, group, function(button)
			return listed[button.bag .. ':' .. button:GetID()]
		end)
	end
end

function UI.HighlightSlot(bag, slot)
	clearToken = clearToken + 1
	local frame, group = inventoryGrid()
	if not frame then
		hideGlow(); hideShade()
		return
	end

	local target = group.byBag and group.byBag[bag] and group.byBag[bag][slot]
	UI.hovering = true
	shadeWhere(frame, group, function(button) return button == target end)
	if target and target:IsVisible() then
		showGlow(frame, target)
	else
		hideGlow()
	end
end

function UI.HighlightItem(itemID)
	clearToken = clearToken + 1
	local frame, group = inventoryGrid()
	if not frame then
		hideGlow(); hideShade()
		return
	end
	UI.hovering = true
	hideGlow()
	shadeWhere(frame, group, function(button) return slotItemID(button) == itemID end)
end

-- Delayed so moving between rows doesn't flash the bags back to normal.
function UI.ClearHighlight()
	clearToken = clearToken + 1
	local token = clearToken
	C_Timer.After(CLEAR_DELAY, function()
		if token == clearToken then
			UI.ApplyBaseline()
		end
	end)
end


--[[ Bagnon menu button ]]--

local button

local function buttonOnEnter(self)
	self.hovered = true
	local entries = Core.buttonEntries
	local entry = entries[1]
	anchorTooltip(self)

	if not entry then
		GameTooltip:AddLine('Bagnon Cheapest', 1, 1, 1)
		if #Core.entries == 0 then
			GameTooltip:AddLine(Core.pending > 0 and 'Item data still loading...' or 'Nothing with a vendor price.', 0.8, 0.8, 0.8)
		else
			local maxQuality = Bagnon_CheapestDB.buttonMaxQuality or 0
			GameTooltip:AddLine(maxQuality == 0 and 'No grey items.'
				or ('Nothing at ' .. Core.QualityName(maxQuality) .. '|cffcccccc quality or below.|r'), 0.8, 0.8, 0.8)
			GameTooltip:AddLine('Change it with /bcheap options.', 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine(clickHint('|L Show list'), 0.5, 0.8, 1)
		GameTooltip:Show()
		return
	end

	GameTooltip:SetBagItem(entry.bag, entry.slot)
	GameTooltip:AddLine(' ')
	GameTooltip:AddDoubleLine('Cheapest stack (x' .. entry.count .. ')', Core.Money(entry.value), 1, 0.82, 0, 1, 1, 1)
	if entry.stacks > 1 then
		GameTooltip:AddLine(('%d stacks in bags; only this one is %s.'):format(entry.stacks, actionVerb() == 'Sell' and 'sold' or 'destroyed'), 0.8, 0.8, 0.8)
	end

	local nextUp = Logic.Slice(entries, 2, 4)
	if #nextUp > 0 then
		GameTooltip:AddLine(' ')
		GameTooltip:AddLine('Next cheapest:', 1, 0.82, 0)
		for _, e in ipairs(nextUp) do
			local label = coloredName(e) .. (e.stacks > 1 and ('|cff999999 x' .. e.stacks .. ' stacks|r') or '')
			GameTooltip:AddDoubleLine(label, Core.Money(e.value), 1, 1, 1, 1, 1, 1)
		end
	end

	GameTooltip:AddLine(' ')
	addActionHint('|LS')
	GameTooltip:AddLine(clickHint('|RS Skip until bags close'), 0.5, 0.8, 1)
	GameTooltip:AddLine(clickHint('|L Show list'), 0.5, 0.8, 1)
	GameTooltip:Show()

	UI.HighlightSlot(entry.bag, entry.slot)
end

local function buttonOnLeave(self)
	self.hovered = false
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
	UI.ClearHighlight()
end

local function buttonOnClick(self, mouse)
	if mouse == 'RightButton' then
		if IsShiftKeyDown() then
			Core.Skip(Core.buttonEntries[1])
		end
	elseif not IsShiftKeyDown() then
		UI.TogglePanel()
	elseif viewingOtherCharacter() then
		Core.Print('Switch Bagnon back to your current character first.')
	else
		Core.Act(Core.buttonEntries[1])
	end
end

local function createButton(parent)
	local b = CreateFrame('Button', 'Bagnon_CheapestButton', parent, 'BagnonButtonTemplate')
	b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	b.icon = b.Icon
	b.icon:SetTexture(EMPTY_ICON)

	b.price = b:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
	b.price:SetPoint('BOTTOMRIGHT', 3, -3)
	smallFont(b.price, 9)

	b:SetScript('OnEnter', buttonOnEnter)
	b:SetScript('OnLeave', buttonOnLeave)
	b:SetScript('OnClick', buttonOnClick)
	return b
end

function UI.GetButton(frame)
	if not button then
		button = createButton(frame)
		UI.UpdateButton()
	end
	return button
end

function UI.UpdateButton()
	if not button then return end
	local entry = Core.buttonEntries[1]

	if entry then
		button.icon:SetTexture(entry.icon or EMPTY_ICON)
		local amount, unit = Logic.CompactMoney(entry.value)
		button.price:SetText(amount .. '|c' .. COIN_COLORS[unit] .. unit .. '|r')
	else
		button.icon:SetTexture(EMPTY_ICON)
		button.price:SetText('')
	end
	button.icon:SetDesaturated(not entry or UI.inCombat)

	if button.hovered then
		buttonOnEnter(button)
	end
end

local function installBagnonHook()
	local Inventory = Bagnon and Bagnon.Inventory
	if not Inventory or UI.hooked then
		return
	end
	UI.hooked = true

	local original = Inventory.GetExtraButtons
	function Inventory:GetExtraButtons()
		local list = original(self) or {}
		local out = {}
		for i = 1, #list do
			if list[i] then
				out[#out + 1] = list[i]
			end
		end
		if self.id == 'inventory' then
			if not self.cheapestHooked then
				self.cheapestHooked = true
				self:HookScript('OnHide', Core.ClearSkipped)
			end
			out[#out + 1] = UI.GetButton(self)
			C_Timer.After(0, function()
				if not UI.hovering then UI.ApplyBaseline() end
			end)
		end
		return out
	end

	UI.RelayoutBagnon()
end

function UI.RelayoutBagnon()
	local frame = inventoryFrame()
	if not frame then
		return
	end
	if InCombatLockdown() then
		UI.relayoutAfterCombat = true
	else
		frame:Layout()
	end
end


--[[ Panel ]]--

UI.showExcluded = false

local function rowOnEnter(self)
	self.hovered = true
	anchorTooltip(self)
	if UI.showExcluded then
		GameTooltip:SetHyperlink('item:' .. self.entry.itemID)
		GameTooltip:AddLine(' ')
		GameTooltip:AddLine(clickHint('|R Restore to the list'), 0.5, 0.8, 1)
		UI.HighlightItem(self.entry.itemID)
	else
		local e = self.entry
		GameTooltip:SetBagItem(e.bag, e.slot)
		GameTooltip:AddLine(' ')
		GameTooltip:AddDoubleLine('This stack (x' .. e.count .. ')', Core.Money(e.value), 1, 0.82, 0, 1, 1, 1)
		addActionHint('|LS')
		GameTooltip:AddLine(clickHint('|R Exclude this item forever'), 0.5, 0.8, 1)
		UI.HighlightSlot(e.bag, e.slot)
	end
	GameTooltip:Show()
end

local function rowOnLeave(self)
	self.hovered = false
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
	UI.ClearHighlight()
end

local function rowOnClick(self, mouse)
	local entry = self.entry
	if not entry then return end

	if UI.showExcluded then
		if mouse == 'RightButton' then
			Core.Restore(entry.itemID)
		end
	elseif mouse == 'RightButton' then
		Core.Exclude(entry)
	elseif not IsShiftKeyDown() then
		return
	elseif viewingOtherCharacter() then
		Core.Print('Switch Bagnon back to your current character first.')
	else
		Core.Act(entry)
	end
end

local function createRow(parent, i)
	local row = CreateFrame('Button', nil, parent)
	row:SetHeight(ROW_HEIGHT)
	local y = -30 - (i - 1) * ROW_HEIGHT
	row:SetPoint('TOPLEFT', parent, 'TOPLEFT', 10, y)
	row:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', -24, y)
	row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	row:SetHighlightTexture('Interface/Buttons/ButtonHilight-Square', 'ADD')

	row.icon = row:CreateTexture(nil, 'ARTWORK')
	row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
	row.icon:SetPoint('LEFT', 1, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.price = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	row.price:SetPoint('RIGHT', -2, 0)
	row.price:SetJustifyH('RIGHT')

	row.stacks = row:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	row.stacks:SetPoint('RIGHT', row.price, 'LEFT', -6, 0)

	row.name = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	row.name:SetPoint('LEFT', row.icon, 'RIGHT', 4, 0)
	row.name:SetPoint('RIGHT', row.stacks, 'LEFT', -4, 0)
	row.name:SetJustifyH('LEFT')
	row.name:SetWordWrap(false)

	row:SetScript('OnEnter', rowOnEnter)
	row:SetScript('OnLeave', rowOnLeave)
	row:SetScript('OnClick', rowOnClick)
	return row
end

local function createPanel()
	panel = CreateFrame('Frame', 'Bagnon_CheapestPanel', UIParent)
	panel:SetSize(PANEL_WIDTH, 30 + NUM_ROWS * ROW_HEIGHT + 30)
	panel:SetFrameStrata('HIGH')
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag('LeftButton')
	panel:SetScript('OnDragStart', panel.StartMoving)
	panel:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		self.moved = true
	end)
	panel:Hide()
	tinsert(UISpecialFrames, panel:GetName())

	local bg = panel:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)
	addBorder(panel, 0.4, 0.4, 0.4, 1)

	panel.title = panel:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	panel.title:SetPoint('TOPLEFT', 10, -9)

	local close = CreateFrame('Button', nil, panel, 'UIPanelCloseButtonNoScripts')
	close:SetPoint('TOPRIGHT', 2, 2)
	close:SetScript('OnClick', function() panel:Hide() end)

	local toggle = CreateFrame('Button', nil, panel)
	toggle:SetSize(100, 18)
	toggle:SetPoint('TOPRIGHT', -28, -6)
	toggle.text = toggle:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	toggle.text:SetPoint('RIGHT')
	toggle:SetFontString(toggle.text)
	toggle:SetHighlightTexture('Interface/Buttons/ButtonHilight-Square', 'ADD')
	toggle:SetScript('OnClick', function()
		UI.showExcluded = not UI.showExcluded
		panel.offset = 0
		UI.RenderPanel()
		UI.ApplyBaseline()
	end)
	panel.toggle = toggle

	panel.rows = {}
	for i = 1, NUM_ROWS do
		panel.rows[i] = createRow(panel, i)
	end

	panel.empty = panel:CreateFontString(nil, 'OVERLAY', 'GameFontDisable')
	panel.empty:SetPoint('TOP', 0, -60)

	panel.footer = panel:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	panel.footer:SetPoint('BOTTOMLEFT', 10, 10)
	panel.footer:SetPoint('BOTTOMRIGHT', -10, 10)
	panel.footer:SetJustifyH('LEFT')

	local slider = CreateFrame('Slider', nil, panel)
	slider:SetOrientation('VERTICAL')
	slider:SetWidth(10)
	slider:SetPoint('TOPRIGHT', -8, -30)
	slider:SetPoint('BOTTOMRIGHT', -8, 30)
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)
	local track = slider:CreateTexture(nil, 'BACKGROUND')
	track:SetAllPoints()
	track:SetColorTexture(1, 1, 1, 0.08)
	slider:SetThumbTexture('Interface/Buttons/WHITE8X8')
	local thumb = slider:GetThumbTexture()
	thumb:SetVertexColor(0.7, 0.7, 0.7, 0.8)
	thumb:SetSize(10, 24)
	slider:SetScript('OnValueChanged', function(_, value)
		if not panel.rendering then
			panel.offset = math.floor(value + 0.5)
			UI.RenderPanel()
		end
	end)
	panel.slider = slider

	panel.offset = 0
	panel:EnableMouseWheel(true)
	panel:SetScript('OnMouseWheel', function(_, delta)
		panel.offset = panel.offset - delta * 3
		UI.RenderPanel()
	end)
	panel:SetScript('OnShow', function() UI.RenderPanel() end)
	panel:SetScript('OnHide', UI.ApplyBaseline)
end

local renderError

local function render()
	local list = UI.showExcluded and Core.ExcludedEntries() or Core.entries
	local maxOffset = math.max(0, #list - NUM_ROWS)
	panel.offset = math.max(0, math.min(panel.offset or 0, maxOffset))

	panel.title:SetText(UI.showExcluded and 'Excluded items' or 'Cheapest stacks')
	panel.toggle.text:SetText(UI.showExcluded and '< Back to list' or 'Show excluded')

	for i, row in ipairs(panel.rows) do
		local entry = list[panel.offset + i]
		row.entry = entry
		if entry then
			if UI.showExcluded then
				local _, _, _, _, icon = C_Item.GetItemInfoInstant(entry.itemID)
				local _, _, quality = C_Item.GetItemInfo(entry.itemID)
				row.icon:SetTexture(icon or EMPTY_ICON)
				row.name:SetText(coloredName({ itemID = entry.itemID, name = entry.name, quality = quality }))
				row.stacks:SetText('')
				row.price:SetText(clickHint('|R |cff999999restore|r'))
			else
				row.icon:SetTexture(entry.icon or EMPTY_ICON)
				row.name:SetText(coloredName(entry))
				row.stacks:SetText(entry.stacks > 1 and ('x' .. entry.stacks .. ' stacks') or '')
				row.price:SetText(Core.Money(entry.value))
			end
			row.icon:SetDesaturated(not UI.showExcluded and UI.inCombat)
			row:Show()
			if row.hovered then
				rowOnEnter(row)
			end
		else
			row:Hide()
		end
	end

	if #list == 0 then
		panel.empty:SetText(UI.showExcluded and 'No excluded items.'
			or (Core.pending > 0 and 'Item data still loading...' or 'Nothing with a vendor price.'))
		panel.empty:Show()
	else
		panel.empty:Hide()
	end

	local footer
	if UI.showExcluded then
		footer = #list .. ' excluded (saved for all characters)'
	else
		footer = #list .. ' items'
		if Core.pending > 0 then footer = footer .. ', ' .. Core.pending .. ' loading' end
		local skipped = 0
		for _ in pairs(Core.skipped) do skipped = skipped + 1 end
		if skipped > 0 then footer = footer .. ', ' .. skipped .. ' skipped' end
		if UI.inCombat then
			footer = footer .. '  |cffff5555In combat: disabled|r'
		elseif Core.VendorState() == 'sell' then
			footer = footer .. '  |cff55ff55At vendor: clicks sell|r'
		end
	end
	panel.footer:SetText(footer)

	panel.rendering = true
	panel.slider:SetMinMaxValues(0, maxOffset)
	panel.slider:SetValue(panel.offset)
	panel.slider:SetShown(maxOffset > 0)
	panel.rendering = false
end

function UI.RenderPanel()
	if not panel or not panel:IsShown() then return end

	local ok, err = pcall(render)
	panel.rendering = false
	if not ok and err ~= renderError then
		renderError = err
		Core.Print('|cffff5555panel error:|r', err)
	end
end

function UI.TogglePanel()
	if not panel then
		local ok, err = pcall(createPanel)
		if not ok then
			panel = nil
			Core.Print('|cffff5555panel error:|r', err)
			return
		end
	end
	if panel:IsShown() then
		panel:Hide()
		return
	end

	if not panel.moved then
		panel:ClearAllPoints()
		local frame = inventoryFrame()
		if frame and frame:IsShown() then
			panel:SetPoint('TOPRIGHT', frame, 'TOPLEFT', -6, 0)
		else
			panel:SetPoint('CENTER')
		end
	end
	panel:Show()
	Core.Scan()
end


--[[ Hooks from Core ]]--

function UI.Init()
	createGlow()
	installBagnonHook()
end

function UI.Refresh()
	UI.UpdateButton()
	UI.RenderPanel()
	if not UI.hovering then
		UI.ApplyBaseline()
	end
end

function UI.OnCombat(inCombat)
	UI.inCombat = inCombat
	if not inCombat and UI.relayoutAfterCombat then
		UI.relayoutAfterCombat = nil
		UI.RelayoutBagnon()
	end
	UI.Refresh()
end
