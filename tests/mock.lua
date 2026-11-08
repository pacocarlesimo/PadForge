-- A small fake WoW client: enough of the API for PadForge to load, plus a
-- restricted-environment runner so secure snippets really execute.
-- luajit tests/run.lua
local M = {}
M.log = {}
M.now = 100
M.combat = false
M.inGame = true
M.pad = { buttons = {}, sticks = { [1] = { x = 0, y = 0 }, [2] = { x = 0, y = 0 } } }
M.events = {}       -- [event] = { frames }
M.frames = {}
M.timers = {}
M.cvars = { ActionButtonUseKeyDown = "1", GamePadStickAxisButtons = "0", GamePadRunThreshold = "0.5", GamePadCameraYawSpeed = "1" }
M.bindSeq = 0
M.bindings = {}     -- [key] = { seq, owner, kind, target }
M.performed = {}

local function noop() end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local Frame = {}
Frame.__index = function(t, k)
    local v = rawget(Frame, k)
    if v ~= nil then return v end
    -- (unknown methods are no-ops; plain fields stay nil)
    if type(k) == "string" and k:match("^%u") then return noop end
    return nil
end

local function NewObject(kind, name, parent)
    local o = setmetatable({ _kind = kind, _name = name, _parent = parent, _attrs = {}, _scripts = {}, _hooks = {},
        _shown = true, _events = {}, _wraps = {}, _text = "" }, Frame)
    return o
end

function Frame:GetObjectType() return self._kind end
function Frame:IsObjectType(t) return t == "Frame" or t == "Region" or t == self._kind end
function Frame:IsForbidden() return false end
function Frame:GetName() return self._name end
function Frame:GetParent() return self._parent end
function Frame:SetAttribute(k, v)
    if M.combat and self._protected and not M.secureContext then error("SetAttribute on protected frame in combat: " .. tostring(k)) end
    self._attrs[k] = v
    for _, h in ipairs(self._hooks.OnAttributeChanged or {}) do h(self, k, v) end
end
function Frame:GetAttribute(k) return self._attrs[k] end
function Frame:SetScript(s, fn) self._scripts[s] = fn end
function Frame:GetScript(s) return self._scripts[s] end
function Frame:HookScript(s, fn) self._hooks[s] = self._hooks[s] or {} table.insert(self._hooks[s], fn) end
function Frame:Fire(s, ...)
    local fn = self._scripts[s]
    if fn then fn(self, ...) end
    for _, h in ipairs(self._hooks[s] or {}) do h(self, ...) end
end
function Frame:Show()
    if self._shown then return end
    self._shown = true
    for _, w in ipairs(self._wraps.OnShow or {}) do M.RunSnippet(w, self, "OnShow") end
    self:Fire("OnShow")
end
function Frame:Hide()
    if not self._shown then return end
    self._shown = false
    for _, w in ipairs(self._wraps.OnHide or {}) do M.RunSnippet(w, self, "OnHide") end
    self:Fire("OnHide")
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:IsVisible()
    local f = self
    while f do
        if not f._shown then return false end
        f = f._parent
    end
    return true
end
function Frame:RegisterEvent(e)
    M.events[e] = M.events[e] or {}
    table.insert(M.events[e], self)
end
function Frame:UnregisterEvent() end
function Frame:CreateTexture() return NewObject("Texture", nil, self) end
function Frame:CreateMaskTexture() return NewObject("MaskTexture", nil, self) end
function Frame:CreateFontString() return NewObject("FontString", nil, self) end
function Frame:SetText(t) self._text = t end
function Frame:SetScale(v) self._scale = v end
function Frame:GetScale() return self._scale or 1 end
function Frame:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function Frame:EnableMouse(on) self._mouse = on end
function Frame:IsMouseEnabled() return self._mouse end
function Frame:GetText() return self._text end
function Frame:GetStringWidth() return 200 end
function Frame:GetFrameLevel() return 1 end
function Frame:GetHeight() return 400 end
function Frame:GetWidth() return 400 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetCenter() return 500, 400 end
function Frame:GetRect() return nil end
function Frame:IsEnabled() return true end
function Frame:CreateAnimationGroup()
    local g = NewObject("AnimationGroup", nil, self)
    g._anims = {}
    g._playing = false
    function g:CreateAnimation() local a = NewObject("Animation", nil, g) table.insert(g._anims, a) return a end
    function g:GetAnimations() return unpack(g._anims) end
    function g:Play() g._playing = true end
    function g:Stop() g._playing = false end
    function g:IsPlaying() return g._playing end
    return g
