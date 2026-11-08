-- The PadForge window: a list-based panel driven entirely by the pad (and
-- fully by mouse and keyboard too). It takes the pad only while it is open
-- (a catcher frame: EnableGamePadButton) and never touches the game's
-- gamepad window manager.
--
-- Pages are lists of rows:
--   header  { text }
--   text    { text }                          (not focusable)
--   toggle  { label, get, set }
--   choice  { label, choices = {{value, label}}, get, set }
--   range   { label, min, max, step, get, set, fmt }
--   button  { label, value (text or fn), run, alt = {label, run} }
--   action  { label, get, set, tabs }         (A picks, Y clears)
--   press   { label, get, set }               (A records a press, Y clears)
-- Any row: tip, warn (fn -> text), disabled (fn), icon (fn or value).
--
-- Pad: D-pad moves / changes, A activates, B back, X the row's alt, Y
-- clears, LB / RB switch pages. Mouse: click, right-click clears, wheel
-- scrolls. The keyboard is never taken.
local _, PF = ...
local Pad = PF.Pad

local W = {}
PF.Widgets = W

local WIDTH, HEIGHT = 780, 540
local NAV_W = 170
local ROW_H = 30
local VISIBLE = 13

local C = {
    bg = { 0.05, 0.06, 0.08, 0.96 },
    panel = { 0.09, 0.10, 0.13, 1 },
    nav = { 0.07, 0.08, 0.10, 1 },
    focus = { 0.31, 0.76, 0.97, 0.22 },
    focusEdge = { 0.31, 0.76, 0.97, 1 },
    accent = { 1, 0.72, 0.3, 1 },
    dim = { 0.6, 0.62, 0.66, 1 },
    warn = { 1, 0.45, 0.35, 1 },
}
W.COLORS = C

