----------------------------------------------------------------------
-- PhantomLockout - Turtle WoW Raid Lockout Tracker
-- Pure Lua - guild lockout sharing via addon messages
----------------------------------------------------------------------

----------------------------------------------------------------------
-- ADDON MESSAGE PREFIX
----------------------------------------------------------------------

local ADDON_PREFIX = "PhantomLock"

----------------------------------------------------------------------
-- CONFIGURATION & DATA
----------------------------------------------------------------------

-- Weekly raids reset Tuesday at 23:00 server time (EST).
-- We compute these from day-of-week + GetGameTime().
-- Rolling resets use anchor-based modulo math.
-- Anchors: known reset moments (UTC epoch) for rolling cycles.
-- Onyxia 5-day anchor: Wed Jan 8, 2025 04:00 UTC (Tue Jan 7 23:00 EST)
local ANCHOR_ONYXIA = 1736308800
-- Karazhan 5-day anchor: offset by 2 days from Onyxia
local ANCHOR_KARAZHAN = 1736308800 + (2 * 86400)
-- Raid 20 / Kara10 3-day anchor: offset by 1 day from Onyxia
local ANCHOR_RAID20 = 1736308800 + 86400

local CYCLE_7DAY = 7 * 24 * 3600
local CYCLE_5DAY = 5 * 24 * 3600
local CYCLE_3DAY = 3 * 24 * 3600

