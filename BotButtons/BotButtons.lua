--[[============================================================================
  BotButtons - draggable, keybindable quick-command buttons for cmangos/playerbots
  Clients: Classic Era 1.14.x, TBC 2.5.x, WotLK 3.4.3

  A movable row of buttons. Left-click sends a bot command; some buttons also
  have a right-click action. Every button can be key-bound in this addon's
  settings window (/bb) or in the standard Key Bindings screen (BotButtons).

  Commands are sent like the Mangosbot addon sends them: as hidden "BOT" addon
  messages on party/raid/whisper (so they do not spam chat), falling back to
  ordinary chat if that path fails or "Visible chat" is enabled.
============================================================================]]

local ADDON_NAME = "BotButtons"

-- friendly name for the standard Key Bindings UI header
BINDING_HEADER_BOTBUTTONS = "BotButtons"

-- defaults -------------------------------------------------------------------
local DEFAULTS = {
    show        = true,
    locked      = false,
    vertical    = false,
    size        = 30,
    spacing     = 3,
    scale       = 1.0,
    visibleChat = false,
    healerName  = "Healer",
    tankName    = "Tank",
    announce    = true,
    waitTime    = 5,
    -- addon-side toggle state (the client cannot read the bots' real strategies)
    toggles     = { passive = false, meleehold = false, wait = false },
    point       = { "BOTTOM", "BOTTOM", 0, 160 },
}

-- class-based (spec is not exposed to addons); used by "Melee Hold"
local MELEE_CLASSES = { WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true, DRUID = true, DEATHKNIGHT = true }

-- button look
local BORDER_ALPHA = 0.28                       -- normal border opacity (subtle)
local BORDER_ACTIVE = { 0.25, 0.95, 0.4, 0.9 }  -- toggle-ON / command-sent highlight
local FLASH_TIME = 0.6                          -- seconds a one-shot command stays lit

-- forward-declared locals (assigned later) -----------------------------------
local BB_sendGroup, BB_setMeleePassive, BB_whisperHealer, BB_whisperTank, BB_pull, BB_tankAttack
local BB_buildBar, BB_layoutBar, BB_updateBarVisibility, BB_refreshKeybinds
local BB_openSettings, BB_toggleSettings, BB_startCapture

-- module state ---------------------------------------------------------------
local O                     -- options (saved variable table)
local bar                   -- the bar frame
local grip                  -- drag grip
local buttonByKey = {}      -- action key -> button
local settings, capture     -- windows
local prefixRegistered = false

--============================================================================
-- small helpers
--============================================================================
local function ensurePrefix()
    if prefixRegistered then return end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix("BOT")
    end
    prefixRegistered = true
end

local function colorTexture(tex, r, g, b, a)
    if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(r, g, b, a) end
end

local function setBackdrop(frame, alpha)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, alpha or 0.85)
    frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
end

local function show(frame, visible)
    if visible then frame:Show() else frame:Hide() end
end

-- deep-ish copy so DEFAULTS tables (arrays like `point`, maps like `toggles`)
-- can be restored without sharing references.
local function copyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = (type(v) == "table") and copyTable(v) or v end
    return out
end

local function applyAnchor()
    if not bar then return end
    local p = O.point or DEFAULTS.point
    bar:ClearAllPoints()
    bar:SetPoint(p[1] or "BOTTOM", UIParent, p[2] or "BOTTOM", p[3] or 0, p[4] or 160)
end

local function saveAnchor(frame)
    local from, _, to, x, y = frame:GetPoint()
    if from then O.point = { from, to, x, y } end
end

--============================================================================
-- transport
--============================================================================
local function groupChat()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Send one command to one target (target nil = whole group).
local function transport(cmd, chat, target)
    if not cmd or cmd == "" then return end
    if O.visibleChat or chat == "SAY" then
        SendChatMessage(cmd, chat, nil, target)
        return
    end
    local ok = pcall(function()
        ensurePrefix()
        C_ChatInfo.SendAddonMessage("BOT", cmd, chat, target)
    end)
    if not ok then SendChatMessage(cmd, chat, nil, target) end
end

BB_sendGroup = function(cmd)
    local chat = groupChat()
    if chat then transport(cmd, chat) else transport(cmd, "SAY") end
end

