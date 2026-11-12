-- Every game function PadForge names must exist on WoW Forever, or be
-- used behind an "if it exists" test. Checked against the client's own
-- API documentation and UI source (tests/README.md says where it comes
-- from), so a function from another client, or one a patch removed, fails
-- here instead of in the game.
--   luajit tests/apicheck.lua       (from the repo root)
package.path = "tests/?.lua;" .. package.path
local Docs = require("sim.docs")
local root, tried = Docs.Root()
if not root then
    print("SKIPPED: no WoW Forever UI source at " .. tostring(tried) .. " (run tests/fetch-ui-source.sh)")
    os.exit(os.getenv("PF_REQUIRE_SIM") and 1 or 0)
end
local docs = Docs.Load(root)

local files = {}
for line in io.lines("PadForge.toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
end

-- Namespaced calls: C_Foo.Bar
local problems, checked = {}, 0
for _, path in ipairs(files) do
    local f = assert(io.open(path))
    local whole = f:read("*a"):gsub("%-%-[^\n]*", "")
    f:close()
    local n = 0
    for line in io.lines(path) do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        for ns, fn in code:gmatch("(C_%a+)%.(%a[%w_]*)") do
            checked = checked + 1
            local known = docs.namespace[ns] and docs.namespace[ns][fn]
            -- guarded somewhere in the file: "C_Foo.Bar and", "C_Foo.Bar then", "(C_Foo.Bar) or"
            local name = ns .. "%." .. fn
            local guarded = whole:find(name .. "%s+and") or whole:find(name .. "%s+then") or whole:find(name .. "%)%s+or")
            if not known and not guarded then
                problems[#problems + 1] = path .. ":" .. n .. " " .. ns .. "." .. fn .. " is not on this client and is used unguarded"
            end
        end
    end
end

-- Events: registered through PF.On, which survives an unknown one, but an
-- event this client never fires is dead code worth knowing about
for _, path in ipairs(files) do
    local n = 0
    for line in io.lines(path) do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        for event in code:gmatch('"([A-Z][A-Z_]+[A-Z])"') do
            if (code:find("PF%.On%(") or code:find("for _, event in ipairs") or code:find('^%s*"')) and event:find("_")
                and not event:find("^PF_") and not event:find("^PAD") and not event:find("^GAMEPAD") then
                local isEventList = code:find("PF%.On%(\"" .. event) or code:find("event in ipairs") or code:find('^%s*"[A-Z_]+",')
                if isEventList and not docs.events[event] then
                    problems[#problems + 1] = path .. ":" .. n .. " event " .. event .. " doesn't exist on this client"
                end
            end
        end
    end
end

for _, p in ipairs(problems) do print("FAIL: " .. p) end
print(checked .. " namespaced calls checked against " .. docs.count .. " documented functions, " .. #problems .. " problem(s)")
os.exit(#problems == 0 and 0 or 1)
