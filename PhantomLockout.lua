----------------------------------------------------------------------
-- PhantomLockout - Turtle WoW Raid Lockout Tracker
-- Displays raid reset timers in an Auction House-style UI
----------------------------------------------------------------------

----------------------------------------------------------------------
-- CONFIGURATION & DATA
----------------------------------------------------------------------

-- All reset times are based on server time (EST / UTC-5)
-- Reference anchor: A known Raid40 reset on Tuesday Jan 7, 2025 at 23:00 EST
-- This gives us a fixed point in time to calculate all rolling resets from.

local RESET_HOUR = 23 -- 11:00 PM server time (EST)
local RESET_MINUTE = 0

-- Anchor timestamps (Unix time, UTC) for each reset cycle.
-- These represent a known reset moment for each category.
-- Raid 40: Tuesday, Jan 7, 2025, 23:00 EST = Jan 8, 2025 04:00 UTC
local ANCHOR_RAID40 = 1736309600  -- approximate anchor
-- Onyxia (5-day): anchored to same date
local ANCHOR_ONYXIA = 1736309600
-- Karazhan (5-day): offset by a couple days from Onyxia
local ANCHOR_KARAZHAN = 1736309600
-- Raid 20 (3-day): anchored to same base
local ANCHOR_RAID20 = 1736309600

-- Cycle lengths in seconds
local CYCLE_7DAY = 7 * 24 * 3600   -- 604800
local CYCLE_5DAY = 5 * 24 * 3600   -- 432000
local CYCLE_3DAY = 3 * 24 * 3600   -- 259200

-- Raid data table
local RAIDS = {
    {
        name = "Molten Core",
        short = "MC",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\Spell_Fire_Incinerate",
        info = "The Firelord Ragnaros awaits in the depths of Blackrock Mountain. Home to Tier 1 gear and legendary bindings.",
        bosses = 10,
    },
    {
        name = "Blackwing Lair",
        short = "BWL",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
        info = "Nefarian's stronghold atop Blackrock Mountain. Home to Tier 2 gear and challenging encounters.",
        bosses = 8,
    },
    {
        name = "Temple of Ahn'Qiraj",
        short = "AQ40",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_01",
        info = "The war effort opens the gates. Face the might of C'Thun and the Qiraji empire. Tier 2.5 gear.",
        bosses = 9,
    },
    {
        name = "Naxxramas",
        short = "Naxx",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\INV_Trinket_Naxxramas06",
        info = "The floating necropolis of Kel'Thuzad. Four wings of undead horror. Tier 3 gear awaits the worthy.",
        bosses = 15,
    },
    {
        name = "Emerald Sanctum",
        short = "ES",
        size = 40,
        cycle = CYCLE_7DAY,
        anchor = ANCHOR_RAID40,
        icon = "Interface\\Icons\\INV_Misc_Gem_Emerald_02",
        info = "A Turtle WoW exclusive raid. Venture into the Emerald Dream to face corrupted guardians.",
        bosses = 4,
    },
    {
        name = "Onyxia's Lair",
        short = "Ony",
        size = 40,
        cycle = CYCLE_5DAY,
        anchor = ANCHOR_ONYXIA,
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        info = "The broodmother Onyxia lurks in her lair in Dustwallow Marsh. A classic single-boss encounter. 5-day reset.",
        bosses = 1,
    },
    {
        name = "Karazhan",
        short = "Kara",
        size = 40,
        cycle = CYCLE_5DAY,
        anchor = ANCHOR_KARAZHAN,
        icon = "Interface\\Icons\\INV_Jewelry_Ring_54",
        info = "Medivh's haunted tower in Deadwind Pass. A Turtle WoW adapted raid experience. 5-day reset.",
        bosses = 11,
    },
    {
        name = "Zul'Gurub",
        short = "ZG",
        size = 20,
        cycle = CYCLE_3DAY,
        anchor = ANCHOR_RAID20,
        icon = "Interface\\Icons\\Ability_Creature_Poison_05",
        info = "The troll city in Stranglethorn Vale. Home to Hakkar the Soulflayer. Resets every 3 days.",
        bosses = 10,
    },
    {
        name = "Ruins of Ahn'Qiraj",
        short = "AQ20",
        size = 20,
        cycle = CYCLE_3DAY,
        anchor = ANCHOR_RAID20,
        icon = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_03",
        info = "The outer ruins of Ahn'Qiraj. A 20-player raid with the prophet Ossirian. Resets every 3 days.",
        bosses = 6,
    },
}

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------

