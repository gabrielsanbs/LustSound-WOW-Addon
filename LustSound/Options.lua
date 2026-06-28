local ADDON_NAME, NS = ...

-- ============================================================================
-- Options.lua
--
-- Builds the modern settings panel using the Blizzard Settings API
-- (Settings.RegisterCanvasLayoutCategory / Settings.RegisterAddOnCategory).
-- All visible text comes from NS.L; spell names/icons come from
-- C_Spell.GetSpellInfo.
-- Interactive controls avoid Blizzard templates to reduce taint risk.
-- ============================================================================

local L = NS.L

local panel -- the main canvas frame
local categoryID
local controls = {} -- references to interactive controls for refresh

-- ----------------------------------------------------------------------------
-- Small UI helpers
-- ----------------------------------------------------------------------------

local function CreateHeading(parent, text, anchor, x, y)
    local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint(anchor, x, y)
    heading:SetText(text)
    return heading, y - 30
end

local function CreateLabel(parent, text, anchor, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint(anchor, x, y)
    label:SetText(text)
    return label, y - 24
end

-- Creates a checkbox bound to a DB key. Updates DB immediately on click and
-- refreshes dependent UI state when needed.
local function CreateCheckBox(parent, labelText, dbKey, anchor, x, y, onChange)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(22, 22)
    cb:SetPoint(anchor, x, y)

    local box = cb:CreateTexture(nil, "BACKGROUND")
    box:SetAllPoints(cb)
    box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")

    local check = cb:CreateTexture(nil, "ARTWORK")
    check:SetAllPoints(cb)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:Hide()

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(labelText)

    function cb:SetChecked(checked)
        self.checked = checked == true
        if self.checked then
            check:Show()
        else
            check:Hide()
        end
    end

    function cb:GetChecked()
        return self.checked == true
    end

    cb:SetScript("OnClick", function(self)
        if NS.DB then
            self:SetChecked(not self:GetChecked())
            if dbKey then
                NS.DB[dbKey] = self:GetChecked()
            end
            if onChange then
                onChange(self:GetChecked())
            end
        end
    end)
    if dbKey then
        controls[dbKey] = cb
    end
    return cb, y - 30
end

-- Creates a standard push button.
local function CreateButton(parent, text, width, height, anchor, x, y, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)
    btn:SetPoint(anchor, x, y)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints(btn)
    btn.bg:SetColorTexture(0.12, 0.12, 0.12, 0.88)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn:SetFontString(btn.text)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn, y - 30
end

local openSelectionMenu = nil

local function HideOpenSelectionMenu()
    if openSelectionMenu then
        openSelectionMenu:Hide()
        openSelectionMenu = nil
    end
end

local function CreateSelectionDropdown(parent, width, anchor, x, y, getEntries, getSelectedKey, onSelect)
    local button
    local menu = CreateFrame("Frame", nil, parent)
    menu:Hide()
    menu:SetWidth(width)
    menu:SetFrameLevel((parent:GetFrameLevel() or 0) + 20)

    local menuBg = menu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints(menu)
    menuBg:SetColorTexture(0.04, 0.04, 0.04, 0.96)

    local rows = {}
    local rowHeight = 24

    local function RebuildMenu()
        local entries = getEntries() or {}
        local selectedKey = getSelectedKey()

        menu:SetHeight(math.max(1, (#entries * rowHeight) + 4))

        for _, row in ipairs(rows) do
            row:Hide()
        end

        for i, entry in ipairs(entries) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, menu)
                row:SetSize(width - 4, rowHeight)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints(row)
                row.bg:SetColorTexture(0.10, 0.10, 0.10, 0.92)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.text:SetPoint("LEFT", 8, 0)
                row:SetFontString(row.text)
                rows[i] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - ((i - 1) * rowHeight))
            local selectedEntry = entry
            row:SetText((selectedEntry.key == selectedKey and "* " or "  ") .. selectedEntry.name)
            row:SetScript("OnClick", function()
                HideOpenSelectionMenu()
                onSelect(selectedEntry)
                NS.RefreshOptions()
            end)
            row:Show()
        end
    end

    button = CreateButton(parent, "", width, 28, anchor, x, y, function()
        if menu:IsShown() then
            HideOpenSelectionMenu()
            return
        end

        HideOpenSelectionMenu()
        RebuildMenu()
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        menu:Show()
        openSelectionMenu = menu
    end)

    return button, y - 40
end

-- ----------------------------------------------------------------------------
-- Selection buttons
-- ----------------------------------------------------------------------------

local function CreateSoundDropdown(parent, anchor, x, y)
    local dd = CreateSelectionDropdown(parent, 240, anchor, x, y,
        function()
            return NS.SoundRegistry
        end,
        function()
            return NS.DB and NS.DB.selectedSound
        end,
        function(entry)
            if NS.DB then
                NS.DB.selectedSound = entry.key
            end
        end
    )

    controls.soundDropdown = dd
    return dd, y - 40
end

local function CreateChannelDropdown(parent, anchor, x, y)
    local dd = CreateSelectionDropdown(parent, 240, anchor, x, y,
        function()
            return NS.AudioChannels
        end,
        function()
            return NS.DB and NS.DB.soundChannel
        end,
        function(entry)
            if NS.DB then
                NS.DB.soundChannel = entry.key
            end
        end
    )

    controls.channelDropdown = dd
    return dd, y - 40
end

-- ----------------------------------------------------------------------------
-- Detected-abilities info area
-- ----------------------------------------------------------------------------

local function CreateAbilitiesArea(parent, anchor, x, y)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint(anchor, x, y)
    title:SetText(L.DETECTED_ABILITIES)
    y = y - 24

    local icons = {}
    for i, spellID in ipairs(NS.LustSpellOrder) do
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(360, 20)
        row:SetPoint(anchor, x, y)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", 0, 0)
        local iconID = NS.GetSpellDisplayIcon(spellID)
        if iconID then
            icon:SetTexture(iconID)
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetText(NS.GetSpellDisplayName(spellID) .. "  |cFF888888(" .. spellID .. ")|r")

        icons[i] = { row = row, icon = icon, name = name, spellID = spellID }
        y = y - 24
    end

    controls.abilityIcons = icons
    return y
end

-- ----------------------------------------------------------------------------
-- Build the whole panel
-- ----------------------------------------------------------------------------

local function BuildPanel()
    if not panel then
        panel = CreateFrame("Frame", nil, UIParent)
        panel.name = L.ADDON_TITLE
    end
    if panel.content then
        return
    end

    -- Plain ScrollFrame without UIPanelScrollFrameTemplate to avoid taint.
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 800)
    scroll:SetScrollChild(content)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        local newScroll = math.min(maxScroll, math.max(0, current - (delta * 40)))
        self:SetVerticalScroll(newScroll)
    end)

    local x = 16
    local y = -16

    -- Title + description.
    local title, _ = CreateHeading(content, L.ADDON_TITLE, "TOPLEFT", x, y)
    title:SetFontObject("GameFontNormalLarge")
    y = y - 36

    local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", x, y)
    desc:SetWidth(500)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.ADDON_DESCRIPTION)
    y = y - 40

    -- Core checkboxes.
    local cbEnabled, y2 = CreateCheckBox(content, L.ENABLE_ADDON, "enabled", "TOPLEFT", x, y)
    y = y2

    local cbGroup, y3 = CreateCheckBox(content, L.GROUP_ONLY, "groupOnly", "TOPLEFT", x, y)
    y = y3

    -- Note about Patch 12.0+ combat-log restrictions.
    local groupNote = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    groupNote:SetPoint("TOPLEFT", x + 28, y + 6)
    groupNote:SetWidth(460)
    groupNote:SetJustifyH("LEFT")
    groupNote:SetText(L.GROUP_ONLY_NOTE)
    y = y - 22

    local cbOverlap, y4 = CreateCheckBox(content, L.PREVENT_OVERLAP, "preventOverlap", "TOPLEFT", x, y)
    y = y4

    local cbChat, y5 = CreateCheckBox(content, L.SHOW_CHAT, "showChatMessage", "TOPLEFT", x, y)
    y = y5

    -- Sound dropdown.
    local soundLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soundLabel:SetPoint("TOPLEFT", x, y)
    soundLabel:SetText(L.SELECTED_SOUND)
    y = y - 24
    local soundDD, y6 = CreateSoundDropdown(content, "TOPLEFT", x, y)
    y = y6

    -- Channel dropdown + help.
    local channelLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelLabel:SetPoint("TOPLEFT", x, y)
    channelLabel:SetText(L.SOUND_CHANNEL)
    y = y - 24
    local channelDD, y8 = CreateChannelDropdown(content, "TOPLEFT", x, y)
    y = y8
    local channelHelp = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    channelHelp:SetPoint("TOPLEFT", x, y)
    channelHelp:SetText(L.CHANNEL_HELP)
    y = y - 24

    -- Buttons row.
    local btnY = y
    local testBtn = CreateButton(content, L.TEST_SOUND, 120, 24, "TOPLEFT", x, btnY, function()
        NS.TestSound()
    end)

    local stopBtn = CreateButton(content, L.STOP_SOUND, 120, 24, "LEFT", 0, 0, function()
        NS.StopCurrentSound()
    end)
    stopBtn:ClearAllPoints()
    stopBtn:SetPoint("LEFT", testBtn, "RIGHT", 8, 0)

    local resetBtn = CreateButton(content, L.RESTORE_DEFAULTS, 140, 24, "LEFT", 0, 0, function()
        NS.RequestResetDefaults()
    end)
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("LEFT", stopBtn, "RIGHT", 8, 0)
    y = btnY - 36

    -- Sounds help text.
    local helpTxt = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    helpTxt:SetPoint("TOPLEFT", x, y)
    helpTxt:SetWidth(500)
    helpTxt:SetJustifyH("LEFT")
    helpTxt:SetText(L.SOUNDS_HELP)
    y = y - 40

    -- Context section (advanced).
    local ctxTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ctxTitle:SetPoint("TOPLEFT", x, y)
    ctxTitle:SetText(L.CONTEXT_SECTION)
    y = y - 26

    local ctxKeys = {
        { key = "world",    label = L.CONTEXT_WORLD },
        { key = "party",    label = L.CONTEXT_PARTY },
        { key = "raid",     label = L.CONTEXT_RAID },
        { key = "arena",    label = L.CONTEXT_ARENA },
        { key = "pvp",      label = L.CONTEXT_BATTLEGROUNG },
        { key = "scenario", label = L.CONTEXT_SCENARIO },
    }
    controls.contextBoxes = {}
    for _, c in ipairs(ctxKeys) do
        local cb
        cb = CreateCheckBox(content, c.label, nil, "TOPLEFT", x, y, function(checked)
            if NS.DB and NS.DB.contexts then
                NS.DB.contexts[c.key] = checked
            end
        end)
        controls.contextBoxes[c.key] = cb
        y = y - 28
    end
    y = y - 8

    -- Detected-abilities area.
    y = CreateAbilitiesArea(content, "TOPLEFT", x, y)

    -- Ensure content height covers everything.
    content:SetHeight(math.abs(y) + 40)

    panel.content = content