local function Color(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4]) end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function W.CreateWindow()
    local f = CreateFrame("Frame", "PadForgeWindow", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Color(bg, C.bg)
    local edge = f:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("TOPRIGHT")
    edge:SetHeight(2)
    Color(edge, C.accent)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetText(PF.TITLE)
    f.version = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.version:SetPoint("LEFT", f.title, "RIGHT", 8, -1)
    f.version:SetText("v" .. PF.version)
    f.profile = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.profile:SetPoint("TOPRIGHT", -44, -18)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Navigation column
    f.nav = CreateFrame("Frame", nil, f)
    f.nav:SetPoint("TOPLEFT", 10, -46)
    f.nav:SetPoint("BOTTOMLEFT", 10, 64)
    f.nav:SetWidth(NAV_W)
    local navBg = f.nav:CreateTexture(nil, "BACKGROUND")
    navBg:SetAllPoints()
    Color(navBg, C.nav)
    f.navButtons = {}
    f.navHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.navHint:SetPoint("BOTTOM", f.nav, "TOP", 0, 4)

    -- Content
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", f.nav, "TOPRIGHT", 10, 0)
    f.content:SetPoint("BOTTOMRIGHT", -10, 64)
    local contentBg = f.content:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints()
    Color(contentBg, C.panel)
    f.content:EnableMouseWheel(true)
    f.content:SetScript("OnMouseWheel", function(_, delta) W.Scroll(f, -delta * 3) end)
    f.rows = {}
    for i = 1, VISIBLE do f.rows[i] = W.CreateRow(f, i) end
    f.scrollMark = f.content:CreateTexture(nil, "OVERLAY")
    f.scrollMark:SetWidth(3)
    Color(f.scrollMark, C.dim)

    -- Footer: the focused row's help, and the buttons
    f.tip = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.tip:SetPoint("BOTTOMLEFT", 16, 34)
    f.tip:SetPoint("BOTTOMRIGHT", -16, 34)
    f.tip:SetJustifyH("LEFT")
    f.tip:SetHeight(26)
    f.tip:SetWordWrap(true)
    f.legend = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.legend:SetPoint("BOTTOMLEFT", 16, 12)

    f.items, f.focus, f.offset = {}, 1, 0
    f.modal = nil
    W.HookInput(f)
    return f
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
function W.CreateRow(f, i)
    local r = CreateFrame("Button", nil, f.content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", -12, -8 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    Color(r.hl, C.focus)
    r.hl:Hide()
    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetWidth(3)
    Color(r.bar, C.focusEdge)
    r.bar:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 8, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", 10, 0)
    r.label:SetJustifyH("LEFT")
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.value:SetPoint("RIGHT", -10, 0)
    r.value:SetJustifyH("RIGHT")
    r.label:SetPoint("RIGHT", r.value, "LEFT", -12, 0)
    r.label:SetWordWrap(false)
    r:SetScript("OnClick", function(self, button)
        if not self.index then return end
        f.focus = self.index
        if button == "RightButton" then W.Press(f, "PAD4") else W.Press(f, "PAD1") end
    end)
    r:SetScript("OnEnter", function(self)
        if self.index and W.Focusable(f.items[self.index]) then
            f.focus = self.index
            W.Render(f)
        end
    end)
    return r
end

function W.Focusable(item)
    return item and item.kind ~= "header" and item.kind ~= "text"
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return fn end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        PF.Report("ui", a)
        return nil
    end
    return a, b
end
W.Call = Call

local function Disabled(item)
    return item.disabled and Call(item.disabled) and true or false
end

local function ChoiceLabel(item)
    local v = Call(item.get)
    for _, c in ipairs(Call(item.choices) or {}) do
        if c[1] == v then return c[2] end
    end
    return v ~= nil and tostring(v) or "-"
end

-- The right-hand text of a row
local function ValueText(item)
    local k = item.kind
    if k == "toggle" then
        return Call(item.get) and "|cff6ee36eOn|r" or "|cff999999Off|r"
    elseif k == "choice" then
        return "|cff999999<|r  " .. ChoiceLabel(item) .. "  |cff999999>|r"
    elseif k == "range" then
        local v = tonumber(Call(item.get)) or 0
        local text = item.fmt and item.fmt(v) or (math.floor(v * 100 + 0.5) / 100)
        return "|cff999999<|r  " .. tostring(text) .. "  |cff999999>|r"
    elseif k == "action" then
        local action = Call(item.get)
        if not action then return "|cff999999Choose...|r" end
        return PF.Actions.Label(action)
    elseif k == "press" then
        local spec = Call(item.get)
        return spec and Pad.SpecText(spec, 18) or "|cff999999Press to set...|r"
    elseif k == "button" then
        return Call(item.value) or ""
    end
    return ""
end

function W.Render(f)
    local items = f.items
    -- (keep the focus on something focusable, inside the list)
    if #items > 0 then
        f.focus = math.max(1, math.min(f.focus, #items))
        if not W.Focusable(items[f.focus]) then
            local found
            for i = f.focus, #items do if W.Focusable(items[i]) then found = i break end end
            if not found then for i = f.focus, 1, -1 do if W.Focusable(items[i]) then found = i break end end end
            f.focus = found or f.focus
        end
    end
    if f.focus <= f.offset then f.offset = math.max(0, f.focus - 2) end
    if f.focus > f.offset + VISIBLE then f.offset = f.focus - VISIBLE end
    f.offset = math.max(0, math.min(f.offset, math.max(0, #items - VISIBLE)))
    -- (a header just above the focus stays in view)
    if f.offset > 0 and items[f.offset] and items[f.offset].kind == "header" and f.focus - f.offset < VISIBLE then
        f.offset = f.offset - 1
    end

    for i, r in ipairs(f.rows) do
        local index = f.offset + i
        local item = items[index]
        r.index = item and index or nil
        if not item then
            r:Hide()
        else
            r:Show()
            local focused = index == f.focus and W.Focusable(item)
            r.hl:SetShown(focused)
            r.bar:SetShown(focused)
            local icon = item.icon and Call(item.icon)
            if item.kind == "action" and not icon then
                local action = Call(item.get)
                icon = action and PF.Actions.Icon(action)
            end
            r.icon:SetShown(icon ~= nil)
            if icon then r.icon:SetTexture(icon) end
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", icon and 38 or 10, 0)
            r.label:SetPoint("RIGHT", r.value, "LEFT", -12, 0)
            local text = Call(item.label) or Call(item.text) or ""
            if item.kind == "header" then
                r.label:SetFontObject("GameFontNormal")
                r.label:SetText("|cffffb74d" .. text .. "|r")
            elseif item.kind == "text" then
                r.label:SetFontObject("GameFontDisableSmall")
                r.label:SetText(text)
            else
                r.label:SetFontObject("GameFontHighlight")
                local warn = item.warn and Call(item.warn)
                r.label:SetText((Disabled(item) and "|cff777777" or "") .. text .. (warn and "  |cffff7359(!)|r" or ""))
            end
            r.value:SetText(item.kind ~= "header" and item.kind ~= "text" and ValueText(item) or "")
        end
    end
    -- Scroll mark
    if #items > VISIBLE then
        local h = f.content:GetHeight() - 16
        local size = math.max(20, h * VISIBLE / #items)
        f.scrollMark:SetHeight(size)
        f.scrollMark:ClearAllPoints()
        f.scrollMark:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -3, -8 - (h - size) * f.offset / (#items - VISIBLE))
        f.scrollMark:Show()
    else
        f.scrollMark:Hide()
    end
    -- Footer
    local item = items[f.focus]
    local tip = item and W.Focusable(item) and (Call(item.tip) or "") or ""
    local warn = item and item.warn and Call(item.warn)
    if warn then tip = "|cffff7359" .. warn .. "|r" .. (tip ~= "" and ("  " .. tip) or "") end
    f.tip:SetText(tip)
    f.legend:SetText(W.LegendFor(f, item))
    f.profile:SetText("Profile: |cffffffff" .. PF.DB.ActiveName() .. "|r")
end

function W.LegendFor(f, item)
    local g = function(k) return Pad.Glyph(k, 16) end
    local parts = {}
    if item and W.Focusable(item) and not Disabled(item) then
        local k = item.kind
        if k == "toggle" then parts[#parts + 1] = g("PAD1") .. " Switch"
        elseif k == "choice" or k == "range" then parts[#parts + 1] = g("PADDLEFT") .. g("PADDRIGHT") .. " Change"
        elseif k == "action" then parts[#parts + 1] = g("PAD1") .. " Choose" parts[#parts + 1] = g("PAD4") .. " Clear"
        elseif k == "press" then parts[#parts + 1] = g("PAD1") .. " Set" parts[#parts + 1] = g("PAD4") .. " Clear"
        elseif k == "button" then parts[#parts + 1] = g("PAD1") .. " " .. (item.verb or "Select") end
        if item.alt then parts[#parts + 1] = g("PAD3") .. " " .. item.alt.label end
    end
    parts[#parts + 1] = g("PADLSHOULDER") .. g("PADRSHOULDER") .. " Pages"
    parts[#parts + 1] = g("PAD2") .. (f.stack and #f.stack > 0 and " Back" or " Close")
    return table.concat(parts, "    ")
end

function W.Scroll(f, delta)
    f.offset = math.max(0, math.min(f.offset + delta, math.max(0, #f.items - VISIBLE)))
    if f.focus <= f.offset or f.focus > f.offset + VISIBLE then
        f.focus = f.offset + (delta > 0 and 1 or VISIBLE)
    end
    W.Render(f)
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
local function Move(f, dir)
    local i = f.focus
    for _ = 1, #f.items do
        i = i + dir
        if i < 1 or i > #f.items then return end
        if W.Focusable(f.items[i]) then
            f.focus = i
            W.Render(f)
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856, "SFX")
            return
        end
    end
end

local function Change(f, item, dir)
    if Disabled(item) then return end
    if item.kind == "choice" then
        local choices = Call(item.choices) or {}
        if #choices == 0 then return end
        local v, at = Call(item.get), 0
        for i, c in ipairs(choices) do if c[1] == v then at = i end end
        local nextOne = choices[((at - 1 + dir) % #choices) + 1]
        Call(item.set, nextOne[1])
    elseif item.kind == "range" then
        local v = tonumber(Call(item.get)) or item.min
        v = math.max(item.min, math.min(item.max, v + dir * item.step))
        v = math.floor(v / item.step + 0.5) * item.step
        Call(item.set, tonumber(string.format("%.4f", v)))
    elseif item.kind == "toggle" then
        Call(item.set, dir > 0)
    end
    PF.Config.Refresh()
end

-- One press, from the pad, the keyboard or a click (raw: the keyboard key)
function W.Press(f, key, raw)
    if f.modal then
        if f.modal.Press then f.modal:Press(key, raw) end
        return
    end
    local item = f.items[f.focus]
    if key == "PADDUP" then Move(f, -1)
    elseif key == "PADDDOWN" then Move(f, 1)
    elseif key == "PADDLEFT" or key == "PADDRIGHT" then
        if item and (item.kind == "choice" or item.kind == "range" or item.kind == "toggle") then
            Change(f, item, key == "PADDRIGHT" and 1 or -1)
        end
    elseif key == "PADLSHOULDER" or key == "PADRSHOULDER" then
        PF.Config.NextPage(key == "PADRSHOULDER" and 1 or -1)
    elseif key == "PAD2" then
        PF.Config.Back()
    elseif not item or not W.Focusable(item) or Disabled(item) then
        return
    elseif key == "PAD1" then
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 857, "SFX")
        if item.kind == "toggle" then
            Call(item.set, not Call(item.get))
            PF.Config.Refresh()
        elseif item.kind == "choice" or item.kind == "range" then
            Change(f, item, 1)
        elseif item.kind == "button" then
            Call(item.run)
            PF.Config.Refresh()
        elseif item.kind == "action" then
            PF.Picker.Open(item.title or Call(item.label), item.tabs, function(action)
                Call(item.set, action)
                PF.Config.Refresh()
            end)
        elseif item.kind == "press" then
            W.Capture(f, item)
        end
    elseif key == "PAD4" then
        if item.kind == "action" or item.kind == "press" then
            Call(item.set, nil)
            PF.Config.Refresh()
        elseif item.clear then
            Call(item.clear)
            PF.Config.Refresh()
        end
    elseif key == "PAD3" and item.alt then
        Call(item.alt.run)
        PF.Config.Refresh()
    end
end

local REPEAT = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true, UP = true, DOWN = true, LEFT = true, RIGHT = true }
local KEYS = { UP = "PADDUP", DOWN = "PADDDOWN", LEFT = "PADDLEFT", RIGHT = "PADDRIGHT", ENTER = "PAD1", SPACE = "PAD1",
    ESCAPE = "PAD2", BACKSPACE = "PAD2", DELETE = "PAD4", TAB = "PADRSHOULDER", PAGEUP = "PADLSHOULDER", PAGEDOWN = "PADRSHOULDER" }

function W.HookInput(f)
    local held, wait = nil, 0
    local function Down(key)
        if REPEAT[key] then held, wait = key, 0.38 else held = nil end
        W.Press(f, KEYS[key] or key, key)
    end
    if f.EnableGamePadButton then
        f:SetScript("OnGamePadButtonDown", function(_, key) Down(key) end)
        f:SetScript("OnGamePadButtonUp", function(_, key) if key == held then held = nil end end)
        -- (setting the handler turns pad input on: off until shown)
        f:EnableGamePadButton(false)
    end
    -- (no keyboard capture: a frame taking the keyboard can swallow every
    -- key on some clients. Nor is it put in UISpecialFrames: the game walks
    -- that list as Escape or the pad's Menu opens its menu, and a name of
    -- ours there taints the gamepad menu's code. B, the close button or
    -- /pf close it.)
    f:SetScript("OnUpdate", function(_, elapsed)
        if not held then return end
        wait = wait - elapsed
        if wait <= 0 then
            wait = 0.07
            W.Press(f, KEYS[held] or held)
        end
    end)
    f:SetScript("OnShow", function(self)
        if self.EnableGamePadButton then self:EnableGamePadButton(true) end
    end)
    f:SetScript("OnHide", function(self)
        held = nil
        if self.EnableGamePadButton then self:EnableGamePadButton(false) end
        if f.modal and f.modal.Cancel then f.modal:Cancel() end
        f.modal = nil
    end)
end

---------------------------------------------------------------------------
-- Modals: a panel over the content that takes the input while up
---------------------------------------------------------------------------
function W.Modal(f, width, height)
    local m = CreateFrame("Frame", nil, f)
    m:SetSize(width, height)
    m:SetPoint("CENTER", f.content, "CENTER")
    m:SetFrameLevel(f:GetFrameLevel() + 20)
    m:EnableMouse(true)
    local shade = m:CreateTexture(nil, "BACKGROUND", nil, -2)
    shade:SetPoint("TOPLEFT", f, "TOPLEFT")
    shade:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    shade:SetColorTexture(0, 0, 0, 0.55)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Color(bg, C.panel)
    local top = m:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(2)
    Color(top, C.focusEdge)
    m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    m.title:SetPoint("TOP", 0, -14)
    m.body = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    m.body:SetPoint("TOPLEFT", 18, -46)
    m.body:SetPoint("TOPRIGHT", -18, -46)
    m.body:SetJustifyH("LEFT")
    m.body:SetJustifyV("TOP")
    m.foot = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.foot:SetPoint("BOTTOM", 0, 12)
    m:Hide()
    function m:Open()
        f.modal = self
        self:Show()
        f.legend:SetText("")
    end
    function m:Close()
        if f.modal == self then f.modal = nil end
        self:Hide()
        W.Render(f)
    end
    return m
end

-- Yes / no
function W.Confirm(f, title, text, onYes, yesLabel)
    local m = f.confirm or W.Modal(f, 420, 190)
    f.confirm = m
    m.title:SetText(title)
    m.body:SetText(text)
    m.foot:SetText(Pad.Glyph("PAD1", 16) .. " " .. (yesLabel or "Yes") .. "      " .. Pad.Glyph("PAD2", 16) .. " Cancel")
    m.onYes = onYes
    function m:Press(key)
        if key == "PAD1" then
            self:Close()
            Call(self.onYes)
            PF.Config.Refresh()
        elseif key == "PAD2" then
            self:Close()
        end
    end
    m:SetScript("OnMouseUp", function(self, button) self:Press(button == "RightButton" and "PAD2" or "PAD1") end)
    m:Open()
end

-- A text box (keyboard): onDone(text). multiline for export / import.
function W.TextInput(f, title, text, onDone, opts)
    opts = opts or {}
    local m = f.textModal
    if not m then
        m = W.Modal(f, 520, 300)
        f.textModal = m
        local scroll = CreateFrame("ScrollFrame", nil, m, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -70)
        scroll:SetPoint("BOTTOMRIGHT", -36, 40)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(460)
        edit:SetAutoFocus(false)
        scroll:SetScrollChild(edit)
        local bg = m:CreateTexture(nil, "ARTWORK")
        bg:SetPoint("TOPLEFT", scroll, -4, 4)
        bg:SetPoint("BOTTOMRIGHT", scroll, 22, -4)
        bg:SetColorTexture(0, 0, 0, 0.5)
        m.edit = edit
        edit:SetScript("OnEscapePressed", function() m:Press("PAD2") end)
        edit:SetScript("OnEnterPressed", function(self)
            if not m.multi then m:Press("PAD1") else self:Insert("\n") end
        end)
        edit:SetScript("OnEditFocusGained", function() m.typing = true end)
        edit:SetScript("OnEditFocusLost", function() m.typing = false end)
        m.body:SetPoint("TOPLEFT", 18, -40)
    end
    m.multi = opts.multiline
    m.title:SetText(title)
    m.body:SetText(opts.body or "")
    m.edit:SetMaxLetters(opts.max or 0)
    m.edit:SetText(text or "")
    m.edit:SetHeight(opts.multiline and 400 or 20)
    m.onDone = onDone
    m.readOnly = opts.readOnly
    m.foot:SetText((opts.readOnly and "" or (Pad.Glyph("PAD1", 16) .. " " .. (opts.doneLabel or "Done") .. "      "))
        .. Pad.Glyph("PAD2", 16) .. (opts.readOnly and " Close" or " Cancel"))
    function m:Press(key)
        if key == "PAD1" and not self.readOnly then
            local value = self.edit:GetText()
            self.edit:ClearFocus()
            self:Close()
            Call(self.onDone, value)
            PF.Config.Refresh()
        elseif key == "PAD2" then
            self.edit:ClearFocus()
            self:Close()
        end
    end
    function m:Cancel() self.edit:ClearFocus() end
    m:Open()
    m.edit:SetFocus()
    if opts.select then m.edit:HighlightText() end
end

-- Records a press: the button pressed, with the triggers held as its layer.
-- Start / Menu or the mouse cancels.
function W.Capture(f, item)
    local m = f.capture or W.Modal(f, 420, 190)
    f.capture = m
    m.title:SetText("Press a button")
    local allow = item.keys and ("Allowed: " .. table.concat((function()
        local names = {}
        for _, k in ipairs(Call(item.keys)) do names[#names + 1] = Pad.Glyph(k, 16) end
        return names
    end)(), " ")) or ""
    m.body:SetText("Hold " .. Pad.Glyph("PADLTRIGGER", 16) .. " / " .. Pad.Glyph("PADRTRIGGER", 16)
        .. " for a layer, then press the button.\n\n" .. allow .. "\n\n|cff999999" .. Pad.Glyph("PADFORWARD", 16) .. " or a click cancels.|r")
    m.foot:SetText("")
    m.item = item
    function m:Press(key, raw)
        if key == "PADFORWARD" or raw == "ESCAPE" then
            self:Close()
            return
        end
        -- (other keyboard keys: not a pad button)
        if raw and raw == key and not key:find("^PAD") then return end
        if key == "PADLTRIGGER" or key == "PADRTRIGGER" then return end
        local allowed = Call(self.item.keys)
        if allowed then
            local ok = false
            for _, k in ipairs(allowed) do if k == key then ok = true end end
            if not ok then
                local why = PF.Binds.GameOwns(key)
                self.body:SetText("|cffff7359" .. Pad.Name(key) .. " can't be used here" .. (why and (": it's " .. why) or "") .. ".|r\n\nPress another button.")
                return
            end
        end
        local layer = self.item.noLayer and "N" or Pad.LayerNow()
        self:Close()
        Call(self.item.set, Pad.Spec(layer, key))
        PF.Config.Refresh()
    end
    m:SetScript("OnMouseUp", function(self) self:Close() end)
    m:Open()
end
