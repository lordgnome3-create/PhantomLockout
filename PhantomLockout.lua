----------------------------------------------------------------------
-- PhantomLockout - Turtle WoW Raid Lockout Tracker
-- Pure Lua addon - resizable, personal lockout detection
----------------------------------------------------------------------

----------------------------------------------------------------------
-- CONFIGURATION & DATA
----------------------------------------------------------------------

local ANCHOR_RAID40 = 1736309600
local ANCHOR_ONYXIA = 1736309600
local ANCHOR_KARAZHAN = 1736309600
local ANCHOR_RAID20 = 1736309600

local CYCLE_7DAY = 7 * 24 * 3600
local CYCLE_5DAY = 5 * 24 * 3600
local CYCLE_3DAY = 3 * 24 * 3600

local RAIDS = {
    {
        name = "Molten Core",
        short = "MC",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\Spell_Fire_Incinerate",
        info = "The Firelord Ragnaros awaits in Blackrock Mountain. Tier 1 gear and legendary bindings.",
        bosses = 10,
    },
    {
        name = "Blackwing Lair",
        short = "BWL",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
        info = "Nefarian's stronghold atop Blackrock Mountain. Tier 2 gear and challenging encounters.",
        bosses = 8,
    },
    {
        name = "Temple of Ahn'Qiraj",
        short = "AQ40",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_01",
        info = "Face C'Thun and the Qiraji empire. Tier 2.5 gear.",
        bosses = 9,
    },
    {
        name = "Naxxramas",
        short = "Naxx",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\INV_Trinket_Naxxramas06",
        info = "The floating necropolis of Kel'Thuzad. Four wings. Tier 3 gear.",
        bosses = 15,
    },
    {
        name = "Emerald Sanctum",
        short = "ES",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\INV_Misc_Gem_Emerald_02",
        info = "Turtle WoW exclusive. Venture into the Emerald Dream.",
        bosses = 4,
    },
    {
        name = "Onyxia's Lair",
        short = "Ony",
        size = 40,
        cycle = CYCLE_5DAY,
        anchor = ANCHOR_ONYXIA,
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        info = "Broodmother Onyxia in Dustwallow Marsh. Single boss. 5-day reset.",
        bosses = 1,
    },
    {
        name = "Karazhan",
        short = "Kara",
        size = 40,
        cycle = CYCLE_5DAY,
        anchor = ANCHOR_KARAZHAN,
        icon = "Interface\\Icons\\INV_Jewelry_Ring_54",
        info = "Medivh's haunted tower in Deadwind Pass. Turtle WoW adapted. 5-day reset.",
        bosses = 11,
    },
    {
        name = "Zul'Gurub",
        short = "ZG",
        size = 20,
        cycle = CYCLE_3DAY,
        anchor = ANCHOR_RAID20,
        icon = "Interface\\Icons\\Ability_Creature_Poison_05",
        info = "Troll city in Stranglethorn. Hakkar the Soulflayer. 3-day reset.",
        bosses = 10,
    },
    {
        name = "Ruins of Ahn'Qiraj",
        short = "AQ20",
        size = 20,
        cycle = CYCLE_3DAY,
        anchor = ANCHOR_RAID20,
        icon = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_03",
        info = "Outer ruins of Ahn'Qiraj. Prophet Ossirian. 3-day reset.",
        bosses = 6,
    },
}

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------

local ROW_HEIGHT = 28
local HEADER_TOP = 78       -- pixels from frame top where rows start
local INFO_HEIGHT = 55      -- info panel height
local INFO_BOTTOM = 15      -- info panel margin from bottom
local RESET_BTN_BOTTOM = 75 -- reset button margin from bottom
local MIN_WIDTH = 550
local MIN_HEIGHT = 300
local DEFAULT_WIDTH = 600
local DEFAULT_HEIGHT = 440

local selectedRaid = nil
local rowFrames = {}
local mainFrame = nil
local infoText = nil
local infoPanel = nil
local serverTimeText = nil
local resetBtn = nil
local sepLine = nil
local hdrFrame = nil

-- Personal lockout tracking
local savedLockouts = {}  -- keyed by raid name lowercase -> true if locked

----------------------------------------------------------------------
-- UTILITY FUNCTIONS
----------------------------------------------------------------------

local function GetSecondsUntilReset(raid)
    local now = time()
    local elapsed = now - raid.anchor
    if elapsed < 0 then
        return raid.cycle + elapsed
    end
    local inCycle = math.mod(elapsed, raid.cycle)
    return raid.cycle - inCycle
