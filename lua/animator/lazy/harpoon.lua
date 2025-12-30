return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  -- Ensure our harpoon takes precendence over any old 
  -- packer harpoon installations
  lazy = false,
  config = function()
    local harpoon = require "harpoon"
    harpoon:setup()

    vim.keymap.set("n", "<leader>ha", function()
      harpoon:list():add()
    end)
    vim.keymap.set("n", "<leader>ht", function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end)

    -- harpoon movement
    for _, idx in ipairs { 1, 2, 3, 4, 5, 6, 7, 8, 9 } do
      vim.keymap.set("n", string.format("<leader>h%d", idx), function()
        harpoon:list():select(idx)
      end)
    end
  end,
}
