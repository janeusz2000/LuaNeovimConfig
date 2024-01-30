local M = {}

require('telescope').setup({
  defaults = {
    layout_strategy = "vertical",
    layout_config = {
      vertical = { width = 0.9 }
    },
  },
})

-- add lines in preview window
vim.api.nvim_create_autocmd("User", {
    pattern = "TelescopePreviewerLoaded",
    callback = function()
        vim.wo.number = true
    end,
})


-- Function to grep for a string
function M.grep_for_string()
    local search_string = vim.fn.input('Grep for: ')
    require('telescope.builtin').grep_string({ search = search_string })
end

-- Function to find files
function M.find_files()
  require('telescope.builtin').find_files()
end
  

return M 
