local keymap = require("animator.keymap")
local nnoremap = keymap.nnoremap
local vnoremap = keymap.vnoremap
local xnoremap = keymap.xnoremap
local nmap = keymap.nmap

-- remap ctrl + z to u in order to avoid crashing application by mistype
nnoremap("<C-Z>", "u")

-- adds tree explorer for file search
nnoremap("<leader>pv", "<cmd>Ex<CR>")

-- opens previous file
nnoremap("<leader>pe", ":e#<CR>")

-- I dont use this very often
-- nnoremap(<Leader>qd,daW"=substitute(@@,"'\\\|\"","","g")<CR>
--

-- Error remap
nmap("<leader>e", ":lua vim.diagnostic.open_float(0, {scope=\"line\"})<CR>")

-- Code formatting with lsp
vnoremap("<leader>f", ":lua vim.lsp.buf.format()<CR>")

-- Move selected code up or down
vnoremap("J", ":m '>+1<CR>gv=gv")
vnoremap("K", ":m '<-2<CR>gv=gv")

-- Better join on line
nnoremap("J", "mzJ`z")

-- Better navigation
nnoremap("<C-d>", "<C-d>zz")
nnoremap("<C-u>", "<C-u>zz")

-- Better finding?
nnoremap("n", "nzzzv")
nnoremap("N", "Nzzzv")

-- Restart the lsp
nnoremap("<leader>lsp", "<cmd>LspRestart<cr>")

-- leader paste does not override the paste
xnoremap("<leader>p", [["_dP]])

-- Codex completion for visual selection or scope at cursor
-- xnoremap("<leader>i", function()
--     require("animator.codex").complete_selection_or_scope()
-- end)
-- nnoremap("<leader>i", function()
--     require("animator.codex").complete_selection_or_scope()
-- end)

-- -- Open last Codex log
-- nnoremap("<leader><leader>i", function()
--     require("animator.codex").open_last_log()
-- end)

-- yionk to the system clipboard if simple "y" doesn't work...
vim.keymap.set({"n", "v"}, "<leader>y", [["+y]])
nnoremap("<leader>Y", [["+Y]])

-- This is convinient...
nnoremap("Q", "<nop>")

-- Quickfix navigation
nnoremap("<C-k>", "<cmd>cnext<CR>zz")
nnoremap("<C-j>", "<cmd>cprev<CR>zz")
nnoremap("<leader>k", "<cmd>lnext<CR>zz")
nnoremap("<leader>j", "<cmd>lprev<CR>zz")

-- Reload the config
nnoremap("<leader><leader>", function()
    vim.cmd("so")
end)

-- make file executable
nnoremap("<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

-- matrix
nnoremap("<leader>mr", "<cmd>CellularAutomaton game_of_life<CR>");