-- Melee DPS hold: whisper an ABSOLUTE passive command to melee classes only
-- (so ranged keep firing). `on` = hold, `off` = release.
BB_setMeleePassive = function(on)
    local cmd = on and "co +passive" or "co -passive"
    local prefix = UnitInRaid("player") and "raid" or "party"
    local n = GetNumGroupMembers()
    for i = 1, n do
        local unit = prefix .. i
        local name = UnitName(unit)
        if name then
            local _, class = UnitClass(unit)
            if class and MELEE_CLASSES[class] then
                transport(cmd, "WHISPER", name)
            end
        end
    end
end

-- Names of the group (lower-cased) so a stale tank/healer name can be caught
-- before whispering somebody who is not there. The client answers that with
-- "player X is not found", which is puzzling when the rest of the command - the
-- group-wide pull - still works.
local function groupNames()
    local set = {}
    local prefix = UnitInRaid("player") and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local name = UnitName(prefix .. i)
        if name then set[string.lower(name)] = true end
    end
    return set
end

local warnedAt = 0
local function inGroupOrWarn(label, name)
    if groupNames()[string.lower(name)] then return true end
    local now = GetTime and GetTime() or 0
    if now - warnedAt > 60 then
        warnedAt = now
        print("|cff33ff99BotButtons|r: " .. label .. " '" .. name ..
              "' is not in your group - change it in /bb")
    end
    return false
end

BB_whisperHealer = function()
    local name = O.healerName
    if name and name ~= "" and inGroupOrWarn("healer name", name) then
        transport("stay", "WHISPER", name)
    end
end

-- Whisper a single command to the tank only. Pull uses this to take the tank
-- out of "stay" before pulling, otherwise it cannot move to reach the target.
BB_whisperTank = function(cmd)
    local name = O.tankName
    if name and name ~= "" and inGroupOrWarn("tank name", name) then
        transport(cmd, "WHISPER", name)
    end
end