end

-- ----------------------------------------------------------------------------
-- Refresh all controls from the current DB state
-- ----------------------------------------------------------------------------

function NS.RefreshOptions()
    if not panel or not NS.DB then
        return
    end

    if controls.enabled then
        controls.enabled:SetChecked(NS.DB.enabled)
    end
    if controls.groupOnly then
        controls.groupOnly:SetChecked(NS.DB.groupOnly)
    end
    if controls.preventOverlap then
        controls.preventOverlap:SetChecked(NS.DB.preventOverlap)
    end
    if controls.showChatMessage then
        controls.showChatMessage:SetChecked(NS.DB.showChatMessage)
    end

    if controls.soundDropdown and NS.SoundRegistry then
        local soundName = NS.DB.selectedSound or ""
        for _, entry in ipairs(NS.SoundRegistry) do
            if entry.key == NS.DB.selectedSound then
                soundName = entry.name
                break
            end
        end
        controls.soundDropdown:SetText(soundName .. "  v")
    end

    if controls.channelDropdown and NS.AudioChannels then
        local channelName = NS.DB.soundChannel or ""
        for _, ch in ipairs(NS.AudioChannels) do
            if ch.key == NS.DB.soundChannel then
                channelName = ch.name
                break
            end
        end
        controls.channelDropdown:SetText(channelName .. "  v")
    end

    if controls.contextBoxes then
        for key, cb in pairs(controls.contextBoxes) do
            cb:SetChecked(NS.DB.contexts and NS.DB.contexts[key] or false)
        end
    end

    -- Refresh localized spell names/icons in case the client language changed.
    if controls.abilityIcons then
        for _, info in ipairs(controls.abilityIcons) do
            local iconID = NS.GetSpellDisplayIcon(info.spellID)
            if iconID then
                info.icon:SetTexture(iconID)
            else
                info.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            info.name:SetText(NS.GetSpellDisplayName(info.spellID) .. "  |cFF888888(" .. info.spellID .. ")|r")
        end
    end
end

-- ----------------------------------------------------------------------------
-- Register the panel with the modern Settings API
-- ----------------------------------------------------------------------------

function NS.InitOptions()
    if not panel then
        panel = CreateFrame("Frame", nil, UIParent)
        panel.name = L.ADDON_TITLE
        panel:SetScript("OnShow", function()
            BuildPanel()
            NS.RefreshOptions()
        end)
    end

    if not categoryID and Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        if category then
            Settings.RegisterAddOnCategory(category)
            categoryID = category:GetID()
        end
    end
end

function NS.OpenOptions()
    if categoryID and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(categoryID)
    elseif NS.InitOptions then
        NS.InitOptions()
        if categoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(categoryID)
        end
    end
end
