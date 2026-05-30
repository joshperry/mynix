
--Leave carriage return here for concatenation

vim.opt.backup = false

local keyset = vim.keymap.set

-- ---------------
-- LSP
-- ---------------
-- Advertise blink.cmp's enhanced completion capabilities to every server.
vim.lsp.config('*', {
  capabilities = require('blink.cmp').get_lsp_capabilities(),
})

vim.lsp.config('nil_ls', {
  cmd = { 'nil' },
  filetypes = { 'nix' },
  root_markers = { 'flake.nix', '.git' },
})

vim.lsp.config('beancount', {
  cmd = { 'beancount-language-server', '--stdio' },
  filetypes = { 'beancount' },
  root_markers = { '.git' },
  init_options = {
    journal_file = 'main.beancount',
    formatting = {
      prefix_width = 30,
      num_width = 10,
      currency_column = 60,
      account_amount_spacing = 2,
      number_currency_spacing = 1,
    },
  },
})

vim.lsp.config('svelte', {
  cmd = { 'svelteserver', '--stdio' },
  filetypes = { 'svelte' },
  root_markers = { 'package.json' },
})

vim.lsp.config('eslint', {
  cmd = { 'vscode-eslint-language-server', '--stdio' },
  filetypes = {
    'javascript', 'javascriptreact',
    'typescript', 'typescriptreact',
    'vue', 'svelte',
  },
  root_markers = {
    '.eslintrc', '.eslintrc.js', '.eslintrc.cjs', '.eslintrc.json',
    'eslint.config.js', 'eslint.config.mjs',
    'package.json', '.git',
  },
})

vim.lsp.config('html', {
  cmd = { 'vscode-html-language-server', '--stdio' },
  filetypes = { 'html' },
  root_markers = { 'package.json', '.git' },
})

vim.lsp.config('cmake', {
  cmd = { 'cmake-language-server' },
  filetypes = { 'cmake' },
  root_markers = { 'CMakeLists.txt', '.git' },
})

vim.lsp.config('gopls', {
  cmd = { 'gopls' },
  filetypes = { 'go', 'gomod', 'gowork' },
  root_markers = { 'go.mod', 'go.sum', '.git' },
})

vim.lsp.config('ts_ls', {
  cmd = { 'typescript-language-server', '--stdio' },
  filetypes = {
    'javascript', 'javascriptreact',
    'typescript', 'typescriptreact',
  },
  root_markers = { 'tsconfig.json', 'package.json', '.git' },
})

vim.lsp.config('yamlls', {
  cmd = { 'yaml-language-server', '--stdio' },
  filetypes = { 'yaml' },
  root_markers = { '.git' },
})

vim.lsp.config('rust_analyzer', {
  cmd = { 'rust-analyzer' },
  filetypes = { 'rust' },
  root_markers = { 'Cargo.toml', '.git' },
})

vim.lsp.config('clangd', {
  cmd = { 'clangd' },
  filetypes = { 'c', 'cpp', 'objc', 'objcpp' },
  root_markers = { 'compile_commands.json', '.clangd', '.git' },
})

vim.lsp.enable({
  'nil_ls', 'beancount', 'svelte', 'eslint', 'html',
  'cmake', 'gopls', 'ts_ls', 'yamlls', 'rust_analyzer', 'clangd',
})

-- GoTo code navigation (preserves muscle memory from CoC bindings).
keyset('n', 'gd', vim.lsp.buf.definition, { silent = true })
keyset('n', 'gy', vim.lsp.buf.type_definition, { silent = true })
keyset('n', 'gi', vim.lsp.buf.implementation, { silent = true })
keyset('n', 'gr', vim.lsp.buf.references, { silent = true })

-- K shows hover docs for LSP-attached buffers, otherwise falls back to keywordprg / :help.
function _G.show_docs()
    local cw = vim.fn.expand('<cword>')
    if vim.fn.index({'vim', 'help'}, vim.bo.filetype) >= 0 then
        vim.api.nvim_command('h ' .. cw)
    elseif next(vim.lsp.get_clients({ bufnr = 0 })) ~= nil then
        vim.lsp.buf.hover()
    else
        vim.api.nvim_command('!' .. vim.o.keywordprg .. ' ' .. cw)
    end
end
keyset('n', 'K', '<CMD>lua _G.show_docs()<CR>', { silent = true })

vim.api.nvim_create_user_command('OR', function()
  vim.lsp.buf.code_action({
    context = { only = { 'source.organizeImports' }, diagnostics = {} },
    apply = true,
  })
end, {})

--Leave carriage return here for concatenation

