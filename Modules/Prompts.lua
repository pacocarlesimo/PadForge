-- Prompts: answer popups without hunting for them (only while the popup
-- does NOT have the pad: when it has it, the game's own A / B answer it). On WoW Forever the
-- party invite, resurrect and release popups stopped taking the gamepad's
-- focus on their own; players had to press Square to reach them, and one
-- reported dying to an invite. While such a popup is up (and no game window
-- has the pad), A answers yes and B answers no; a hint shows the buttons.
--
-- The answer is the popup's own button, clicked from a secure macro
-- ("/click StaticPopup1Button1"), so the game's own code runs it as if the
-- player clicked. A short grace time after a popup appears keeps a press
-- meant for something else (a jump) from answering it.
local _, PF = ...
local A, B, Pad = PF.Actions, PF.Binds, PF.Pad

local M = PF.NewModule("prompts", {
    title = "Popup answers",
    desc = "A / B answer invites, resurrects, summons, ready checks and more without focusing them.",
    order = 5,
})
PF.Prompts = M

-- Each kind: the popups that are it (StaticPopup "which" names, or a
-- frame), what yes / no do when its buttons can't be clicked by name
M.KINDS = {
    { id = "invite", label = "Group invites", popups = { "PARTY_INVITE", "PARTY_INVITE_XREALM" },
        yes = function() if AcceptGroup then AcceptGroup() end end,
        no = function() if DeclineGroup then DeclineGroup() end end },
    { id = "resurrect", label = "Resurrection", popups = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" },
        yes = function() if AcceptResurrect then AcceptResurrect() end end,
        no = function() if DeclineResurrect then DeclineResurrect() end end },
    { id = "release", label = "Release spirit", popups = { "DEATH" }, grace = 1.2, noNo = true,
        yes = function() if RepopMe then RepopMe() end end },
    { id = "summon", label = "Summons", popups = { "CONFIRM_SUMMON" },
        yes = function()
            if C_SummonInfo and C_SummonInfo.ConfirmSummon then C_SummonInfo.ConfirmSummon() elseif ConfirmSummon then ConfirmSummon() end
        end,
        no = function()
            if C_SummonInfo and C_SummonInfo.CancelSummon then C_SummonInfo.CancelSummon() elseif CancelSummon then CancelSummon() end
        end },
    { id = "readycheck", label = "Ready checks", frame = "ReadyCheckFrame",
        yesButton = "ReadyCheckFrameYesButton", noButton = "ReadyCheckFrameNoButton",
        yes = function() if ConfirmReadyCheck then ConfirmReadyCheck(1) end end,
        no = function() if ConfirmReadyCheck then ConfirmReadyCheck(nil) end end },
    { id = "loot", label = "Loot confirmations (bind on pickup, rolls)", popups = { "LOOT_BIND", "CONFIRM_LOOT_ROLL", "EQUIP_BIND", "AUTOEQUIP_BIND" },
        clickOnly = true },
    { id = "duel", label = "Duel requests", popups = { "DUEL_REQUESTED" },
        yes = function() if AcceptDuel then AcceptDuel() end end,
        no = function() if CancelDuel then CancelDuel() end end },
}

local function Validate(t)
    t.on = type(t.on) == "table" and t.on or {}
    if t.yes ~= "PAD1" and t.yes ~= "PAD3" and t.yes ~= "PAD4" then t.yes = "PAD1" end
    if t.no ~= "PAD2" and t.no ~= "PAD3" and t.no ~= "PAD4" then t.no = "PAD2" end
    if t.yes == t.no then t.no = "PAD2" t.yes = "PAD1" end
    t.grace = math.max(0, math.min(2, tonumber(t.grace) or 0.4))
    return t
end

PF.DB.RegisterDefaults("prompts", {
    on = { invite = true, resurrect = true, release = true, summon = true, readycheck = true, loot = true, duel = false },
    yes = "PAD1", no = "PAD2", grace = 0.4, hint = true,
}, Validate)

local function Section()
    local p = PF.P()
    return p and p.prompts
end

---------------------------------------------------------------------------
-- Finding a popup that's up
---------------------------------------------------------------------------
-- (read only: no function of the game's is called for it)
local function FindPopup(which)
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local frame = _G["StaticPopup" .. i]
        if frame and frame:IsShown() and frame.which == which then return frame end
    end
end

local function ButtonName(frame, n)
    if not frame then return nil end
    local button = frame["button" .. n]
        or (frame.ButtonContainer and frame.ButtonContainer["Button" .. n])
        or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "Button" .. n])
    if not (button and button.IsShown and button:IsShown()) then return nil end
    if button.IsEnabled and not button:IsEnabled() then return nil end
    return button.GetName and button:GetName() or nil
end