end
function Frame:SetPropagateKeyboardInput() end
M.keyboardTaken = {}
function Frame:EnableKeyboard(on) if on then M.keyboardTaken[#M.keyboardTaken + 1] = self._name or "?" end end

function M.CreateFrame(kind, name, parent, template)
    local o = NewObject(kind, name, parent)
    if template and template:find("Secure") then o._protected = true end
    if kind == "Frame" and template and template:find("SecureHandlerState") then o._state = true end
    if name then _G[name] = o end
    table.insert(M.frames, o)
    return o
end

---------------------------------------------------------------------------
-- Restricted environment
---------------------------------------------------------------------------
local function Handle(frame)
    if not frame then return nil end
    return frame
end

local function MakeEnv(self)
    local env = {
        ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, tonumber = tonumber, select = select,
        string = string, math = math, table = { insert = table.insert, remove = table.remove, concat = table.concat },
        newtable = function(...) return { ... } end,
        GetGamePadState = function() return M.pad end,
        PlayerInCombat = function() return M.combat end,
        SecureCmdOptionParse = function(s) return M.ParseCondition(s) end,
    }
    return env
end

-- extra methods only snippets get
function Frame:GetFrameRef(name) return self._refs and self._refs[name] end
function Frame:RunAttribute(name, ...)
    local body = self._attrs[name]
    assert(type(body) == "string", "RunAttribute: no body " .. tostring(name))
    return M.RunBody(body, self, "attr:" .. name, ...)
end
function Frame:SetBindingClick(prio, key, target, mouse)
    M.bindSeq = M.bindSeq + 1
    M.bindings[key] = M.bindings[key] or {}
    table.insert(M.bindings[key], { seq = M.bindSeq, owner = self, kind = "click", target = target, mouse = mouse })
end
function Frame:SetBinding(prio, key, cmd)
    M.bindSeq = M.bindSeq + 1
    M.bindings[key] = M.bindings[key] or {}
    table.insert(M.bindings[key], { seq = M.bindSeq, owner = self, kind = "command", target = cmd })
end
function Frame:ClearBindings() M.ClearOwner(self) end

M.compiled = {}
function M.Compile(body, params, where)
    local key = params .. "\0" .. body
    if M.compiled[key] then return M.compiled[key] end
    local src = "return function(" .. params .. ") " .. body .. "\nend"
    local chunk, err = loadstring(src, "=" .. (where or "snippet"))
    if not chunk then error("snippet syntax (" .. tostring(where) .. "): " .. err) end
    M.compiled[key] = chunk
    return chunk
end

function M.RunBody(body, self, where, ...)
    local chunk = M.Compile(body, "self, ...", where)
    setfenv(chunk, MakeEnv(self))
    local fn = chunk()
    local old = M.secureContext
    M.secureContext = true
    local r = { pcall(fn, self, ...) }
    M.secureContext = old
    if not r[1] then error("snippet error (" .. tostring(where) .. "): " .. tostring(r[2])) end
    return select(2, unpack(r))
end

function M.RunSnippet(w, frame, script, button, down)
    local chunk = M.Compile(w.body, "self, button, down", w.where)
    setfenv(chunk, MakeEnv(w.header))
    local fn = chunk()
    local old = M.secureContext
    M.secureContext = true
    local ok, r = pcall(fn, w.header, button, down)
    M.secureContext = old
    if not ok then error("snippet error (" .. tostring(w.where) .. "): " .. tostring(r)) end
    return r
end

function M.SecureHandlerWrapScript(frame, script, header, body)
    frame._wraps[script] = frame._wraps[script] or {}
    table.insert(frame._wraps[script], { header = header, body = body, where = (frame._name or "?") .. ":" .. script })
    M.Compile(body, "self, button, down", (frame._name or "?") .. ":" .. script)
end

function M.SecureHandlerSetFrameRef(frame, name, ref)
    frame._refs = frame._refs or {}
    frame._refs[name] = ref
end

function M.SecureHandlerExecute(frame, body)
    return M.RunBody(body, frame, (frame._name or "?") .. ":execute")
end

-- State drivers: [frame] = { name, cond }
M.drivers = {}
function M.RegisterStateDriver(frame, name, cond)
    M.drivers[frame] = { name = name, cond = cond }
    M.UpdateDriver(frame)
end
function M.UnregisterStateDriver(frame, name)
    M.drivers[frame] = nil
end
function M.UpdateDriver(frame)
    local d = M.drivers[frame]
    if not d then return end
    local value = M.ParseCondition(d.cond)
    if frame._attrs["state-" .. d.name] ~= value then
        frame._attrs["state-" .. d.name] = value
        local body = frame._attrs["_onstate-" .. d.name]
        if body then M.RunBody(body, frame, "onstate", d.name, value) end
    end
end
function M.UpdateDrivers() for f in pairs(M.drivers) do M.UpdateDriver(f) end end

-- "[harm,nodead] on; off": only the conditions PadForge uses
M.target = { harm = false, dead = false }
M.units = { player = { hp = 100, max = 100 } }
function M.ParseCondition(s)
    for clause in s:gmatch("[^;]+") do
        clause = clause:gsub("^%s+", "")
        local conds, value = clause:match("^(.-)%s*([%w]*)$")
        local ok = true
        if conds and conds:find("%[") then
            ok = false
            for group in conds:gmatch("%[(.-)%]") do
                local all = true
                local unit = group:match("@([%w]+)")
                for c in group:gmatch("[^,]+") do
                    if c:sub(1, 1) == "@" then
                        -- (the unit the rest of the group is about)
                    elseif c == "exists" then all = all and unit ~= nil and M.units[unit] ~= nil
                    elseif c == "nodead" and unit then all = all and M.units[unit] ~= nil and not M.units[unit].dead
                    elseif c == "harm" then all = all and M.target.harm
                    elseif c == "nodead" then all = all and not M.target.dead
                    elseif c == "combat" then all = all and M.combat
                    else all = false end
                end
                if all then ok = true end
            end
        end
        if ok then return value end
    end
end

---------------------------------------------------------------------------
-- Bindings and clicks
---------------------------------------------------------------------------
function M.SetOverrideBinding(owner, prio, key, cmd)
    if M.combat then error("SetOverrideBinding in combat") end
    M.bindSeq = M.bindSeq + 1
    M.bindings[key] = M.bindings[key] or {}
    table.insert(M.bindings[key], { seq = M.bindSeq, owner = owner, kind = "command", target = cmd })
end
function M.SetOverrideBindingClick(owner, prio, key, target, mouse)
    if M.combat then error("SetOverrideBindingClick in combat") end
    M.bindSeq = M.bindSeq + 1
    M.bindings[key] = M.bindings[key] or {}
    table.insert(M.bindings[key], { seq = M.bindSeq, owner = owner, kind = "click", target = target, mouse = mouse })
end
function M.ClearOwner(owner)
    for key, list in pairs(M.bindings) do
        for i = #list, 1, -1 do if list[i].owner == owner then table.remove(list, i) end end
    end
end
function M.ClearOverrideBindings(owner)
    if M.combat then error("ClearOverrideBindings in combat") end
    M.ClearOwner(owner)
end
-- The binding a key resolves to now (the latest set)
function M.Binding(key)
    local list = M.bindings[key]
    if not list or #list == 0 then return nil end
    local best
    for _, b in ipairs(list) do if not best or b.seq > best.seq then best = b end end
    return best
end

-- Clicks a secure button as a key press would
function M.Click(button, mouse, down)
    if type(button) == "string" then button = _G[button] end
    assert(button, "no button")
    for _, w in ipairs(button._wraps.OnClick or {}) do
        local r = M.RunSnippet(w, button, "OnClick", mouse, down)
        if r == false then return nil end
    end
    -- the template acts on its edge
    local onDown = button._attrs.useOnKeyDown
    if onDown == nil then onDown = M.cvars.ActionButtonUseKeyDown ~= "0" end
    if (down and true or false) ~= (onDown and true or false) then
        if button._scripts.OnClick and not button._protected then button._scripts.OnClick(button, mouse, down) end
        return nil
    end
    if button._protected then
        local a = button._attrs
        if not a.type then return nil end
        local rec = { type = a.type, spell = a.spell, item = a.item, macro = a.macro, macrotext = a.macrotext, unit = a.unit, button = button._name }
        table.insert(M.performed, rec)
        -- (a /click in a macro clicks that button too)
        if a.type == "macro" and a.macrotext then
            local target, m, d = a.macrotext:match("^/click (%S+)%s*(%S*)%s*(%S*)")
            if target and _G[target] and _G[target]._name ~= button._name then
                rec.clicked = target
            end
        end
        for _, h in ipairs(button._hooks.OnClick or {}) do h(button, mouse, down) end
        return rec
    end
    if button._scripts.OnClick then button._scripts.OnClick(button, mouse, down) end
    return true
end

-- A key press: the binding on it (a prefix-less key)
function M.Press(key, down)
    local b = M.Binding(key)
    if not b then return "native" end
    if b.kind == "command" then return "command:" .. b.target end
    return M.Click(b.target, b.mouse, down)
end

---------------------------------------------------------------------------
-- Events and time
---------------------------------------------------------------------------
function M.Fire(event, ...)
    for _, f in ipairs(M.events[event] or {}) do
        if f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

function M.Advance(seconds, step)
    step = step or 0.05
    local t = 0
    while t < seconds do
        M.now = M.now + step
        t = t + step
        local due = {}
        for i = #M.timers, 1, -1 do
            if M.timers[i].at <= M.now then table.insert(due, table.remove(M.timers, i)) end
        end
        for _, timer in ipairs(due) do timer.fn() end
        for _, f in ipairs(M.frames) do
            if f._scripts.OnUpdate and f:IsVisible() then f._scripts.OnUpdate(f, step) end
        end
    end
end

---------------------------------------------------------------------------
-- The game's globals
---------------------------------------------------------------------------
local BIND_KEYS = {
    GAMEPADACTIONBUTTON1 = "PADDLEFT", GAMEPADACTIONBUTTON2 = "PADDUP", GAMEPADACTIONBUTTON3 = "PADDRIGHT", GAMEPADACTIONBUTTON4 = "PADDDOWN",
    GAMEPADACTIONBUTTON5 = "PAD3", GAMEPADACTIONBUTTON6 = "PAD4", GAMEPADACTIONBUTTON7 = "PAD2", GAMEPADACTIONBUTTON8 = "PAD1",
    GAMEPADLEFTMOD = "PADLTRIGGER", GAMEPADRIGHTMOD = "PADRTRIGGER", TOGGLEAUTORUN = "PADLSTICK",
}
local KEY_BINDS = {}
for action, key in pairs(BIND_KEYS) do KEY_BINDS[key] = action end
M.KEY_BINDS = KEY_BINDS

local PAD_INDEX = { PAD1 = 0, PAD2 = 1, PAD3 = 2, PAD4 = 3, PADLSHOULDER = 4, PADRSHOULDER = 5, PADLTRIGGER = 6, PADRTRIGGER = 7,
    PADLSTICK = 8, PADRSTICK = 9, PADDUP = 10, PADDDOWN = 11, PADDLEFT = 12, PADDRIGHT = 13 }
M.PAD_INDEX = PAD_INDEX

function M.Hold(binding, on) M.pad.buttons[PAD_INDEX[binding] + 1] = on or nil end
function M.SetStick(x, y) M.pad.sticks[2].x, M.pad.sticks[2].y = x, y end

local SPELLS = { [133] = { "Fireball", 135812 }, [116] = { "Frostbolt", 135846 }, [10] = { "Blizzard", 135857 }, [1459] = { "Arcane Intellect", 135932 },
    [2136] = { "Fire Blast", 135807 }, [1953] = { "Blink", 135736 }, [122] = { "Frost Nova", 135848 }, [999] = { "Swift Mount", 132261 } }
M.book = { 133, 116, 10, 1459 }
local ITEMS = { [5350] = { "Conjured Water", 0, 5 }, [2512] = { "Rough Arrow", 2, 0 }, [858] = { "Lesser Healing Potion", 0, 1 },
    [7500] = { "Strange Book", 12, 0 }, [6948] = { "Hearthstone", 15, 0 } }
M.BAGS = { [0] = { 5350, 858, 7500, 6948 } }

function M.Install()
    _G.CreateFrame = M.CreateFrame
    _G.UIParent = M.CreateFrame("Frame", "UIParent")
    _G.WorldFrame = M.CreateFrame("Frame", "WorldFrame")
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(M.log, msg) end }
    _G.InCombatLockdown = function() return M.combat end
    _G.GetTime = function() return M.now end
    _G.time = os.time
    _G.date = os.date
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.geterrorhandler = function() return function(e) table.insert(M.log, "ERROR: " .. tostring(e)) end end
    _G.C_Timer = { After = function(d, fn) table.insert(M.timers, { at = M.now + d, fn = fn }) end }
    _G.C_AddOns = { GetAddOnMetadata = function() return "1.0.0-test" end, IsAddOnLoaded = function(n) return M.loaded and M.loaded[n] end }
    _G.SlashCmdList = {}
    _G.UnitName = function() return "Tester" end
    _G.GetRealmName = function() return "Realm" end
    _G.UnitClass = function() return "Mage", "MAGE" end
    _G.UnitExists = function(u) return u == "player" end
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return M.group end
    _G.GetBuildInfo = function() return "1.60.1", "12345", "Nov 1 2026", 16001 end
    _G.PlaySound = noop
    _G.SOUNDKIT = {}
    _G.Enum = { ItemClass = { Consumable = 0, Questitem = 12, Miscellaneous = 15 } }
    _G.C_CVar = {
        GetCVar = function(n) return M.cvars[n] end,
        SetCVar = function(n, v) M.cvars[n] = tostring(v) return true end,
        GetCVarDefault = function(n) return ({ GamePadRunThreshold = "0.5", GamePadCameraYawSpeed = "1" })[n] end,
    }
    _G.C_Console = { GetAllCommands = function() return { { command = "GamePadRunThreshold", commandType = 0 }, { command = "GamePadSomethingNew", commandType = 0 } } end }
    M.cvars.GamePadSomethingNew = "3"
    _G.GetBindingKey = function(action) return BIND_KEYS[action] end
    _G.GetBindingAction = function(key) return KEY_BINDS[key] or "" end
    _G.SetOverrideBinding = M.SetOverrideBinding
    _G.SetOverrideBindingClick = M.SetOverrideBindingClick
    _G.ClearOverrideBindings = M.ClearOverrideBindings
    _G.SecureHandlerWrapScript = M.SecureHandlerWrapScript
    _G.SecureHandlerSetFrameRef = M.SecureHandlerSetFrameRef
    _G.SecureHandlerExecute = M.SecureHandlerExecute
    _G.RegisterStateDriver = M.RegisterStateDriver
    _G.UnregisterStateDriver = M.UnregisterStateDriver
    M.desk = {}
    _G.IsKeyDown = function(k)
        if M.desk[k] then return true end
        return M.pad.buttons[(PAD_INDEX[k] or -9) + 1] and true or false
    end
    _G.C_GamePad = {
        ButtonBindingToIndex = function(b) return PAD_INDEX[b] end,
        StickConfigNameToIndex = function(n) return n == "Right" and 1 or 0 end,
        GetActiveDeviceID = function() return 1 end,
        GetDeviceMappedState = function() return { buttons = M.pad.buttons, sticks = M.pad.sticks, labelStyle = "Letters" } end,
    }
    _G.C_Texture = { GetAtlasInfo = function() return {} end }
    _G.GamepadSharedUtility = { InputBindingManager = { IsOnlyCoreBindingSetActive = function() return M.inGame end } }
    _G.GamepadMode = { FrameControlsManager = setmetatable({ focusedFrame = nil }, {
        __index = function(_, k) if k == "isUIFocused" then return not M.inGame end end }) }
    local bars = {}
    for _, bar in ipairs({ "topBar", "leftBar", "rightBar", "bottomBar" }) do
        local b = { Left = {}, Right = {} }
        for i = 1, 4 do
            b.Left["ActionButton" .. i] = M.CreateFrame("Button", "GP_" .. bar .. "_L" .. i)
            b.Right["ActionButton" .. i] = M.CreateFrame("Button", "GP_" .. bar .. "_R" .. i)
        end
        bars[bar] = b
    end
    _G.GamepadMainActionBarFrame = { PageUnit = { actionBars = bars } }
    _G.GetSpellInfo = function(id) local s = SPELLS[id] if s then return s[1], nil, s[2] end end
    _G.GetNumSpellTabs = function() return 1 end
    _G.GetSpellTabInfo = function() return "General", nil, 0, #M.book end
    _G.GetSpellBookItemInfo = function(i) return "SPELL", M.book[i] end
    _G.IsPassiveSpell = function() return false end
    _G.BOOKTYPE_SPELL = "spell"
    _G.C_Item = {
        GetItemInfo = function(id) return ITEMS[id] and ITEMS[id][1] end,
        GetItemIconByID = function() return 134400 end,
        GetItemInfoInstant = function(id) local i = ITEMS[id] if i then return id, nil, nil, "", 134400, i[2], i[3] end end,
        GetItemSpell = function(id) if id ~= 2512 then return "Use", 1 end end,
        GetItemCount = function() return 3 end,
    }
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return M.BAGS[bag] and #M.BAGS[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot) local id = M.BAGS[bag] and M.BAGS[bag][slot] if id then return { itemID = id } end end,
        GetContainerItemQuestInfo = function(bag, slot) local id = M.BAGS[bag][slot] return { isQuestItem = id == 7500, questID = id == 7500 and 123 or nil } end,
        GetItemCooldown = function() return 0, 0 end,
    }
    _G.GetInventoryItemID = function() return nil end
    _G.GetNumMacros = function() return 1, 0 end
    _G.GetMacroInfo = function(i) if i == 1 or i == "Pull" then return "Pull", 136377, "/cast Fireball" end end
    _G.GetMacroIndexByName = function(n) return n == "Pull" and 1 or 0 end
    _G.MAX_ACCOUNT_MACROS = 120
    _G.NUM_BAG_SLOTS = 4
    _G.STATICPOPUP_NUMDIALOGS = 4
    _G.StaticPopup_FindVisible = function(which)
        for i = 1, 4 do
            local f = _G["StaticPopup" .. i]
            if f and f._shown and f.which == which then return f end
        end
    end
    for i = 1, 4 do
        local f = M.CreateFrame("Frame", "StaticPopup" .. i)
        f._shown = false
        f.button1 = M.CreateFrame("Button", "StaticPopup" .. i .. "Button1", f)
        f.button2 = M.CreateFrame("Button", "StaticPopup" .. i .. "Button2", f)
        f.text = M.CreateFrame("FontString", nil, f)
    end
    _G.EnumerateFrames = function() return nil end
    _G.UISpecialFrames = {}
    _G.Minimap = M.CreateFrame("Frame", "Minimap")
    _G.UnitExists = function(u) return M.units[u] ~= nil end
    _G.UnitIsDeadOrGhost = function(u) return M.units[u] ~= nil and M.units[u].dead == true end
    _G.UnitHealth = function(u)
        local hp = M.units[u] and M.units[u].hp or 0
        if M.secretHealth then return M.Secret(hp) end
        return hp
    end
    _G.UnitHealthMax = function(u)
        local max = M.units[u] and M.units[u].max or 0
        if M.secretHealth then return M.Secret(max) end
        return max
    end
    _G.UnitName = function(u) return u == "player" and "Tester" or u end
    M.instance = "none"
    _G.IsInInstance = function() return M.instance ~= "none", M.instance end
    _G.GetNumGroupMembers = function() return 0 end
    _G.UnitThreatSituation = function() return M.threat or 0 end
    M.vibes = {}
    _G.C_GamePad.SetVibration = function(kind, v) table.insert(M.vibes, { kind, v }) end
    _G.C_GamePad.StopVibration = function() table.insert(M.vibes, { "stop" }) end
    _G.GetNumCompanions = function(kind) return kind == "MOUNT" and 1 or 0 end
    _G.GetCompanionInfo = function(kind, i) return 1, "Swift Mount", 999 end
    _G.GameTooltip = M.CreateFrame("Frame", "GameTooltip")
    _G.GetCVar = function(n) return M.cvars[n] end
    _G.Enum.InputDeviceInterfaceType = { KeyboardMouse = 0, Gamepad = 1 }
    M.cvars.InputDeviceInterfaceStyle = "1"
    M.cursor = { 0, 0 }
    _G.GetCursorPosition = function() return M.cursor[1], M.cursor[2] end
    M.keyboardFocus = nil
    _G.GetCurrentKeyBoardFocus = function() return M.keyboardFocus end
    _G.IsGamePadCursorControlEnabled = function() return false end
    -- Secret values: a table that errors on compare and arithmetic, as the
    -- real client does in combat
    local secretMT = {
        __lt = function() error("attempt to compare a secret number value") end,
        __le = function() error("attempt to compare a secret number value") end,
        __div = function() error("attempt to perform arithmetic on a secret number value") end,
        __mul = function() error("attempt to perform arithmetic on a secret number value") end,
        __concat = function() error("attempt to concatenate a secret value") end,
    }
    function M.Secret(v) return setmetatable({ secret = v }, secretMT) end
    _G.issecretvalue = function(v) return type(v) == "table" and getmetatable(v) == secretMT end
    M.reloads = 0
    _G.ReloadUI = function() M.reloads = M.reloads + 1 end
end

return M
