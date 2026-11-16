-- oxl Neovim plugin: filetype detection + LSP client wiring.
--
-- Highlighting comes from the server's semanticTokens (advertised
-- unconditionally by `oxl lsp`); syntax/oxl.vim covers sessions without
-- the language server attached.
local M = {}

-- filename -> project root (oxl.mod or .git, walking up)
local function root_dir(fname)
  local markers = { 'oxl.mod', '.git' }
  local found = vim.fs and vim.fs.find and vim.fs.find(markers, { path = fname, upward = true })[1]
  if found then
    return vim.fs.dirname(found)
  end
  return vim.fn.fnamemodify(fname, ':h')
end

function M.setup(opts)
  opts = opts or {}
  local cmd = opts.cmd or { 'oxl', 'lsp' }

  if vim.lsp and vim.lsp.config and vim.lsp.enable then
    -- Neovim 0.11+: native vim.lsp.config — root_dir takes
    -- (bufnr, on_dir), not a filename
    vim.lsp.config('oxl', {
      cmd = cmd,
      filetypes = { 'oxl' },
      root_dir = function(bufnr, on_dir)
        on_dir(root_dir(vim.api.nvim_buf_get_name(bufnr)))
      end,
    })
    vim.lsp.enable('oxl')
  else
    -- Neovim 0.10 and earlier: nvim-lspconfig
    local ok, lspconfig = pcall(require, 'lspconfig')
    if ok then
      require('lspconfig.configs').oxl = {
        default_config = {
          cmd = cmd,
          filetypes = { 'oxl' },
          root_dir = root_dir,
        },
      }
      lspconfig.oxl.setup({})
    else
      vim.notify('nvim-oxl: no LSP config mechanism found (need Neovim 0.11+ or nvim-lspconfig)', vim.log.levels.WARN)
    end
  end
  -- lets plugin/oxl.lua skip auto-setup when the user already configured
  M.configured = true
end

return M
