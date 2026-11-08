-- The action picker: tabs of spells, items, macros, emotes, markers,
-- group targets, chat phrases, ground spells and specials. LB / RB switch
-- tabs, the D-pad moves, A picks, Y picks "nothing", B cancels.
local _, PF = ...
local A, Pad, W = PF.Actions, PF.Pad, PF.Widgets

local P = {}
PF.Picker = P

local ROWS = 10
local ROW_H = 30

P.TABS = {
    spells = { label = "Spells", list = A.SpellbookSpells },
    items = { label = "Items", list = A.UsableItems },
    macros = { label = "Macros", list = A.Macros,
        empty = "No macros yet. Make them in the game: type /macro (or Esc > Macros), then come back." },
    special = { label = "Special", list = A.Specials },
    markers = { label = "Markers", list = A.Markers },
    group = { label = "Group", list = A.Units },
    chat = { label = "Chat", list = A.Phrases },
    emotes = { label = "Emotes", list = A.Emotes },
    feet = { label = "Spell at feet", list = function()
        local out = {}
        for _, e in ipairs(A.SpellbookSpells()) do
            local id = e.action:match("^spell:(%d+)$")
            if id then
                local action = "ground:player:" .. id
                local label, icon = A.Describe(action)
                out[#out + 1] = { action = action, label = label, icon = icon }
            end
        end
        return out
    end },
    attarget = { label = "Spell at target", list = function()
        local out = {}
        for _, e in ipairs(A.SpellbookSpells()) do
            local id = e.action:match("^spell:(%d+)$")
            if id then
                local action = "ground:target:" .. id
                local label, icon = A.Describe(action)
                out[#out + 1] = { action = action, label = label, icon = icon }
            end
        end
        return out
    end },
}
P.ALL = { "spells", "macros", "items", "special", "markers", "group", "chat", "emotes", "feet", "attarget" }

local m

local function Build(f)
    m = W.Modal(f, 520, 420)
    m.tabsText = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.tabsText:SetPoint("TOP", 0, -40)
    m.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, m)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 16, -64 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -16, -64 - (i - 1) * ROW_H)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(0.31, 0.76, 0.97, 0.22)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("LEFT", 6, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r.text:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self)
            if self.index then
                m.focus = self.index
                m:Press("PAD1")
            end
        end)
        r:SetScript("OnEnter", function(self)
            if self.index then m.focus = self.index P.Render() end
        end)
        m.rows[i] = r
    end
    m.empty = m:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    m.empty:SetPoint("CENTER")
    m.empty:SetWidth(440)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseWheel", function(_, delta) m:Press(delta > 0 and "PADDUP" or "PADDDOWN") end)
    m.foot:SetText(Pad.Glyph("PAD1", 16) .. " Pick    " .. Pad.Glyph("PAD4", 16) .. " Nothing    "
        .. Pad.Glyph("PADLSHOULDER", 16) .. Pad.Glyph("PADRSHOULDER", 16) .. " Tabs    " .. Pad.Glyph("PAD2", 16) .. " Cancel")

    function m:Press(key)
        if key == "PADDUP" then
            self.focus = math.max(1, self.focus - 1)
        elseif key == "PADDDOWN" then
            self.focus = math.min(#self.list, self.focus + 1)
        elseif key == "PADDLEFT" then
            self.focus = math.max(1, self.focus - ROWS)
        elseif key == "PADDRIGHT" then
            self.focus = math.min(#self.list, self.focus + ROWS)
        elseif key == "PADLSHOULDER" or key == "PADRSHOULDER" then
            local n = #self.tabs
            self.tab = ((self.tab - 1 + (key == "PADRSHOULDER" and 1 or -1)) % n) + 1
            P.Load()
        elseif key == "PAD1" then
            local e = self.list[self.focus]
            if e then
                self:Close()
                W.Call(self.onPick, e.action)
            end
            return
        elseif key == "PAD4" then
            self:Close()
            W.Call(self.onPick, nil)
            return
        elseif key == "PAD2" then
            self:Close()
            return
        end
        P.Render()
    end
end

function P.Load()
    local id = m.tabs[m.tab]
    local tab = P.TABS[id]
    local ok, list = pcall(tab.list)
    m.list = ok and list or {}
    m.focus, m.offset = 1, 0
    P.Render()
end

function P.Render()
    local parts = {}
    for i, id in ipairs(m.tabs) do
        local label = P.TABS[id].label
        parts[#parts + 1] = i == m.tab and ("|cff4fc3f7[" .. label .. "]|r") or ("|cff999999" .. label .. "|r")
    end
    m.tabsText:SetText(table.concat(parts, "  "))
    if m.focus <= m.offset then m.offset = m.focus - 1 end
    if m.focus > m.offset + ROWS then m.offset = m.focus - ROWS end
    m.offset = math.max(0, m.offset)
    for i, r in ipairs(m.rows) do
        local index = m.offset + i
        local e = m.list[index]
        r.index = e and index or nil
        if e then
            r.icon:SetTexture(e.icon or 134400)
            r.text:SetText(e.label .. (e.sub and ("  |cff999999" .. e.sub .. "|r") or ""))
            r.hl:SetShown(index == m.focus)
            r:Show()
        else
            r:Hide()
        end
    end
    local tab = P.TABS[m.tabs[m.tab]]
    m.empty:SetText(#m.list == 0 and (tab.empty or "Nothing here.") or "")
end

-- tabs: a list of tab ids (nil: all); onPick(action or nil)
function P.Open(title, tabs, onPick)
    local f = PF.Config.window
    if not m then Build(f) end
    m.title:SetText(title or "Choose an action")
    m.tabs = W.Call(tabs) or P.ALL
    m.tab = 1
    m.onPick = onPick
    m:Open()
    P.Load()
end
