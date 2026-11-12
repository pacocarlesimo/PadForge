-- Reads the game's own API documentation (Blizzard_APIDocumentationGenerated
-- in a checkout of the WoW Forever UI source) so the tests know which
-- functions and widget methods this client really has.
--
--   local Docs = require("sim.docs").Load(root)
--   Docs.widget.SimpleFrameAPI.SetAttribute   -> the documentation entry
--   Docs.namespace.C_GamePad.GetActiveDeviceID
--   Docs.global.UnitHealth
local Docs = {}

local function ListFiles(dir, pattern)
    local out = {}
    local p = io.popen('ls "' .. dir .. '" 2>/dev/null')
    if not p then return out end
    for name in p:lines() do
        if name:match(pattern) then out[#out + 1] = dir .. "/" .. name end
    end
    p:close()
    return out
end
Docs.ListFiles = ListFiles

-- Where the UI source is: $WOW_UI_SOURCE, else tests/.wow-ui-source
function Docs.Root()
    local root = os.getenv("WOW_UI_SOURCE")
    if not root or root == "" then root = "tests/.wow-ui-source" end
    local f = io.open(root .. "/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureHandlers.lua")
    if not f then return nil, root end
    f:close()
    return root
end

function Docs.Load(root)
    local dir = root .. "/Interface/AddOns/Blizzard_APIDocumentationGenerated"
    local out = { widget = {}, namespace = {}, global = {}, events = {}, count = 0 }
    local env = setmetatable({}, { __index = _G })
    -- (the files read Enum.X.Y and Constants.X.Y for default values)
    local function Any()
        local num = function() return 0 end
        return setmetatable({}, { __index = function(t, k) local v = Any() rawset(t, k, v) return v end,
            __add = num, __sub = num, __mul = num, __div = num, __unm = num, __concat = function() return "" end })
    end
    env.Enum, env.Constants = Any(), Any()
    out.failed = {}
    env.APIDocumentation = {
        AddDocumentationTable = function(_, t)
            if type(t) ~= "table" then return end
            local into
            if t.Type == "ScriptObject" then
                out.widget[t.Name] = out.widget[t.Name] or {}
                into = out.widget[t.Name]
            elseif t.Namespace then
                out.namespace[t.Namespace] = out.namespace[t.Namespace] or {}
                into = out.namespace[t.Namespace]
            else
                into = out.global
            end
            for _, fn in ipairs(t.Functions or {}) do
                into[fn.Name] = fn
                out.count = out.count + 1
            end
            for _, ev in ipairs(t.Events or {}) do
                if ev.LiteralName then out.events[ev.LiteralName] = ev end
            end
        end,
    }
    for _, path in ipairs(ListFiles(dir, "%.lua$")) do
        local chunk = loadfile(path)
        if chunk then
            setfenv(chunk, env)
            local ok, err = pcall(chunk)
            if not ok then out.failed[#out.failed + 1] = tostring(err) end
        end
    end
    return out
end

return Docs