local ROW_HEIGHT = 28
local MAX_VISIBLE_ROWS = 10
local selectedRaid = nil
local rowFrames = {}

----------------------------------------------------------------------
-- UTILITY FUNCTIONS
----------------------------------------------------------------------

-- Get current UTC time
local function GetUTCTime()
    return time()
end

-- Calculate seconds until next reset for a given raid
local function GetSecondsUntilReset(raid)
    local now = GetUTCTime()
    local elapsed = now - raid.anchor
    if elapsed < 0 then
        return raid.cycle + elapsed
    end
    local inCycle = math.mod(elapsed, raid.cycle)
    local remaining = raid.cycle - inCycle
    return remaining
end

-- Format seconds into a readable countdown string
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

-- Get a cycle label string
local function GetCycleLabel(cycle)
    if cycle == CYCLE_7DAY then
        return "7-Day"
    elseif cycle == CYCLE_5DAY then
        return "5-Day"
    elseif cycle == CYCLE_3DAY then
        return "3-Day"
    end
    return "Unknown"
end

-- Get status color based on time remaining
local function GetStatusInfo(seconds)
    local total = seconds
    if total < 3600 then
        -- Less than 1 hour - imminent
        return "|cffff3333IMMINENT|r", 1, 0.2, 0.2
    elseif total < 6 * 3600 then
        -- Less than 6 hours
        return "|cffff9933SOON|r", 1, 0.6, 0.2
    elseif total < 24 * 3600 then
        -- Less than 1 day
        return "|cffffff33TODAY|r", 1, 1, 0.2
    else
        return "|cff33ff33LOCKED|r", 0.2, 1, 0.2
    end
end

-- Get the next reset date/time as a formatted string
local function GetResetDateString(seconds)
    local resetTime = GetUTCTime() + seconds
    return date("!%A, %b %d at %I:%M %p", resetTime) .. " (UTC)"
end

----------------------------------------------------------------------
-- ROW CREATION
----------------------------------------------------------------------

