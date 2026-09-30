-- Modern Neovim Configuration
-- Essentials machines keep nvim (the vim alias) but run it stock. No file stores a
-- profile selection, so the provisioned lazy.nvim install is the signal for the dev
-- setup; a ProfileSync run sets vim.g.profile_sync before init.lua loads and must
-- provision even when lazypath is still empty. vim.loop covers nvim before 0.10,
-- which must reach this return without an error.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.g.profile_sync and not (vim.uv or vim.loop).fs_stat(lazypath) then
  return
end

-- vim.lsp.config and vim.lsp.enable, used below, first shipped in 0.11.
if vim.fn.has('nvim-0.11') == 0 then
  vim.api.nvim_echo({ { 'This config needs Neovim 0.11 or later', 'ErrorMsg' } }, true, {})
  return
end

-- Key Mappings
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Lazy.nvim Bootstrap
local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
-- Read as bytes ('b'), so the write-back after lazy.setup reproduces the committed file exactly.
local committed_lock = vim.fn.filereadable(lockfile) == 1 and vim.fn.readfile(lockfile, "b") or nil
if not vim.uv.fs_stat(lazypath) then
  -- Clone at the locked commit: lazy restore does not move lazy.nvim itself, so
  -- another commit here would be written back into lazy-lock.json.
  local lock = vim.json.decode(table.concat(assert(committed_lock, "missing " .. lockfile), "\n"))
  local clone = vim.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", lazypath }):wait()
  local checkout = clone.code == 0
    and vim.system({ "git", "-C", lazypath, "checkout", lock["lazy.nvim"].commit }):wait()
  if clone.code ~= 0 or checkout.code ~= 0 then
    vim.fn.delete(lazypath, "rf")
    vim.api.nvim_echo({ { "Failed to install lazy.nvim:\n" .. (clone.stderr or "") .. (checkout and checkout.stderr or ""), "ErrorMsg" } }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

-- Plugins
require("lazy").setup({
  -- Git integration
  'tpope/vim-fugitive',
  'tpope/vim-rhubarb',

  -- Detect tabstop and shiftwidth automatically
  'tpope/vim-sleuth',

  -- LSP server definitions. brew/Brewfile installs the servers themselves.
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Useful status updates for LSP
      { 'j-hui/fidget.nvim', opts = {} },
    },
  },

  -- Neovim Lua API completion and types when editing the config
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {},
  },

  -- Autocompletion
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'L3MON4D3/LuaSnip',
      'saadparwaiz1/cmp_luasnip',
    },
  },

  -- Highlight, edit, and navigate code
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
    },
    build = ":TSUpdate",
  },

  -- Fuzzy Finder (files, lsp, etc)
  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
    },
  },

  -- Theme (Solarized to match your preference)
  {
    'ishan9299/nvim-solarized-lua',
    priority = 1000,
    config = function()
      vim.cmd.colorscheme 'solarized'
    end,
  },
  
  -- Status line
  {
    'nvim-lualine/lualine.nvim',
    opts = {
      options = {
        icons_enabled = false,
        theme = 'solarized_dark',
        component_separators = '|',
        section_separators = '',
      },
    },
  },
}, {
  -- Headless-only: with process streaming on, lazy writes a failed process's output
  -- straight to stdout and never logs it at ERROR level, so task:has_errors() stays
  -- false and ProfileSync cannot see the failure.
  headless = { process = false },
})

-- lazy.setup installs the plugins that are missing at startup and then rewrites the whole
-- lockfile from the installed commits, so one new plugin makes it lose the committed entry
-- of every plugin whose installation is behind the lockfile. Put the committed file back,
-- and drop lazy's in-memory copy of it, so ProfileSync and :Lazy restore target the
-- committed versions. lock and _loaded are internal to lazy.nvim, but the lockfile pins
-- lazy.nvim itself, so they cannot change under this config silently.
if committed_lock and not vim.deep_equal(vim.fn.readfile(lockfile, "b"), committed_lock) then
  vim.fn.writefile(committed_lock, lockfile, "b")
  local lock_cache = require("lazy.manage.lock")
  lock_cache.lock, lock_cache._loaded = {}, false
end

-- Options
vim.o.hlsearch = true
vim.o.incsearch = true
vim.wo.number = true
vim.wo.relativenumber = true
vim.o.mouse = 'a'
vim.o.clipboard = 'unnamedplus'
vim.o.breakindent = true
vim.o.undofile = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.wo.signcolumn = 'yes'
vim.o.updatetime = 250
vim.o.timeout = true
vim.o.timeoutlen = 300
vim.o.completeopt = 'menuone,noselect'
vim.o.termguicolors = true

-- Basic Keymaps
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- Telescope Keymaps
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })

-- Treesitter Config
-- :ProfileSync installs these; nothing compiles at startup.
local parsers = { "c", "cpp", "go", "lua", "python", "rust", "tsx", "typescript", "vimdoc", "vim" }

