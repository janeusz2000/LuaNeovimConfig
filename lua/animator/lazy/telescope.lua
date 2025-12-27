return {
  "nvim-telescope/telescope.nvim",
  tag = "0.1.8",

  dependencies = {
    "nvim-lua/plenary.nvim"
  },

  config = function()
    require('telescope').setup({})

    local ok_utils, previewers_utils = pcall(require, "telescope.previewers.utils")
    if ok_utils then
      local attempted = {}
      local orig_ts = previewers_utils.ts_highlighter
      previewers_utils.ts_highlighter = function(bufnr, ft)
        local ok, res = pcall(orig_ts, bufnr, ft)
        if ok then
          return res
        end

        local lang = (vim.treesitter and vim.treesitter.language and vim.treesitter.language.get_lang)
          and (vim.treesitter.language.get_lang(ft) or ft)
          or ft
        if lang and attempted[lang] ~= true and vim.fn.exists(":TSInstall") == 2 then
          attempted[lang] = true
          vim.schedule(function()
            pcall(vim.cmd, "TSInstall " .. lang)
          end)
        end
        return false
      end
    end

    local builtin = require('telescope.builtin')
    vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
    vim.keymap.set('n', '<C-p>', builtin.git_files, {})
    vim.keymap.set('n', '<leader>pws', function()
      local word = vim.fn.expand("<cword>")
      builtin.grep_string({ search = word })
    end)
    vim.keymap.set('n', '<leader>pWs', function()
      local word = vim.fn.expand("<cWORD>")
      builtin.grep_string({ search = word })
    end)
    vim.keymap.set('n', '<leader>ps', function()
      builtin.grep_string({ search = vim.fn.input("grep >:") })
    end)
    vim.keymap.set('n', '<leader>vh', builtin.help_tags, {})
  end
}