-- Ordered command pairs for the tank.
--
-- Pull and Tank Attack both need two commands where the first must land before
-- the second. A bot only runs the chat commands it has queued on its own AI
-- tick, and it does not even look at the queue while it is busy finishing
-- another action, so two commands sent close together can end up being handled
-- on the same tick with no ordering guarantee: the tank would pull before its
-- "stay" is cleared, or attack while still "passive" (which suppresses the
-- attack), and the button silently does nothing. That is why a fixed "send X,
-- wait a little, send Y" delay only mostly works - the delay cannot know when
-- the tank actually processed X.
--
-- Instead we wait for the tank to answer. The tank shortcuts whisper back to
-- the requester, and they do so after they have applied the change, so the
-- reply is a real "ready" signal. A timeout covers a silent tank (wrong name,
-- another player's bot, "silent" bots, or a reply the server rate-limits): the
-- change still happens, we just did not hear about it.
local TANK_ACK_TIMEOUT = 1.5                    -- seconds to wait for the tank

local tankWaitName                              -- tank we are waiting on, or nil
local tankWaitSeq = 0                           -- invalidates stale replies/timeouts
local tankWaitThen                              -- runs once the tank has answered

local function tankAnswer(seq)
    if seq ~= tankWaitSeq or tankWaitName == nil then return end
    local thenDo = tankWaitThen
    tankWaitName, tankWaitThen = nil, nil
    if thenDo then thenDo() end
end

-- Whisper `first` to the tank and run `thenDo` once it answers. Returns false
-- (and sends nothing) when there is no usable tank name, so the caller can
-- fall back to a plain group command.
local function tankThen(first, thenDo)
    local name = O.tankName
    if not name or name == "" or not inGroupOrWarn("tank name", name) then
        return false
    end

    tankWaitSeq = tankWaitSeq + 1
    local seq = tankWaitSeq
    tankWaitName = string.lower(name)
    tankWaitThen = thenDo

    BB_whisperTank(first)

    if C_Timer and C_Timer.After then
        C_Timer.After(TANK_ACK_TIMEOUT, function() tankAnswer(seq) end)
    else
        tankAnswer(seq)
    end
    return true
end

-- Any whisper from the tank means the command has been handled, so the follow-up
-- can go out at once.
local function tankAck(sender)
    if tankWaitName and sender and string.lower(sender) == tankWaitName then
        tankAnswer(tankWaitSeq)
    end
end

-- Pull: take the tank out of "stay" (it will not walk to its pull target while
-- holding position), then have the whole group pull. Without a tank to prepare,
-- the group pull still goes out on its own.
BB_pull = function()
    if not tankThen("follow", function() BB_sendGroup("pull") end) then
        BB_sendGroup("pull")
    end
end

-- Tank Attack: the tank drops "passive" and then attacks your current target,
-- which walks it into range when the fight has not started yet. "attack" alone
-- is suppressed while passive, hence the two steps; only the tank is addressed.
BB_tankAttack = function()
    if not tankThen("tank attack", function() BB_whisperTank("attack") end) then
        BB_sendGroup("tank attack")
    end
end

--============================================================================
-- actions (order = order on the bar)
--============================================================================
local ACTIONS = {
    { key = "follow", label = "Follow", icon = "Ability_Rogue_Sprint",
      binding = "BOTBUTTONS_FOLLOW",
      desc = "Follow the group leader (out of combat).",
      rightDesc = "Regroup: stop attacking and follow (flee).",
      onLeft  = function() BB_sendGroup("follow") end,
      onRight = function() BB_sendGroup("flee") end },

    { key = "stay", label = "Stay", icon = "Ability_Warrior_DefensiveStance",
      binding = "BOTBUTTONS_STAY",
      desc = "Hold position and keep fighting (clears follow/wander/passive).",
      onLeft  = function() BB_sendGroup("stay") end },

    { key = "regroup", label = "Regroup", icon = "Spell_Frost_Stun",
      binding = "BOTBUTTONS_REGROUP",
      desc = "Stop attacking and regroup on you (passive + follow).",
      onLeft  = function() BB_sendGroup("flee") end },

    { key = "summon", label = "Summon", icon = "Spell_Arcane_PortalIronForge",
      binding = "BOTBUTTONS_SUMMON",
      desc = "Teleport every bot in your group to you.",
      onLeft  = function() BB_sendGroup("summon") end },

    { key = "attack", label = "Attack", icon = "Ability_Warrior_Charge",
      binding = "BOTBUTTONS_ATTACK",
      desc = "Attack your current target.",
      onLeft  = function() BB_sendGroup("attack") end },

    { key = "pull", label = "Pull", icon = "Ability_Hunter_AimedShot",
      binding = "BOTBUTTONS_PULL",
      desc = "Pull your current target (tank). Asks the tank to follow first (so it can move if it was holding position), waits for it to reply, then pulls.",
      onLeft  = function() BB_pull() end },

    { key = "passive", label = "Stop / Go", icon = "Spell_Frost_FrostNova",
      binding = "BOTBUTTONS_PASSIVE", isToggle = true,
      desc = "Toggle |cffff8080stop attacking|r on all bots (both states).",
      rightDesc = "Force attack (clear passive).",
      onOn  = function() BB_sendGroup("all +passive") end,
      onOff = function() BB_sendGroup("all -passive") end },

    { key = "meleehold", label = "Melee Hold", icon = "Ability_Warrior_ShieldWall",
      binding = "BOTBUTTONS_MELEEHOLD", isToggle = true,
      desc = "Toggle: melee DPS hold (keep following, stop attacking) while ranged keep firing.",
      rightDesc = "Release melee (clear passive).",
      onOn  = function() BB_setMeleePassive(true) end,
      onOff = function() BB_setMeleePassive(false) end },

    { key = "wait", label = "Wait at Pull", icon = "Spell_Nature_TimeStop",
      binding = "BOTBUTTONS_WAIT", isToggle = true,
      desc = "Toggle: bots hold for a few seconds after a pull starts (set the time in settings).",
      rightDesc = "Force wait at pull off.",
      onOn  = function() BB_sendGroup("co +wait for attack") end,
      onOff = function() BB_sendGroup("co -wait for attack") end },

    { key = "tankattack", label = "Tank Attack", icon = "Ability_Warrior_ShieldBash",
      binding = "BOTBUTTONS_TANKATTACK",
      desc = "Whisper your tank: drop passive and attack your target (runs into range when the fight has not started).",
      onLeft  = function() BB_tankAttack() end },

    { key = "maxdps", label = "Max DPS", icon = "Spell_Fire_Fireball02",
      binding = "BOTBUTTONS_MAXDPS",
      desc = "DPS: drop threat / conserve mana / cast-time limits.",
      onLeft  = function() BB_sendGroup("max dps") end },

    { key = "healerstay", label = "Healer Stay", icon = "Spell_Holy_FlashHeal",
      binding = "BOTBUTTONS_HEALERSTAY",
      desc = "Whisper 'stay' to your healer (hold position, keep healing).",
      onLeft  = function() BB_whisperHealer() end },
}

local actionByKey = {}
for _, a in ipairs(ACTIONS) do actionByKey[a.key] = a end

-- indicators -----------------------------------------------------------------
-- The green border means "this toggle is ON as far as the addon knows". It is
-- NOT read from the server: the client cannot query a bot's strategies, so a
-- bot changed elsewhere (another addon, the console, apply_bots.py, a relog
-- onto a recreated bot) can be out of step until the button is pressed again.
-- One-shot buttons only flash the border briefly as "command sent" feedback.
local function buttonBorder(b, active)
    if not b or not b.SetBackdropBorderColor then return end
    if active then
        b:SetBackdropBorderColor(BORDER_ACTIVE[1], BORDER_ACTIVE[2], BORDER_ACTIVE[3], BORDER_ACTIVE[4])
    else
        b:SetBackdropBorderColor(0, 0, 0, BORDER_ALPHA)
    end
end

local function toggleState(a)
    return (O.toggles and O.toggles[a.key]) and true or false
end

local function refreshToggle(a)
    buttonBorder(a.button, toggleState(a))
end

-- Flip a toggle, send the matching ABSOLUTE command (never "~"), and light it.
-- Absolute commands mean a lost sync self-corrects on the next press instead of
-- compounding the way a "~" toggle does.
local function setToggle(a, on, send)
    O.toggles[a.key] = on and true or false
    if send then
        local fn = on and a.onOn or a.onOff
        if fn then fn() end
    end
    refreshToggle(a)
end

-- Transient cue for one-shot buttons.
local function flash(a)
    local b = a.button
    if not b then return end
    buttonBorder(b, true)
    local function restore()
        if a.isToggle then refreshToggle(a) else buttonBorder(b, false) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(FLASH_TIME, restore) else restore() end
end

-- Chat-frame record of what was pressed (private: nothing goes to a channel).
local function announce(a, rightClick, state)
    if O.announce == false then return end
    local text = a.label
    if rightClick then text = text .. " (right-click)" end
    if state then text = text .. " -> " .. state end
    print("|cff33ff99BotButtons|r: " .. text)
end

-- Called from Bindings.xml and from button clicks.
function BotButtons_Fire(key, rightClick)
    local a = actionByKey[key]
    if not a then return end

    if a.isToggle then
        -- Left-click flips the addon state; right-click forces it off.
        if rightClick then
            setToggle(a, false, true)
        else
            setToggle(a, not toggleState(a), true)
        end
        announce(a, rightClick, toggleState(a) and "ON" or "off")
        return
    end

    local fn = rightClick and a.onRight or a.onLeft
    if fn then fn() end
    if fn and not a.noMark then flash(a) end
    if fn then announce(a, rightClick) end
end

--============================================================================
-- the bar
--============================================================================
BB_buildBar = function()
    if bar then return end

    bar = CreateFrame("Frame", "BotButtonsBar", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    setBackdrop(bar, 0.5)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not O.locked then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); saveAnchor(self) end)

    grip = CreateFrame("Frame", nil, bar)
    grip:SetSize(12, 12)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() if not O.locked then bar:StartMoving() end end)
    grip:SetScript("OnDragStop", function() bar:StopMovingOrSizing(); saveAnchor(bar) end)
    local gtex = grip:CreateTexture(nil, "ARTWORK")
    gtex:SetAllPoints()
    gtex:SetTexture("Interface\\Buttons\\UI-Panel-ResizeButton")

    for _, a in ipairs(ACTIONS) do
        local b = CreateFrame("Button", "BotButtonsButton" .. a.key, bar,
                              BackdropTemplateMixin and "BackdropTemplate")
        if b.SetBackdrop then
            b:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            b:SetBackdropBorderColor(0, 0, 0, BORDER_ALPHA)
        end
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
        b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
        b.icon:SetTexture("Interface\\Icons\\" .. a.icon)

        b:SetScript("OnClick", function(_, mouseButton)
            BotButtons_Fire(a.key, mouseButton == "RightButton")
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(a.label, 1, 1, 1)
            GameTooltip:AddLine(a.desc, 0.9, 0.9, 0.9, true)
            if a.rightDesc then
                GameTooltip:AddLine("|cffa0a0a0Right-click:|r " .. a.rightDesc, 0.8, 0.8, 0.8, true)
            end
            if a.isToggle then
                local state = toggleState(a) and "|cff40ff66ON|r" or "|cffff8080off|r"
                GameTooltip:AddLine("Addon toggle: " .. state .. "  |cffa0a0a0(this addon's view, not read from the server)|r",
                                    0.8, 0.8, 0.8, true)
            end
            local key = GetBindingKey and GetBindingKey(a.binding)
            if key then GameTooltip:AddLine("|cffffd100Bound to " .. key .. "|r") end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        buttonByKey[a.key] = b
        a.button = b
    end

    BB_layoutBar()
    BB_updateBarVisibility()
end

BB_layoutBar = function()
    if not bar then return end
    local n = #ACTIONS
    local size, gap = O.size, O.spacing
    local gripW = O.locked and 0 or 14
    local pad = 4

    for i, a in ipairs(ACTIONS) do
        local b = buttonByKey[a.key]
        b:SetSize(size, size)
        if O.vertical then
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + gripW, -(pad + (i - 1) * (size + gap)))
        else
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + gripW + (i - 1) * (size + gap), -pad)
        end
    end

    local used = n * size + (n - 1) * gap
    if O.vertical then
        bar:SetSize(pad * 2 + gripW + size, pad * 2 + used)
    else
        bar:SetSize(pad * 2 + gripW + used, pad * 2 + size)
    end

    grip:ClearAllPoints()
    grip:SetPoint("TOPLEFT", bar, "TOPLEFT", pad, -pad)
    show(grip, not O.locked)

    bar:SetScale(O.scale)
    bar:SetMovable(not O.locked)
