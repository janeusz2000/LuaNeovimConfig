keymap = require("animator.keymap")
local nnoremap = keymap.nnoremap
local nmap = keymap.nmap

-- remap ctrl + z to u in order to avoid crashing application by mistype
nnoremap("<C-Z>", "u")

-- adds tree explorer for file search
nnoremap("<leader>pv", "<cmd>Ex<CR>")

-- greps for the word in the entire repo
nnoremap("<leader>ps", ":lua require('telescope.builtin').grep_string({ search = vim.fn.input('grep for: ')})<CR>")

-- finds files by name
nnoremap("<leader>pf", ":lua require('telescope.builtin').find_files()<CR>")

-- opens previous file
nnoremap("<leader>pe", ":e#<CR>")

-- toggle word below cursor into/out of the double quotes
nnoremap("<leader>\"","ciw\"\"<CR>")

-- toggle word below cursor into/out of the single quote
nnoremap("<leader>'","ciw''<CR>")

-- I dont use this very often
-- nnoremap(<Leader>qd,daW"=substitute(@@,"'\\\|\"","","g")<CR>

-- harpoon add current file into scope
nnoremap("<leader>ha", ":lua require(\"harpoon.mark\").add_file()<CR>")

-- harpoop view jump terminal
nnoremap("<leader>ht", ":lua require(\"harpoon.ui\").toggle_quick_menu()<CR>")

-- harpoon go next file
nnoremap("<leader>hn", ":lua require(\"harpoon.ui\").nav_next()<CR>")

-- harpoon go previous file
nnoremap("<leader>hb", ":lua require(\"harpoon.ui\").nav_prev()<CR>")

-- harpoon absolute files navigation
nnoremap("<leader>h1", ":lua require(\"harpoon.ui\").nav_file(1)<CR>")
nnoremap("<leader>h2", ":lua require(\"harpoon.ui\").nav_file(2)<CR>")
nnoremap("<leader>h3", ":lua require(\"harpoon.ui\").nav_file(3)<CR>")
nnoremap("<leader>h4", ":lua require(\"harpoon.ui\").nav_file(4)<CR>")
nnoremap("<leader>h5", ":lua require(\"harpoon.ui\").nav_file(5)<CR>")

-- error remap
nmap("<leader>e", ":lua vim.diagnostic.open_float(0, {scope=\"line\"})<CR>")

-- close quickFix list
nnoremap("<leader>b", ":cclose<CR>")