local RAIDS = {
    {
        name = "Molten Core",
        short = "MC",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = 0, -- weekly: computed from day-of-week
        icon = "Interface\\Icons\\Spell_Fire_Incinerate",
        info = "The Firelord Ragnaros awaits in Blackrock Mountain. Tier 1 gear and legendary bindings.",
        bosses = 10,
    },
    {
        name = "Blackwing Lair",
        short = "BWL",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = 0, -- weekly: computed from day-of-week
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
        info = "Nefarian's stronghold atop Blackrock Mountain. Tier 2 gear and challenging encounters.",
        bosses = 8,
    },
    {
        name = "Temple of Ahn'Qiraj",
        short = "AQ40",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = 0, -- weekly: computed from day-of-week
        icon = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_01",
        info = "Face C'Thun and the Qiraji empire. Tier 2.5 gear.",
        bosses = 9,
    },
    {
        name = "Naxxramas",
        short = "Naxx",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = 0, -- weekly: computed from day-of-week
        icon = "Interface\\Icons\\INV_Trinket_Naxxramas06",
        info = "The floating necropolis of Kel'Thuzad. Four wings. Tier 3 gear.",
        bosses = 15,
    },
    {
        name = "Emerald Sanctum",
        short = "ES",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = 0, -- weekly: computed from day-of-week
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
        short = "Kara40",
        size = 40,
        cycle = CYCLE_5DAY,
        anchor = ANCHOR_KARAZHAN,
        icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
        info = "Medivh's haunted tower (40-man). Deadwind Pass. 5-day reset.",
        bosses = 11,
    },
    {
        name = "Karazhan (10)",
        short = "Kara10",
        size = 10,
        cycle = CYCLE_3DAY,
        anchor = ANCHOR_RAID20,
        icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
        info = "Medivh's haunted tower (10-man). Deadwind Pass. 3-day reset.",
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
local HEADER_TOP = 78
local INFO_HEIGHT = 55
local INFO_BOTTOM = 15
local RESET_BTN_BOTTOM = 75
local MIN_WIDTH = 680
local MIN_HEIGHT = 300
local DEFAULT_WIDTH = 740
local DEFAULT_HEIGHT = 470

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
local savedLockouts = {}

-- Guild lockout tracking: guildLockouts[raidShortLower] = { ["PlayerName"] = expiryEpoch, ... }
local guildLockouts = {}

-- Track all guild members who have the addon installed (anyone who sends a message)
local addonUsers = {}  -- ["PlayerName"] = lastSeenEpoch

-- Guild MOTD (message of the day) - shared message editable by admins only
local guildMOTD = ""
local MOTD_ADMINS = { ["Mczuknuuk"] = true, ["Morganni"] = true }
local motdFrame = nil

-- Initialize guild lockout tables for each raid
local function InitGuildTables()
    for i = 1, table.getn(RAIDS) do
        local key = string.lower(RAIDS[i].short)
        if not guildLockouts[key] then
            guildLockouts[key] = {}
        end
    end
end

-- Prune expired guild lockout entries
local function PruneGuildLockouts()
    local now = time()
    for i = 1, table.getn(RAIDS) do
        local key = string.lower(RAIDS[i].short)
        if guildLockouts[key] then
            for name, expiry in pairs(guildLockouts[key]) do
                if type(expiry) ~= "number" or expiry <= now then
                    guildLockouts[key][name] = nil
                end
            end
        end
    end
end

-- Save guild lockout data to SavedVariables
local function SaveGuildData()
    if not PhantomLockoutDB then PhantomLockoutDB = {} end
    PhantomLockoutDB.guildData = guildLockouts
    PhantomLockoutDB.addonUsers = addonUsers
    PhantomLockoutDB.motd = guildMOTD
end

-- Load guild lockout data from SavedVariables
local function LoadGuildData()
    if PhantomLockoutDB and PhantomLockoutDB.guildData then
        guildLockouts = PhantomLockoutDB.guildData
    end
    if PhantomLockoutDB and PhantomLockoutDB.addonUsers then
        addonUsers = PhantomLockoutDB.addonUsers
    end
    if PhantomLockoutDB and PhantomLockoutDB.motd then
        guildMOTD = PhantomLockoutDB.motd
    end
    InitGuildTables()
    PruneGuildLockouts()
end

----------------------------------------------------------------------
-- UTILITY FUNCTIONS
----------------------------------------------------------------------

local function GetSecondsUntilReset(raid)
    -- Pure epoch-based modulo for ALL raid types.
    -- Weekly anchor: Wed Jan 8, 2025 04:00 UTC = Tue Jan 7, 2025 23:00 EST
    -- This is a known 40-man weekly reset point.
    local WEEKLY_ANCHOR = 1736308800

    local anchor
    if raid.cycle == CYCLE_7DAY then
        anchor = WEEKLY_ANCHOR
    else
        anchor = raid.anchor
    end

    local now = time()
    local elapsed = now - anchor
    if elapsed < 0 then
        return raid.cycle
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
    return date("%A, %b %d at %I:%M %p", resetTime) .. " (Local)"
end

----------------------------------------------------------------------
-- PERSONAL LOCKOUT DETECTION
----------------------------------------------------------------------

-- savedLockouts[lowerName] = absolute expiry time (epoch)
local function RefreshSavedInstances()
    savedLockouts = {}
    local num = GetNumSavedInstances()
    if not num or num == 0 then return end
    local now = time()
    for i = 1, num do
        local name, id, resetTime = GetSavedInstanceInfo(i)
        if name and resetTime and resetTime > 0 then
            -- Store the absolute epoch when lockout expires
            savedLockouts[string.lower(name)] = now + resetTime
        end
    end
end

-- Returns isLocked (bool), secondsRemaining (number or nil)
local function IsPlayerLocked(raid)
    local now = time()

    local expiry = savedLockouts[string.lower(raid.name)]
    if expiry and expiry > now then
        return true, expiry - now
    end

    expiry = savedLockouts[string.lower(raid.short)]
    if expiry and expiry > now then
        return true, expiry - now
    end

    -- Handle Karazhan variants matching just "karazhan"
    if string.find(string.lower(raid.name), "karazhan") then
        expiry = savedLockouts["karazhan"]
        if expiry and expiry > now then
            return true, expiry - now
        end
    end
    return false, nil
end

local function GetPlayerStatus(raid)
    local locked, personalTime = IsPlayerLocked(raid)
    if locked then
        return "|cffff3333LOCKED|r", true, personalTime
    else
        return "|cff33ff33AVAILABLE|r", false, nil
    end
end

-- Get the display countdown: personal timer if locked, global timer if available
local function GetDisplayCountdown(raid)
    local locked, personalTime = IsPlayerLocked(raid)
    if locked and personalTime and personalTime > 0 then
        return personalTime
    end
    return GetSecondsUntilReset(raid)
end

----------------------------------------------------------------------
-- GUILD LOCKOUT COMMUNICATION
----------------------------------------------------------------------

-- Build a message string with remaining seconds: "MC:25200,BWL:86400"
local function BuildLockoutMessage()
    local parts = {}
    for i = 1, table.getn(RAIDS) do
        local locked, personalTime = IsPlayerLocked(RAIDS[i])
        if locked and personalTime and personalTime > 0 then
            -- Send the raw remaining seconds
            table.insert(parts, RAIDS[i].short .. ":" .. math.floor(personalTime))
        end
    end
    if table.getn(parts) == 0 then
        return "NONE"
    end
    return table.concat(parts, ",")
end

-- Broadcast our lockouts to guild
local function BroadcastLockouts()
    if not IsInGuild() then return end
    local msg = "LOCKOUTS:" .. BuildLockoutMessage()
    SendAddonMessage(ADDON_PREFIX, msg, "GUILD")
end

-- Parse incoming lockout message from a guild member
local function ParseLockoutMessage(sender, message)
    if not message then return end
    if string.sub(message, 1, 9) ~= "LOCKOUTS:" then return end

    -- Record this sender as having the addon
    addonUsers[sender] = time()

    local payload = string.sub(message, 10)

    -- Clear this sender from all raids first
    for i = 1, table.getn(RAIDS) do
        local key = string.lower(RAIDS[i].short)
        if guildLockouts[key] then
            guildLockouts[key][sender] = nil
        end
    end

    if payload == "NONE" then
        SaveGuildData()
        return
    end

    local now = time()

    -- Parse comma-separated "SHORT:REMAINING_SECONDS" pairs
    local start = 1
    while true do
        local commaPos = string.find(payload, ",", start, true)
        local token
        if commaPos then
            token = string.sub(payload, start, commaPos - 1)
            start = commaPos + 1
        else
            token = string.sub(payload, start)
        end
        if token and token ~= "" then
            local colonPos = string.find(token, ":", 1, true)
            if colonPos then
                local raidShort = string.sub(token, 1, colonPos - 1)
                local remainStr = string.sub(token, colonPos + 1)
                local remainSec = tonumber(remainStr)
                local key = string.lower(raidShort)
                if guildLockouts[key] and remainSec and remainSec > 0 then
                    -- Convert to absolute expiry: now + remaining
                    guildLockouts[key][sender] = now + remainSec
                end
            end
        end
        if not commaPos then break end
    end

    SaveGuildData()
end

-- Get list of guild members locked to a specific raid (with valid expiry)
local function GetGuildLockedNames(raid)
    local key = string.lower(raid.short)
    local names = {}
    local now = time()
    if not guildLockouts[key] then return names end
    for name, expiry in pairs(guildLockouts[key]) do
        if type(expiry) == "number" and expiry > now then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

local function GetGuildLockedCount(raid)
    local key = string.lower(raid.short)
    if not guildLockouts[key] then return 0 end
    local count = 0
    local now = time()
    for name, expiry in pairs(guildLockouts[key]) do
        if type(expiry) == "number" and expiry > now then
            count = count + 1
        end
    end
    return count
end

-- Get a member's remaining lockout seconds
local function GetGuildMemberLockoutRemaining(raid, memberName)
    local key = string.lower(raid.short)
    if not guildLockouts[key] then return nil end
    local expiry = guildLockouts[key][memberName]
    if not expiry or type(expiry) ~= "number" then return nil end
    local remaining = expiry - time()
    if remaining <= 0 then return nil end
    return remaining
end

-- Check if a guild member is locked to a specific raid
local function IsGuildMemberLocked(raid, memberName)
    local key = string.lower(raid.short)
    if not guildLockouts[key] then return false end
    local expiry = guildLockouts[key][memberName]
    if not expiry or type(expiry) ~= "number" then return false end
    return expiry > time()
end

-- Get all addon users who are NOT locked to a specific raid
local function GetAvailableMembers(raid)
    local myName = UnitName("player")
    local available = {}
    for name, lastSeen in pairs(addonUsers) do
        if name ~= myName then
            if not IsGuildMemberLocked(raid, name) then
                table.insert(available, name)
            end
        end
    end
    table.sort(available)
    return available
end

-- Invite all available members for a raid
local function InviteAvailableMembers(raid)
    local available = GetAvailableMembers(raid)
    local count = table.getn(available)
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r: No available guild members with addon for " .. raid.name .. ".")
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r: Inviting " .. count .. " available members for |cffffd100" .. raid.name .. "|r:")
    for i = 1, count do
        InviteByName(available[i])
        DEFAULT_CHAT_FRAME:AddMessage("  |cff33ff33+|r " .. available[i])
    end
end

----------------------------------------------------------------------
-- GUILD MOTD (admin message)
----------------------------------------------------------------------

local function IsPlayerAdmin()
    local myName = UnitName("player")
    return MOTD_ADMINS[myName] == true
end

-- Broadcast MOTD to guild
local function BroadcastMOTD()
    if not IsInGuild() then return end
    if guildMOTD and guildMOTD ~= "" then
        SendAddonMessage(ADDON_PREFIX, "MOTD:" .. guildMOTD, "GUILD")
    else
        SendAddonMessage(ADDON_PREFIX, "MOTD:", "GUILD")
    end
end

-- Parse incoming MOTD
local function ParseMOTDMessage(sender, message)
    if not message then return end
    if string.sub(message, 1, 5) ~= "MOTD:" then return end
    -- Only accept MOTD from admins
    if not MOTD_ADMINS[sender] then return end
    local newMOTD = string.sub(message, 6)
    guildMOTD = newMOTD
    SaveGuildData()
    -- Update the MOTD frame if it's open
    if motdFrame and motdFrame:IsVisible() and motdFrame.messageText then
        motdFrame.messageText:SetText(guildMOTD ~= "" and guildMOTD or "|cff555555No message set.|r")
    end
end

-- Build MOTD popup frame
local function BuildMOTDFrame()
    local mf = CreateFrame("Frame", "PhantomLockoutMOTDFrame", UIParent)
    mf:SetWidth(400)
    mf:SetHeight(250)
    mf:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    mf:SetFrameStrata("DIALOG")
    mf:EnableMouse(true)
    mf:SetMovable(true)
    mf:RegisterForDrag("LeftButton")
    mf:SetScript("OnDragStart", function() this:StartMoving() end)
    mf:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    mf:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    mf:SetBackdropColor(0.1, 0.1, 0.1, 1.0)

    tinsert(UISpecialFrames, "PhantomLockoutMOTDFrame")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, mf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mf, "TOPRIGHT", -5, -5)

    -- Title
    local titleText = mf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", mf, "TOP", 0, -18)
    titleText:SetText("|cff8800ffPhantom|r|cffcc44ffLockout|r |cffffd100Board|r")

    -- Separator
    local sep = mf:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(1, 1, 1, 0.15)
    sep:SetWidth(360)
    sep:SetHeight(1)
    sep:SetPoint("TOP", mf, "TOP", 0, -42)

    -- Message display area
    local msgBg = CreateFrame("Frame", nil, mf)
    msgBg:SetWidth(360)
    msgBg:SetHeight(130)
    msgBg:SetPoint("TOP", sep, "BOTTOM", 0, -8)
    msgBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    msgBg:SetBackdropColor(0.05, 0.05, 0.05, 1.0)
    msgBg:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    mf.messageText = msgBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mf.messageText:SetPoint("TOPLEFT", msgBg, "TOPLEFT", 10, -10)
    mf.messageText:SetPoint("BOTTOMRIGHT", msgBg, "BOTTOMRIGHT", -10, 10)
    mf.messageText:SetJustifyH("LEFT")
    mf.messageText:SetJustifyV("TOP")
    mf.messageText:SetText(guildMOTD ~= "" and guildMOTD or "|cff555555No message set.|r")

    -- Admin controls (only visible to admins)
    if IsPlayerAdmin() then
        -- Hide the static text when admin
        mf.messageText:Hide()

        -- Simple multiline edit box directly inside msgBg
        local editBox = CreateFrame("EditBox", "PhantomLockoutMOTDEditBox", msgBg)
        editBox:SetPoint("TOPLEFT", msgBg, "TOPLEFT", 10, -8)
        editBox:SetPoint("BOTTOMRIGHT", msgBg, "BOTTOMRIGHT", -10, 8)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(GameFontHighlight)
        editBox:SetTextColor(1, 1, 1)
        editBox:SetText(guildMOTD or "")
        editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        editBox:EnableMouse(true)

        mf.editBox = editBox

        -- Save button
        local saveBtn = CreateFrame("Button", nil, mf, "UIPanelButtonTemplate")
        saveBtn:SetWidth(100)
        saveBtn:SetHeight(22)
        saveBtn:SetPoint("BOTTOMRIGHT", mf, "BOTTOMRIGHT", -20, 15)
        saveBtn:SetText("Save & Share")
        saveBtn:SetScript("OnClick", function()
            local newText = mf.editBox:GetText() or ""
            guildMOTD = newText
            SaveGuildData()
            BroadcastMOTD()
            DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r: Board message updated and shared.")
        end)

        -- Clear button
        local clearBtn = CreateFrame("Button", nil, mf, "UIPanelButtonTemplate")
        clearBtn:SetWidth(80)
        clearBtn:SetHeight(22)
        clearBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            mf.editBox:SetText("")
            guildMOTD = ""
            SaveGuildData()
            BroadcastMOTD()
            DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r: Board message cleared.")
        end)

        -- Admin label
        local adminLabel = mf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        adminLabel:SetPoint("BOTTOMLEFT", mf, "BOTTOMLEFT", 20, 19)
        adminLabel:SetText("|cffff8833Admin Mode|r")
    end

    mf:Hide()
    return mf
