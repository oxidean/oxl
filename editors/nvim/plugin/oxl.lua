-- Auto-configure the oxl language client with defaults. Users who want a
-- custom command can call require('oxl').setup{ cmd = {...} } before this
-- runs — e.g. from an earlier plugin or init.lua — and the defaults below
-- are skipped.
local oxl = require('oxl')
if not vim.g.oxl_no_auto_setup and not oxl.configured then
  oxl.setup()
end