end

BB_updateBarVisibility = function()
    if bar then show(bar, O.show) end
end

--============================================================================
-- keybinding
--============================================================================
local function bind(binding, key)
    local existing = { GetBindingKey(binding) }
    for i = 1, #existing do
        if existing[i] then SetBinding(existing[i]) end
    end
    if key then SetBinding(key, binding) end
    if SaveBindings then
        pcall(SaveBindings, GetCurrentBindingSet and GetCurrentBindingSet() or 2)
    end
end

BB_refreshKeybinds = function()
    for _, a in ipairs(ACTIONS) do
        if a.keyLabel then
            local key = GetBindingKey and GetBindingKey(a.binding)
            a.keyLabel:SetText(key or "|cff808080Not bound|r")
        end
    end
end

--============================================================================
-- settings window
--============================================================================
local function buildCapture()
    capture = CreateFrame("Frame", "BotButtonsCapture", UIParent)
    capture:SetAllPoints(UIParent)
    capture:SetFrameStrata("FULLSCREEN_DIALOG")
    capture:EnableMouse(true)
    capture:EnableKeyboard(true)
    capture:Hide()

    local bg = capture:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    colorTexture(bg, 0, 0, 0, 0.6)

    local box = CreateFrame("Frame", nil, capture, BackdropTemplateMixin and "BackdropTemplate")
    setBackdrop(box, 0.95)
    box:SetSize(340, 130)
    box:SetPoint("CENTER")

    capture.text = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    capture.text:SetPoint("CENTER", box, "CENTER", 0, 0)
    capture.text:SetJustifyH("CENTER")

    local function finish(key)
        if capture.target and key then bind(capture.target.binding, key) end
        capture.target = nil
        capture:Hide()
        if capture.SetPropagateKeyboardInput then capture:SetPropagateKeyboardInput(true) end
        BB_refreshKeybinds()
    end

    capture:SetScript("OnKeyDown", function(self, key)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        if key == "ESCAPE" then finish(nil) return end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
           or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
            return
        end
        local mods = ""
        if IsShiftKeyDown() then mods = "SHIFT-" end
        if IsControlKeyDown() then mods = mods .. "CTRL-" end
        if IsAltKeyDown() then mods = mods .. "ALT-" end
        finish(mods .. key)
    end)
    capture:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then
            finish(nil)
        elseif button == "MiddleButton" or button == "Button4" or button == "Button5" then
            finish(button)
        end
    end)
