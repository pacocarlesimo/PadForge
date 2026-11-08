-- PadForge core: namespace, events, the out-of-combat queue, modules with
-- isolated errors, slash commands, compatibility with other controller
-- addons.
--
-- Ground rules every file follows (learned the hard way by the addons that
-- came before on WoW Forever, see LICENSE-ThirdParty.md):
--  * Never set a property of the game's frames (SetAlpha, Hide, SetPoint...).
--    To hide one, play an alpha animation of ours on it (PF.Fade).
--  * Never call the game's gamepad window code (FrameControlsManager Focus*,
--    ShowUIPanel...) and never add callbacks of ours to its lists: only read.
--  * Bindings and secure attributes change out of combat only: anything asked
--    for in combat is queued (PF.AfterCombat) and runs as combat ends.
--  * World bindings step aside while a game window holds the gamepad.
local ADDON, PF = ...
_G.PadForge = PF

PF.name = ADDON
PF.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata or function() end)(ADDON, "Version") or "dev"
PF.TITLE = "|cff4fc3f7Pad|r|cffffb74dForge|r"

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------
function PF.Print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(PF.TITLE .. ": " .. table.concat(parts, " "))
end

-- Once per session per key (warnings that would otherwise repeat)
local said = {}
function PF.PrintOnce(key, ...)
    if said[key] then return end
    said[key] = true
    PF.Print(...)
end

---------------------------------------------------------------------------
-- Events: any number of handlers per event, each isolated
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

PF.errors = {}
local MAX_ERRORS = 20

-- Swallows an error so the other handlers keep running. Never handed to the game's
-- error handler: running the game's code from ours spreads our taint into
-- it (that is how a PadForge error once got the game's own action buttons
-- blocked, "UseAction").
function PF.Report(where, err)
    local entry = date("%H:%M:%S") .. " " .. tostring(where) .. ": " .. tostring(err)
    table.insert(PF.errors, 1, entry)
    if #PF.errors > MAX_ERRORS then PF.errors[#PF.errors] = nil end
end

-- Secret values: on this client, many numbers the game hands out in
-- combat (damage, health, cooldowns...) are secret, and comparing one in
-- addon code is an error. PF.Num(v) is v when it's a number PadForge may
-- use, else nil; PF.IsSecret(v) says whether a value is one.
function PF.IsSecret(v)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        return not ok or secret and true or false
    end
    return false
end

function PF.Num(v)
    if type(v) ~= "number" or PF.IsSecret(v) then return nil end
    return v
end

function PF.SafeCall(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then PF.Report(where, err) end
    return ok, err
end

function PF.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not event:find("^PF_") then pcall(eventFrame.RegisterEvent, eventFrame, event) end
    end
    table.insert(handlers[event], fn)
end

-- Our own events ("PF_PROFILE_CHANGED"...) go through the same lists
function PF.Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do PF.SafeCall(event, fn, event, ...) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...) PF.Fire(event, ...) end)

---------------------------------------------------------------------------
-- Login: the database is ready (Database.lua) before these run
---------------------------------------------------------------------------
local loginList, loggedIn = {}, false

function PF.OnLogin(fn)
    if loggedIn then
        PF.SafeCall("login", fn)
    else
        loginList[#loginList + 1] = fn
    end
end

function PF.IsReady() return loggedIn end

PF.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    PF.SafeCall("database", PF.DB.Init)
end)

PF.On("PLAYER_LOGIN", function()
    if not PF.db then PF.SafeCall("database", PF.DB.Init) end
    loggedIn = true
    for _, fn in ipairs(loginList) do PF.SafeCall("login", fn) end
    wipe(loginList)
    PF.CheckCompat()
    PF.EnableModules()
    PF.Fire("PF_READY")
end)

---------------------------------------------------------------------------
-- Combat: the queue of work that must wait for it to end
---------------------------------------------------------------------------
local queue, queueOrder = {}, {}

function PF.InCombat()
    return InCombatLockdown() and true or false
end

