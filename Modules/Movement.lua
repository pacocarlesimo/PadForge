-- Movement & camera: the game's own gamepad settings (CVars), set directly.
-- Players found some of the Gamepad menu's sliders not doing what they say
-- (the movement face angle acting as an on / off switch) and the stick run
-- threshold too high (walking when you meant to run). Only the settings
-- this client really has are shown; the values live in the profile, so an
-- exported profile carries them, and each can go back to the game's default.
local _, PF = ...

local M = PF.NewModule("movement", {
    title = "Movement & camera",
    desc = "The game's gamepad movement and camera settings, tuned directly and saved in your profile.",
    order = 50,
})
PF.Movement = M

local function Validate(t)
    t.cvars = type(t.cvars) == "table" and t.cvars or {}
    for name, value in pairs(t.cvars) do
        if type(name) ~= "string" or not name:find("^GamePad") or (type(value) ~= "string" and type(value) ~= "number") then
            t.cvars[name] = nil
        else
            t.cvars[name] = tostring(value)
        end
    end
    return t
end

PF.DB.RegisterDefaults("movement", { cvars = {} }, Validate)

-- Known settings: kind "range" (min, max, step) or "bool" or "choice"
M.KNOWN = {
    { name = "GamePadRunThreshold", label = "Stick run threshold", kind = "range", min = 0.05, max = 0.95, step = 0.05,
        tip = "How far the left stick must be pushed to run instead of walk. Lower: run sooner." },
    { name = "GamePadFaceMovementMaxAngle", label = "Face movement angle", kind = "range", min = 0, max = 180, step = 5,
        tip = "Out of combat: up to this angle from the camera you strafe, beyond it your character turns to face where you go." },
    { name = "GamePadFaceMovementMaxAngleCombat", label = "Face movement angle (combat)", kind = "range", min = 0, max = 180, step = 5,
        tip = "The same, in combat." },
    { name = "GamePadCameraYawSpeed", label = "Camera turn speed", kind = "range", min = 0.1, max = 4, step = 0.1 },
    { name = "GamePadCameraPitchSpeed", label = "Camera tilt speed", kind = "range", min = 0.1, max = 4, step = 0.1 },
    { name = "GamePadTurnWithCamera", label = "Character turns with camera", kind = "choice",
        choices = { { "0", "Never" }, { "1", "In combat" }, { "2", "Always" } } },
    { name = "GamePadCameraLookMaxYaw", label = "Look-around max turn", kind = "range", min = 0, max = 180, step = 5 },
    { name = "GamePadCameraLookMaxPitch", label = "Look-around max tilt", kind = "range", min = 0, max = 90, step = 5 },
    { name = "GamePadCursorAutoEnable", label = "Cursor shows by itself", kind = "bool" },
    { name = "GamePadCursorAutoDisableJump", label = "Jumping hides the cursor", kind = "bool" },
}

local function Get(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, value = pcall(get, name)
    return ok and value or nil
end

local function Default(name)
    local fn = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if not fn then return nil end
    local ok, value = pcall(fn, name)
    return ok and value or nil
end
M.Default = Default

local function Set(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local ok, r = pcall(set, name, value)
    return ok and r ~= false
end

function M.Exists(name) return Get(name) ~= nil end

-- Known settings this client has
function M.Available()
    local out = {}
    for _, def in ipairs(M.KNOWN) do
        if M.Exists(def.name) then out[#out + 1] = def end
    end
    return out
end

-- Other gamepad CVars the client lists (shown read-only with a reset)
function M.Others()
    local out, known = {}, {}
    for _, def in ipairs(M.KNOWN) do known[def.name] = true end
    if C_Console and C_Console.GetAllCommands then
        local ok, all = pcall(C_Console.GetAllCommands)
        if ok and type(all) == "table" then
            for _, c in ipairs(all) do
                local name = c.command
                if type(name) == "string" and name:find("^GamePad") and not known[name] and (c.commandType == 0 or c.commandType == nil) and M.Exists(name) then
                    out[#out + 1] = { name = name, label = name, tip = c.help }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function M.Value(name)
    local s = PF.P() and PF.P().movement
    return (s and s.cvars[name]) or Get(name)
end

local function Apply()
    if PF.InCombat() then return PF.AfterCombat("movement", Apply) end
    local s = PF.P() and PF.P().movement
    if not s then return end
    for name, value in pairs(s.cvars) do
        if M.Exists(name) and Get(name) ~= value then
            Set(name, value)
        end
    end
end
M.Apply = Apply

function M.SetValue(name, value)
    local s = PF.P().movement
    s.cvars[name] = value ~= nil and tostring(value) or nil
    if value == nil then
        local def = Default(name)
        if def then PF.AfterCombat("movement:" .. name, function() Set(name, def) end) end
    end
    Apply()
end

function M.ResetAll()
    local s = PF.P().movement
    for name in pairs(s.cvars) do
        local def = Default(name)
        if def then Set(name, def) end
    end
    wipe(s.cvars)
end

-- (never applied by itself, at login, on a profile switch or entering a
-- dungeon: changing gamepad settings from addon code runs the game's
-- gamepad code under our name. Only the player's own change in the
-- window writes one; a profile whose values differ says so on the page.)
function M.Differs()
    local s = PF.P() and PF.P().movement
    local n = 0
    for name, value in pairs(s and s.cvars or {}) do
        if M.Exists(name) and Get(name) ~= value then n = n + 1 end
    end
    return n
end
