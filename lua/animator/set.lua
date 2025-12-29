local encoding = "utf-8"
local tabstop = 2

vim.g.mapleader = " "

vim.opt.backup = false
vim.opt.completeopt = "menuone,noinsert,noselect"
vim.opt.encoding = encoding
vim.opt.expandtab = true
vim.opt.fileencodings = encoding
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.scrolloff = 8
vim.opt.shiftwidth = tabstop
vim.opt.smartindent = false
vim.opt.autoindent = true
vim.opt.softtabstop = tabstop
vim.opt.swapfile = false
vim.opt.tabstop = tabstop
vim.opt.termguicolors = true
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true
vim.opt.backupdir = os.getenv("HOME") .. "/.vim/backupdir"
vim.opt.wrap = false
vim.opt.writebackup = false

vim.g.codex_stream_lines = 12

vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")
vim.opt.updatetime = 50
vim.opt.colorcolumn = "80"
vim.opt.clipboard = "unnamedplus"
vim.opt.updatetime = 50
