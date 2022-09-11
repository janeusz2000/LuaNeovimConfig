--[[ 
#1 execute on your linux machine

git clone --depth 1 https://github.com/wbthomason/packer.nvim\
~/.local/share/nvim/site/pack/packer/start/packer.nvim

--]] 
vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)
    -- Packer can manage itself
    use 'wbthomason/packer.nvim'
    -- coloreShceme
    use 'folke/tokyonight.nvim'

    -- telesocpe requirements:
    use 'nvim-lua/popup.nvim'
    use 'nvim-lua/plenary.nvim'
    use 'nvim-treesitter/nvim-treesitter'

    -- telescope
    use 'nvim-telescope/telescope.nvim'
    -- some additional uttilities for telescope
    use 'nvim-telescope/telescope-fzy-native.nvim'

    -- comment toogle
    use 'tpope/vim-commentary'

    -- auto open and close brackets
    use 'jiangmiao/auto-pairs'

    -- harpooon for marking down workspace files
    use 'ThePrimeagen/harpoon'

    -- LSP configuration for intellisense
    -- ==================================
    -- main package:
    use 'neovim/nvim-lspconfig'

    -- Neovim-cmp: comletion engine
    use 'hrsh7th/cmp-nvim-lsp'
    use 'hrsh7th/cmp-buffer'
    use 'hrsh7th/cmp-path'
    use 'hrsh7th/cmp-cmdline'
    use 'hrsh7th/nvim-cmp'
    use 'hrsh7th/cmp-vsnip'
    use 'hrsh7th/vim-vsnip'

end)
