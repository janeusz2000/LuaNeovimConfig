vim.g.tokyonight_transparent_sidebar = true
vim.g.tokyonight_transparent = true
vim.opt.background = "dark"

vim.cmd("colorscheme tokyonight")


-- Custom colored groups
vim.api.nvim_set_hl(0, "Comment", { fg = "#009933" })

-- Line Numbers colors
local relativeLineColor = "#FCAD03"
vim.api.nvim_set_hl(0, "LineNr", { fg = "#03FCF4" })
vim.api.nvim_set_hl(0, "LineNrAbove", { fg = relativeLineColor })
vim.api.nvim_set_hl(0, "LineNrBelow", { fg = relativeLineColor })
vim.api.nvim_set_hl(0, "Visual", {reverse = true})
