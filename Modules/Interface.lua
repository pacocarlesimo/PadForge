-- Interface: hide what the gamepad UI won't let you turn off. Forum
-- reports: a big animated swing / shot timer forced in the middle of the
-- screen for controller players, and the Issue Reporter icon covering the
-- action bars on small screens.
--
-- Hiding is an alpha animation of ours aimed at the frame (PF.Fade): none
-- of the game's frames is ever changed from addon code, which is what
-- taints the gamepad window manager. Any named frame can be hidden:
--   * found by name (swing / shot timers, the Issue Reporter),
--   * found under the middle of the screen (where the swing circle sits;
--     run it while the circle is showing),
--   * picked with the mouse (/pf pick).
local _, PF = ...
local Pad = PF.Pad

local M = PF.NewModule("interface", {
    title = "Hide elements",
    desc = "Hide the forced swing timer, the Issue Reporter or anything else you pick.",
    order = 40,
})
PF.Interface = M

local function Validate(t)
    t.hidden = type(t.hidden) == "table" and t.hidden or {}
    for name, on in pairs(t.hidden) do
        if type(name) ~= "string" or not name:match("^[%w_%.]+$") or on ~= true then t.hidden[name] = nil end
    end
    return t
end

PF.DB.RegisterDefaults("interface", { hidden = {} }, Validate)

local function Section()
    local p = PF.P()
    return p and p.interface
end

-- Name patterns of things players asked to hide (lowercase)
M.PATTERNS = {
    { find = "swingtimer", label = "Swing timer" },
    { find = "shottimer", label = "Shot timer" },
    { find = "attacktimer", label = "Attack timer" },
    { find = "autoshot", label = "Auto Shot timer" },
    { find = "swing", label = "Swing" },
    { find = "issuereporter", label = "Issue Reporter" },
    { find = "inputlegend", label = "Button legend" },
    { find = "gamepadlegend", label = "Button legend" },
    { find = "bindinglegend", label = "Button legend" },
}

local function Usable(frame, name)
    if type(name) ~= "string" or name:find("^PadForge") then return false end
    if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then return false end
    local ok, forbidden = pcall(function() return frame.IsForbidden and frame:IsForbidden() end)
    if not ok or forbidden then return false end
    local ok2, isRegion = pcall(function() return frame:IsObjectType("Region") or frame:IsObjectType("Frame") end)
    if not ok2 or not isRegion then return false end
    if name:lower():find("nameplate") then return false end
    return true
end

