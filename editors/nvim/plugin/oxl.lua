-- Auto-configure the oxl language client with defaults. Users who want a
-- custom command can call require('oxl').setup{ cmd = {...} } before this
-- runs — e.g. from an earlier plugin or init.lua — and the defaults below
-- are skipped.
if not vim.g.oxl_no_auto_setup then
  require('oxl').setup()
end