local function CreateRow(index)
    local row = CreateFrame("Button", "PhantomLockoutRow"..index, PhantomLockoutFrame)
    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(545)
    row:SetPoint("TOPLEFT", PhantomLockoutFrame, "TOPLEFT", 22, -72 - ((index - 1) * ROW_HEIGHT))

    -- Alternating row background
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    if math.mod(index, 2) == 0 then
        row.bg:SetVertexColor(0.3, 0.25, 0.1, 0.3)
    else
        row.bg:SetVertexColor(0.2, 0.15, 0.05, 0.2)
    end

    -- Highlight on hover
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    row.highlight:SetVertexColor(0.6, 0.5, 0.2, 0.4)

    -- Selected indicator
    row.selected = row:CreateTexture(nil, "ARTWORK")
    row.selected:SetAllPoints()
    row.selected:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    row.selected:SetVertexColor(0.8, 0.6, 0.1, 0.35)
    row.selected:Hide()

    -- Raid icon
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetWidth(22)
    row.icon:SetHeight(22)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

    -- Raid name text
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameText:SetWidth(150)
    row.nameText:SetJustifyH("LEFT")

    -- Size text
    row.sizeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sizeText:SetPoint("LEFT", row, "LEFT", 195, 0)
    row.sizeText:SetWidth(45)
    row.sizeText:SetJustifyH("CENTER")

    -- Cycle text
    row.cycleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.cycleText:SetPoint("LEFT", row, "LEFT", 245, 0)
    row.cycleText:SetWidth(60)
    row.cycleText:SetJustifyH("CENTER")

    -- Status text
    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.statusText:SetPoint("LEFT", row, "LEFT", 310, 0)
    row.statusText:SetWidth(80)
    row.statusText:SetJustifyH("CENTER")

    -- Timer text
    row.timerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.timerText:SetPoint("LEFT", row, "LEFT", 395, 0)
    row.timerText:SetWidth(140)
    row.timerText:SetJustifyH("LEFT")

    -- Click handler
    row:SetScript("OnClick", function()
        selectedRaid = row.raidIndex
        PhantomLockout_UpdateSelection()
        PhantomLockout_UpdateInfoPanel()
    end)

    -- Tooltip
    row:SetScript("OnEnter", function()
        if row.raidIndex then
            local raid = RAIDS[row.raidIndex]
            local remaining = GetSecondsUntilReset(raid)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(raid.name, 1, 0.82, 0)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Players:", raid.size .. "-Man", 0.8, 0.8, 0.6, 1, 1, 1)
            GameTooltip:AddDoubleLine("Bosses:", raid.bosses, 0.8, 0.8, 0.6, 1, 1, 1)
            GameTooltip:AddDoubleLine("Reset Cycle:", GetCycleLabel(raid.cycle), 0.8, 0.8, 0.6, 1, 1, 1)
            GameTooltip:AddDoubleLine("Resets In:", FormatCountdown(remaining), 0.8, 0.8, 0.6, 0.4, 1, 0.4)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Next Reset:", 0.6, 0.6, 0.4)
            GameTooltip:AddLine(GetResetDateString(remaining), 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click for more details.", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:Hide()
    return row
end

----------------------------------------------------------------------
-- UPDATE FUNCTIONS
----------------------------------------------------------------------

function PhantomLockout_UpdateSelection()
    for i = 1, table.getn(rowFrames) do
        if rowFrames[i].raidIndex == selectedRaid then
            rowFrames[i].selected:Show()
        else
            rowFrames[i].selected:Hide()
        end
    end
end

function PhantomLockout_UpdateInfoPanel()
    if not selectedRaid then
        PhantomLockoutInfoText:SetText("Select a raid instance above to view detailed lockout information.")
        return
    end

    local raid = RAIDS[selectedRaid]
    local remaining = GetSecondsUntilReset(raid)
    local status, _, _, _ = GetStatusInfo(remaining)
    local resetDate = GetResetDateString(remaining)

    local info = string.format(
        "|cffffd100%s|r  |cff888888(%s-Man)|r\n" ..
        "Resets in: |cff44ff44%s|r  |cff888888(%s cycle)|r  -  Status: %s  -  Bosses: |cffffffff%d|r\n" ..
        "|cffaaaaaa%s|r",
        raid.name,
        raid.size,
        FormatCountdown(remaining),
        GetCycleLabel(raid.cycle),
        status,
        raid.bosses,
        raid.info
    )
    PhantomLockoutInfoText:SetText(info)
end

function PhantomLockout_UpdateScrollFrame()
    local numRaids = table.getn(RAIDS)
    FauxScrollFrame_Update(PhantomLockoutScrollFrame, numRaids, MAX_VISIBLE_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(PhantomLockoutScrollFrame)

    for i = 1, MAX_VISIBLE_ROWS do
        local row = rowFrames[i]
        if not row then
            row = CreateRow(i)
            rowFrames[i] = row
        end

        local dataIndex = i + offset
        if dataIndex <= numRaids then
            local raid = RAIDS[dataIndex]
            local remaining = GetSecondsUntilReset(raid)
            local status, sr, sg, sb = GetStatusInfo(remaining)

            row.raidIndex = dataIndex
            row.icon:SetTexture(raid.icon)
            row.nameText:SetText(raid.name)

            -- Size with color coding
            if raid.size == 40 then
                row.sizeText:SetText("|cffff8833" .. raid.size .. "-Man|r")
            else
                row.sizeText:SetText("|cff33aaff" .. raid.size .. "-Man|r")
            end

            row.cycleText:SetText(GetCycleLabel(raid.cycle))
            row.statusText:SetText(status)
            row.timerText:SetText("|cffffffff" .. FormatCountdown(remaining) .. "|r")

            -- Update selection visual
            if dataIndex == selectedRaid then
                row.selected:Show()
            else
                row.selected:Hide()
            end

            row:Show()
        else
            row.raidIndex = nil
            row:Hide()
        end
    end
end

-- Refresh all timers (called every second)
local function RefreshTimers()
    if not PhantomLockoutFrame:IsVisible() then return end

    -- Update server time display
    local hours, minutes = GetGameTime()
    PhantomLockoutServerTime:SetText(string.format("Server Time: %02d:%02d", hours, minutes))

    -- Update rows
    PhantomLockout_UpdateScrollFrame()

    -- Update info panel if something is selected
    if selectedRaid then
        PhantomLockout_UpdateInfoPanel()
    end
end

----------------------------------------------------------------------
-- TOGGLE & SLASH COMMANDS
----------------------------------------------------------------------

-- Reset All Instances with confirmation
function PhantomLockout_ResetInstances()
    -- Create a simple confirmation via StaticPopup
    StaticPopupDialogs["PHANTOMLOCKOUT_RESET_CONFIRM"] = {
        text = "Are you sure you want to reset all dungeon instances?\n\n|cffff8833This will NOT affect raid lockouts.|r",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            ResetInstances()
            DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r: All dungeon instances have been reset.")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("PHANTOMLOCKOUT_RESET_CONFIRM")
end

function PhantomLockout_ToggleFrame()
    if PhantomLockoutFrame:IsVisible() then
        PhantomLockoutFrame:Hide()
    else
        PhantomLockoutFrame:Show()
        PhantomLockout_UpdateScrollFrame()
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

local updateElapsed = 0

local function OnUpdate()
    updateElapsed = updateElapsed + arg1
    if updateElapsed >= 1 then
        updateElapsed = 0
        RefreshTimers()
    end
end

local function OnEvent()
    if event == "VARIABLES_LOADED" then
        -- Initialize saved variables
        if not PhantomLockoutDB then
            PhantomLockoutDB = {}
        end

        -- Register slash commands
        SLASH_PHANTOMLOCKOUT1 = "/phantomlockout"
        SLASH_PHANTOMLOCKOUT2 = "/pl"
        SLASH_PHANTOMLOCKOUT3 = "/plock"
        SlashCmdList["PHANTOMLOCKOUT"] = function(msg)
            if msg == "help" then
                DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r Commands:")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/pl|r - Toggle the lockout window")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/pl help|r - Show this help message")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/pl next|r - Show next reset in chat")
                DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/pl reset|r - Reset all dungeon instances")
            elseif msg == "next" then
                DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r - Upcoming Resets:")
                for i = 1, table.getn(RAIDS) do
                    local raid = RAIDS[i]
                    local remaining = GetSecondsUntilReset(raid)
                    local countdown = FormatCountdown(remaining)
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffffd100%s|r (%s-Man): %s", raid.name, raid.size, countdown))
                end
            elseif msg == "reset" then
                PhantomLockout_ResetInstances()
            else
                PhantomLockout_ToggleFrame()
            end
        end

        -- Set up the update ticker on the main frame
        PhantomLockoutFrame:SetScript("OnUpdate", OnUpdate)

        DEFAULT_CHAT_FRAME:AddMessage("|cff8800ffPhantom|r|cffcc44ffLockout|r v1.0 loaded. Type |cffffd100/pl|r to toggle. |cffffd100/pl help|r for commands.")
    end
end

-- Register events
PhantomLockoutFrame:RegisterEvent("VARIABLES_LOADED")
PhantomLockoutFrame:SetScript("OnEvent", OnEvent)
