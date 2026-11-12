-- The PadForge window: pages, sub-pages (B goes back), opening and
-- closing. It closes as combat starts (settings change out of combat) and
-- can't open during it.
local _, PF = ...
local W, Pad = PF.Widgets, PF.Pad

local Config = {}
PF.Config = Config

local pages = {}
local current = 1

-- build() -> rows
function Config.AddPage(id, label, build, order)
    pages[#pages + 1] = { id = id, label = label, build = build, order = order or 50 }
    table.sort(pages, function(a, b) return a.order < b.order end)
end

local function Window()
    if Config.window then return Config.window end
    local f = W.CreateWindow()
    Config.window = f
    f.stack = {}
    for i = 1, 14 do
        local b = CreateFrame("Button", nil, f.nav)
        b:SetHeight(30)
        b:SetPoint("TOPLEFT", 0, -6 - (i - 1) * 32)
        b:SetPoint("TOPRIGHT", 0, -6 - (i - 1) * 32)
        b.hl = b:CreateTexture(nil, "BACKGROUND")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 0.72, 0.3, 0.16)
        b.bar = b:CreateTexture(nil, "BORDER")
        b.bar:SetPoint("TOPRIGHT")
        b.bar:SetPoint("BOTTOMRIGHT")
        b.bar:SetWidth(3)
        b.bar:SetColorTexture(1, 0.72, 0.3, 1)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("LEFT", 14, 0)
        b:SetScript("OnClick", function(self)
            if self.page then
                wipe(f.stack)
                current = self.page
                f.focus, f.offset = 1, 0
                Config.Refresh()
            end
        end)
        f.navButtons[i] = b
    end
    return f
end

local function RenderNav(f)
    for i, b in ipairs(f.navButtons) do
        local page = pages[i]
        b.page = page and i or nil
        if page then
            local on = i == current
            b.hl:SetShown(on)
            b.bar:SetShown(on)
            b.text:SetText(on and ("|cffffffff" .. page.label .. "|r") or ("|cffaaaaaa" .. page.label .. "|r"))
            b:Show()
        else
            b:Hide()
        end
    end
    f.navHint:SetText(Pad.Glyph("PADLSHOULDER", 14) .. "  pages  " .. Pad.Glyph("PADRSHOULDER", 14))
end

-- The rows of what is shown: the top of the stack, or the page
local function Build(f)
    local top = f.stack[#f.stack]
    local ok, items
    if top then
        ok, items = pcall(top.build)
    else
        ok, items = pcall(pages[current].build)
    end
    if not ok then
        PF.Report("page", items)
        items = { { kind = "text", text = "|cffff7359This page failed to draw: " .. tostring(items) .. "|r" } }
    end
    if top then
        table.insert(items, 1, { kind = "header", text = "< " .. top.label })
    end
    return items
end

function Config.Refresh()
    local f = Config.window
    if not (f and f:IsShown()) then return end
    f.items = Build(f)
    RenderNav(f)
    W.Render(f)
end

function Config.Show(pageId)
    if PF.InCombat() then
        PF.Print("Settings open after combat.")
        return
    end
    if not PF.IsReady() then return end
    if PF.Binds.WindowHasPad() then return PF.Binds.WaitForWindow() end
    -- (the first time, until it's applied: the quick setup)
    if not pageId and not Config.setupOffered and PF.Setup and not PF.Setup.Done() then
        pageId = "setup"
    end
    Config.setupOffered = true
    local f = Window()
    local p = PF.P()
    f:SetScale((p and p.ui and p.ui.scale) or 1)
    if pageId then
        for i, page in ipairs(pages) do if page.id == pageId then current = i end end
        wipe(f.stack)
        f.focus, f.offset = 1, 0
    end
    f:Show()
    Config.Refresh()
end

function Config.Hide()
    if Config.window then Config.window:Hide() end
end

function Config.Toggle()
    if Config.window and Config.window:IsShown() then Config.Hide() else Config.Show() end
end

function Config.IsShown()
    return Config.window and Config.window:IsShown() or false
end

function Config.NextPage(dir)
    local f = Config.window
    wipe(f.stack)
    current = ((current - 1 + dir) % #pages) + 1
    f.focus, f.offset = 1, 0
    Config.Refresh()
end

-- A sub-page (B comes back)
function Config.Push(label, build)
    local f = Config.window
    f.stack[#f.stack + 1] = { label = label, build = build, focus = f.focus, offset = f.offset }
    f.focus, f.offset = 2, 0
    Config.Refresh()
end

function Config.Back()
    local f = Config.window
    local top = table.remove(f.stack)
    if top then
        f.focus, f.offset = top.focus or 1, top.offset or 0
        Config.Refresh()
    else
        f:Hide()
    end
end

-- A game window taking the pad while ours is open: ours steps aside
local watcher = CreateFrame("Frame")
local wWait = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    wWait = wWait - elapsed
    if wWait > 0 then return end
    wWait = 0.2
    if Config.IsShown() and PF.Binds.WindowHasPad() then Config.Hide() end
end)

PF.On("PLAYER_REGEN_DISABLED", function()
    if Config.IsShown() then
        Config.Hide()
        PF.Print("Settings closed for combat.")
    end
end)
PF.On("PF_PROFILE_CHANGED", function() C_Timer.After(0, Config.Refresh) end)
PF.On("PF_PAD_STYLE", function() Config.Refresh() end)

---------------------------------------------------------------------------
-- First login: one line on how to open, and a welcome page
---------------------------------------------------------------------------
PF.On("PF_READY", function()
    local g = PF.db.global
    if not g.welcomed then
        g.welcomed = true
        PF.Print("Thanks for trying PadForge! Type /pf to set it up (it opens on the Start page).")
    end
end)

-- (No page in Options > AddOns: registering one adds an entry of ours to
-- the game's Settings lists, which its gamepad code walks; that is how
-- other addons got "blocked from an action" errors on Forever. PadForge
-- opens from the minimap button, /pf or its key binding.)