vim.api.nvim_create_autocmd('FileType', {
  callback = function()
    -- Fails for filetypes without an installed parser; those keep regex highlighting.
    if pcall(vim.treesitter.start) then
      vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

-- LSP Config
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local bufnr = args.buf
    local nmap = function(keys, func, desc)
      vim.keymap.set('n', keys, func, { buffer = bufnr, desc = 'LSP: ' .. desc })
    end

    nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
    nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')
    nmap('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')
    nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
    nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  end,
})

-- bin is explicit because some lspconfig definitions (tsc) set cmd to a function.
local servers = {
  lua_ls = {
    bin = 'lua-language-server',
    settings = {
      Lua = {
        workspace = { checkThirdParty = false },
        telemetry = { enable = false },
      },
    },
  },
  stylua = { bin = 'stylua' },
  gopls = { bin = 'gopls' },
  basedpyright = { bin = 'basedpyright-langserver' },
  tsc = { bin = 'tsc' },
}

vim.lsp.config('*', {
  capabilities = require('cmp_nvim_lsp').default_capabilities(),
})

for server_name, server in pairs(servers) do
  if server.settings then
    vim.lsp.config(server_name, { settings = server.settings })
  end
  -- The essentials profile installs no dev servers, and an enabled server without its binary logs an error on each start.
  if vim.fn.executable(server.bin) == 1 then
    vim.lsp.enable(server_name)
  end
end

-- Headless provisioning for `profile install`: `nvim --headless +ProfileSync`.
-- nvim --headless exits with 0 after errors, so the exit status must come from cquit.
vim.api.nvim_create_user_command('ProfileSync', function()
  local failures = {}
  local function collect_task_errors(plugins)
    for _, plugin in pairs(plugins) do
      for _, task in ipairs(plugin._.tasks or {}) do
        if task:has_errors() then
          table.insert(failures, 'plugin ' .. plugin.name .. ': ' .. task:output(vim.log.levels.ERROR))
        end
      end
    end
  end

  require('lazy').restore { wait = true, show = false }
  require('lazy').clean { wait = true, show = false }
  local lazy_config = require('lazy.core.config')
  for _, plugin in pairs(lazy_config.plugins) do
    if not plugin._.installed then
      table.insert(failures, 'plugin not installed: ' .. plugin.name)
    end
  end
  collect_task_errors(lazy_config.plugins)
  -- clean runs its tasks on to_clean, not on plugins, so a failed removal only shows up here.
  collect_task_errors(lazy_config.to_clean)
  -- lazy's fs.clean ignores the result of each remove, so a leftover directory is the only evidence.
  for _, plugin in pairs(lazy_config.to_clean) do
    if vim.uv.fs_stat(plugin.dir) then
      table.insert(failures, 'plugin not removed: ' .. plugin.name)
    end
  end

  local ok, err = pcall(function()
    assert(require('nvim-treesitter').install(parsers):wait(600000), 'install failed')
    -- The :TSUpdate build hook starts an async update that restore does not await, and
    -- install skips a parser that is present but stale. update selects by revision and
    -- waits on any in-flight install of the same parser, so this blocks until every
    -- parser is at the pinned revision.
    assert(require('nvim-treesitter').update(parsers):wait(600000), 'update failed')
  end)
  if not ok then
    table.insert(failures, 'treesitter install: ' .. tostring(err))
  end
  -- Not nvim_get_runtime_file: it caches the search, and the parser directory can be new in this session.
  local installed = require('nvim-treesitter').get_installed 'parsers'
  for _, lang in ipairs(parsers) do
    if not vim.list_contains(installed, lang) then
      table.insert(failures, 'parser not installed: ' .. lang)
    end
  end

  for _, failure in ipairs(failures) do
    io.stderr:write(failure .. '\n')
  end
  -- restore and clean rewrite the lockfile from the installed commits even when they fail,
  -- so a failed run would commit the wrong versions as the new target of the retry.
  if #failures > 0 and committed_lock then
    vim.fn.writefile(committed_lock, lockfile, 'b')
  end
  vim.cmd(#failures == 0 and 'qall!' or 'cquit 1')
end, { desc = 'Restore plugins to lazy-lock.json and install the treesitter parsers' })

-- CMP Config
local cmp = require 'cmp'
local luasnip = require 'luasnip'
require('luasnip.loaders.from_vscode').lazy_load()
luasnip.config.setup {}

cmp.setup {
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert {
    ['<C-n>'] = cmp.mapping.select_next_item(),
    ['<C-p>'] = cmp.mapping.select_prev_item(),
    ['<C-d>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete {},
    ['<CR>'] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    },
    ['<Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif luasnip.expand_or_locally_jumpable() then
        luasnip.expand_or_jump()
      else
        fallback()
      end
    end, { 'i', 's' }),
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      elseif luasnip.locally_jumpable(-1) then
        luasnip.jump(-1)
      else
        fallback()
      end
    end, { 'i', 's' }),
  },
  sources = {
    -- group_index 0 keeps lazydev ahead of lua_ls for require() path completion.
    { name = 'lazydev', group_index = 0 },
    { name = 'nvim_lsp' },
    { name = 'luasnip' },
  },
}