-- Named frames matching the patterns: { name, label }
function M.Discover()
    local out, seen = {}, {}
    for name, value in pairs(_G) do
        if type(name) == "string" and type(value) == "table" and #name < 80 then
            local lower = name:lower()
            for _, p in ipairs(M.PATTERNS) do
                if lower:find(p.find, 1, true) and not seen[name] and Usable(value, name) then
                    seen[name] = true
                    out[#out + 1] = { name = name, label = p.label }
                    break
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Named, shown frames covering the middle of the screen, smallest first
function M.AtCenter()
    local out = {}
    if not EnumerateFrames then return out end
    local cx, cy = UIParent:GetCenter()
    local scale = UIParent:GetEffectiveScale()
    cx, cy = cx * scale, cy * scale
    local frame = EnumerateFrames()
    local guard = 0
    while frame and guard < 20000 do
        guard = guard + 1
        local ok, name = pcall(frame.GetName, frame)
        if ok and name and Usable(frame, name) and frame:IsVisible() then
            local okRect, l, b, w, h = pcall(frame.GetRect, frame)
            if okRect and l and w and w > 0 and h > 0 then
                local s = frame:GetEffectiveScale()
                l, b, w, h = l * s, b * s, w * s, h * s
                local area = w * h
                local sw, sh = GetPhysicalScreenSize and GetPhysicalScreenSize()
                local full = sw and area > sw * sh * 0.6
                if not full and cx >= l and cx <= l + w and cy >= b and cy <= b + h and name ~= "UIParent" and name ~= "WorldFrame" then
                    out[#out + 1] = { name = name, label = "At the middle of the screen", area = area }
                end
            end
        end
        frame = EnumerateFrames(frame)
    end
    table.sort(out, function(a, b) return a.area < b.area end)
    while #out > 12 do table.remove(out) end
    return out
end

local function Resolve(name)
    local frame = _G[name]
    if Usable(frame, name) then return frame end
end

local faded = {}
local function Apply()
    if PF.InCombat() then return PF.AfterCombat("interface", Apply) end
    local s = Section()
    local want = {}
    if M.running and s then
        for name in pairs(s.hidden) do want[name] = true end
    end
    for name in pairs(faded) do
        if not want[name] then
            PF.Fade(Resolve(name), false)
            faded[name] = nil
        end
    end
    for name in pairs(want) do
        local frame = Resolve(name)
        if frame then
            PF.Fade(frame, true)
            faded[name] = true
        end
    end
end
M.Apply = Apply

function M.IsHidden(name)
    local s = Section()
    return s and s.hidden[name] == true
end

function M.SetHidden(name, on)
    local s = Section()
    s.hidden[name] = on and true or nil
    Apply()
end

function M.Enable() Apply() end
function M.Refresh() Apply() end
function M.Disable() Apply() end

-- Frames made later (load-on-demand UI): try again a few times
PF.On("ADDON_LOADED", function() if M.running then C_Timer.After(1, Apply) end end)
PF.On("PLAYER_ENTERING_WORLD", function() if M.running then C_Timer.After(2, Apply) end end)

---------------------------------------------------------------------------
-- Picking with the mouse: /pf pick. The named frames under the mouse are
-- listed; D-pad up / down (or the mouse wheel) chooses one, A (or Enter)
-- hides it, B (or Escape) stops.
---------------------------------------------------------------------------
local picker = CreateFrame("Frame", "PadForgePicker", UIParent)
picker:SetSize(360, 120)
picker:SetPoint("TOP", 0, -80)
picker:SetFrameStrata("TOOLTIP")
picker:Hide()
picker.bg = picker:CreateTexture(nil, "BACKGROUND")
picker.bg:SetAllPoints()
picker.bg:SetColorTexture(0, 0, 0, 0.8)
picker.text = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
picker.text:SetPoint("TOPLEFT", 10, -10)
picker.text:SetPoint("BOTTOMRIGHT", -10, 10)
picker.text:SetJustifyH("LEFT")
picker.text:SetJustifyV("TOP")
picker.box = CreateFrame("Frame", nil, UIParent)
picker.box:SetFrameStrata("TOOLTIP")
picker.box.tex = picker.box:CreateTexture(nil, "OVERLAY")
picker.box.tex:SetAllPoints()
picker.box.tex:SetColorTexture(1, 0.6, 0.1, 0.25)
picker.box:Hide()

local chain, choice = {}, 1

local function UnderMouse()
    local list = {}
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local frame = foci and foci[1]
    local guard = 0
    while frame and guard < 30 do
        guard = guard + 1
        local ok, name = pcall(frame.GetName, frame)
        if ok and name and Usable(frame, name) and name ~= "UIParent" and name ~= "WorldFrame" then list[#list + 1] = name end
        local okP, parent = pcall(frame.GetParent, frame)
        frame = okP and parent or nil
    end
    return list
end

local function Draw()
    local lines = { "|cffffb74dPick an element to hide|r  " .. Pad.Glyph("PADDUP", 14) .. Pad.Glyph("PADDDOWN", 14) .. " choose   "
        .. Pad.Glyph("PAD1", 14) .. " hide   " .. Pad.Glyph("PAD2", 14) .. " stop" }
    if #chain == 0 then lines[#lines + 1] = "|cff999999Move the mouse over the element.|r" end
    for i, name in ipairs(chain) do
        lines[#lines + 1] = (i == choice and "|cff4fc3f7> " or "   ") .. name .. (i == choice and "|r" or "")
        if i >= 6 then break end
    end
    picker.text:SetText(table.concat(lines, "\n"))
    local frame = chain[choice] and _G[chain[choice]]
    if frame and frame.GetRect and frame:GetRect() then
        picker.box:ClearAllPoints()
        picker.box:SetAllPoints(frame)
        picker.box:Show()
    else
        picker.box:Hide()
    end
end

local elapsedSince = 0
picker:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.1 then return end
    elapsedSince = 0
    local now = UnderMouse()
    if table.concat(now, ",") ~= table.concat(chain, ",") then
        chain, choice = now, 1
        Draw()
    end
end)

local function Stop()
    picker:Hide()
    picker.box:Hide()
    if picker.EnableGamePadButton then picker:EnableGamePadButton(false) end
end

local function Pick()
    local name = chain[choice]
    if name then
        M.SetHidden(name, true)
        PF.Print("Hidden: " .. name .. " (bring it back in /pf, Hide elements).")
    end
    Stop()
    if PF.Config and PF.Config.Refresh then PF.Config.Refresh() end
end

local function Press(key)
    if key == "PADDUP" or key == "UP" then
        choice = math.max(1, choice - 1)
        Draw()
    elseif key == "PADDDOWN" or key == "DOWN" then
        choice = math.min(#chain, choice + 1)
        Draw()
    elseif key == "PAD1" or key == "ENTER" then
        Pick()
    elseif key == "PAD2" or key == "ESCAPE" then
        Stop()
    end
end

if picker.EnableGamePadButton then
    picker:SetScript("OnGamePadButtonDown", function(_, key) Press(key) end)
    picker:EnableGamePadButton(false)
end
picker:EnableMouseWheel(true)
picker:SetScript("OnMouseWheel", function(_, delta) Press(delta > 0 and "UP" or "DOWN") end)

function M.StartPicker()
    if PF.InCombat() then return PF.Print("Pick after combat.") end
    if PF.Binds.FocusedFrame() then return PF.Binds.WaitForWindow() end
    if PF.Config and PF.Config.Hide then PF.Config.Hide() end
    chain, choice = {}, 1
    picker:Show()
    if picker.EnableGamePadButton then picker:EnableGamePadButton(true) end
    Draw()
end

PF.AddCommand("pick", function() M.StartPicker() end, "pick an element on screen to hide")
PF.AddCommand("center", function()
    local list = M.AtCenter()
    PF.Print("Named elements at the middle of the screen:" .. (#list == 0 and " none" or ""))
    for _, e in ipairs(list) do DEFAULT_CHAT_FRAME:AddMessage("  " .. e.name) end
    if #list > 0 then PF.Print("Hide one in /pf, Hide elements, or with /pf hide <name>.") end
end, "list elements in the middle of the screen")
PF.AddCommand("hide", function(name)
    if not name or name == "" then return PF.Print("/pf hide <frame name>") end
    if not Resolve(name) then return PF.Print("No frame named " .. name .. " (or it can't be hidden).") end
    local on = not M.IsHidden(name)
    M.SetHidden(name, on)
    PF.Print(name .. (on and " hidden." or " shown again."))
end, "<name>: hide or show a named element")
