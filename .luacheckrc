-- luacheck . (the game's globals are checked by tests/apicheck.lua and the
-- simulator, not listed here one by one)
std = "lua51"
max_line_length = false
exclude_files = { "tests/.wow-ui-source/**" }
ignore = {
    "11.",      -- globals: the WoW API
    "212",      -- unused arguments (handlers have fixed signatures)
    "213",      -- unused loop variables
    "431", "432", -- shadowing upvalues
    "211/_.*",  -- unused variables named _something
}
files["tests/**"] = { ignore = { "11.", "12.", "211", "212", "213", "231", "311", "411", "421", "431", "432", "542", "582", "631" } }
