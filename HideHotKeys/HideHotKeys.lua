--[[----------------------------------------------------------------------------
    HideHotKeys (2.5.3)

    Hides the keybind text on all action buttons, and optionally the macro name.
    It keeps a range cue: when an action is out of range, the game's own range
    indicator ("●") is shown in red (this is the same marker Blizzard uses for
    unbound buttons), instead of the red-tinted keybind it would normally show.

    Slash commands
        /hhk          help + current state
        /hotkeyhide   toggle keybind text
        /macrohide    toggle macro name text

    Settings are saved per character via HideHotKeysDB
    (declared in the .toc as ## SavedVariablesPerCharacter).
------------------------------------------------------------------------------]]

local ADDON_TAG = "|cff33ff99HideHotKeys|r"

-- FrameXML constants (captured once). RANGE_INDICATOR is "●" in this client.
local RANGE_MARK = RANGE_INDICATOR or "*"
local RED_R, RED_G, RED_B = 1.0, 0.1, 0.1
if RED_FONT_COLOR then
    RED_R, RED_G, RED_B = RED_FONT_COLOR:GetRGB()
end

local defaults = {
    hideHotkeys    = true,
    hideMacroNames = true,
}

-- Base names of the Blizzard action bars, numbered 1..12 (missing ones skipped).
local BAR_BASES = {
    "Action",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "BonusAction",
    "PetAction",
}

local db

local function EnsureDB()
    if type(HideHotKeysDB) ~= "table" then
        HideHotKeysDB = {}
    end
    for key, value in pairs(defaults) do
        if HideHotKeysDB[key] == nil then
            HideHotKeysDB[key] = value
        end
    end
    db = HideHotKeysDB
end

------------------------------------------------------------------------------
-- Hotkeys
------------------------------------------------------------------------------

-- Does this action report a range and is it currently out of range?
-- IsActionInRange returns true / false / nil (nil = the action does not check).
local function IsOutOfRange(button)
    local action = button.action
    if not action then return false end
    local range = IsActionInRange(action)
    return range == false or range == 0
end

-- Hide the keybind, but keep the range cue when out of range.
local function ApplyHotkey(button)
    local hotkey = button and button.HotKey
    if not hotkey then return end
    if not db.hideHotkeys then return end  -- leave Blizzard's own state alone

    -- Remember the real keybind so we can put it back if the toggle is turned off.
    local text = hotkey:GetText()
    if text and text ~= RANGE_MARK then
        button.__hhkKeybind = text
    end

    if IsOutOfRange(button) then
        hotkey:SetText(RANGE_MARK)
        hotkey:SetVertexColor(RED_R, RED_G, RED_B)
        hotkey:Show()
    else
        hotkey:Hide()
    end
end

-- Put a button back to the game's own keybind display (used when hiding is off).
local function RestoreHotkey(button)
    local hotkey = button and button.HotKey
    if not hotkey then return end

    -- Blizzard always calls UpdateHotkeys(self, self.buttonType); do the same so
    -- it works out the right binding and visibility itself.
    if button.buttonType and type(ActionButton_UpdateHotkeys) == "function" then
        pcall(ActionButton_UpdateHotkeys, button, button.buttonType)
    else
        if button.__hhkKeybind then
            hotkey:SetText(button.__hhkKeybind)
        end
        hotkey:Show()
    end
end

------------------------------------------------------------------------------
-- Macro names
------------------------------------------------------------------------------

-- We only change visibility; the game keeps the label text up to date on its
-- own, so an empty-but-shown label is invisible.
local function ApplyName(button)
    local name = button and button.Name
    if not name then return end
    if db.hideMacroNames then name:Hide() else name:Show() end
end

------------------------------------------------------------------------------
-- Applying to every button
------------------------------------------------------------------------------

local function ApplyToButton(button)
    if not button then return end
    if db.hideHotkeys then
        ApplyHotkey(button)
    else
        RestoreHotkey(button)
    end
    ApplyName(button)
end

local function ApplyToAll()
    for _, base in ipairs(BAR_BASES) do
        for i = 1, 12 do
            ApplyToButton(_G[base .. "Button" .. i])
        end
    end
end

------------------------------------------------------------------------------
-- Hooks - run after the game's own updaters so our state always wins
------------------------------------------------------------------------------

local function InstallHooks()
    if type(ActionButton_UpdateHotkeys) == "function" then
        hooksecurefunc("ActionButton_UpdateHotkeys", function(self)
            if self then ApplyHotkey(self) end
        end)
    end

    -- Runs every ~0.2s for actions that check range; it hands us the result,
    -- so we do not need to call IsActionInRange ourselves here.
    if type(ActionButton_UpdateRangeIndicator) == "function" then
        hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
            if not db.hideHotkeys then return end
            local hotkey = self and self.HotKey
            if not hotkey then return end
            if checksRange and not inRange then
                hotkey:SetText(RANGE_MARK)
                hotkey:SetVertexColor(RED_R, RED_G, RED_B)
                hotkey:Show()
            else
                hotkey:Hide()
            end
        end)
    end

    if type(ActionButton_Update) == "function" then
        hooksecurefunc("ActionButton_Update", function(self)
            if not self then return end
            ApplyHotkey(self)
            if db.hideMacroNames and self.Name then
                self.Name:Hide()
            end
        end)
    end
end

------------------------------------------------------------------------------
-- Safety net - re-apply whenever the bars get rebuilt
------------------------------------------------------------------------------

local events = {
    "PLAYER_ENTERING_WORLD",
    "UPDATE_BINDINGS",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM",
    "PET_BAR_UPDATE",
}

local frame = CreateFrame("Frame")
for _, event in ipairs(events) do
    -- pcall: registering an unknown event name throws, and an uncaught error
    -- here would abort the rest of the file. Never let that take the addon down.
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", ApplyToAll)

------------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------------

local function Describe(value)
    return value and "|cff00ff00hidden|r" or "|cffff5555shown|r"
end

local function PrintState()
    print(string.format("%s  keybinds: %s   macro names: %s",
        ADDON_TAG, Describe(db.hideHotkeys), Describe(db.hideMacroNames)))
end

SLASH_HIDEHOTKEYS_HELP1 = "/hhk"
SlashCmdList["HIDEHOTKEYS_HELP"] = function()
    print(ADDON_TAG .. " commands:")
    print("  |cffffd100/hotkeyhide|r  toggle keybind text (a red \"●\" still shows out of range)")
    print("  |cffffd100/macrohide|r   toggle macro names on the action bars")
    print("  |cffffd100/hhk|r         show this help and the current state")
    PrintState()
end

SLASH_HIDEHOTKEYS_HK1 = "/hotkeyhide"
SlashCmdList["HIDEHOTKEYS_HK"] = function()
    db.hideHotkeys = not db.hideHotkeys
    ApplyToAll()
    print(ADDON_TAG .. " keybind text " .. (db.hideHotkeys and "hidden." or "shown."))
    PrintState()
end

SLASH_HIDEHOTKEYS_MN1 = "/macrohide"
SlashCmdList["HIDEHOTKEYS_MN"] = function()
    db.hideMacroNames = not db.hideMacroNames
    ApplyToAll()
    print(ADDON_TAG .. " macro names " .. (db.hideMacroNames and "hidden." or "shown."))
    PrintState()
end

------------------------------------------------------------------------------
-- Load
------------------------------------------------------------------------------

EnsureDB()
InstallHooks()
ApplyToAll()
