-- A simulated WoW Forever client for tests.
--
-- Unlike tests/mock.lua (small, forgiving, hand-written), this one is strict
-- and leans on the game's own files:
--   * widgets only have the methods the client's API documentation lists
--     for their type: a typo or a method from another client is an error;
--   * frame state lives behind frame[0], as in the real client, so the
--     game's own secure code (loaded by sim/game.lua) runs on it unchanged;
--   * it tracks who is running, the game or the addon ("taint"), and
--     records what the real client would block: protected changes from
--     addon code in combat, protected actions from addon code, and addon
--     code changing a frame the game owns;
--   * key presses go through a binding table with override bindings,
--     priorities and the trigger modifiers (LT = SHIFT, RT = CTRL), then
--     into the game's real SecureActionButton / SecureHandler code.
--
-- What it can't do: follow taint through values (a tainted field read by
-- the game), or know C-side details that aren't in the UI source. Those
-- stay for the in-game self test (/pf selftest).
local S = {}
local Docs = require("sim.docs")

S.now = 1000
S.combat = false
S.taint = nil            -- nil: the game is running; else the addon's name
S.blocked = {}           -- what the client would have blocked
S.violations = {}        -- ground rules broken (addon changing game frames...)
S.errors = {}            -- Lua errors (the game's error handler)
S.performed = {}         -- protected actions that went through
S.chat = {}              -- chat frame lines
S.timers = {}
S.frames = {}
S.state = setmetatable({}, { __mode = "k" })
S.held = {}
S.cvars = {}
S.unknownEvents = {}

local unpack, select, type, pairs, ipairs = unpack, select, type, pairs, ipairs
local function pack(...) return { n = select("#", ...), ... } end

---------------------------------------------------------------------------
-- Who is running
---------------------------------------------------------------------------
function S.IsAddonFn(fn)
    return type(fn) == "function" and S.addonEnv ~= nil and getfenv(fn) == S.addonEnv
end

function S.Error(err)
    S.errors[#S.errors + 1] = tostring(err)
end

function S.Blocked(what)
    S.blocked[#S.blocked + 1] = what .. (S.combat and " (in combat)" or "")
end

function S.Violation(what)
    S.violations[#S.violations + 1] = what
end

-- Calls fn as the client calls a script handler: an addon's function
-- runs tainted, one of the game's runs secure whoever caused it (which is
-- how the game's attribute handlers do secure work for addon code).
-- Errors go to the error handler and don't stop the caller.
function S.Call(fn, ...)
    if type(fn) ~= "function" then return end
    local prev = S.taint
    S.taint = S.IsAddonFn(fn) and (S.addonName or "addon") or nil
    local r = pack(xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end, ...))
    S.taint = prev
    if not r[1] then
        S.Error(r[2])
        return
    end
    return unpack(r, 2, r.n)
end

-- The game doing something (a test driving the client): never tainted
function S.AsGame(fn, ...)
    local prev = S.taint
    S.taint = nil
    local r = pack(fn(...))
    S.taint = prev
    return unpack(r, 1, r.n)
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local BASE = { "SimpleFrameScriptObjectAPI", "SimpleObjectAPI" }
local REGION = { "SimpleFrameScriptObjectAPI", "SimpleObjectAPI", "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI",
    "SimpleAnimatableObjectAPI" }
local function chain(base, ...)
    local out = {}
    for _, n in ipairs(base) do out[#out + 1] = n end
    for _, n in ipairs({ ... }) do out[#out + 1] = n end
    return out
end
local FRAME = chain(REGION, "SimpleFrameAPI")
local LAYERED = chain(REGION, "SimpleRegionAPI")
S.CHAINS = {
    Frame = FRAME,
    Button = chain(FRAME, "SimpleButtonAPI"),
    CheckButton = chain(FRAME, "SimpleButtonAPI", "SimpleCheckboxAPI"),
    EditBox = chain(FRAME, "SimpleEditBoxAPI", "SimpleFontAPI"),
    ScrollFrame = chain(FRAME, "SimpleScrollFrameAPI"),
    Slider = chain(FRAME, "SimpleSliderAPI"),
    StatusBar = chain(FRAME, "SimpleStatusBarAPI"),
    Cooldown = chain(FRAME, "FrameAPICooldown"),
    GameTooltip = chain(FRAME, "FrameAPITooltip"),
    Texture = chain(LAYERED, "SimpleTextureBaseAPI", "SimpleTextureAPI"),
    MaskTexture = chain(LAYERED, "SimpleTextureBaseAPI", "SimpleMaskTextureAPI"),
    FontString = chain(LAYERED, "SimpleFontStringAPI", "SimpleFontAPI"),
    AnimationGroup = chain(BASE, "SimpleAnimGroupAPI"),
    Animation = chain(BASE, "SimpleAnimAPI"),
    Alpha = chain(BASE, "SimpleAnimAPI", "SimpleAnimAlphaAPI"),
}
local IS_FRAME = { Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, Slider = true,
    StatusBar = true, Cooldown = true, GameTooltip = true }

-- Changing these on a protected frame is protected in combat
local PROTECTED_CHANGE = { Show = true, Hide = true, SetShown = true, SetPoint = true, SetAllPoints = true, ClearAllPoints = true,
    ClearPoint = true, SetSize = true, SetWidth = true, SetHeight = true, SetScale = true, SetParent = true, SetAttribute = true,
    SetAttributeNoHandler = true, EnableMouse = true, SetFrameStrata = true, SetFrameLevel = true, SetID = true,
    EnableGamePadButton = true, EnableGamePadStick = true, EnableKeyboard = true, SetPropagateKeyboardInput = true }

local function IsMutator(name)
    return name == "Show" or name == "Hide" or name == "Click" or name:find("^Set") or name:find("^Clear") or name:find("^Enable")
        or name:find("^Disable") or name:find("^Register") or name:find("^Unregister") or name:find("^Raise") or name:find("^Lower")
        or name:find("^Start") or name:find("^Stop") or name:find("^Lock") or name:find("^Unlock")
end

local function st(self) return S.state[self[0]] end
S.St = st

local IMPL = {}

function IMPL.GetName(self) return st(self).name end
function IMPL.GetDebugName(self) return st(self).name or st(self).kind end
function IMPL.GetObjectType(self) return st(self).kind end
function IMPL.IsObjectType(self, t)
    local kind = st(self).kind
    if t == kind then return true end
    if t == "Region" or t == "ScriptRegion" or t == "Object" then return true end
    if t == "Frame" then return IS_FRAME[kind] or false end
    if t == "Button" then return kind == "Button" or kind == "CheckButton" end
    return false
end
function IMPL.IsForbidden() return false end
function IMPL.HasAccessConstraints() return false end
function IMPL.HasAnyForbiddenAspects() return false end
function IMPL.HasSecretValues() return false end
function IMPL.IsProtected(self) local p = st(self).protected and true or false return p, p end
function IMPL.GetParent(self) return st(self).parent end
function IMPL.SetParent(self, p) st(self).parent = p end
function IMPL.GetID(self) return st(self).id or 0 end
function IMPL.SetID(self, id) st(self).id = id end

function IMPL.IsShown(self) return st(self).shown end
function IMPL.IsVisible(self)
    local o = self
    while o do
        local s = S.state[o[0]]
        if not s or not s.shown then return false end
        o = s.parent
    end
    return true
end
local function SetShown(self, shown)
    local s = st(self)
    shown = shown and true or false
    if s.shown == shown then return end
    s.shown = shown
    S.Run(s.obj, shown and "OnShow" or "OnHide")
end
function IMPL.Show(self) SetShown(self, true) end
function IMPL.Hide(self) SetShown(self, false) end
function IMPL.SetShown(self, v) SetShown(self, v) end

function IMPL.SetScript(self, name, fn) st(self).scripts[name] = fn end
function IMPL.GetScript(self, name) return st(self).scripts[name] end
function IMPL.HasScript() return true end
function IMPL.HookScript(self, name, fn)
    local s = st(self)
    local old = s.scripts[name]
    s.scripts[name] = function(...)
        if old then S.Call(old, ...) end
        S.Call(fn, ...)
    end
end

-- GetAttribute(name) or GetAttribute(prefix, name, suffix): the modified
-- lookup secure buttons use
function IMPL.GetAttribute(self, a, b, c)
    local attrs = st(self).attrs
    if b == nil then return attrs[a] end
    local prefix, name, suffix = a or "", b, c or ""
    local v = attrs[prefix .. name .. suffix]
    if v == nil then v = attrs["*" .. name .. suffix] end
    if v == nil then v = attrs[prefix .. name .. "*"] end
    if v == nil then v = attrs["*" .. name .. "*"] end
    if v == nil then v = attrs[name] end
    return v
end
function IMPL.SetAttribute(self, name, value)
    local s = st(self)
    s.attrs[name] = value
    S.Run(s.obj, "OnAttributeChanged", name, value)
end
function IMPL.SetAttributeNoHandler(self, name, value) st(self).attrs[name] = value end

function IMPL.RegisterEvent(self, event)
    if S.docs and not S.docs.events[event] then
        S.unknownEvents[event] = true
        error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
    end
    S.events[event] = S.events[event] or {}
    S.events[event][self[0]] = st(self).obj
    return true
end
function IMPL.RegisterUnitEvent(self, event) return IMPL.RegisterEvent(self, event) end
function IMPL.UnregisterEvent(self, event) if S.events[event] then S.events[event][self[0]] = nil end end
function IMPL.UnregisterAllEvents(self) for _, list in pairs(S.events) do list[self[0]] = nil end end
function IMPL.IsEventRegistered(self, event) return S.events[event] ~= nil and S.events[event][self[0]] ~= nil end

local function Child(kind)
    return function(self, name) return S.NewObject(kind, name, st(self).obj) end
end
IMPL.CreateTexture = Child("Texture")
IMPL.CreateMaskTexture = Child("MaskTexture")
function IMPL.CreateFontString(self, name, _, inherits)
    if inherits and S.fonts and not S.fonts[inherits] then
        error("CreateFontString: no font object named " .. tostring(inherits), 2)
    end
    return S.NewObject("FontString", name, st(self).obj)
end
function IMPL.SetFontObject(self, font)
    if type(font) == "string" and S.fonts and not S.fonts[font] then
        error("SetFontObject: no font object named " .. font, 2)
    end
    st(self).vals.FontObject = font
end
function IMPL.CreateAnimationGroup(self, name)
    local g = S.NewObject("AnimationGroup", name, st(self).obj)
    st(g).anims = {}
    return g
end
function IMPL.CreateAnimation(self, kind, name)
    local a = S.NewObject(kind == "Alpha" and "Alpha" or "Animation", name, st(self).obj)
    table.insert(st(self).anims, a)
    return a
end
function IMPL.GetAnimations(self) return unpack(st(self).anims) end
function IMPL.Play(self) st(self).playing = true end
function IMPL.Stop(self) st(self).playing = false end
function IMPL.IsPlaying(self) return st(self).playing or false end
function IMPL.SetTarget(self, target) st(self).target = target end
function IMPL.GetTarget(self) return st(self).target end

function IMPL.SetText(self, text) st(self).text = text == nil and "" or tostring(text) end
function IMPL.GetText(self) return st(self).text or "" end
function IMPL.GetStringWidth(self) return 7 * #((st(self).text or ""):gsub("|A.-|a", "MM"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
function IMPL.GetStringHeight() return 12 end
function IMPL.SetSize(self, w, h) local s = st(self) s.w, s.h = w, h end
function IMPL.SetWidth(self, w) st(self).w = w end
function IMPL.SetHeight(self, h) st(self).h = h end
function IMPL.GetWidth(self) return st(self).w or 0 end
function IMPL.GetHeight(self) return st(self).h or 0 end
function IMPL.GetSize(self) return st(self).w or 0, st(self).h or 0 end
function IMPL.SetScale(self, v) st(self).scale = v end
function IMPL.GetScale(self) return st(self).scale or 1 end
function IMPL.GetEffectiveScale(self) return st(self).scale or 1 end
function IMPL.SetPoint(self, ...) local s = st(self) s.points[#s.points + 1] = { ... } end
function IMPL.ClearAllPoints(self) st(self).points = {} end
function IMPL.SetAllPoints(self, to) st(self).points = { { "ALL", to } } end
function IMPL.GetNumPoints(self) return #st(self).points end
function IMPL.GetCenter(self)
    local s = st(self)
    if s.center then return s.center[1], s.center[2] end
    return 960, 540
end
function IMPL.GetRect(self)
    local s = st(self)
    if not s.rect then return nil end
    return unpack(s.rect)
end
function IMPL.GetFrameLevel(self) return st(self).vals.FrameLevel and st(self).vals.FrameLevel[1] or 1 end
function IMPL.SetAlpha(self, a) st(self).alpha = a end
function IMPL.GetAlpha(self) return st(self).alpha or 1 end

function IMPL.Enable(self) st(self).enabled = true end
function IMPL.Disable(self) st(self).enabled = false end
function IMPL.SetEnabled(self, on) st(self).enabled = on and true or false end
function IMPL.IsEnabled(self) return st(self).enabled end
function IMPL.RegisterForClicks(self, ...)
    local clicks = {}
    for i = 1, select("#", ...) do clicks[(select(i, ...))] = true end
    st(self).clicks = clicks
end
function IMPL.Click(self, mouse, down)
    local s = st(self)
    if not s.enabled then return end
    S.ClickScripts(s.obj, mouse or "LeftButton", down and true or false)
end
function IMPL.EnableGamePadButton(self, on) st(self).padButtons = on ~= false end
function IMPL.EnableGamePadStick(self, on) st(self).padStick = on ~= false end
function IMPL.SetCooldown(self, start, duration) st(self).cooldown = { start, duration } end
function IMPL.Clear(self) st(self).cooldown = nil end
function IMPL.GetChildren() return end

-- Documented methods without an implementation above: setters store,
-- getters return what was stored, the rest do nothing
local function Generic(name)
    local set = name:match("^Set(.+)$")
    if set then return function(self, ...) st(self).vals[set] = { ... } end end
    local get = name:match("^Get(.+)$")
    if get then
        return function(self)
            local v = st(self).vals[get]
            if v then return unpack(v) end
        end
    end
    local is = name:match("^Is(.+)$") or name:match("^Has(.+)$") or name:match("^Can(.+)$")
    if is then
        return function(self)
            local v = st(self).vals[is] or st(self).vals[is:gsub("Enabled$", "")]
            return v and v[1] and true or false
        end
    end
    local en = name:match("^Enable(.+)$")
    if en then return function(self, on) st(self).vals[en] = { on ~= false } end end
    return function() end
end

local function Guarded(name, impl)
    local mutator = IsMutator(name)
    local protectedChange = PROTECTED_CHANGE[name]
    return function(self, ...)
        if S.taint and mutator then
            local s = S.state[self[0]]
            if s then
                if protectedChange and s.protected and S.combat then
                    S.Blocked((s.name or s.kind) .. ":" .. name .. "()")
                    return
                end
                -- (straight from addon code: the game's own secure API
                -- working on its frames for the addon is the allowed way)
                local caller = s.game and not s.shared and debug.getinfo(2, "f")
                if caller and S.IsAddonFn(caller.func) then
                    S.Violation("addon code called " .. (s.name or s.kind) .. ":" .. name .. "() on a frame the game owns")
                end
            end
        end
        return impl(self, ...)
    end
end

-- Methods the documentation doesn't list but the client has
local UNDOCUMENTED = {
    Frame = { "SetAttributeNoHandler" },
}

S.meta = {}
function S.BuildWidgets(docs)
    S.docs = docs
    for kind, apis in pairs(S.CHAINS) do
        local methods = {}
        for _, api in ipairs(apis) do
            local set = docs.widget[api]
            if not set then error("no widget documentation named " .. api) end
            for name in pairs(set) do
                methods[name] = Guarded(name, IMPL[name] or Generic(name))
            end
        end
        if IS_FRAME[kind] then
            for _, name in ipairs(UNDOCUMENTED.Frame) do methods[name] = Guarded(name, IMPL[name]) end
        end
        S.meta[kind] = { __index = methods }
    end
end

function S.NewObject(kind, name, parent)
    -- (frame types are not case sensitive)
    for known in pairs(S.meta) do
        if known:lower() == tostring(kind):lower() then kind = known end
    end
    local meta = S.meta[kind]
    if not meta then error("CreateFrame: unknown frame type " .. tostring(kind), 3) end
    local ud = newproxy()
    local obj = setmetatable({ [0] = ud }, meta)
    S.state[ud] = { kind = kind, name = name, parent = parent, shown = true, attrs = {}, scripts = {}, vals = {}, points = {},
        enabled = true, clicks = { AnyUp = true }, obj = obj, game = S.taint == nil, text = "" }
    if IS_FRAME[kind] then S.frames[#S.frames + 1] = obj end
    if name and (IS_FRAME[kind] or S.taint == nil) then _G[name] = obj end
    return obj
end

-- Templates: what each sets up (the XML the client reads)
S.templates = {
    SecureFrameTemplate = function(f) st(f).protected = true end,
    SecureActionButtonTemplate = function(f)
        st(f).protected = true
        st(f).scripts.OnClick = SecureActionButton_OnClick
    end,
    SecureHandlerBaseTemplate = function(f)
        st(f).protected = true
        SecureHandler_OnLoad(f)
    end,
    SecureHandlerStateTemplate = function(f)
        st(f).protected = true
        SecureHandler_OnLoad(f)
        st(f).scripts.OnAttributeChanged = SecureHandler_StateOnAttributeChanged
    end,
    SecureHandlerAttributeTemplate = function(f)
        st(f).protected = true
        SecureHandler_OnLoad(f)
        st(f).scripts.OnAttributeChanged = SecureHandler_AttributeOnAttributeChanged
    end,
    CooldownFrameTemplate = function() end,
    UIPanelCloseButton = function() end,
    UIPanelButtonTemplate = function() end,
    UIPanelScrollFrameTemplate = function(f) f.ScrollBar = S.NewObject("Slider", nil, f) end,
    BackdropTemplate = function() end,
}

function S.CreateFrame(kind, name, parent, template, id)
    if type(kind) ~= "string" then error("CreateFrame: frame type expected", 2) end
    if S.taint and name and _G[name] ~= nil then
        S.Violation("addon frame name " .. name .. " overwrites an existing global")
    end
    local f = S.NewObject(kind, name, parent)
    if id then st(f).id = id end
    if template then
        for t in template:gmatch("[^,%s]+") do
            local apply = S.templates[t]
            if not apply then error("CreateFrame: unknown template " .. t, 2) end
            S.AsGame(apply, f)
        end
    end
    return f
end

function S.Run(obj, script, ...)
    local fn = S.state[obj[0]].scripts[script]
    if fn then return S.Call(fn, obj, ...) end
end

function S.ClickScripts(obj, mouse, down)
    S.Run(obj, "PreClick", mouse, down)
    S.Run(obj, "OnClick", mouse, down)
    S.Run(obj, "PostClick", mouse, down)
end

---------------------------------------------------------------------------
-- Events and time
---------------------------------------------------------------------------
S.events = {}

function S.Fire(event, ...)
    local list = {}
    for _, obj in pairs(S.events[event] or {}) do list[#list + 1] = obj end
    table.sort(list, function(a, b) return tostring(a[0]) < tostring(b[0]) end)
    for _, obj in ipairs(list) do S.AsGame(S.Run, obj, "OnEvent", event, ...) end
end

function S.Advance(seconds, step)
    step = step or 0.05
    local t = 0
    while t < seconds - 1e-9 do
        S.now = S.now + step
        t = t + step
        local due = {}
        for i = #S.timers, 1, -1 do
            if S.timers[i].at <= S.now + 1e-9 then table.insert(due, 1, table.remove(S.timers, i)) end
        end
        for _, timer in ipairs(due) do
            if not timer.cancelled then
                if timer.noArgs then S.AsGame(S.Call, timer.fn) else S.AsGame(S.Call, timer.fn, timer) end
                if timer.every and not timer.cancelled then
                    timer.at = S.now + timer.every
                    S.timers[#S.timers + 1] = timer
                end
            end
        end
        for _, obj in ipairs(S.frames) do
            local s = S.state[obj[0]]
            if s.scripts.OnUpdate and obj:IsVisible() then S.AsGame(S.Run, obj, "OnUpdate", step) end
        end
    end
end

function S.EnterCombat()
    -- (the event comes just before the lockdown)
    S.Fire("PLAYER_REGEN_DISABLED")
    S.combat = true
end

function S.LeaveCombat()
    S.combat = false
    S.Fire("PLAYER_REGEN_ENABLED")
end

---------------------------------------------------------------------------
-- Bindings
---------------------------------------------------------------------------
S.keybinds = {}      -- [key] = command (the client's own bindings)
S.overrides = {}     -- { owner, priority, key, kind, target, mouse, seq }
S.commands = {}      -- [command] = function(down) (the game's Bindings.xml)
S.seq = 0

local function BindingsLocked(what)
    if S.combat and S.taint then
        S.Blocked(what)
        return true
    end
end

local function RemoveOverride(owner, key)
    for i = #S.overrides, 1, -1 do
        local o = S.overrides[i]
        if o.owner[0] == owner[0] and (key == nil or o.key == key) then table.remove(S.overrides, i) end
    end
end

local function AddOverride(owner, priority, key, kind, target, mouse)
    if type(owner) ~= "table" or not S.state[owner[0]] then error("override binding: owner frame expected", 3) end
    if type(key) ~= "string" then error("override binding: key expected", 3) end
    RemoveOverride(owner, key)
    if target == nil or target == "" then return end
    S.seq = S.seq + 1
    S.overrides[#S.overrides + 1] = { owner = owner, priority = priority and true or false, key = key, kind = kind,
        target = target, mouse = mouse, seq = S.seq }
end

function S.SetOverrideBinding(owner, priority, key, command)
    if BindingsLocked("SetOverrideBinding()") then return end
    AddOverride(owner, priority, key, "command", command)
end
function S.SetOverrideBindingClick(owner, priority, key, button, mouse)
    if BindingsLocked("SetOverrideBindingClick()") then return end
    AddOverride(owner, priority, key, "click", button, mouse or "LeftButton")
end
function S.ClearOverrideBindings(owner)
    if BindingsLocked("ClearOverrideBindings()") then return end
    RemoveOverride(owner)
end

-- The binding a key string resolves to: priority overrides, then
-- overrides (the latest set wins among equals), then the client's own
function S.Resolve(key)
    local best
    for _, o in ipairs(S.overrides) do
        if o.key == key then
            if not best or (o.priority and not best.priority) or (o.priority == best.priority and o.seq > best.seq) then best = o end
        end
    end
    if best then return best end
    if S.keybinds[key] then return { kind = "command", target = S.keybinds[key], key = key, native = true } end
end

-- LT is SHIFT and RT is CTRL to the binding system on this client
-- (GAMEPAD_MOD_LEFT / GAMEPAD_MOD_RIGHT in the game's GamepadConstants)
function S.ModPrefix(except)
    local p = ""
    if S.held.PADRTRIGGER and except ~= "PADRTRIGGER" then p = p .. "CTRL-" end
    if S.held.PADLTRIGGER and except ~= "PADLTRIGGER" then p = p .. "SHIFT-" end
    return p
end

local function Route(binding)
    if not binding then return "nothing" end
    return binding.kind .. ":" .. tostring(binding.target)
end

local function RunBinding(binding, down)
    if not binding then return end
    if binding.kind == "command" then
        local fn = S.commands[binding.target]
        if fn then
            S.AsGame(fn, down)
        elseif down then
            S.performed[#S.performed + 1] = { command = binding.target }
        end
        return
    end
    local button = _G[binding.target]
    if type(button) ~= "table" or not S.state[button[0]] then return end
    local s = S.state[button[0]]
    if not s.enabled then return end
    local c = s.clicks
    local registered = down and (c.AnyDown or c[binding.mouse .. "Down"]) or (not down and (c.AnyUp or c[binding.mouse .. "Up"]))
    if registered then S.AsGame(S.ClickScripts, s.obj, binding.mouse, down) end
end

-- A shown frame that asked for the pad's buttons gets them before any
-- binding does (the latest made first)
local function PadCatcher()
    for i = #S.frames, 1, -1 do
        local obj = S.frames[i]
        local s = S.state[obj[0]]
        if s.padButtons and (s.scripts.OnGamePadButtonDown or s.scripts.OnGamePadButtonUp) and obj:IsVisible() then return obj end
    end
end

S.downBinding = {}
-- A pad button going down / up. Returns where the press went:
-- "command:JUMP", "click:PadForgeKey_PAD1", "frame:<name>" or "nothing"
function S.Press(key)
    S.held[key] = true
    if S.padIndex[key] then S.pad.buttons[S.padIndex[key] + 1] = true end
    local catcher = PadCatcher()
    if catcher then
        S.downBinding[key] = { catcher = catcher }
        S.AsGame(S.Run, catcher, "OnGamePadButtonDown", key)
        return "frame:" .. tostring(catcher:GetName())
    end
    local full = S.ModPrefix(key) .. key
    local binding = S.Resolve(full) or S.Resolve(key)
    S.downBinding[key] = binding
    RunBinding(binding, true)
    if key == "PADLTRIGGER" or key == "PADRTRIGGER" then S.Fire("MODIFIER_STATE_CHANGED", key, 1) end
    return Route(binding)
end
function S.Release(key)
    S.held[key] = nil
    if S.padIndex[key] then S.pad.buttons[S.padIndex[key] + 1] = false end
    local binding = S.downBinding[key]
    S.downBinding[key] = nil
    if binding and binding.catcher then
        S.AsGame(S.Run, binding.catcher, "OnGamePadButtonUp", key)
        return "frame:" .. tostring(binding.catcher:GetName())
    end
    RunBinding(binding, false)
    if key == "PADLTRIGGER" or key == "PADRTRIGGER" then S.Fire("MODIFIER_STATE_CHANGED", key, 0) end
    return Route(binding)
end
function S.Tap(key)
    local route = S.Press(key)
    S.Release(key)
    return route
end
-- Where a press of key would go right now, without pressing it
function S.RouteOf(key)
    local catcher = PadCatcher()
    if catcher then return "frame:" .. tostring(catcher:GetName()) end
    return Route(S.Resolve(S.ModPrefix(key) .. key) or S.Resolve(key))
end

-- The right stick (and the "Camera" one that follows it), or "Left"
function S.SetStick(x, y, which)
    for i, name in pairs(S.stickNames) do
        local right = name == "Right" or name == "Camera"
        if (which == "Left") ~= right then
            local stick = S.pad.sticks[i + 1]
            stick.x, stick.y, stick.len = x, y, math.sqrt(x * x + y * y)
        end
    end
end

---------------------------------------------------------------------------
-- Macro conditions and protected actions
---------------------------------------------------------------------------
S.units = { player = { hp = 100, max = 100, name = "Tester" } }

local function UnitOf(token)
    return S.units[token]
end

local function Condition(c, unit)
    local u = UnitOf(unit)
    if c == "exists" then return u ~= nil end
    if c == "harm" then return u ~= nil and u.harm == true end
    if c == "help" then return u ~= nil and not u.harm end
    if c == "dead" then return u ~= nil and u.dead == true end
    if c == "nodead" then return u ~= nil and not u.dead end
    if c == "combat" then return S.combat end
    if c == "nocombat" then return not S.combat end
    error("macro condition not modelled: " .. c)
end

-- SecureCmdOptionParse: the first clause whose conditions hold
function S.OptionParse(text)
    for clause in (text .. ";"):gmatch("([^;]*);") do
        local rest, ok, target = clause, nil, nil
        local sawGroup = false
        while true do
            local group, after = rest:match("^%s*%[([^%]]*)%](.*)$")
            if not group then break end
            sawGroup = true
            rest = after
            if not ok then
                local unit, all = "target", true
                local conds = {}
                for c in group:gmatch("[^,]+") do
                    c = c:gsub("^%s+", ""):gsub("%s+$", "")
                    local u = c:match("^@(.+)$") or c:match("^target=(.+)$")
                    if u then unit = u elseif c ~= "" then conds[#conds + 1] = c end
                end
                for _, c in ipairs(conds) do all = all and Condition(c, unit) end
                if all then
                    ok = true
                    target = group:find("@") and unit or (group:find("target=") and unit or nil)
                end
            end
        end
        if ok or not sawGroup then
            return (rest:gsub("^%s+", ""):gsub("%s+$", "")), target
        end
    end
end

-- A protected action: goes through only for the game's own code
function S.Protected(what, record)
    if S.taint then
        S.Blocked(what)
        return false
    end
    if record then S.performed[#S.performed + 1] = record end
    return true
end

S.dangerousScriptsAllowed = false
S.slash = {}

local CHAT = { s = "SAY", say = "SAY", p = "PARTY", party = "PARTY", ra = "RAID", raid = "RAID", y = "YELL", yell = "YELL",
    g = "GUILD", guild = "GUILD" }

function S.RunMacroLine(line)
    local cmd, rest = line:match("^/(%S+)%s*(.*)$")
    if not cmd then return end
    cmd = cmd:lower()
    if cmd == "click" then
        local action = S.OptionParse(rest)
        if action and action ~= "" then
            local name, mouse, down = action:match("([^%s]+)%s+([^%s]+)%s*(.*)")
            if not name then name = action end
            mouse = mouse or "LeftButton"
            down = (down or ""):lower() == "true" or down == "1"
            local button = _G[name]
            if type(button) == "table" and S.state[button[0]] and button:IsObjectType("Button") then
                button:Click(mouse, down)
            else
                S.performed[#S.performed + 1] = { missingClick = name }
            end
        end
    elseif cmd == "cast" or cmd == "use" then
        local spell, target = S.OptionParse(rest)
        if spell and spell ~= "" then S.Protected("/cast", { cast = spell, unit = target }) end
    elseif CHAT[cmd] then
        S.performed[#S.performed + 1] = { say = rest, channel = CHAT[cmd] }
    elseif cmd == "tm" or cmd == "targetmarker" then
        local marker, target = S.OptionParse(rest)
        S.performed[#S.performed + 1] = { marker = tonumber(marker), unit = target or "target" }
    elseif cmd == "run" or cmd == "script" then
        if not S.dangerousScriptsAllowed then
            -- (the client asks first, and runs nothing)
            S.performed[#S.performed + 1] = { popup = "DANGEROUS_SCRIPTS_WARNING" }
            return
        end
        local chunk = loadstring(rest)
        if chunk then
            local prev = S.taint
            S.taint = "macro"
            local ok, err = pcall(chunk)
            S.taint = prev
            if not ok then S.Error(err) end
        end
    elseif S.slash[cmd] then
        S.slash[cmd](rest)
    else
        S.performed[#S.performed + 1] = { emote = cmd:upper() }
    end
end

function S.RunMacroText(text)
    if not S.Protected("RunMacroText()") then return end
    for line in (text or ""):gmatch("[^\r\n]+") do S.RunMacroLine(line) end
end

---------------------------------------------------------------------------
-- Globals of the client (the C side)
---------------------------------------------------------------------------
S.padIndex = { PAD1 = 0, PAD2 = 1, PAD3 = 2, PAD4 = 3, PADLSHOULDER = 4, PADRSHOULDER = 5, PADLTRIGGER = 6, PADRTRIGGER = 7,
    PADLSTICK = 8, PADRSTICK = 9, PADDUP = 10, PADDDOWN = 11, PADDLEFT = 12, PADDRIGHT = 13, PADBACK = 14, PADFORWARD = 15,
    PADSOCIAL = 16, PADPADDLE1 = 17, PADPADDLE2 = 18, PADPADDLE3 = 19, PADPADDLE4 = 20 }
S.stickNames = { [0] = "Left", [1] = "Right", [2] = "Movement", [3] = "Camera" }
S.pad = { name = "Sim Pad", labelStyle = "Letters", buttons = {}, axes = {}, buttonCount = 21, axisCount = 6, stickCount = 4,
    sticks = { { x = 0, y = 0, len = 0 }, { x = 0, y = 0, len = 0 }, { x = 0, y = 0, len = 0 }, { x = 0, y = 0, len = 0 } } }
S.padConnected = true

local secretMT = {
    __lt = function() error("attempt to compare a secret value") end,
    __le = function() error("attempt to compare a secret value") end,
    __eq = function() error("attempt to compare a secret value") end,
    __add = function() error("attempt to perform arithmetic on a secret value") end,
    __sub = function() error("attempt to perform arithmetic on a secret value") end,
    __div = function() error("attempt to perform arithmetic on a secret value") end,
    __mul = function() error("attempt to perform arithmetic on a secret value") end,
    __concat = function() error("attempt to concatenate a secret value") end,
    __index = function() error("attempt to index a secret value") end,
    __tostring = function() error("attempt to convert a secret value") end,
}
function S.Secret(v) return setmetatable({ secret = v }, secretMT) end

function S.InstallBase()
    local G = _G
    G.CreateFrame = S.CreateFrame
    G.GetTime = function() return S.now end
    G.time, G.date = os.time, os.date
    G.InCombatLockdown = function() return S.combat end
    G.issecure = function() return S.taint == nil end
    G.forceinsecure = function() S.taint = S.taint or "insecure" end
    G.issecretvalue = function(v) return type(v) == "table" and getmetatable(v) == secretMT end
    G.canaccessvalue = function(v) return not G.issecretvalue(v) or S.taint == nil end
    G.scrub = function(...)
        local r = pack(...)
        for i = 1, r.n do
            local t = type(r[i])
            if t ~= "string" and t ~= "number" and t ~= "boolean" then r[i] = nil end
        end
        return unpack(r, 1, r.n)
    end
    G.mapvalues = function(fn, ...)
        local r = pack(...)
        for i = 1, r.n do r[i] = fn(r[i]) end
        return unpack(r, 1, r.n)
    end
    G.securecallfunction = function(fn, ...)
        local prev = S.taint
        if S.IsAddonFn(fn) then S.taint = S.addonName end
        local r = pack(fn(...))
        S.taint = prev
        return unpack(r, 1, r.n)
    end
    G.securecall = function(fn, ...)
        if type(fn) == "string" then fn = G[fn] end
        if type(fn) ~= "function" then return end
        return G.securecallfunction(fn, ...)
    end
    G.hooksecurefunc = function(a, b, c)
        local tbl, name, hook = G, a, b
        if type(a) == "table" then tbl, name, hook = a, b, c end
        local orig = tbl[name]
        if type(orig) ~= "function" then error("hooksecurefunc: " .. tostring(name) .. " is not a function", 2) end
        rawset(tbl, name, function(...)
            local r = pack(orig(...))
            S.Call(hook, ...)
            return unpack(r, 1, r.n)
        end)
    end
    G.loadstring_untainted = loadstring
    G.geterrorhandler = function() return S.Error end
    G.seterrorhandler = function() end
    G.GetGlobalEnvironment = function() return G end
    G.debugstack = function() return debug.traceback() end
    G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    G.table.wipe = G.wipe
    G.tinsert, G.tremove = table.insert, table.remove
    G.format, G.gsub, G.gmatch, G.strfind, G.strmatch, G.strsub = string.format, string.gsub, string.gmatch, string.find, string.match, string.sub
    G.strlen, G.strlower, G.strupper, G.strrep, G.strrev, G.strbyte, G.strchar = string.len, string.lower, string.upper, string.rep,
        string.reverse, string.byte, string.char
    G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    G.strsplit = function(sep, s)
        local out = {}
        for part in (s .. sep:sub(1, 1)):gmatch("([^" .. sep:gsub("%p", "%%%0") .. "]*)" .. sep:sub(1, 1):gsub("%p", "%%%0")) do out[#out + 1] = part end
        return unpack(out)
    end
    G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    G.strconcat = function(...) return table.concat({ ... }) end
    G.strlenutf8, G.strcmputf8i = string.len, function(a, b) return a:lower() == b:lower() and 0 or 1 end
    for _, n in ipairs({ "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "deg", "exp", "floor", "frexp", "ldexp", "log", "log10",
        "max", "min", "rad", "random", "sin", "tan" }) do G[n] = math[n] end
    G.mod = math.fmod
    G.CopyTable = function(t)
        local out = {}
        for k, v in pairs(t) do out[k] = type(v) == "table" and G.CopyTable(v) or v end
        return out
    end
    G.Mixin = function(obj, ...)
        for i = 1, select("#", ...) do
            for k, v in pairs((select(i, ...))) do obj[k] = v end
        end
        return obj
    end
    G.CreateFromMixins = function(...) return G.Mixin({}, ...) end
    G.CreateAndInitFromMixin = function(mixin, ...)
        local obj = G.CreateFromMixins(mixin)
        obj:Init(...)
        return obj
    end
    G.GenerateClosure = function(fn, ...)
        local bound = pack(...)
        return function(...)
            local args = {}
            for i = 1, bound.n do args[i] = bound[i] end
            local extra = pack(...)
            for i = 1, extra.n do args[bound.n + i] = extra[i] end
            return fn(unpack(args, 1, bound.n + extra.n))
        end
    end
    G.GetFrameMetatable = function() return S.meta.Frame end
    G.GetButtonMetatable = function() return S.meta.Button end
    G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        S.chat[#S.chat + 1] = table.concat(parts, " ")
    end

    -- Bindings
    G.SetOverrideBinding = S.SetOverrideBinding
    G.SetOverrideBindingClick = S.SetOverrideBindingClick
    G.ClearOverrideBindings = S.ClearOverrideBindings
    G.GetBindingKey = function(command)
        local keys = {}
        for key, cmd in pairs(S.keybinds) do if cmd == command then keys[#keys + 1] = key end end
        table.sort(keys)
        return unpack(keys)
    end
    G.GetBindingAction = function(key, checkOverride)
        if checkOverride then
            local b = S.Resolve(key)
            if b then return b.kind == "command" and b.target or ("CLICK " .. b.target .. ":" .. tostring(b.mouse)) end
        end
        return S.keybinds[key] or ""
    end
    G.IsKeyDown = function(key) return S.held[key] and true or false end
    G.IsShiftKeyDown = function() return S.held.PADLTRIGGER and true or false end
    G.IsControlKeyDown = function() return S.held.PADRTRIGGER and true or false end
    G.IsAltKeyDown = function() return false end
    G.IsModifiedClick = function() return false end
    G.GetCVar = function(name) return S.cvars[name] end
    G.GetCVarBool = function(name) return S.cvars[name] == "1" end

    -- Protected actions the secure templates end in
    G.SecureCmdOptionParse = function(text) return S.OptionParse(text) end
    G.CastSpellByName = function(name, unit) S.Protected("CastSpellByName()", { cast = name, unit = unit }) end
    G.CastSpellByID = function(id, unit) S.Protected("CastSpellByID()", { cast = id, unit = unit }) end
    G.TargetUnit = function(unit)
        if S.Protected("TargetUnit()", { target = unit }) then S.units.target = S.units[unit] end
    end
    G.ClearTarget = function() if S.Protected("ClearTarget()", { target = "none" }) then S.units.target = nil end end
    G.SpellIsTargeting = function() return false end
    G.SpellCanTargetItem = function() return false end
    G.SpellCanTargetItemID = function() return false end
    G.CursorHasItem = function() return false end
    G.SecureCmdItemParse = function(item) return item end
    G.SecureCmdUseItem = function(name, _, _, unit) S.Protected("UseItemByName()", { item = name, unit = unit }) end
    G.RunMacro = function(name) S.Protected("RunMacro()", { macro = name }) end
    G.SetRaidTarget = function(unit, index) S.performed[#S.performed + 1] = { marker = index, unit = unit, viaScript = S.taint ~= nil } end
    G.SaveMacro = function() end
end

return S
