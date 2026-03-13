vim.opt.rtp:append(".")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
vim.cmd("runtime plugin/plenary.vim")