end

BB_startCapture = function(a)
    if not capture then buildCapture() end
    capture.target = a
    capture.text:SetText("Press a key to bind to\n|cffffd100" .. a.label .. "|r\n\n|cffa0a0a0ESC to cancel|r")
    capture:Show()
    if capture.SetPropagateKeyboardInput then capture:SetPropagateKeyboardInput(false) end
end

local function buildSettings()
    settings = CreateFrame("Frame", "BotButtonsSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    if settings.SetBackdrop then
        settings:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    settings:SetSize(580, 500)
    settings:SetPoint("CENTER")
    settings:SetFrameStrata("DIALOG")
    settings:SetClampedToScreen(true)
    settings:SetMovable(true)
    settings:EnableMouse(true)
    settings:RegisterForDrag("LeftButton")
    settings:SetScript("OnDragStart", settings.StartMoving)
    settings:SetScript("OnDragStop", settings.StopMovingOrSizing)
    settings:Hide()

    -- classic dialog header
    local header = settings:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(300, 64)
    header:SetPoint("TOP", settings, "TOP", 0, 12)
    local title = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("BotButtons")

    local close = CreateFrame("Button", "BotButtonsCloseButton", settings, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", settings, "TOPRIGHT", -6, -6)

    -- Left content margin. The key-bind column on the right ends 38px short of
    -- the frame edge, so match that here (16 sat too close to the dialog border).
    local PAD = 38

    local checks = {}
    local sliders = {}

    local function makeCheck(name, label, getter, setter, y)
        local cb = CreateFrame("CheckButton", name, settings, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", settings, "TOPLEFT", PAD, y)
        cb.Text:SetText(label)
        cb:SetChecked(getter())
        cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
        checks[name] = { frame = cb, getter = getter }
        return cb
    end

    local function fmtVal(v)
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return (string.format("%.2f", v):gsub("0$", ""))
    end

    local function makeSlider(name, label, minv, maxv, step, ticks, getter, setter, y)
        -- Match the buttons below (160 wide) so the whole left column lines up.
        local WIDTH = 160
        local s = CreateFrame("Slider", name, settings, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", settings, "TOPLEFT", PAD, y)
        s:SetWidth(WIDTH)
        s:SetHeight(16)
        s:SetMinMaxValues(minv, maxv)
        s:SetValueStep(step)
        if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

        -- The stock template centres the title and anchors LOW/HIGH 4px *outside*
        -- the frame, which overhangs the column and crowds the dialog edge.
        -- Re-anchor them so the widget is flush with the checkboxes above and
        -- the buttons below.
        local text = s.Text or _G[name .. "Text"]
        if text then
            text:ClearAllPoints()
            text:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
            text:SetJustifyH("LEFT")
        end
        local low  = s.Low  or _G[name .. "Low"]
        local high = s.High or _G[name .. "High"]
        if low then
            low:ClearAllPoints()
            low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
        end
        if high then
            high:ClearAllPoints()
            high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
        end

        local function showValue(v)
            if text then text:SetText(label .. ": |cffffd100" .. fmtVal(v) .. "|r") end
        end

        -- ruler ticks across the track
        if ticks and ticks > 0 then
            local inset, travel = 8, math.max(1, WIDTH - 16)
            for i = 0, ticks do
                local t = s:CreateTexture(nil, "BACKGROUND")
                if t.SetColorTexture then t:SetColorTexture(1, 1, 1, 0.35) else t:SetTexture(1, 1, 1, 0.35) end
                t:SetSize(1, 7)
                t:SetPoint("CENTER", s, "TOPLEFT", inset + travel * (i / ticks), -8)
            end
        end

        if low then low:SetText(tostring(minv)) end
        if high then high:SetText(tostring(maxv)) end
        s:SetValue(getter())
        s:SetScript("OnValueChanged", function(_, value)
            local v = math.floor(value / step + 0.5) * step
            setter(v)
            showValue(v)
        end)
        showValue(getter())
        sliders[name] = { frame = s, getter = getter }
        return s
    end

    local optHeader = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    optHeader:SetPoint("TOPLEFT", settings, "TOPLEFT", PAD, -54)
    optHeader:SetText("Options")

    local y = -78
    makeCheck("BBSettingsShow", "Show the button bar",
        function() return O.show end,
        function(v) O.show = v; BB_updateBarVisibility() end, y)

    y = y - 24
    makeCheck("BBSettingsLock", "Lock the bar (stop dragging)",
        function() return O.locked end,
        function(v) O.locked = v; BB_layoutBar() end, y)

    y = y - 24
    makeCheck("BBSettingsVertical", "Vertical (column instead of row)",
        function() return O.vertical end,
        function(v) O.vertical = v; BB_layoutBar() end, y)

    y = y - 24
    makeCheck("BBSettingsVisibleChat", "Send as visible chat (debug)",
        function() return O.visibleChat end,
        function(v) O.visibleChat = v end, y)

    y = y - 24
    makeCheck("BBSettingsAnnounce", "Announce presses in chat",
        function() return O.announce end,
        function(v) O.announce = v end, y)

    y = y - 48
    makeSlider("BBSettingsScale", "Bar scale", 0.6, 1.6, 0.05, 5,
        function() return O.scale end,
        function(v) O.scale = v; BB_layoutBar() end, y)

    y = y - 58
    makeSlider("BBSettingsSize", "Button size", 20, 44, 1, 6,
        function() return O.size end,
        function(v) O.size = v; BB_layoutBar() end, y)

    y = y - 58
    makeSlider("BBSettingsWait", "Wait at pull (seconds)", 0, 20, 1, 4,
        function() return O.waitTime end,
        function(v) O.waitTime = v end, y)

    y = y - 30
    local sendWait = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    sendWait:SetSize(160, 22)
    sendWait:SetPoint("TOPLEFT", settings, "TOPLEFT", PAD, y)
    sendWait:SetText("Send wait time to bots")
    sendWait:SetScript("OnClick", function()
        local n = math.floor(O.waitTime)
        BB_sendGroup("wait for attack time " .. n)
        print("|cff33ff99BotButtons|r: sent wait time " .. n .. "s")
    end)

    y = y - 28
    local resync = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    resync:SetSize(160, 22)
    resync:SetPoint("TOPLEFT", settings, "TOPLEFT", PAD, y)
    resync:SetText("Force toggles off (resync)")
    resync:SetScript("OnClick", function()
        for _, a in ipairs(ACTIONS) do
            if a.isToggle then setToggle(a, false, true) end
        end
        print("|cff33ff99BotButtons|r: toggles forced off")
    end)
    resync:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Force toggles off")
        GameTooltip:AddLine("Clears this addon's toggle state and sends the matching " ..
                            "|cffff8080off|r commands, so the bots and the buttons agree again.",
                            0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    resync:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Name boxes save as you type (and when the focus leaves), not only on
    -- Enter: typing a new name and clicking away used to leave the old value
    -- stored, so the whisper went to the previous bot while the panel showed the
    -- new name. Escape restores the stored name instead of saving the edit.
    local function bindNameEdit(edit, key)
        local function commit(self)
            local text = self:GetText() or ""
            if strtrim then text = strtrim(text) end
            if text ~= "" then O[key] = text end
        end
        edit:SetScript("OnTextChanged", function(self) commit(self) end)
        edit:SetScript("OnEditFocusLost", function(self) commit(self) end)
        edit:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
        edit:SetScript("OnEscapePressed", function(self)
            self:SetText(O[key] or "")
            self:ClearFocus()
        end)
    end

    y = y - 32
    local healerLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healerLabel:SetPoint("TOPLEFT", settings, "TOPLEFT", PAD, y)
    healerLabel:SetText("Healer bot name:")
    local healerEdit = CreateFrame("EditBox", "BBHealerNameEdit", settings, "InputBoxTemplate")
    healerEdit:SetSize(150, 20)
    healerEdit:SetPoint("LEFT", healerLabel, "RIGHT", 8, 0)
    healerEdit:SetAutoFocus(false)
    healerEdit:SetText(O.healerName or "")
    bindNameEdit(healerEdit, "healerName")

    y = y - 24
    local tankLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tankLabel:SetPoint("TOPLEFT", settings, "TOPLEFT", PAD, y)
    tankLabel:SetText("Tank bot name:")
    local tankEdit = CreateFrame("EditBox", "BBTankNameEdit", settings, "InputBoxTemplate")
    tankEdit:SetSize(150, 20)
    tankEdit:SetPoint("LEFT", tankLabel, "RIGHT", 8, 0)
    tankEdit:SetAutoFocus(false)
    tankEdit:SetText(O.tankName or "")
    bindNameEdit(tankEdit, "tankName")

    -- keybindings ---------------------------------------------------------
    local kbHeader = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kbHeader:SetPoint("TOPLEFT", settings, "TOPLEFT", 300, -54)
    kbHeader:SetText("Key bindings")

    local rowY = -76
    for _, a in ipairs(ACTIONS) do
        local row = CreateFrame("Frame", nil, settings)
        row:SetPoint("TOPLEFT", settings, "TOPLEFT", 300, rowY)
        row:SetSize(264, 20)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetWidth(96)
        label:SetJustifyH("LEFT")
        label:SetText(a.label)

        local bindBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        bindBtn:SetSize(116, 18)
        bindBtn:SetPoint("LEFT", label, "RIGHT", 4, 0)
        bindBtn:SetScript("OnClick", function() BB_startCapture(a) end)
        a.keyLabel = bindBtn

        local clear = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        clear:SetSize(22, 18)
        clear:SetPoint("LEFT", bindBtn, "RIGHT", 4, 0)
        clear:SetText("|cffff8080X|r")
        clear:SetScript("OnClick", function() bind(a.binding, nil); BB_refreshKeybinds() end)
        clear:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Clear binding")
            GameTooltip:Show()
        end)
        clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

        rowY = rowY - 22
    end

    local hint = settings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", settings, "TOPLEFT", 300, rowY - 8)
    hint:SetWidth(264)
    hint:SetJustifyH("LEFT")
    hint:SetText("Click a box, then press the key you want. The same bindings also appear under Key Bindings \226\134\146 BotButtons.")

    local reset = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    reset:SetSize(130, 22)
    reset:SetPoint("BOTTOMLEFT", settings, "BOTTOMLEFT", PAD, 16)
    reset:SetText("Reset defaults")
    reset:SetScript("OnClick", function()
        for k, v in pairs(DEFAULTS) do O[k] = copyTable(v) end
        applyAnchor(); BB_layoutBar(); BB_updateBarVisibility()
        for name, entry in pairs(checks) do entry.frame:SetChecked(entry.getter()) end
        for name, entry in pairs(sliders) do entry.frame:SetValue(entry.getter()) end
        healerEdit:SetText(O.healerName or "")
        tankEdit:SetText(O.tankName or "")
        for _, a in ipairs(ACTIONS) do if a.isToggle then refreshToggle(a) end end
        BB_refreshKeybinds()
        print("|cff33ff99BotButtons|r: defaults restored")
    end)
end

BB_openSettings = function()
    if not settings then buildSettings() end
    if not capture then buildCapture() end
    settings:Show()
    BB_refreshKeybinds()
end

BB_toggleSettings = function()
    if settings and settings:IsShown() then settings:Hide() else BB_openSettings() end
end

--============================================================================
-- startup
--============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UPDATE_BINDINGS")
f:RegisterEvent("CHAT_MSG_WHISPER")

f:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        BotButtonsDB = BotButtonsDB or {}
        BotButtonsDB.options = BotButtonsDB.options or {}
        O = BotButtonsDB.options
        for k, v in pairs(DEFAULTS) do
            if O[k] == nil then O[k] = copyTable(v) end
        end
        O.activeKey = nil               -- drop the old single-slot "last pressed" mark
        if type(O.toggles) ~= "table" then O.toggles = copyTable(DEFAULTS.toggles) end
        for _, a in ipairs(ACTIONS) do
            if a.isToggle and O.toggles[a.key] == nil then O.toggles[a.key] = false end
            _G["BINDING_NAME_" .. a.binding] = "BotButtons: " .. a.label
        end
    elseif event == "PLAYER_LOGIN" then
        BB_buildBar()
        applyAnchor()
        BB_layoutBar()
        BB_updateBarVisibility()
        for _, a in ipairs(ACTIONS) do
            if a.isToggle then refreshToggle(a) end
        end
    elseif event == "UPDATE_BINDINGS" then
        if settings and settings:IsShown() then BB_refreshKeybinds() end
    elseif event == "CHAT_MSG_WHISPER" then
        tankAck(arg2)               -- arg1 = text, arg2 = sender
    end
end)

SLASH_BOTBUTTONS1 = "/bb"
SLASH_BOTBUTTONS2 = "/botbuttons"
SlashCmdList["BOTBUTTONS"] = function(msg)
    local raw = msg or ""
    msg = string.lower(raw)
    if msg == "lock" then
        O.locked = true; BB_layoutBar()
    elseif msg == "unlock" then
        O.locked = false; BB_layoutBar()
    elseif msg == "show" then
        O.show = true; BB_updateBarVisibility()
    elseif msg == "hide" then
        O.show = false; BB_updateBarVisibility()
    elseif msg == "announce" then
        O.announce = not O.announce
        print("|cff33ff99BotButtons|r: chat announce " .. (O.announce and "on" or "off"))
    elseif msg == "reset" then
        for k, v in pairs(DEFAULTS) do O[k] = copyTable(v) end
        applyAnchor(); BB_layoutBar(); BB_updateBarVisibility(); BB_refreshKeybinds()
        for _, a in ipairs(ACTIONS) do if a.isToggle then refreshToggle(a) end end
    elseif msg:match("^tank%s") or msg:match("^healer%s") or msg == "tank" or msg == "healer" then
        -- /bb tank Tanky  (also handy when the name box is fiddly)
        local key, value = raw:match("^(%a+)%s*(.*)$")
        key = (key == "tank") and "tankName" or "healerName"
        value = strtrim and strtrim(value) or value
        if value ~= "" then
            O[key] = value
            local edit = _G[(key == "tankName") and "BBTankNameEdit" or "BBHealerNameEdit"]
            if edit then edit:SetText(value) end
        end
        print("|cff33ff99BotButtons|r: " .. ((key == "tankName") and "tank" or "healer") ..
              " bot name = '" .. (O[key] or "") .. "'")
    else
        BB_toggleSettings()
    end
end