end

local function FormatCountdown(seconds)
    if seconds <= 0 then
        return "|cff00ff00Resetting...|r"
    end
    local days = math.floor(seconds / 86400)
    local hours = math.floor(math.mod(seconds, 86400) / 3600)
    local mins = math.floor(math.mod(seconds, 3600) / 60)
    local secs = math.floor(math.mod(seconds, 60))
    if days > 0 then
        return string.format("%dd %02dh %02dm", days, hours, mins)
    elseif hours > 0 then
        return string.format("%02dh %02dm %02ds", hours, mins, secs)
    else
        return string.format("%02dm %02ds", mins, secs)
    end
end

local function GetCycleLabel(cycle)
    if cycle == CYCLE_7DAY then return "7-Day"
    elseif cycle == CYCLE_5DAY then return "5-Day"
    elseif cycle == CYCLE_3DAY then return "3-Day"
    end
    return "?"
end

local function GetResetDateString(seconds)
    local resetTime = time() + seconds
    return date("!%A, %b %d at %I:%M %p", resetTime) .. " (UTC)"
end

----------------------------------------------------------------------
-- PERSONAL LOCKOUT DETECTION
----------------------------------------------------------------------

local function RefreshSavedInstances()
    savedLockouts = {}
    local num = GetNumSavedInstances()
    if not num or num == 0 then return end
    for i = 1, num do
        local name, id, resetTime = GetSavedInstanceInfo(i)
        if name and resetTime and resetTime > 0 then
            savedLockouts[string.lower(name)] = true
        end
    end
end

local function IsPlayerLocked(raid)
    -- Check by full name
    if savedLockouts[string.lower(raid.name)] then
        return true
    end
    -- Check by short name (some servers report abbreviated names)
    if savedLockouts[string.lower(raid.short)] then
        return true
    end
    return false
end

local function GetPlayerStatus(raid)
    if IsPlayerLocked(raid) then
        return "|cffff3333LOCKED|r", true
    else
        return "|cff33ff33AVAILABLE|r", false
    end
end

----------------------------------------------------------------------
-- LAYOUT HELPERS
----------------------------------------------------------------------

local function GetVisibleRowCount()
    if not mainFrame then return 9 end
    local frameH = mainFrame:GetHeight()
    local usable = frameH - HEADER_TOP - INFO_HEIGHT - INFO_BOTTOM - RESET_BTN_BOTTOM + 40
    local count = math.floor(usable / ROW_HEIGHT)
    if count < 1 then count = 1 end
    return count
end

local function GetContentWidth()
    if not mainFrame then return 555 end
    return mainFrame:GetWidth() - 45
end

local function RepositionElements()
    if not mainFrame then return end
    local cw = GetContentWidth()

    -- Resize separator
    if sepLine then
        sepLine:SetWidth(cw + 5)
    end

    -- Resize header
    if hdrFrame then
        hdrFrame:SetWidth(cw)
    end

    -- Resize info panel
    if infoPanel then
        infoPanel:SetWidth(cw)
        if infoText then
            infoText:SetWidth(cw - 15)
        end
    end

    -- Resize rows
    for i = 1, table.getn(rowFrames) do
        rowFrames[i]:SetWidth(cw)
    end
end

----------------------------------------------------------------------
-- SELECTION / INFO
----------------------------------------------------------------------

local function UpdateSelection()
    for i = 1, table.getn(rowFrames) do
        if rowFrames[i].raidIndex == selectedRaid then
            rowFrames[i].selected:Show()
        else
            rowFrames[i].selected:Hide()
        end
    end
end

local function UpdateInfoPanel()
    if not infoText then return end
    if not selectedRaid then
        infoText:SetText("|cff888888Select a raid instance above to view details.|r")
        return
    end
    local raid = RAIDS[selectedRaid]
    local remaining = GetSecondsUntilReset(raid)
    local status, locked = GetPlayerStatus(raid)
    local lockLabel
    if locked then
        lockLabel = "|cffff3333You are saved to this instance.|r"
    else
        lockLabel = "|cff33ff33You are not saved. Good to go!|r"
    end
    infoText:SetText(string.format(
        "|cffffd100%s|r  |cff888888(%s-Man  |  %d bosses)|r\n" ..
        "Next global reset in: |cff44ff44%s|r  |cff888888(%s cycle)|r  -  %s\n" ..
        "%s  |cff888888-|r  |cffaaaaaa%s|r",
        raid.name, raid.size, raid.bosses,
        FormatCountdown(remaining), GetCycleLabel(raid.cycle), status,
        lockLabel, raid.info
    ))
