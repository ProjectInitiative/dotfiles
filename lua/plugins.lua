-- bootstrap packer install on any system with this config
local fn = vim.fn
local install_path = fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
if fn.empty(fn.glob(install_path)) > 0 then
  packer_bootstrap = fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
end

-- auto compile plugins added to this file
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerCompile
  augroup end
]])


return require('packer').startup(function(use)
  -- My plugins here
  use 'wbthomason/packer.nvim'
  use {'neoclide/coc.nvim', branch = 'release'}
  use {'junegunn/fzf', dir = '~/.fzf', run = './install --all' }
  use {'junegunn/fzf.vim'}
  use {"akinsho/toggleterm.nvim", tag = 'v2.*', config = function()
    require("toggleterm").setup()
  end}

  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if packer_bootstrap then
    require('packer').sync()
  end
end)

