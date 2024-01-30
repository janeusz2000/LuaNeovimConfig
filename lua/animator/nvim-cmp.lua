local cmp = require('cmp')


-- Copilot 
require("copilot").setup({
  suggetion  = { enabled = false },
  panel = { enabled = false },
})

require("copilot_cmp").setup()

cmp.setup({
  snippet = {
    expand = function(args)
      vim.fn["vsnip#anonymous"](args.body)
    end,
  },
  window = {
    -- completion = cmp.config.window.bordered(),
    -- documentation = cmp.config.window.bordered(),
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.abort(),
    ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set select to false to only confirm explicitly selected items.
  }),
  sources = cmp.config.sources(
    {
      { name = "copilot", group_index = 2 },
      { name = 'nvim_lsp' },
      { name = 'vsnip' }, 
    }, 
    {
      { name = 'buffer' },
    }
  ),
  sorting = {
    priority_weight = 1,
    comparators = {
      require("copilot_cmp.comparators").prioritize,

      -- Below is the default comparitor list and order for nvim-cmp
      cmp.config.compare.offset,
      -- cmp.config.compare.scopes, --this is commented in nvim-cmp too
      cmp.config.compare.exact,
      cmp.config.compare.score,
      cmp.config.compare.recently_used,
      cmp.config.compare.locality,
      cmp.config.compare.kind,
      cmp.config.compare.sort_text,
      cmp.config.compare.length,
      cmp.config.compare.order,
    },
  },
})

-- Use buffer source for / (if you enabled native_menu, this won't work anymore).
cmp.setup.cmdline('/', {
mapping = cmp.mapping.preset.cmdline(),
sources = {
  { name = 'buffer' }
}
})

-- Use cmdline & path source for ':' (if you enabled native_menu, this won't work anymore).
cmp.setup.cmdline(':', {
mapping = cmp.mapping.preset.cmdline(),
sources = cmp.config.sources({
  { name = 'path' }
}, {
  { name = 'cmdline' }
})
})

-- Setup lspconfig.
local capabilities = require('cmp_nvim_lsp').default_capabilities(vim.lsp.protocol.make_client_capabilities())
-- Replace <YOUR_LSP_SERVER> with each lsp server you've enabled.

-- This needs to be fixed because clangd does not work propertly in this case.
require('lspconfig').clangd.setup {
    cmd = {
        "clangd-17",
        "--log=verbose",
        "--background-index"
    },
    capabilities = capabilities
}

require('lspconfig').rust_analyzer.setup {
  capabilities = capabilities,
}

require('lspconfig').pylsp.setup{
  settings = {
    pylsp = {
      plugins = {
        pycodestyle = {
          ignore = {'W391'},
          maxLineLength = 100
        }
      }
    }
  }
}

require('lspconfig').tsserver.setup{}