end

----------------------------------------------------------------------
-- ROW CREATION
----------------------------------------------------------------------

local function CreateRow(parent, index)
    local cw = GetContentWidth()
    local row = CreateFrame("Button", "PhantomLockoutRow" .. index, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(cw)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -HEADER_TOP - ((index - 1) * ROW_HEIGHT))

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    if math.mod(index, 2) == 0 then
        row.bg:SetVertexColor(0.25, 0.2, 0.1, 0.25)
    else
        row.bg:SetVertexColor(0.15, 0.1, 0.05, 0.15)
    end

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    row.highlight:SetVertexColor(0.6, 0.5, 0.2, 0.35)

    row.selected = row:CreateTexture(nil, "ARTWORK")
    row.selected:SetAllPoints()
    row.selected:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    row.selected:SetVertexColor(0.8, 0.6, 0.1, 0.3)
    row.selected:Hide()

    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetWidth(22)
    row.icon:SetHeight(22)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameText:SetWidth(150)
    row.nameText:SetJustifyH("LEFT")

    row.sizeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sizeText:SetPoint("LEFT", row, "LEFT", 195, 0)
    row.sizeText:SetWidth(50)
    row.sizeText:SetJustifyH("CENTER")

    row.cycleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.cycleText:SetPoint("LEFT", row, "LEFT", 250, 0)
    row.cycleText:SetWidth(60)
    row.cycleText:SetJustifyH("CENTER")

    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.statusText:SetPoint("LEFT", row, "LEFT", 315, 0)
    row.statusText:SetWidth(80)
    row.statusText:SetJustifyH("CENTER")

    row.timerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.timerText:SetPoint("LEFT", row, "LEFT", 400, 0)
    row.timerText:SetWidth(140)
    row.timerText:SetJustifyH("LEFT")

    row:SetScript("OnClick", function()
        selectedRaid = row.raidIndex
        UpdateSelection()
        UpdateInfoPanel()
    end)

    row:SetScript("OnEnter", function()
        if not row.raidIndex then return end
        local raid = RAIDS[row.raidIndex]
        local remaining = GetSecondsUntilReset(raid)
        local pStatus, pLocked = GetPlayerStatus(raid)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(raid.name, 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Players:", raid.size .. "-Man", 0.8, 0.8, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("Bosses:", raid.bosses, 0.8, 0.8, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("Reset Cycle:", GetCycleLabel(raid.cycle), 0.8, 0.8, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("Resets In:", FormatCountdown(remaining), 0.8, 0.8, 0.6, 0.4, 1, 0.4)
        if pLocked then
            GameTooltip:AddDoubleLine("Your Status:", "LOCKED", 0.8, 0.8, 0.6, 1, 0.2, 0.2)
        else
            GameTooltip:AddDoubleLine("Your Status:", "AVAILABLE", 0.8, 0.8, 0.6, 0.2, 1, 0.2)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Next Reset:", 0.6, 0.6, 0.4)
        GameTooltip:AddLine(GetResetDateString(remaining), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888Click for details|r")
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:Hide()
    return row
end

----------------------------------------------------------------------
-- ROW UPDATES
----------------------------------------------------------------------

local function UpdateRows()
    if not mainFrame then return end
    if not mainFrame:IsVisible() then return end

    local numRaids = table.getn(RAIDS)
    local visibleRows = GetVisibleRowCount()
    if visibleRows > numRaids then visibleRows = numRaids end

    -- Create rows on demand
    local totalNeeded = numRaids
    for i = 1, totalNeeded do
        if not rowFrames[i] then
            rowFrames[i] = CreateRow(mainFrame, i)
        end
    end

    for i = 1, totalNeeded do
        local row = rowFrames[i]
        if i <= numRaids then
            local raid = RAIDS[i]
            local remaining = GetSecondsUntilReset(raid)
            local status, locked = GetPlayerStatus(raid)

            row.raidIndex = i
            row.icon:SetTexture(raid.icon)
            row.nameText:SetText(raid.name)

            if raid.size == 40 then
                row.sizeText:SetText("|cffff883340-Man|r")
            else
                row.sizeText:SetText("|cff33aaff20-Man|r")
            end

            row.cycleText:SetText(GetCycleLabel(raid.cycle))
            row.statusText:SetText(status)
            row.timerText:SetText("|cffffffff" .. FormatCountdown(remaining) .. "|r")

            if i == selectedRaid then
                row.selected:Show()
            else
                row.selected:Hide()
            end

            -- Only show rows that fit
            if i <= visibleRows then
                row:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -HEADER_TOP - ((i - 1) * ROW_HEIGHT))
                row:Show()
            else
                row:Hide()
            end
        else
            row.raidIndex = nil
            row:Hide()
        end
    end
end

----------------------------------------------------------------------
-- MAIN FRAME BUILDER
----------------------------------------------------------------------

local function BuildMainFrame()
    local f = CreateFrame("Frame", "PhantomLockoutMainFrame", UIParent)
    f:SetWidth(DEFAULT_WIDTH)
    f:SetHeight(DEFAULT_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    f:SetMaxResize(900, 700)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)

    tinsert(UISpecialFrames, "PhantomLockoutMainFrame")

    -- Resize grip (bottom-right corner)
    local grip = CreateFrame("Frame", nil, f)
    grip:SetWidth(16)
    grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    grip:EnableMouse(true)
    grip:SetFrameLevel(f:GetFrameLevel() + 5)

    -- Grip visual: small triangular dots
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    local gripHi = grip:CreateTexture(nil, "HIGHLIGHT")
    gripHi:SetAllPoints()
    gripHi:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

    grip:SetScript("OnMouseDown", function()
        mainFrame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        RepositionElements()
        UpdateRows()
    end)

    -- Also reposition on size changed
    f:SetScript("OnSizeChanged", function()
        RepositionElements()
        UpdateRows()
    end)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("|cff8800ffPhantom|r|cffcc44ffLockout|r")

    -- Subtitle
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetText("|cff888888Turtle WoW Raid Reset Tracker|r")

    -- Server time
    serverTimeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    serverTimeText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -18)
    serverTimeText:SetTextColor(0.8, 0.8, 0.6)
    serverTimeText:SetText("Server Time: --:--")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- Separator under title
    sepLine = f:CreateTexture(nil, "ARTWORK")
    sepLine:SetTexture(1, 1, 1, 0.15)
    sepLine:SetWidth(GetContentWidth() + 5)
    sepLine:SetHeight(1)
    sepLine:SetPoint("TOP", f, "TOP", 0, -50)

    -- Column headers
    hdrFrame = CreateFrame("Frame", nil, f)
    hdrFrame:SetWidth(GetContentWidth())
    hdrFrame:SetHeight(20)
    hdrFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -55)

    local function MakeHeader(parent, text, xOff, width)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", parent, "LEFT", xOff, 0)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cffffd100" .. text .. "|r")
    end

    MakeHeader(hdrFrame, "Raid Instance", 30, 160)
    MakeHeader(hdrFrame, "Size", 195, 50)
    MakeHeader(hdrFrame, "Cycle", 250, 60)
    MakeHeader(hdrFrame, "Status", 315, 80)
    MakeHeader(hdrFrame, "Resets In", 400, 140)

    -- Separator under headers
    local sep2 = f:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture(1, 1, 1, 0.1)
    sep2:SetWidth(GetContentWidth())
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", hdrFrame, "BOTTOMLEFT", 0, -2)

    -- Info panel (anchored to bottom)
    infoPanel = CreateFrame("Frame", nil, f)
    infoPanel:SetWidth(GetContentWidth())
    infoPanel:SetHeight(INFO_HEIGHT)
    infoPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, INFO_BOTTOM)
    infoPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-Listbox-Highlight2",
    })
    infoPanel:SetBackdropColor(0.15, 0.12, 0.05, 0.5)

    infoText = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", infoPanel, "TOPLEFT", 8, -5)
    infoText:SetWidth(GetContentWidth() - 15)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("|cff888888Select a raid for details.|r")

    -- Reset Instances button
    resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetWidth(155)
    resetBtn:SetHeight(22)
    resetBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, RESET_BTN_BOTTOM)
    resetBtn:SetText("Reset All Instances")
    resetBtn:SetScript("OnClick", function()
        StaticPopupDialogs["PHANTOMLOCKOUT_RESET"] = {
            text = "Reset all dungeon instances?\n\n|cffff8833Does NOT affect raid lockouts.|r",
            button1 = "Reset",
            button2 = "Cancel",
            OnAccept = function()
                ResetInstances()
                DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r: Dungeon instances reset.")
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("PHANTOMLOCKOUT_RESET")
    end)
    resetBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset All Instances", 1, 0.82, 0)
        GameTooltip:AddLine("Resets non-persistent dungeon instances.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Must be party leader or solo.", 0.6, 0.6, 0.4, true)
        GameTooltip:AddLine("Does NOT affect raid lockouts.", 1, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Refresh saved lockout button
    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetWidth(120)
    refreshBtn:SetHeight(22)
    refreshBtn:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)
    refreshBtn:SetText("Refresh Lockouts")
    refreshBtn:SetScript("OnClick", function()
        RequestRaidInfo()
        DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r: Refreshing lockout data...")
    end)
    refreshBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Refresh Lockouts", 1, 0.82, 0)
        GameTooltip:AddLine("Re-queries the server for your personal", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("raid lockout status.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f:Hide()
    return f
end

----------------------------------------------------------------------
-- MINIMAP BUTTON
----------------------------------------------------------------------

local function BuildMinimapButton()
    local btn = CreateFrame("Button", "PhantomLockoutMiniBtn", Minimap)
    btn:SetWidth(33)
    btn:SetHeight(33)
    btn:SetFrameStrata("MEDIUM")
    btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -90)
    btn:EnableMouse(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(21)
    icon:SetHeight(21)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Key_03")
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetWidth(56)
    border:SetHeight(56)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")

    btn:SetScript("OnClick", function()
        PhantomLockout_ToggleFrame()
    end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff8800ffPhantom|r|cffcc44ffLockout|r", 1, 1, 1)
        GameTooltip:AddLine("Click to toggle lockout window.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnDragStart", function() this:StartMoving() end)
    btn:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
end

----------------------------------------------------------------------
-- TOGGLE (global)
----------------------------------------------------------------------

function PhantomLockout_ToggleFrame()
    if not mainFrame then return end
    if mainFrame:IsVisible() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        RequestRaidInfo()
        UpdateRows()
    end
end

----------------------------------------------------------------------
-- TICK (1 second refresh)
----------------------------------------------------------------------

local updateElapsed = 0
local function OnTick()
    updateElapsed = updateElapsed + arg1
    if updateElapsed < 1 then return end
    updateElapsed = 0

    if not mainFrame then return end
    if not mainFrame:IsVisible() then return end

    local hours, minutes = GetGameTime()
    if serverTimeText then
        serverTimeText:SetText(string.format("Server Time: %02d:%02d", hours, minutes))
    end

    UpdateRows()

    if selectedRaid then
        UpdateInfoPanel()
    end
end

----------------------------------------------------------------------
-- BOOT
----------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("VARIABLES_LOADED")
boot:RegisterEvent("UPDATE_INSTANCE_INFO")
boot:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if not PhantomLockoutDB then
            PhantomLockoutDB = {}
        end

        -- Build everything
        mainFrame = BuildMainFrame()
        BuildMinimapButton()

        -- Request lockout info from server
        RequestRaidInfo()

        -- Timer tick
        boot:SetScript("OnUpdate", OnTick)

        -- Slash commands
        SLASH_PHANTOMLOCKOUT1 = "/phantomlockout"
        SLASH_PHANTOMLOCKOUT2 = "/pl"
        SLASH_PHANTOMLOCKOUT3 = "/plock"
        SlashCmdList["PHANTOMLOCKOUT"] = function(msg)
            if msg == "help" then
                DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r Commands:")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/pl|r - Toggle the lockout window")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/pl help|r - Show this help")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/pl next|r - Show resets in chat")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/pl reset|r - Reset dungeon instances")
            elseif msg == "next" then
                DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r - Upcoming Resets:")
                for i = 1, table.getn(RAIDS) do
                    local raid = RAIDS[i]
                    local remaining = GetSecondsUntilReset(raid)
                    local status, _ = GetPlayerStatus(raid)
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffffd100%s|r (%s-Man): %s  -  %s",
                        raid.name, raid.size, FormatCountdown(remaining), status))
                end
            elseif msg == "reset" then
                StaticPopupDialogs["PHANTOMLOCKOUT_RESET"] = {
                    text = "Reset all dungeon instances?\n\n|cffff8833Does NOT affect raid lockouts.|r",
                    button1 = "Reset",
                    button2 = "Cancel",
                    OnAccept = function()
                        ResetInstances()
                        DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r: Dungeon instances reset.")
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("PHANTOMLOCKOUT_RESET")
            else
                PhantomLockout_ToggleFrame()
            end
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r v1.0 loaded. Type |cffffd100/pl|r to toggle.")

    elseif event == "UPDATE_INSTANCE_INFO" then
        -- Server responded with our lockout data
        RefreshSavedInstances()
        UpdateRows()
        if selectedRaid then
            UpdateInfoPanel()
        end
    end
end)