-- Runs fn now, or once combat ends when locked. Keyed: asking again with
-- the same key before then runs it once (the latest fn).
function PF.AfterCombat(key, fn)
    if not PF.InCombat() then
        PF.SafeCall(key, fn)
        return true
    end
    if not queue[key] then queueOrder[#queueOrder + 1] = key end
    queue[key] = fn
    return false
end

PF.On("PLAYER_REGEN_ENABLED", function()
    local order, jobs = queueOrder, queue
    queueOrder, queue = {}, {}
    for _, key in ipairs(order) do
        if jobs[key] then PF.SafeCall(key, jobs[key]) end
    end
end)

---------------------------------------------------------------------------
-- Fading a frame we don't own: an alpha animation of ours aimed at it, so
-- none of its properties is set from addon code (that taints the gamepad
-- window manager).
---------------------------------------------------------------------------
local fader = CreateFrame("Frame")
local fades = setmetatable({}, { __mode = "k" })

function PF.Fade(region, hide, alpha)
    if not (region and region.GetObjectType) then return end
    if region.IsForbidden and region:IsForbidden() then return end
    alpha = alpha or 0
    local group = fades[region]
    if not group then
        if not hide then return end
        local ok
        ok, group = pcall(function()
            local g = fader:CreateAnimationGroup()
            g:CreateAnimation("Alpha"):SetTarget(region)
            return g
        end)
        if not ok or not group then return end
        local anim = group:GetAnimations()
        anim:SetDuration(3600)
        group:SetLooping("REPEAT")
        fades[region] = group
    end
    if hide then
        if group.pfAlpha ~= alpha then
            group:Stop()
            local anim = group:GetAnimations()
            anim:SetFromAlpha(alpha)
            anim:SetToAlpha(alpha)
            group.pfAlpha = alpha
        end
        if not group:IsPlaying() then group:Play() end
    elseif group:IsPlaying() then
        group:Stop()
    end
end

function PF.IsFaded(region)
    local group = fades[region]
    return group ~= nil and group:IsPlaying()
end

---------------------------------------------------------------------------
-- Modules: each enabled from the profile, each one's failure its own
---------------------------------------------------------------------------
PF.modules, PF.moduleOrder = {}, {}

-- def: { title, desc, order, Enable(), Disable(), Refresh() (profile or
-- settings changed), compat = { addon = "why" } (turned off while that
-- addon is loaded), defaultOff = true (only on once turned on) }
function PF.NewModule(key, def)
    def.key = key
    def.order = def.order or 50
    PF.modules[key] = def
    PF.moduleOrder[#PF.moduleOrder + 1] = def
    table.sort(PF.moduleOrder, function(a, b) return a.order < b.order end)
    return def
end

function PF.ModuleBlockedBy(def)
    for addon, why in pairs(def.compat or {}) do
        if PF.IsLoaded(addon) then return addon, why end
    end
end

function PF.ModuleWanted(def)
    if PF.safeMode then return false end
    if PF.ModuleBlockedBy(def) then return false end
    local p = PF.P and PF.P()
    local set = p and p.modules and p.modules[def.key]
    if def.defaultOff then return set == true end
    return set ~= false
end

local function SetModule(def, on)
    if on == (def.running or false) then return end
    def.running = on
    if on then
        if def.Enable then PF.SafeCall(def.key .. ":enable", def.Enable, def) end
    else
        if def.Disable then PF.SafeCall(def.key .. ":disable", def.Disable, def) end
    end
end

-- Every module on or off as the profile says; the running ones refreshed.
-- Out of combat (bindings and secure frames change with them).
function PF.EnableModules()
    PF.AfterCombat("modules", function()
        for _, def in ipairs(PF.moduleOrder) do SetModule(def, PF.ModuleWanted(def)) end
        for _, def in ipairs(PF.moduleOrder) do
            if def.running and def.Refresh then PF.SafeCall(def.key .. ":refresh", def.Refresh, def) end
        end
        if PF.Binds then PF.Binds.Apply() end
    end)
end

function PF.RefreshModule(key)
    local def = PF.modules[key]
    if not def then return end
    PF.AfterCombat("refresh:" .. key, function()
        if def.running and def.Refresh then PF.SafeCall(key .. ":refresh", def.Refresh, def) end
        if PF.Binds then PF.Binds.Apply() end
    end)
end

PF.On("PF_PROFILE_CHANGED", function() PF.EnableModules() end)

---------------------------------------------------------------------------
-- Other controller addons: what clashes is turned off on our side, said once
---------------------------------------------------------------------------
local function IsLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return fn and fn(name) and true or false
end
PF.IsLoaded = IsLoaded

PF.COMPAT = {
    { addon = "ConsolePort", text = "ConsolePort replaces the native gamepad UI. PadForge's button and wheel modules are off while it is loaded." },
    { addon = "ImprovedForever_Wheel", text = "Improved Forever: Wheel also uses the right stick click. PadForge's wheels are off while it is loaded." },
    { addon = "EasyController", text = "Easy Controller also rebinds the face buttons. Use one of them for that; PadForge's button module is off while it is loaded." },
    { addon = "EasyControllerForever", text = "Easy Controller also rebinds the face buttons. Use one of them for that; PadForge's button module is off while it is loaded." },
}

function PF.CheckCompat()
    local found = {}
    for _, c in ipairs(PF.COMPAT) do
        if IsLoaded(c.addon) then
            found[#found + 1] = c
            local seen = PF.db.global.compatSeen
            if not seen[c.addon] then
                seen[c.addon] = true
                PF.Print(c.text)
            end
        end
    end
    PF.compatFound = found
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local commands, commandOrder = {}, {}

function PF.AddCommand(name, fn, help)
    commands[name] = { fn = fn, help = help }
    commandOrder[#commandOrder + 1] = name
end

SLASH_PADFORGE1, SLASH_PADFORGE2 = "/padforge", "/pf"
SlashCmdList.PADFORGE = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local name, rest = msg:match("^(%S+)%s*(.-)$")
    name = name and name:lower()
    if not name or name == "" then
        if PF.Config then PF.Config.Toggle() end
        return
    end
    local cmd = commands[name]
    if not cmd then
        PF.Print("Commands:")
        for _, n in ipairs(commandOrder) do
            DEFAULT_CHAT_FRAME:AddMessage("  /pf " .. n .. (commands[n].help and (" - " .. commands[n].help) or ""))
        end
        return
    end
    PF.SafeCall("/pf " .. name, cmd.fn, rest)
end

PF.AddCommand("help", function() SlashCmdList.PADFORGE("?") end, "this list")

-- Key binding (Bindings.xml)
BINDING_HEADER_PADFORGE = "PadForge"
BINDING_NAME_PADFORGE_TOGGLE = "Open PadForge"
function PadForge_Toggle()
    if PF.Config then PF.Config.Toggle() end
end