end

-- Toggle MOTD frame
local function ToggleMOTDFrame()
    if not motdFrame then
        motdFrame = BuildMOTDFrame()
    end
    if motdFrame:IsVisible() then
        motdFrame:Hide()
    else
        -- Refresh display text for non-admins
        if not IsPlayerAdmin() and motdFrame.messageText then
            motdFrame.messageText:SetText(guildMOTD ~= "" and guildMOTD or "|cff555555No message set.|r")
        end
        -- Refresh edit box text for admins
        if IsPlayerAdmin() and motdFrame.editBox then
            motdFrame.editBox:SetText(guildMOTD or "")
        end
        motdFrame:Show()
    end
end

----------------------------------------------------------------------
-- LAYOUT HELPERS
----------------------------------------------------------------------

local function GetVisibleRowCount()
    if not mainFrame then return 10 end
    local frameH = mainFrame:GetHeight()
    local usable = frameH - HEADER_TOP - INFO_HEIGHT - INFO_BOTTOM - RESET_BTN_BOTTOM + 40
    local count = math.floor(usable / ROW_HEIGHT)
    if count < 1 then count = 1 end
    return count
end

local function GetContentWidth()
    if not mainFrame then return 695 end
    return mainFrame:GetWidth() - 45
end

local function RepositionElements()
    if not mainFrame then return end
    local cw = GetContentWidth()

    if sepLine then sepLine:SetWidth(cw + 5) end
    if hdrFrame then hdrFrame:SetWidth(cw) end
    if infoPanel then
        infoPanel:SetWidth(cw)
        if infoText then infoText:SetWidth(cw - 15) end
    end
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
    local remaining = GetDisplayCountdown(raid)
    local status, locked, personalTime = GetPlayerStatus(raid)
    local lockLabel
    if locked then
        lockLabel = "|cffff3333You are saved to this instance.|r"
    else
        lockLabel = "|cff33ff33You are not saved. Good to go!|r"
    end

    -- Guild lockout info
    local guildNames = GetGuildLockedNames(raid)
    local guildStr = ""
    if table.getn(guildNames) > 0 then
        guildStr = "  |cff888888Guild locked:|r |cffffaa33" .. table.concat(guildNames, ", ") .. "|r"
    end

    local timerLine
    if locked then
        timerLine = string.format("Lockout expires in: |cffff8833%s|r  |cff888888(%s cycle)|r  -  %s",
            FormatCountdown(remaining), GetCycleLabel(raid.cycle), status)
    else
        timerLine = string.format("|cff888888%s cycle|r  -  %s",
            GetCycleLabel(raid.cycle), status)
    end

    infoText:SetText(string.format(
        "|cffffd100%s|r  |cff888888(%s-Man  |  %d bosses)|r\n" ..
        "%s\n" ..
        "%s  |cff888888-|r  |cffaaaaaa%s|r%s",
        raid.name, raid.size, raid.bosses,
        timerLine,
        lockLabel, raid.info, guildStr
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
    row.timerText:SetWidth(110)
    row.timerText:SetJustifyH("LEFT")

    -- Guild Lockouts column
    row.guildText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.guildText:SetPoint("LEFT", row, "LEFT", 520, 0)
    row.guildText:SetWidth(160)
    row.guildText:SetJustifyH("LEFT")

    -- Register both mouse buttons
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Click: Left = select, Right = invite available members
    row:SetScript("OnClick", function()
        if not row.raidIndex then return end
        if arg1 == "RightButton" then
            local raid = RAIDS[row.raidIndex]
            -- Confirm before inviting
            StaticPopupDialogs["PHANTOMLOCKOUT_INVITE"] = {
                text = "Invite all available guild members\nwith PhantomLockout for:\n\n|cffffd100" .. raid.name .. "|r?",
                button1 = "Invite",
                button2 = "Cancel",
                OnAccept = function()
                    InviteAvailableMembers(raid)
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("PHANTOMLOCKOUT_INVITE")
        else
            selectedRaid = row.raidIndex
            UpdateSelection()
            UpdateInfoPanel()
        end
    end)

    -- Tooltip builder (reusable so it can tick)
    local function BuildRowTooltip()
        if not row.raidIndex then return end
        local raid = RAIDS[row.raidIndex]
        local remaining = GetDisplayCountdown(raid)
        local pStatus, pLocked, pTime = GetPlayerStatus(raid)
        GameTooltip:ClearLines()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(raid.name, 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Players:", raid.size .. "-Man", 0.8, 0.8, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("Bosses:", raid.bosses, 0.8, 0.8, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("Reset Cycle:", GetCycleLabel(raid.cycle), 0.8, 0.8, 0.6, 1, 1, 1)
        if pLocked then
            GameTooltip:AddDoubleLine("Lockout Expires:", FormatCountdown(remaining), 0.8, 0.8, 0.6, 1, 0.53, 0.2)
            GameTooltip:AddDoubleLine("Your Status:", "LOCKED", 0.8, 0.8, 0.6, 1, 0.2, 0.2)
        else
            GameTooltip:AddDoubleLine("Your Status:", "AVAILABLE", 0.8, 0.8, 0.6, 0.2, 1, 0.2)
        end
        if pLocked then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Unlocks:", 0.6, 0.6, 0.4)
            GameTooltip:AddLine(GetResetDateString(remaining), 1, 1, 1)
        end

        -- Guild locked names with live timers
        local gNames = GetGuildLockedNames(raid)
        if table.getn(gNames) > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Guild Members Locked (" .. table.getn(gNames) .. "):", 1, 0.67, 0.2)
            for gi = 1, table.getn(gNames) do
                local memberRemaining = GetGuildMemberLockoutRemaining(raid, gNames[gi])
                if memberRemaining then
                    GameTooltip:AddDoubleLine("  " .. gNames[gi], FormatCountdown(memberRemaining), 1, 0.85, 0.5, 0.8, 0.6, 0.2)
                else
                    GameTooltip:AddLine("  " .. gNames[gi], 1, 0.85, 0.5)
                end
            end
        else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("No guild members locked (with addon).", 0.5, 0.5, 0.5)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888Left-click for details|r")
        GameTooltip:AddLine("|cff888888Right-click to invite available members|r")
        GameTooltip:Show()
    end

    -- Hover state and tick timer
    row.isHovered = false
    row.tooltipElapsed = 0

    row:SetScript("OnEnter", function()
        row.isHovered = true
        row.tooltipElapsed = 0
        BuildRowTooltip()
    end)

    row:SetScript("OnLeave", function()
        row.isHovered = false
        row.tooltipElapsed = 0
        GameTooltip:Hide()
    end)

    -- Tick the tooltip every second while hovering
    row:SetScript("OnUpdate", function()
        if not row.isHovered then return end
        row.tooltipElapsed = row.tooltipElapsed + arg1
        if row.tooltipElapsed >= 1 then
            row.tooltipElapsed = 0
            BuildRowTooltip()
        end
    end)

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

    for i = 1, numRaids do
        if not rowFrames[i] then
            rowFrames[i] = CreateRow(mainFrame, i)
        end
    end

    for i = 1, numRaids do
        local row = rowFrames[i]
        local raid = RAIDS[i]
        local remaining = GetDisplayCountdown(raid)
        local status, locked, personalTime = GetPlayerStatus(raid)

        row.raidIndex = i
        row.icon:SetTexture(raid.icon)
        row.nameText:SetText(raid.name)

        if raid.size == 40 then
            row.sizeText:SetText("|cffff883340-Man|r")
        elseif raid.size == 20 then
            row.sizeText:SetText("|cff33aaff20-Man|r")
        else
            row.sizeText:SetText("|cff88ddff" .. raid.size .. "-Man|r")
        end

        row.cycleText:SetText(GetCycleLabel(raid.cycle))
        row.statusText:SetText(status)

        -- Only show countdown timer for locked raids
        if locked then
            row.timerText:SetText("|cffff8833" .. FormatCountdown(remaining) .. "|r")
        else
            row.timerText:SetText("|cff555555" .. "---" .. "|r")
        end

        -- Guild lockouts column
        local gCount = GetGuildLockedCount(raid)
        if gCount > 0 then
            local gNames = GetGuildLockedNames(raid)
            -- Show first 2 names + count if more
            local display
            if gCount <= 2 then
                display = "|cffffaa33" .. table.concat(gNames, ", ") .. "|r"
            else
                display = "|cffffaa33" .. gNames[1] .. ", " .. gNames[2] .. "|r |cff888888(+" .. (gCount - 2) .. ")|r"
            end
            row.guildText:SetText(display)
        else
            row.guildText:SetText("|cff555555--|r")
        end

        if i == selectedRaid then
            row.selected:Show()
        else
            row.selected:Hide()
        end

        if i <= visibleRows then
            row:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -HEADER_TOP - ((i - 1) * ROW_HEIGHT))
            row:Show()
        else
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
    f:SetMaxResize(1000, 750)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 1.0)

    tinsert(UISpecialFrames, "PhantomLockoutMainFrame")

    -- Resize grip
    local grip = CreateFrame("Frame", nil, f)
    grip:SetWidth(16)
    grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    grip:EnableMouse(true)
    grip:SetFrameLevel(f:GetFrameLevel() + 5)

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

    -- Time displays (top left)
    serverTimeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    serverTimeText:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -18)
    serverTimeText:SetTextColor(0.8, 0.8, 0.6)
    serverTimeText:SetText("Server: --:--  |  Local: --:--")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- Separator
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
    MakeHeader(hdrFrame, "Resets In", 400, 110)
    MakeHeader(hdrFrame, "Guild Lockouts", 520, 160)

    -- Separator under headers
    local sep2 = f:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture(1, 1, 1, 0.1)
    sep2:SetWidth(GetContentWidth())
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", hdrFrame, "BOTTOMLEFT", 0, -2)

    -- Info panel
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

    -- Refresh lockouts button
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
        GameTooltip:AddLine("raid lockout status and broadcasts", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("to guild members with this addon.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hidden MOTD button (bottom-left)
    local motdBtn = CreateFrame("Button", nil, f)
    motdBtn:SetWidth(20)
    motdBtn:SetHeight(20)
    motdBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    motdBtn:SetFrameLevel(f:GetFrameLevel() + 5)
    -- Invisible - no textures
    motdBtn:SetScript("OnClick", function()
        ToggleMOTDFrame()
    end)
    motdBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cff8800ffPhantom|r|cffcc44ffLockout|r Board", 1, 1, 1)
        GameTooltip:AddLine("Click to view guild board message.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    motdBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
-- TICK
----------------------------------------------------------------------

local updateElapsed = 0
local broadcastElapsed = 0
local pruneElapsed = 0
local motdBroadcastDelay = 0
local motdBroadcasted = false
local BROADCAST_INTERVAL = 60
local PRUNE_INTERVAL = 300  -- prune expired guild data every 5 minutes

local function OnTick()
    updateElapsed = updateElapsed + arg1
    broadcastElapsed = broadcastElapsed + arg1
    pruneElapsed = pruneElapsed + arg1

    -- One-time delayed MOTD broadcast for admins on login
    if not motdBroadcasted then
        motdBroadcastDelay = motdBroadcastDelay + arg1
        if motdBroadcastDelay >= 10 then
            motdBroadcasted = true
            if IsPlayerAdmin() and guildMOTD ~= "" then
                BroadcastMOTD()
            end
        end
    end

    -- Periodic guild broadcast
    if broadcastElapsed >= BROADCAST_INTERVAL then
        broadcastElapsed = 0
        BroadcastLockouts()
    end

    -- Periodic prune of expired guild lockouts
    if pruneElapsed >= PRUNE_INTERVAL then
        pruneElapsed = 0
        PruneGuildLockouts()
        SaveGuildData()
    end

    if updateElapsed < 1 then return end
    updateElapsed = 0

    if not mainFrame then return end
    if not mainFrame:IsVisible() then return end

    local hours, minutes = GetGameTime()
    if serverTimeText then
        local localH = tonumber(date("%H"))
        local localM = tonumber(date("%M"))
        serverTimeText:SetText(string.format(
            "|cffffd100Server:|r %02d:%02d  |cff888888|||r  |cffffd100Local:|r %02d:%02d",
            hours, minutes, localH, localM
        ))
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
boot:RegisterEvent("CHAT_MSG_ADDON")
boot:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if not PhantomLockoutDB then
            PhantomLockoutDB = {}
        end

        LoadGuildData()

        mainFrame = BuildMainFrame()
        BuildMinimapButton()

        RequestRaidInfo()

        boot:SetScript("OnUpdate", OnTick)

        -- Slash commands
        SLASH_PHANTOMLOCKOUT1 = "/phantomlockout"
        SLASH_PHANTOMLOCKOUT2 = "/plockout"
        SLASH_PHANTOMLOCKOUT3 = "/plock"
        SlashCmdList["PHANTOMLOCKOUT"] = function(msg)
            if msg == "help" then
                DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r Commands:")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plockout|r - Toggle the lockout window")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plockout help|r - Show this help")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plockout next|r - Show resets in chat")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plockout reset|r - Reset dungeon instances")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plockout guild|r - Show guild lockout summary")
                DEFAULT_CHAT_FRAME:AddMessage("  |cff888888Right-click a raid to invite all available guild members with addon.|r")
            elseif msg == "next" then
                DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r - Upcoming Resets:")
                for i = 1, table.getn(RAIDS) do
                    local raid = RAIDS[i]
                    local status, locked, _ = GetPlayerStatus(raid)
                    if locked then
                        local remaining = GetDisplayCountdown(raid)
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffffd100%s|r (%s-Man): |cffff8833%s|r  -  %s",
                            raid.name, raid.size, FormatCountdown(remaining), status))
                    else
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffffd100%s|r (%s-Man): %s",
                            raid.name, raid.size, status))
                    end
                end
            elseif msg == "guild" then
                DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r - Guild Lockouts:")
                for i = 1, table.getn(RAIDS) do
                    local raid = RAIDS[i]
                    local gNames = GetGuildLockedNames(raid)
                    local gCount = table.getn(gNames)
                    if gCount > 0 then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffffd100%s|r: |cffffaa33%s|r",
                            raid.name, table.concat(gNames, ", ")))
                    end
                end
                local totalFound = false
                for i = 1, table.getn(RAIDS) do
                    if GetGuildLockedCount(RAIDS[i]) > 0 then totalFound = true end
                end
                if not totalFound then
                    DEFAULT_CHAT_FRAME:AddMessage("  |cff888888No guild lockouts detected (need addon installed).|r")
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

        DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r v1.1 loaded. Type |cffffd100/plockout|r to toggle. Guild sync enabled.")

    elseif event == "UPDATE_INSTANCE_INFO" then
        RefreshSavedInstances()
        BroadcastLockouts()
        UpdateRows()
        if selectedRaid then
            UpdateInfoPanel()
        end

    elseif event == "CHAT_MSG_ADDON" then
        -- arg1=prefix, arg2=message, arg3=channel, arg4=sender
        if arg1 == ADDON_PREFIX and arg3 == "GUILD" then
            local myName = UnitName("player")
            if arg4 and arg4 ~= myName then
                -- Check if it's a MOTD message
                if arg2 and string.sub(arg2, 1, 5) == "MOTD:" then
                    ParseMOTDMessage(arg4, arg2)
                else
                    ParseLockoutMessage(arg4, arg2)
                    UpdateRows()
                    if selectedRaid then
                        UpdateInfoPanel()
                    end
                end
            end
        end
    end
end)