-- The prompt to answer now: { kind, frame, yes = name|nil, no = name|nil, text }
local function Current()
    local s = Section()
    if not s then return nil end
    for _, kind in ipairs(M.KINDS) do
        if s.on[kind.id] then
            if kind.frame then
                local frame = _G[kind.frame]
                if frame and frame:IsShown() then
                    return { kind = kind, frame = frame, yes = _G[kind.yesButton] and kind.yesButton, no = _G[kind.noButton] and kind.noButton }
                end
            else
                for _, which in ipairs(kind.popups) do
                    local frame = FindPopup(which)
                    if frame then
                        local text = frame.text and frame.text.GetText and frame.text:GetText()
                            or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "Text"] and _G[frame:GetName() .. "Text"]:GetText())
                        return { kind = kind, frame = frame, which = which, yes = ButtonName(frame, 1), no = not kind.noNo and ButtonName(frame, 2) or nil, text = text }
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- The answering buttons: secure ones running /click on the popup's button
-- (the game's code answers), plain ones calling the game's API when the
-- popup's buttons have no name
---------------------------------------------------------------------------
local function MakeSecure(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:SetSize(1, 1)
    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)
    b:SetAttribute("type", "macro")
    return b
end
local secureYes, secureNo = MakeSecure("PadForgePromptYes"), MakeSecure("PadForgePromptNo")

local active          -- the prompt bound now
local plainYes = CreateFrame("Button", "PadForgePromptYesAPI", UIParent)
plainYes:SetScript("OnClick", function() if active and active.kind.yes then PF.SafeCall("prompt yes", active.kind.yes) end end)
local plainNo = CreateFrame("Button", "PadForgePromptNoAPI", UIParent)
plainNo:SetScript("OnClick", function() if active and active.kind.no then PF.SafeCall("prompt no", active.kind.no) end end)

-- What yes / no click for a prompt (nil: nothing)
local function Targets(prompt)
    local yes, no
    if prompt.yes then
        secureYes:SetAttribute("macrotext", "/click " .. prompt.yes)
        yes = secureYes:GetName()
    elseif prompt.kind.yes and not prompt.kind.clickOnly then
        yes = plainYes:GetName()
    end
    if prompt.no then
        secureNo:SetAttribute("macrotext", "/click " .. prompt.no)
        no = secureNo:GetName()
    elseif prompt.kind.no and not prompt.kind.clickOnly and not prompt.kind.noNo then
        no = plainNo:GetName()
    end
    return yes, no
end

B.Register("prompts", function()
    if not (M.running and active and active.ready) then return {} end
    -- (a game window holding the pad, the popup included, answers its own
    -- buttons: binding them then taints its closing)
    if B.FocusedFrame() then return {} end
    local s = Section()
    local claims = {}
    if active.yesTarget then
        claims[#claims + 1] = { key = s.yes, click = active.yesTarget, world = false, label = "Answer yes: " .. active.kind.label }
    end
    if active.noTarget then
        claims[#claims + 1] = { key = s.no, click = active.noTarget, world = false, label = "Answer no: " .. active.kind.label }
    end
    return claims
end, 5)

---------------------------------------------------------------------------
-- The hint
---------------------------------------------------------------------------
local hint = CreateFrame("Frame", "PadForgePromptHint", UIParent)
hint:SetSize(420, 46)
hint:SetPoint("TOP", UIParent, "TOP", 0, -150)
hint:SetFrameStrata("FULLSCREEN_DIALOG")
hint:Hide()
hint.bg = hint:CreateTexture(nil, "BACKGROUND")
hint.bg:SetAllPoints()
hint.bg:SetColorTexture(0, 0, 0, 0.7)
hint.edge = hint:CreateTexture(nil, "BORDER")
hint.edge:SetPoint("BOTTOMLEFT")
hint.edge:SetPoint("BOTTOMRIGHT")
hint.edge:SetHeight(2)
hint.edge:SetColorTexture(1, 0.72, 0.3, 0.9)
hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
hint.text:SetPoint("CENTER")

local function ShowHint()
    local s = Section()
    if not (active and s and s.hint) then hint:Hide() return end
    local parts = {}
    if PF.InCombat() and not active.bound then
        parts[1] = "|cffffb74d" .. active.kind.label .. "|r: answer after combat, or focus it"
    else
        parts[1] = "|cffffb74d" .. active.kind.label .. "|r"
        if active.yesTarget then parts[#parts + 1] = Pad.Glyph(s.yes, 18) .. " Yes" end
        if active.noTarget then parts[#parts + 1] = Pad.Glyph(s.no, 18) .. " No" end
        if not active.ready then parts[#parts + 1] = "|cff999999...|r" end
    end
    hint.text:SetText(table.concat(parts, "     "))
    hint:SetWidth(math.max(300, hint.text:GetStringWidth() + 40))
    hint:Show()
end

---------------------------------------------------------------------------
-- Watching
---------------------------------------------------------------------------
local watch = CreateFrame("Frame")
local wait = 0
watch:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - elapsed
    if wait > 0 or not M.running then return end
    wait = 0.15
    local now = Current()
    local same = now and active and now.frame == active.frame and now.which == active.which and now.kind == active.kind
    if same then
        if not active.ready and GetTime() >= active.readyAt then
            active.ready = true
            PF.AfterCombat("binds", B.Apply)
            ShowHint()
        end
        return
    end
    -- (a new prompt, or none)
    if now and not PF.InCombat() then
        now.yesTarget, now.noTarget = Targets(now)
    end
    local s = Section()
    if now then
        now.readyAt = GetTime() + math.max(s.grace or 0.4, now.kind.grace or 0)
        now.ready = false
    end
    local had = active ~= nil
    active = now
    if had or now then PF.AfterCombat("binds", B.Apply) end
    ShowHint()
end)

PF.On("PF_BINDS_APPLIED", function()
    if active then
        active.bound = B.applied[Section().yes] ~= nil and B.applied[Section().yes].source == "prompts"
        ShowHint()
    end
end)

PF.On("PLAYER_REGEN_ENABLED", function()
    -- (a prompt that came in combat: its targets now)
    if active and not active.yesTarget and not active.noTarget then
        active.yesTarget, active.noTarget = Targets(active)
        PF.AfterCombat("binds", B.Apply)
    end
end)

function M.Enable() end
function M.Refresh() ShowHint() end
function M.Disable()
    active = nil
    hint:Hide()
end
